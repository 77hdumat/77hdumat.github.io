---
date: 2025-11-02
title: NestJS에서 Spring Boot Cache 흉내내기
readingTime: 15
---

## 페인 포인트

최근 큰 규모의 고객사가 사내 서비스로 이전하게 되면서 서비스 전반의 부하 안정성 개선이 최우선 과제로 떠올랐습니다. 
저희 서비스는 모두 MSA로 구성되어 있었고, 저는 이 서비스들을 팔로업 하는 'BFF(Backend for Frontend)' 서버를 담당하고 있습니다.

MSA 환경에서 BFF 서버는 다양한 서비스의 엔드포인트에 의존하다 보니, 트래픽이 집중될 때 병목 현상이 발생하기 가장 쉬운 구간이었습니다.
이 문제를 빠르게 해결하기 위해 (판교 사투리로 ASAP 이라고 하나요?...😅) 기존 비즈니스 로직과 복잡하게 얽혀있던 캐시 구현을 모두 걷어낸 후, 지속 가능하고 편한 캐시 관리 방안을 모색했습니다.

**기존 캐시 로직에는 몇 가지 문제점이 있었습니다.**

- 비즈니스 로직의 오염
- 조건부 캐싱의 어려움 (혹은 귀찮은)
- 에러 핸들링을 위한 보일러플레이트 코드
- 캐시 무효화의 일관성 문제
- 계층형 캐시 미지원
 
위와 같은 문제를 해결하지 않고 구현에만 급급했던 탓에 다음과 같은 코드가 남발되고 있었습니다.

```typescript
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

깔끔한 문제 해결을 위해 Spring Boot의 **@Cacheable** 어노테이션과 같은 **선언적 캐싱 방식**을 도입하기로 했습니다.

## Spring Boot Cache 참고하기

문제 해결에 앞서 참고할만한 [스프링 부트 캐시의 옵션](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/cache/annotation/package-summary.html)을 몇가지 추려보겠습니다.

### @Cacheable

| Option             | Description                      |
|:-------------------|:---------------------------------|
| cacheNames / value | 캐시를 그룹화하는 네임스페이스                 |
| key                | 캐시 항목을 식별하는 고유 키                 |
| cacheManager       | 여러 캐시 전략(Redis, Memory) 중 하나 선택  |
| condition          | 메서드 실행 전 캐시 로직을 실행할지 결정하는 SpEL   |
| unless             | 메서드 실행 후 결과값을 캐시에 저장할지 결정하는 SpEL |

### @CacheEvict

| Option             | Description                                |
|:-------------------|:-------------------------------------------|
| cacheNames / value | 삭제할 캐시가 속한 네임스페이스                          |
| key                | 삭제할 특정 캐시 항목의 키                            |
| cacheManager       | 캐시 삭제를 수행할 캐시 매니저를 선택                      |
| condition          | 메서드 실행 전 캐시 삭제 로직을 실행할지 결정하는 함수            |
| allEntries         | `true`일 경우, `key`와 무관하게 네임스페이스의 모든 항목을 삭제  |
| beforeInvocation   | `true`일 경우, 메서드 실행 전 캐시 삭제 (메서드 성공 여부와 무관) |

캐시 네임스페이스 / 메서드 실행 전, 후 평가 / 캐시 전략 선택 등 다양한 옵션들을 추려보았습니다. BFF 서비스에서 사용하기에 부족하지 않은 옵션들 입니다.
하지만 구현하기에 앞서 한가지 큰 문제에 직면합니다.

## NestJS에 AOP 적용하기 

NestJS는 Spring Boot의 AOP(Aspect-Oriented Programming) 즉, 메서드 호출을 가로채 실행 전 후로 원하는 로직을 실행 시킬 수 있는 횡단 관심사 기능을 제공하고 있지 않다는 점입니다.
그렇다면 NestJS에서 선언적 캐시를 위한 데코레이터를 어떻게 구현할 수 있을까요? (비슷한 기능으로 interceptor가 있지만 라우트 핸들러에서만 동작하기 때문에 적합하지 않습니다.)

간단한 해결책으로 **[@toss/nestjs-aop](https://github.com/toss/nestjs-aop)** 를 사용했습니다. [^1]

**nestjs-aop**는 라우터 핸들러에서만 동작하는 Interceptor가 아닌 부팅 라이프 사이클을 이용해 DI 컨테이너가 초기화된 후, AOP의 대상이 되는 메서드를 찾아 **런타임에 직접 교체(Monkey-Patching)** 하는 원리로
서비스 내부 메서드를 포함한 모든 프로바이더에 AOP를 적용할 수 있게 합니다.

내부 동작 원리는 크게 **[마킹] → [탐색] → [교체] → [실행]** 4단계로 나뉩니다.

### 마킹
metadata 식별자와 metadata를 인자로 받아 고유한 AOP 심볼로 데코레이터를 생성합니다. `applyDecorators` 를 통해 두 개의 데코레이터 함수를 순차적으로 적용합니다. 
코드를 살펴보면 다음과 같습니다.

```typescript {title="create-decorator.ts"}
export const createDecorator = (
    metadataKey: symbol | string,
    metadata?: unknown,
): MethodDecorator => {
    const aopSymbol = Symbol('AOP_DECORATOR');
    return applyDecorators(
        // 1. 메타 데이터 저장 (Reflect를 통해 메서드에 부착되고 추후 Discovery 과정에서 식별됩니다.)
        (target: object, propertyKey: string | symbol, descriptor: PropertyDescriptor) => {
            return AddMetadata<symbol | string, AopMetadata>(metadataKey, {
                originalFn: descriptor.value, // 원본 메서드 
                metadata, // 데코레이터에 전달된 옵션 인자
                aopSymbol, // 고유 심볼
            })(target, propertyKey, descriptor);
        },
        
        // 2. 원본 메서드에 프록시 메서드 Wrapping 
        (_: object, propertyKey: string | symbol, descriptor: PropertyDescriptor) => {
            const originalFn = descriptor.value;

            descriptor.value = function (this: any, ...args: unknown[]) {
                // 데코레이터가 붙은 메서드가 호출되면, 런타임은 원본 함수 대신 wrappedFn 함수를 실행하게 됩니다.
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

`descriptor`는 자바스크립트 런타임이 메서드 데코레이터가 실행될 때 자동으로 전달하는 표준 내장 객체입니다. 
해당 인자는 자바스크립트의 `Object.getOwnPropertyDescriptor()`과 동일합니다. 

DMN 공식 문서에 따르면 주어진 객체는 속성 설명자(descriptor)를 반환하고, 반환 속성은 다음과 같다고합니다. [^2]

- value: 원본 메서드 (originalFn)
- writable: 값을 덮어쓸 수 있는지 여부
- enumerable: 열거 가능 여부
- configurable: 속성을 삭제하거나 descriptor를 수정할 수 있는지 여부

### 탐색
탐색은 AutoAspectExecutor 클래스의 OnModuleInit 부팅 라이프사이클 훅에서 시작됩니다. 
애플리케이션이 시작되면 모든 의존성 주입이 완료되고 이후 discoveryService 를 통해 모든 프로바이더를 조회할 수 있게 됩니다. 
조회된 프로바이더는 lookupLazyDecorators 를 통해 @Aspect() 데코레이터와 wrap 함수가 존재하는 클래스(AOP 로직 클래스)를 찾아낼 수 있습니다.

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
        // 모든 프로바이더를 조회합니다.
        const controllers = this.discoveryService.getControllers();
        const providers = this.discoveryService.getProviders();

        // 조회된 프로바이더는 lookupLazyDecorators로 넘겨집니다.
        const lazyDecorators = this.lookupLazyDecorators(providers);
        if (lazyDecorators.length === 0) {
            return;
        }

        const instanceWrappers = providers
            .concat(controllers)
            .filter(({instance}) => instance && Object.getPrototypeOf(instance));

        // lazyDecorator 즉, AOP 클래스를 모두 찾아(Outer Loop) 모든 프로바이더를 순회(Inner Loop)합니다.
        for (const lazyDecorator of lazyDecorators) {
            for (const wrapper of instanceWrappers) {
                this.applyLazyDecorator(lazyDecorator, wrapper);
            }
        }
    }

    // AOP 데코레이터와 `wrap` 함수가 존재하는 클래스를 찾아 반환합니다.
    // 이 구간에서 나중에 구현하게 될 cacheable.aspect.ts가 찾아집니다.
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

        // 클래스의 모든 메서드를 metadataScanner로 조회합니다
        const propertyKeys = this.metadataScanner.scanFromPrototype(
            target,
            instanceWrapper.isDependencyTreeStatic() ? Object.getPrototypeOf(target) : target,
            (name) => name,
        );

        // createDecorator를 통해 메타데이터를 생성할때 인자로 넘겨 받은 metadataKey를 조회합니다.
        const metadataKey = this.reflector.get(ASPECT, lazyDecorator.constructor);
        for (const propertyKey of propertyKeys) {
            // @see: https://github.com/rbuckton/reflect-metadata/blob/9562d6395cc3901eaafaf8a6ed8bc327111853d5/Reflect.ts#L938
            const targetProperty = target[propertyKey];
            if (!targetProperty || (typeof targetProperty !== "object" && typeof targetProperty !== "function")) {
                continue;
            }

            // 프로바이더 내 메서드를 순회하면서 metadataKey가 적용되어있는 메서드를 찾아 AOP 메타데이터를 반환합니다.
            const metadataList: AopMetadata[] = this.reflector.get<AopMetadata[]>(
                metadataKey,
                targetProperty,
            );
            if (!metadataList) {
                continue;
            }

            // 찾은 메서드는 실제 AOP 로직을 연결하기위해 wrapMethod 넘겨집니다.
            for (const aopMetadata of metadataList) {
                this.wrapMethod({lazyDecorator, aopMetadata, methodName: propertyKey, target});
            }
        }
    }
}
```

### 교체
`wrapMethod` 는 AOP 로직(lazyDecorator.wrap)을 실행하여 AOP가 적용된 함수(wrappedMethod)를 생성합니다. 
이 함수는 WeakMap을 통해 캐시되어 성능을 최적화합니다.
이렇게 생성된 wrappedFn은 **[마킹]** 단계에서 만든 프록시 함수가 참조하는 `aopSymbol` 에 연결됩니다.

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
    // 원본 메서드, 데코레이터에 전달된 인자, 고유 심볼 조회
    const { originalFn, metadata, aopSymbol } = aopMetadata;

    const self = this;
    const wrappedFn = function (this: object, ...args: unknown[]) {
      const cache = self.wrappedMethodCache.get(this) || new WeakMap();
      const cached = cache.get(originalFn);
      if (cached) {
        return cached.apply(this, args);
      }

      // 클래스 인스턴스와 원본 메서드와 인자, 메서드 이름을 전달하고 캐시합니다.
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

    target[aopSymbol] ??= {};
    // 데코레이터의 프록시 함수를 wrappedFn으로 교체합니다.
    target[aopSymbol][methodName] = wrappedFn;
}
```

### 실행
애플리케이션 로직 어딘가에서 `someService.someMethod()` 를 실행하고, 해당 메서드에 AOP 데코레이터가 붙어있다면 **[마킹]** 단계에서 덮어쓴 프록시 함수가 먼저 실행됩니다.
프록시 함수는 `this[aopSymbol][methodName]` 을 호출하며, **[교체]** 단계에서 wrappedFn을 연결해 두었기 때문에 AOP 클래스가 실행됩니다.

아래 예제는 추후 구현하게 될 캐시 AOP 클래스의 실행 순서를 간략하게 표현한 코드입니다.

```typescript
@Aspect()
@Injectable()
export class CacheableAspect
    implements LazyDecorator<any, CacheableOption> {
    
    wrap({method, metadata: options}) {
        return (...args: any[]) => {
            console.log('AOP: Before original method'); // ('before' 로직)

            // '원본 함수'가 '스텁 함수' 내부에 매핑 (Closure)
            const result = method(...args);

            console.log('AOP: After original method'); // ('after' 로직)
            return result;
        };
    }
    
}
```

간단(?)하게 내부 동작 원리를 살펴보았으니 이제 구현만 하면 되겠습니다.

## 구현하기

[^1]: [@toss/nestjs-aop](https://github.com/toss/nestjs-aop)
[^2]: [MDN - Object.getOwnPropertyDescriptor()](https://developer.mozilla.org/ko/docs/Web/JavaScript/Reference/Global_Objects/Object/getOwnPropertyDescriptor)

