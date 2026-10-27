# PROTOTYPE — references 읽기 지시 준수 확인 (버리는 코드)

wayfinder 티켓 "온디맨드 references 읽기 지시 준수 확인"(hdmun/anything#4)을 답하기 위한 일회용 실험. main에 머지하지 않는다.

질문: SKILL.md의 (f) 게이트 단계를 `references/gate.md`로 빼면 Sonnet 진행자가 그 파일을 실제로 Read 하는가? 어떤 지시 형태가 지켜지는가?

| 변형 | (f) 자리에 남는 것 |
|---|---|
| v0-monolith | 현재 SKILL.md 그대로 (대조군) |
| v1-pointer | `상세: references/gate.md` 한 줄 |
| v2-imperative | "이 단계에 들어서면 먼저 Read 한다. 읽기 전에는 판정하지 않는다" |
| v3-entry-table | v2 + SKILL.md 맨 앞의 "단계 진입표"(단계 → 먼저 읽을 파일) |

실행: `bash build.sh` → `bash run.sh` (변형 4 × 케이스 3 × runs 3 = sonnet 36회)
