---
date: 2025-11-02
title: NestJS 캐시 어떻게 활용하고 계신가요?
readingTime: 20
---

## 개요

최근 큰 규모의 고객사 이전으로 서비스 전반의 부하 안정성 개선이 사내 최우선 과제로 떠올랐습니다.
저는 여러 마이크로서비스(MSA) 사이에서 프론트엔드의 협업을 돕는 'BFF(Backend for Frontend)' 서버를 담당하고 있었습니다.

흔히 BFF는 여러 서비스 엔드포인트를 팔로업하고 FE가 원하는 응답을 적절하게 'Partial Response' 하는 서버를 의미합니다.
하지만 BFF는 웹사이트 트래픽이 집중될 때 각 서비스로 가해지는 트래픽을 조절해 시스템 전체의 병목을 방어하는 **Offload**의 핵심 계층이기도 합니다.

이러한 책임을 갖는 서버에서 단기간에 확실한 개선 효과를 낼 수 있는 방법은 '캐시'라고 판단했습니다.

**하지만 기존 캐시에는 몇 가지 문제가 있었습니다.**

- 캐시 로직으로 인한 비즈니스 로직 오염
- 조건부 캐싱의 어려움
- 캐시 무효화의 일관성 문제
- 계층형 캐시 미지원
- 캐시 쇄도 문제
- 40kb 이상의 큰 문자열을 I/O 할 때 생기는 응답 지연 문제 (Redis)

여러 문제가 있었지만 선언적 방식으로 캐싱 로직을 관리할 수 있도록 간단한 리팩토링을 먼저 진행하기로 했습니다.

## 선언적 캐시 데코레이터 지원

당시 기능을 빠르게 붙여야 했던 탓에 구현에만 급급했었고... 다음과 같은 코드가 남발하고 있었습니다.

```typescript {title="some.service.ts"}
async getPaymentsKey(@Ctx() user: UserContext) {
    const storeId = user.storeId;
    
    const cacheKey = `get-clientKey-${storeId}`;
    let cacheValue = null;
    
    try {
        cacheValue = await this.cacheService.get(cacheKey);
    } catch (err) {
        this.logger.error(`캐시 조회 실패: ${cacheKey}`, err.stack);
        cacheValue = null;
    }
    
    if (cacheValue) {
        return cacheValue;
    }
    
    const {clientKey, state} = await this.paymentsServcie.getPaymentsKey(storeId);
    
    try {
        if (state === 'ACTIVE') {
            await this.cacheService.set(cacheKey, {clientKey, state});
        }
    } catch (err) {
        this.logger.error(`캐시 설정 실패: ${cacheKey}`, err.stack);
    }
    
    return new GetPaymentsKeyResponse(clientKey, state);
}
```

당시 NestJS 캐시 모듈은 메서드 호출을 가로채 실행 전 후로 원하는 로직을 실행 시킬 수 있는 횡단 관심사 기능(AOP)을 제가 원하는 수준으로 제공하지 않았습니다.
(Interceptor 가 있었지만 라우터 핸들러에서만 동작했기에 적합하지 않다고 판단했습니다.)
그렇다면 NestJS에서 선언적 캐시를 위한 데코레이터를 어떻게 구현할 수 있을까요? 

간단한 해결책으로 **[@toss/nestjs-aop](https://github.com/toss/nestjs-aop)** 를 사용했습니다. [^1]

**nestjs-aop**는 라우터 핸들러에서만 동작하는 Interceptor가 아닌 부팅 라이프 사이클(Bootstrap)을 이용해 DI 컨테이너가 초기화된 후
AOP의 대상이 되는 메서드를 찾아 **런타임에 직접 교체(Monkey-Patching)** 하는 원리로 서비스 메서드를 포함한 모든 프로바이더에 AOP를 적용할 수 있게 합니다.

내부 동작 원리는 크게 **[마킹] → [탐색] → [교체] → [실행]** 4단계로 나뉩니다.

### 마킹
metadataKey와 metadata를 인자로 받아 고유한 심볼로 데코레이터를 생성합니다. 코드를 살펴보면 다음과 같습니다.
 
```typescript {title="create-decorator.ts"}
export const createDecorator = (
    metadataKey: symbol | string,
    metadata?: unknown,
): MethodDecorator => {
    const aopSymbol = Symbol('AOP_DECORATOR');
    
    return applyDecorators(
        // 메타데이터 저장
        (target: object, propertyKey: string | symbol, descriptor: PropertyDescriptor) => {
            return AddMetadata<symbol | string, AopMetadata>(metadataKey, {
                originalFn: descriptor.value, // 원본 메서드 저장 
                metadata,                     // 데코레이터 옵션 저장
                aopSymbol,                    // 식별자 저장
            })(target, propertyKey, descriptor);
        },
        
        // 원본 메서드 바꿔치기 
        (_: object, propertyKey: string | symbol, descriptor: PropertyDescriptor) => {
            const originalFn = descriptor.value;

            descriptor.value = function (this: any, ...args: unknown[]) {
                // 데코레이터가 붙은 메서드가 호출되면, 런타임은 원본 함수 대신 wrappedFn 함수 실행
                const wrappedFn = this[aopSymbol]?.[propertyKey];
                if (wrappedFn) {
                    return wrappedFn.apply(this, args);
                }

                // AopModule이 없거나 실패한 경우 원본 메서드 실행 (Fallback)
                return originalFn.apply(this, args);
            };

            Object.defineProperty(descriptor.value, 'name', {
                value: propertyKey.toString(),
                writable: false,
            });
            Object.setPrototypeOf(descriptor.value, originalFn);
        },
    );
};
```

`applyDecorators`는 두 개의 데코레이터 함수를 순차적으로 적용합니다.

#### 메타데이터 저장
NestJS가 실행되는(bootstrap) 과정에서 메서드에 AOP를 적용하고 런타임에 동작이 변경될 수 있도록 메타데이터를 마킹합니다.

> `descriptor`는 자바스크립트 런타임이 메서드 데코레이터가 실행될 때 자동으로 전달하는 표준 내장 객체입니다.
MDN 공식 문서에 따르면 반환 값은 다음과 같다고 합니다. [^2]
> 
> - value: 원본 메서드
> - writable: 값을 덮어쓸 수 있는지 여부
> - enumerable: 열거 가능 여부
> - configurable: 속성을 삭제하거나 descriptor를 수정할 수 있는지 여부

`descriptor.value`가 원본 메서드인 것을 활용해 `AddMetadata`가 메타데이터를 원본 메서드에 마킹할 수 있습니다.
추후 NestJS의 `DiscoveryService`가 메타데이터를 스캔하면서 AOP 로직 주입 대상을 찾습니다.

#### 원본 메서드 바꿔치기

위에서 `descriptor.value`는 원본 메서드임을 확인했습니다. 따라서 `descriptor.value`는 `function`으로 교체되는 것을 알 수 있습니다.

교체는 `OnModuleInit` 단계에서 위에서 마킹한 메타데이터를 발견하면 실제 데코레이터 로직이 담긴 새로운 함수를 생성하고
`instance[aopSymbol][propertyKey]`를 통해 **원본 메서드를 바꿔치기** 합니다.
(원본 메서드가 실행되면 바꿔치기된 함수가 실행되고, 원본 함수 대신 AOP가 적용된 함수가 실행되게 됩니다.)

이후 바꿔치기 과정에서 프로토타입 체인이 망가지는 것을 방지하기 위해 바꿔치기 한 함수의 이름을 원본 함수 이름으로 바꾸고 프로토타입을 원본 함수로 연결합니다.

중요한 점은 아직 원본 메서드를 바꿔치기한 `this[aopSymbol][propertyKey]`은 빈 껍데기라는 점입니다. 
**[교체]** 단계에서 다시 살펴보도록 하겠습니다.

### 탐색
탐색은 `AutoAspectExecutor`의 `OnModuleInit` 훅에서 시작됩니다. 코드를 살펴보겠습니다.

```typescript {title="auto-aspect-executor.ts"}
export class AutoAspectExecutor implements OnModuleInit {
    private readonly wrappedMethodCache = new WeakMap();

    constructor(
        private readonly discoveryService: DiscoveryService,
        private readonly metadataScanner: MetadataScanner,
        private readonly reflector: Reflector,
    ) {
    }

    onModuleInit() {
        this.bootstrapLazyDecorators();
    }

    private bootstrapLazyDecorators() {
        const controllers = this.discoveryService.getControllers();
        const providers = this.discoveryService.getProviders();

        const lazyDecorators = this.lookupLazyDecorators(providers);
        if (lazyDecorators.length === 0) {
            return;
        }

        const instanceWrappers = providers
            .concat(controllers)
            .filter(({ instance }) => instance && Object.getPrototypeOf(instance));

        for (const lazyDecorator of lazyDecorators) {
            for (const wrapper of instanceWrappers) {
                this.applyLazyDecorator(lazyDecorator, wrapper);
            }
        }
    }

    // AOP 데코레이터와 `wrap` 함수가 존재하는 클래스를 찾아 반환
    private lookupLazyDecorators(providers: InstanceWrapper[]): LazyDecorator[] {
        const {reflector} = this;

        return providers
            .filter((wrapper) => wrapper.isDependencyTreeStatic())
            .filter(({instance, metatype}) => {
                if (!instance || !metatype) {
                    return false;
                }
                const aspect =
                    reflector.get<string>(ASPECT, metatype) ||
                    reflector.get<string>(ASPECT, Object.getPrototypeOf(instance).constructor);

                if (!aspect) {
                    return false;
                }

                return typeof instance.wrap === 'function';
            })
            .map(({instance}) => instance);
    }

    private applyLazyDecorator(lazyDecorator: LazyDecorator, instanceWrapper: InstanceWrapper<any>) {
        const target = instanceWrapper.isDependencyTreeStatic()
            ? instanceWrapper.instance
            : instanceWrapper.metatype?.prototype;

        if (!target) {
            console.debug('[applyLazyDecorator] not found target');
            return;
        }

        const propertyKeys = this.metadataScanner.scanFromPrototype(
            target,
            instanceWrapper.isDependencyTreeStatic() ? Object.getPrototypeOf(target) : target,
            (name) => name,
        );

        const metadataKey = this.reflector.get(ASPECT, lazyDecorator.constructor);
        for (const propertyKey of propertyKeys) {
            // @see: https://github.com/rbuckton/reflect-metadata/blob/9562d6395cc3901eaafaf8a6ed8bc327111853d5/Reflect.ts#L938
            const targetProperty = target[propertyKey];
            if (!targetProperty || (typeof targetProperty !== "object" && typeof targetProperty !== "function")) {
                continue;
            }

            // 메서드를 순회하면서 metadataKey가 적용되어있는 메서드를 찾아 AOP 메타데이터를 반환
            const metadataList: AopMetadata[] = this.reflector.get<AopMetadata[]>(
                metadataKey,
                targetProperty
            );
            
            if (!metadataList) {
                continue;
            }

            // 실제 AOP 로직을 연결하기위해 wrapMethod에 전달
            for (const aopMetadata of metadataList) {
                this.wrapMethod({lazyDecorator, aopMetadata, methodName: propertyKey, target});
            }
        }
    }
}
```

애플리케이션이 시작되면 모든 의존성 주입이 완료되고 이후 `DiscoveryService`를 통해 모든 프로바이더를 조회할 수 있게 됩니다.

즉 의존성 주입이 끝난 직후인 `OnModuleInit` 단계에서 `bootstrapLazyDecorators`이 실행됩니다. 
따라서 `lookupLazyDecorators`를 통해 `@Aspect()` 데코레이터와 `wrap` 함수가 존재하는 클래스를 찾아낼 수 있습니다.
(AOP 클래스에서 `AOP 로직(LazyDecorator)`를 구현해야하는 이유입니다.)

이후 `applyLazyDecorator`에 위에서 찾은 `LazyDecorator`와 `InstanceWrapper`를 전달합니다.

`metadataScanner`은 클래스(instanceWrapper)가 가진 함수를 배열로 반환하고 `reflector`를 통해 `metadataKey`가 적용되어있는 메서드를 찾아 AOP 메타데이터
즉, `createDecorator`에서 마킹한 AOP 메타데이터(원본 메서드, 메타데이터 옵션, 심볼)를 반환합니다.

찾은 메서드와 AOP 메타데이터는 `wrapMethod`에 함께 전달됩니다.

### 교체
`wrapMethod` 는 `AOP 로직(LazyDecorator)`을 실행할 수 있는 `wrappedFn`을 만듭니다. 코드를 살펴보겠습니다.

```typescript {title="auto-aspect-executor.ts"}
private wrapMethod({
    lazyDecorator,
    aopMetadata,
    methodName,
    target,
}: {
    lazyDecorator: LazyDecorator;
    aopMetadata: AopMetadata;
    methodName: string;
    target: any;
}) {
    // 원본 메서드, 메타데이터 옵션, 심볼 조회
    const { originalFn, metadata, aopSymbol } = aopMetadata;

    const self = this;
    const wrappedFn = function (this: object, ...args: unknown[]) {
        const cache = self.wrappedMethodCache.get(this) || new WeakMap();
        const cached = cache.get(originalFn);
        if (cached) {
            return cached.apply(this, args);
        }

        const wrappedMethod = lazyDecorator.wrap({
            instance: this,
            methodName,
            method: originalFn.bind(this),
            metadata,
        });
        cache.set(originalFn, wrappedMethod);
        self.wrappedMethodCache.set(this, cache);
        return wrappedMethod.apply(this, args);
    };

    // 데코레이터의 프록시 함수를 wrappedFn으로 교체
    target[aopSymbol] ??= {};
    target[aopSymbol][methodName] = wrappedFn;
}
```

`wrappedFn`은 `WeakMap`을 통해 캐시되어 성능을 최적화하고, AOP 로직이 구현되어 있는 `lazyDecorator.wrap`를 `wrappedMethod`에 할당합니다.
이후 마킹 단계에서 원본 메서드에 바꿔치기 한 빈 껍데기 프록시 함수를 `wrappedFn`로 교체합니다.

### 실행
애플리케이션 로직 어딘가에서 AOP 데코레이터가 붙어있는 함수가 실행되면 **[마킹]** 단계에서 덮어쓴 프록시 함수가 먼저 실행됩니다.
프록시 함수는 `this[aopSymbol][methodName]`을 호출하게 되고 **[교체]** 단계에서 `wrappedFn`를 할당 하였으므로 AOP 로직이 실행됩니다.

아래 예제는 추후 구현하게 될 캐시 AOP 클래스의 실행 순서를 간략하게 표현한 코드입니다.

```typescript
@Aspect()
@Injectable()
export class CacheableAspect
    implements LazyDecorator<any, CacheableOption> {
    
    wrap({method, metadata: options}) {
        return (...args: any[]) => {
            console.log('AOP: Before original method'); // ('before' 로직)

            // '원본 함수'가 '스텁 함수' 내부에 매핑
            const result = method(...args);

            console.log('AOP: After original method'); // ('after' 로직)
            return result;
        };
    }
    
}
```

간단(?)하게 내부 동작 원리를 살펴보았으니 이제 구현만 하면 되겠습니다.

### Option 설계하기

Spring Boot의 캐시 어노테이션과 유사한 DX를 제공하는 NestJS의 캐시 데코레이터를 구현하고 싶었습니다.

현재 프로젝트 규모에서는 캐시를 저장하고, 동작에 따라 캐시를 삭제할 수 있는 기능만 있으면 됐기에 `@Cacheable`과 `@CacheEvict` 데코레이터만 구현하기로 했습니다.

먼저 캐시 데코레이터에 필요한 옵션을 설계합니다. (Spring Cache의 검증된 옵션 설계를 참고했습니다.)

#### CacheableOption

캐시 저장을 위한 @Cacheable 데코레이터의 옵션입니다.

```typescript {title="cacheable-option.ts"}
export interface CacheableOption {
    ttl: number;
    cacheManager?: CacheManager;
    name?: string | ((...args: any[]) => string);
    key?: string | ((...args: any[]) => string);
    condition?: (...args: any[]) => boolean;
    unless?: (result: any, ...args: any[]) => boolean;
}
```

- **ttl** 캐시 만료 시간을 초 단위로 지정합니다.
- **cacheManager** 캐시 프로바이더를 선택합니다.
- **name** 동일한 name을 가진 캐시들을 일괄 관리할 수 있도록 캐시를 논리적으로 그룹화합니다.
- **key** 캐시를 식별하는 고유 키를 생성합니다.
- **condition** 메서드 실행 전 평가해 true일 때만 캐싱합니다.
- **unless** 메서드 실행 후 평가해 true일 때는 결과를 캐싱하지 않습니다.

#### CacheEvictOption

캐시 삭제를 위한 @CacheEvict 데코레이터의 옵션입니다.

```typescript {title="cache-evict-option.ts"}
export interface CacheEvictOption {
    cacheManager?: CacheManager;
    name?: string | string[] | ((...args: any[]) => string | string[]);
    key?: string | ((...args: any[]) => string);
    condition?: (...args: any[]) => boolean;
    allEntries?: boolean;
    beforeInvocation?: boolean;
}
```

- **cacheManager** 캐시 프로바이더를 선택합니다.
- **name** 동일한 name을 가진 캐시들을 일괄 관리할 수 있도록 캐시를 논리적으로 그룹화합니다. CacheableOption과 동일하게 동작하지만 일괄 삭제를 위해 배열도 지원합니다.
- **key** 캐시를 식별하는 고유 키를 생성합니다.
- **condition** 메서드 실행 전 평가해 true일 때만 캐시를 삭제합니다.
- **allEntries** true로 설정하면 해당 네임스페이스의 모든 캐시를 삭제합니다. key 옵션은 무시합니다.
- **beforeInvocation** 캐시 삭제 시점을 제어합니다. true 인 경우 메서드 실행 전에 캐시를 삭제합니다.

이정도 옵션이면 사용하기 충분해보입니다. 다만 `CacheManager` 를 통해 각 캐시 프로바이더를 계층형으로 제공 할 수 있도록 옵션을 설계했는데요.

이유는 다음과 같습니다.

- 사내 프로젝트로 개발 중인 웹 빌더 폰트는 비용 문제로 한번 변경된 이후 항상 동일했습니다. 폰트와 같은 정적인 데이터는 레디스가 아닌 메모리에 저장한 후 응답하도록 다양한 캐시 프로바이더를 활용하고 싶었습니다.
- 고객사 이벤트 시 수 천건의 요청이 똑같은 키로 발생하는 `Hot Key` 방어 전략으로 멀티 캐싱을 활용할 수 있습니다. 보통 스케일 아웃이 일어나도 레디스 클러스터는 1대인 경우가 많은데,
  로컬 캐시에 아주 짧은 TTL(1초)을 설정하면 레디스로 요청되는 네트워크 대역폭을 줄일 수 있습니다.

캐시 프로바이더 구현은 밑에서 따로 다루도록 하겠습니다.

### KeyGenerator

```typescript {title="cache-key-generator.ts"}
import { Injectable } from '@nestjs/common';
import * as XXH from 'xxhashjs';

import type { CacheableOption, CacheEvictOption } from '../types';

export type CacheKeyContext = {
    target: any;
    methodName: string;
    args: any[];
};

@Injectable()
export class CacheKeyGenerator {
    generateCacheableKey(option: CacheableOption, context: CacheKeyContext): string {
        const { name } = option;

        const namespace = name
            ? typeof name === 'function'
                ? name(...context.args)
                : name
            : undefined;
        const key = this.resolveKey(option.key, context);

        return namespace ? `${namespace}::${key}` : key;
    }

    generateEvictKeys(option: CacheEvictOption, context: CacheKeyContext): string[] {
        const { name } = option;

        const namespaces = name
            ? (() => {
                const resolved = typeof name === 'function' ? name(...context.args) : name;
                return Array.isArray(resolved) ? resolved.filter(Boolean) : [resolved];
            })()
            : [];

        if (option.allEntries) {
            return namespaces.map((ns) => `${ns}::`);
        }

        const key = this.resolveKey(option.key, context);

        return namespaces.length === 0 ? [key] : namespaces.map((ns) => `${ns}::${key}`);
    }

    private resolveKey(
        resolver: string | ((...args: any[]) => string) | undefined,
        context: CacheKeyContext,
    ): string {
        // 커스텀 키 리졸버가 있는 경우 우선 사용
        if (resolver) {
            const resolved = typeof resolver === 'function' ? resolver(...context.args) : resolver;

            if (resolved) {
                return resolved;
            }
        }

        // 커스텀 키가 없으면 기본 키 생성
        return this.generateAutoKey(context);
    }

    private generateAutoKey(context: CacheKeyContext): string {
        const { target, methodName, args } = context;
        const className = target?.constructor?.name;
        const prefix = className ? `${className}:${methodName}` : methodName;

        // 인자가 없는 경우
        if (args.length === 0) {
            return prefix;
        }

        // 인자가 1개이고 원시 타입인 경우
        if (args.length === 1) {
            const arg = args[0];

            if (this.isPrimitive(arg)) {
                return `${prefix}:${arg}`;
            }
        }

        // 복잡한 경우 해시 사용
        return this.generateHashedKey(prefix, args);
    }

    private isPrimitive(value: unknown): boolean {
        return typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean';
    }
    
    private generateHashedKey(prefix: string, args: any[]): string {
        const json = JSON.stringify(args);
        const hash = XXH.h32(json, 0x654c6162).toString(16);

        return `${prefix}:${hash}`;
    }
}
```

`KeyGenerator`는 데코레이터의 우선순위에 따라 다음과 같이 캐시 키를 생성합니다.

- **커스텀 키가 있는 경우** `key` 옵션에 지정된 값을 그대로 해석해 사용
- **인자가 없는 경우** `ClassName:methodName` 형태로 생성
- **원시 타입 인자가 1개인 경우**: `ClassName:methodName:value` 형태로 생성
- **복잡한 인자인 경우** `ClassName:methodName:${hash}` 형태로 생성

복잡한 인자인 경우 `generateHashedKey`를 통해 해싱을 적용했습니다. 요청에 따라 파라미터를 그대로 직렬화해서 사용하면 Redis에서 권장하는 1KB 이하의 키 길이를 넘어설 수 있습니다.

> Very long keys are not a good idea. For instance, a key of 1024 bytes is a bad idea not only memory-wise, but also because the lookup of the key in the dataset may require several costly key-comparisons. Even when the task at hand is to match the existence of a large value, hashing it (for example with SHA1) is a better idea, especially from the perspective of memory and bandwidth.

레디스 공식 문서[^3]에 따르면 `1024 bytes`의 키는 메모리 사용량과 조회 시 키 비교 비용 측면에서 비효율적이니
큰  값을 키로 사용해야 할 때는 해싱을 사용하라고 권장하고 있습니다.

Redis 공식 문서에서는 `SHA1`을 예시로 들었지만, 캐시 키는 고유 식별자의 역할이 더 크므로 더 빠르고 짧은(32bit/64bit) 비 암호화 해시인 `XXHash`를 사용했습니다.







[^1]: [@toss/nestjs-aop](https://github.com/toss/nestjs-aop)
[^2]: [MDN - Object.getOwnPropertyDescriptor()](https://developer.mozilla.org/ko/docs/Web/JavaScript/Reference/Global_Objects/Object/getOwnPropertyDescriptor)
[^3]: [redis](https://redis.io/docs/latest/develop/using-commands/keyspace/)
