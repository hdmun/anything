# 도메인 문서

엔지니어링 스킬이 코드베이스를 살펴볼 때 이 저장소의 도메인 문서를 어떻게 읽어야 하는지 적는다.

## 살펴보기 전에 이것을 읽는다

- 저장소 루트의 **`GLOSSARY.md`**, 또는
- 저장소 루트에 **`GLOSSARY-MAP.md`** 가 있으면 그것: 컨텍스트마다 `GLOSSARY.md` 하나씩을 가리킨다. 주제와 관련된 것을 모두 읽는다.
- **`docs/adr/`**: 작업하려는 영역에 닿는 ADR 을 읽는다. 멀티 컨텍스트 저장소라면 컨텍스트 범위의 결정이 담긴 `src/<context>/docs/adr/` 도 확인한다.

이 파일들 중 없는 것이 있으면 **아무 말 없이 진행한다**. 없다고 지적하지 않고, 미리 만들자고 제안하지도 않는다. `/domain-modeling` 스킬(`/grill-with-docs` 와 `/improve-codebase-architecture` 를 거쳐 쓰인다)이 용어나 결정이 실제로 정해질 때 그때그때 만든다.

## 파일 구조

단일 컨텍스트 저장소(대부분의 저장소):

```
/
├── GLOSSARY.md
├── docs/adr/
│   ├── 0001-event-sourced-orders.md
│   └── 0002-postgres-for-write-model.md
└── src/
```

멀티 컨텍스트 저장소(루트에 `GLOSSARY-MAP.md` 가 있음):

```
/
├── GLOSSARY-MAP.md
├── docs/adr/                          ← 시스템 전체 결정
└── src/
    ├── ordering/
    │   ├── GLOSSARY.md
    │   └── docs/adr/                  ← 컨텍스트별 결정
    └── billing/
        ├── GLOSSARY.md
        └── docs/adr/
```

## 용어집의 어휘를 쓴다

출력에서 도메인 개념을 부를 때(이슈 제목, 리팩터링 제안, 가설, 테스트 이름) `GLOSSARY.md` 에 정의된 용어를 쓴다. 용어집이 피하라고 명시한 동의어로 바꿔 쓰지 않는다.

필요한 개념이 아직 용어집에 없다면 그것은 신호다. 프로젝트가 쓰지 않는 말을 지어내고 있거나(다시 생각한다), 실제로 빈 곳이 있다(`/domain-modeling` 용으로 적어 둔다).

## ADR 과 어긋나면 드러낸다

출력이 기존 ADR 과 어긋나면 조용히 덮어쓰지 말고 분명하게 드러낸다:

> _ADR-0007(event-sourced orders)과 어긋나지만, 다시 열어 볼 만하다. 이유는…_
