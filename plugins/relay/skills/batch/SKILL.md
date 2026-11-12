---
name: batch
description: 'relay 일괄 진행을 시작하거나 재개한다. 사람이 /relay:batch <구현 이슈 URL> 로만 부른다. 진행 목록을 만들고 모든 이슈를 검사한 뒤 첫 이슈의 진행자 세션을 띄우고 끝난다. 구현 이슈 하나만 PR 까지 넘기는 일은 relay:handoff 다.'
disable-model-invocation: true
---

<!-- disable-model-invocation: true 이유: 연쇄하는 진행자 세션이 이 스킬을 불러 진행 목록을 도중에 다시 만드는 일을 막는다. 잘못 발동하면 사람 확인 없는 머지가 된다. -->

# relay:batch

## 불변식

- orca 명령을 쓰기 전에 **Skill 도구로 Orca 스킬 `orca-cli` 를 불러** Orca 가이드를 읽는다. 이 스킬은 명령 문법을 적지 않는다 — 동사 이름과 relay 가 정한 값만 적는다. 충돌하면 Orca 가이드가 옳다.
- **검사를 끝까지 돌려 실패를 한 번에 보고한다.** `FAIL` 이 하나라도 있으면 아무 이슈도 띄우지 않는다.
- **순서를 보여 준 뒤 확인을 기다리지 않는다.**
- **첫 이슈를 띄우면 끝난다. 감독하지 않는다.** 그 뒤는 진행자 세션들이 `references/merge.md` 대로 한다.
- `$RELAY` 는 이 스킬을 불러왔을 때 표시되는 *Base directory* 에서 두 단계 위(플러그인 루트)다 — `python "$RELAY/scripts/relay_cli.py" --help`.

## 순서

1. `python "$RELAY/scripts/relay_cli.py" doctor` 한 번. `FAIL` 이면 `→` 줄과 함께 보고하고 끝난다. `WARN` 처리는 `relay:handoff` 2절과 같다(미검증 버전은 smoke 를 권하고 사람과 정한다. 사람이 이 자리에 있다).
2. `python "$RELAY/scripts/relay_cli.py" batch-plan --issue <URL>`. 종료코드 1 이면 모든 `FAIL` 과 `→` 줄을 그대로 보고하고 끝난다. 2 면 입력 오류를 보고하고 끝난다.
3. **살아 있는 에이전트 검사**: 진행 목록의 이슈마다 이슈 워크트리(`I-<n>-` 로 시작하는 이름)가 있는지 Orca 가이드대로 워크트리 목록에서 본다. 있으면 그 워크트리에 살아 있는 에이전트 터미널이 있는지 본다. 하나라도 있으면 시작하지 않고 그 워크트리들을 보고하고 끝난다.
4. 한 줄로 보여 준다: `일괄 진행: #a #b #c — 첫 이슈 #a 를 띄운다`.
5. 첫 이슈를 `$RELAY/skills/handoff/references/launch.md` 절차로 띄운다. 기동 줄은 일괄 진행 줄이고, 필드는 `batch-plan` 출력의 `기동 줄 필드:` 값 그대로다. 첫 이슈의 워크트리가 이미 있으면 `launch.md` 의 재개 분기다(살아 있는 에이전트 검사는 3 에서 했다).
6. 영수증(Orca 가이드대로 읽는다)을 한 줄로 보고하고 끝난다.

## 재개

재개는 같은 명령이다. `batch-plan` 이 진행 목록을 매번 새로 만들고, 머지된 이슈는 닫혀서 빠진다. 멈춘 이슈는 이슈 워크트리가 남아 있어 재개로 뜬다.

## 사람용 안내

머지·연쇄·멈춤·완료 보고는 진행자 세션이 `skills/relay/references/merge.md` 대로 한다. 성공하면 Orca 에 아무것도 남지 않고, 멈추면 이슈 워크트리가 남고 미읽음이 뜬다.
