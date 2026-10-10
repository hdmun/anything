---
status: accepted
---

# 역할별 model·effort 는 설정 파일 두 겹으로 정하고, 정본 해석은 코드가 한다

모델을 바꾸려면 리뷰어(codex)는 `~/.codex/config.toml` 의 `model`, 구현자(agy)는 손댈 곳이 없고, Claude 세션은 `/model` 을 직접 쳐야 했다. 역할 배정이 한곳에 모여 있지 않았고, 리뷰어는 codex 를 평소 용도로 쓰는 모델에 묶여 있었다. 그래서 `~/.relay/models.json`(사용자 전역)과 `<저장소>/.ai/relay-models.json`(저장소별)을 필드 단위로 겹치는 설정을 둔다. 우선순위·검증·기본값으로의 복귀는 `relaylib/models.py` 가 정본이다 (ADR 0001) — SKILL.md 는 결정기(`model <역할>`, `models`)가 돌려준 값을 따를 뿐 우선순위를 다시 계산하지 않는다.

**리뷰어 모델은 codex `config.toml` 의 `model` 로 되돌아가지 않는다.** codex 를 평소에 쓰는 모델과 리뷰어 모델은 목적이 다르다. 설정 파일에 `reviewer.model` 이 없으면 기동을 거부한다(`human / reviewer_model_unset`). `config.toml` 은 Orca 가 codex 준비를 감지하는 사전 조건 키만 확인한다.

## Considered Options

- **사용자 전역 파일만**: 팀이 모델을 통일할 수 없다. 기각.
- **저장소 파일만**: 모델은 계정·쿼터에 따른 개인 선호라 저장소마다 반복해야 한다. 기각.
- **리뷰어만 codex `config.toml` 폴백 유지**: 설정 없이도 돌지만 평소 용도 모델을 낮추면 리뷰어도 함께 낮아지는 결합이 남는다. 기각.
- **SKILL.md 표를 고치는 방식 유지**: 플러그인 업데이트가 사용자 선택을 덮고, 버전 문자열이 SKILL.md 에 되돌아온다. 기각.

## Consequences

- 모델 버전은 설정 파일에만 적힌다. 플러그인 파일에는 여전히 계열만 있다 (CONTEXT.md 「모델 계열」「모델 설정」).
- 설계자·진행자는 Claude 세션이라 강제할 수 없다. 결정기는 `claude --model … --effort …` 를 안내만 하고, 진행 세션이 사용자에게 전한다.
- agy 는 `--model <기본 이름> --effort <레벨>` 을 받고, 레벨이 이름에 든 모델(`…-low`)에 `--effort` 를 같이 주면 거부한다. 거부되면 기동 실패 예산을 쓰므로 `agy models` 출력과 대조해 기동 전에 `human / agy_model_invalid` 로 막는다 (실측 agy 1.3.3, 2026-10-11).
- model 값은 셸 명령줄에 그대로 들어가므로 문자 집합(`^[A-Za-z0-9][A-Za-z0-9._:/-]*$`)을 코드가 강제한다.
- agy 명령은 `$null=1; agy [--model …] [--effort …]` 로, 맨 앞 토큰이 `$null=1;` 인 한 Orca 가 에이전트 시작 경로로 가로채지 않는다. 인자가 붙은 형태의 `tui-idle` 통과는 smoke 로 실측해 `verified-cli.json` 에 등록한다.
