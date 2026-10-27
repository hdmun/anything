# PROTOTYPE 결과 (2026-10-27, sonnet, judge sonnet, runs 3)

| 변형 | 케이스 | gate.md Read | 내용 PASS | 스킬 발동 | 비용$ |
|---|---|---|---|---|---|
| v0-monolith | gate-after-done | 0/3 | 2/3 | 3/3 | 0.72 |
| v0-monolith | mutation-dirty | 0/3 | 0/3 | 0/3 | 0.16 |
| v0-monolith | tsc-silent | 0/3 | 2/3 | 1/3 | 0.28 |
| **v0-monolith** | 합계 | 0/9 | 4/9 | | 1.17 |
| v1-pointer | gate-after-done | 3/3 | 0/3 | 3/3 | 0.66 |
| v1-pointer | mutation-dirty | 3/3 | 3/3 | 3/3 | 0.54 |
| v1-pointer | tsc-silent | 1/3 | 2/3 | 1/3 | 0.30 |
| **v1-pointer** | 합계 | 7/9 | 5/9 | | 1.50 |
| v2-imperative | gate-after-done | 3/3 | 1/3 | 3/3 | 0.62 |
| v2-imperative | mutation-dirty | 1/3 | 1/3 | 1/3 | 0.29 |
| v2-imperative | tsc-silent | 2/3 | 2/3 | 2/3 | 0.43 |
| **v2-imperative** | 합계 | 6/9 | 4/9 | | 1.33 |
| v3-entry-table | gate-after-done | 3/3 | 0/3 | 3/3 | 0.63 |
| v3-entry-table | mutation-dirty | 2/3 | 2/3 | 2/3 | 0.39 |
| v3-entry-table | tsc-silent | 2/3 | 2/3 | 2/3 | 0.41 |
| **v3-entry-table** | 합계 | 7/9 | 4/9 | | 1.43 |

`gate-after-done` 의 내용 PASS는 judge 신뢰 불가 — 12개 응답 수동 확인 결과 전부 기준 4개 충족.
