# 모델·effort 설정 파일

> 이 파일은 SKILL.md의 단계 절차 중 일부다. SKILL.md의 불변식과 함께 읽는다. (역할 표의 상세)

**모델·effort 설정 파일** — 두 파일을 필드 단위로 겹친다(뒤가 앞을 덮는다). 둘 다 없으면 위 표대로 동작한다.

| 순서 | 파일 | 용도 |
|---|---|---|
| 1 | `~/.relay/models.json` | 사용자 전역 — 계정·쿼터에 따른 개인 선호 |
| 2 | `<저장소>/.ai/relay-models.json` | 저장소별 — 팀 통일 또는 이 저장소만 다르게 |

```json
{ "designer":    { "model": "opus",   "effort": "high" },
  "coordinator": { "model": "opus",   "effort": "low" },
  "implementer": { "model": "gemini-3.8-flash", "effort": "low" },
  "reviewer":    { "effort": "high" },
  "judge":       { "model": "opus",   "effort": "high" } }
```

- 역할은 `designer`·`coordinator`·`implementer`·`reviewer`·`judge`. 필드는 `model`·`effort`, 둘 다 생략할 수 있다(생략 = 기본 동작).
- **지금 어떤 값이 적용되는지는 `relay_cli.py models`에 묻는다.** 역할별 `model <역할>` 결정기가 기동에 쓸 값을 돌려준다. 이 문서에서 우선순위를 다시 계산하지 않는다.
- 진행자 세션은 `relay:handoff` 가 띄운다. `model coordinator`의 `launch`가 주는 `model`·`effort`를 handoff 가 진행자 기동의 `--model`·`--effort`에 **그대로** 준다. 설정이 없으면 `opus`/`low`이다.
- 판정 서브에이전트는 진행자가 Agent 도구로 띄운다. `model judge` 의 `model`·`effort` 를 Agent 도구 인자에 그대로 준다. 기본 `opus`/`high`. Agent 도구는 모델 별칭(`opus`·`sonnet`·`haiku`·`fable`)만 받으므로 다른 값이면 `human / judge_model_invalid` 다.
- 설계자는 사람이 연 세션이라 플러그인이 모델을 바꿀 수 없다. `model designer`가 `command`(예: `claude --model opus --effort high`)를 알려 주면 **사용자에게 전하는 것까지**가 일이다.
- 구현자의 `model`은 `agy models`의 기본 이름(예: `gemini-3.8-flash`)이고 effort는 따로 준다. `gemini-3.8-flash-low`처럼 effort가 이름에 든 모델에 `effort`를 함께 주면 agy가 거부한다 — 결정기가 `human / agy_model_invalid`로 미리 막는다.
- **리뷰어의 `model`은 기본값이 없다.** 설정 파일에 없으면 `human / reviewer_model_unset`이다. `~/.codex/config.toml`의 `model`(평소 용도)은 리뷰어 모델로 쓰지 않는다 — codex를 평소에 어떤 모델로 쓰든 리뷰어는 설정 파일 값으로 뜬다. `config.toml`은 사전 조건 키(아래 리뷰 워커 절)만 본다.
