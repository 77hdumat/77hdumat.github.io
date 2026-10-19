---
title: 서민규
type: docs
bookToC: false
---

{{% resume %}}

<section class="r-hero">
<p class="r-eyebrow">Backend Engineer</p>
<h1 class="r-name">서민규</h1>
<p class="r-lead">새로운 기술을 겁내지 않고 실험하고, 도입하고, 팀에 정착시키는걸 좋아합니다. 고객에게 가치 있는 제품을 빠르게 전하는 일에 집중합니다.</p>
<div class="r-links">
<a href="mailto:77hdumat@gmail.com">77hdumat@gmail.com</a>
<a href="https://github.com/77hdumat" target="_blank" rel="noopener">GitHub</a>
<a href="https://www.linkedin.com/in/mingyu-seo/" target="_blank" rel="noopener">LinkedIn</a>
</div>
</section>

<div class="r-stats">
<div class="r-stat"><strong>81<small>배</small></strong><span>웹사이트 페이지 조회 처리량<br>82 req/s에서 6,640 req/s로</span></div>
<div class="r-stat"><strong>2.6<small>ms</small></strong><span>캐시 히트 p50 응답 시간<br>235ms에서 줄인 결과</span></div>
<div class="r-stat"><strong>90<small>%</small></strong><span>느린 원본 서비스 호출 감소<br>같은 부하, 캐시 적용 전후</span></div>
</div>

<h2 class="r-label">Experience</h2>

<div class="r-timeline">

<div class="r-item">
<div class="r-item-head">
<h3>식스샵</h3>
<p class="r-meta"><span>Backend Engineer</span><span>2022.05 ~ 현재</span></p>
</div>

- 식스샵 차세대 웹 빌더의 백엔드 개발을 맡고 있습니다.
- 에디터 MCP(Model Context Protocol)를 국내 최초로 도입해 AI 기반 자동화 환경을 만들고, 파트너의 개발 경험을 개선했습니다.
- GraphQL과 BFF로 프론트엔드 협업을 지원하고, 새로운 기술을 실험하고 도입해 팀에 정착시킵니다.
- DDD와 클린 아키텍처를 바탕으로 오래 유지할 수 있는 코드를 지향합니다.

<p class="r-tags"><span>TypeScript</span><span>NestJS</span><span>GraphQL</span><span>MongoDB</span><span>Redis</span><span>Spring</span><span>JPA</span><span>QueryDSL</span></p>

<div class="r-card">
<div class="r-card-head">
<h4>웹사이트, BFF 캐시 고도화</h4>
<span class="r-pill">2025.09 ~ 2025.12</span>
</div>

대형 고객사 이전을 앞둔 부하 테스트에서, 외부 호출을 모킹하면 300 TPS를 버티던 BFF가 리뷰 서비스 하나만 실제로 호출해도 p95 9.71초까지 느려졌습니다. 외부 서비스의 지연이 번지지 않도록 캐시 계층을 다시 설계했습니다.

<div class="r-compare">
<p class="r-compare-title">웹사이트 페이지 조회 처리량 (k6, 캐시 히트)</p>
<div class="r-bar-row"><span class="r-bar-label">이전</span><div class="r-bar"><i style="width:1.2%"></i></div><span class="r-bar-value">82 req/s</span></div>
<div class="r-bar-row is-after"><span class="r-bar-label">이후</span><div class="r-bar"><i style="width:100%"></i></div><span class="r-bar-value">6,640 req/s</span></div>
</div>

- `@toss/nestjs-aop` 기반 선언적 캐시 데코레이터(`@Cacheable`, `@CacheEvict`)로 비즈니스 로직에 섞인 캐시 코드 공통화
- 메모리(L1)와 Redis(L2) 계층형 캐시, SWR 패턴, 분산 락, 지터로 캐시 쇄도 방지 적용을 통해 **TPS 5.4배, 원본 호출 90% 감소**
- msgpack 직렬화와 zstd 압축으로 40KB 값의 **Redis 저장 크기 67% 감소로 비용 절감**
- 페이지 응답을 gzip Buffer로 캐시해 **p50 235ms에서 2.6ms로** 단축
- 33개 e2e 시나리오로 동시 요청과 SWR 동작 검증, 이관 후 대형 이벤트를 4대의 서버로 장애 없이 대응

<a class="r-more" href="/docs/server/nestjs/nestjs-cache-어디까지-활용하고-계신가요/">NestJS 캐시 어떻게 활용하고 계신가요?</a>
</div>
</div>

<div class="r-item">
<div class="r-item-head">
<h3>셀메이트</h3>
<p class="r-meta"><span>Backend Engineer</span><span>2020.05 ~ 2021.10</span></p>
</div>

- 통합 이커머스 관리 솔루션의 고객 기술지원을 맡았습니다.
- 고객 문의의 원인을 찾아 해결하며 고객 만족도 향상에 기여했습니다.
- CX 팀과 협업해 VOC를 바탕으로 사용자 중심의 기능을 빠르게 기획하고 개선했습니다.

<p class="r-tags"><span>ASP</span></p>
</div>

</div>

<h2 class="r-label">Open Source</h2>

<div class="r-card r-card-oss">
<div class="r-card-head">
<h4>nestjs-cachex</h4>
<span class="r-pill">2026.03 ~ 현재</span>
</div>

사내에서 만든 캐시 모듈을 다듬어 공개한 NestJS 캐시 라이브러리입니다. 선언적 데코레이터, SWR, 분산 락(Single-flight), 계층형 캐시, msgpack과 zstd 압축을 지원합니다.

<div class="r-links r-links-sm">
<a href="https://github.com/77hdumat/nestjs-cachex" target="_blank" rel="noopener">GitHub</a>
<a href="https://www.npmjs.com/package/nestjs-cachex" target="_blank" rel="noopener">npm</a>
</div>
</div>

<h2 class="r-label">Writing</h2>

<a class="r-post" href="/docs/server/nestjs/nestjs-cache-어디까지-활용하고-계신가요/">
<strong>NestJS 캐시 어떻게 활용하고 계신가요?</strong>
<span>선언적 캐시 데코레이터부터 SWR, 압축, k6 부하 테스트까지</span>
</a>

{{% /resume %}}
