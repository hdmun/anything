---
name: handoff
description: 설계 세션에서 다 쓴 구현 이슈를 relay 진행자 세션에 넘길 때 사용한다. 머신 점검(doctor)과 기동 전 검사(handoff-check)를 돌리고, 통과하면 이슈 워크트리와 진행자 세션을 한 번에 띄운 뒤 끝난다. "relay:handoff", "구현 이슈를 relay 로 넘겨줘", "relay 로 이 이슈 시작해줘"처럼 relay 를 명시해 구현 이슈를 넘기라고 할 때 쓴다. relay 없이 작업을 다른 워크트리나 에이전트에 통째로 맡기는 단순 위임(감독·리뷰 없음)에는 쓰지 않는다 — 그것은 Orca 스킬 `orca-cli` 의 handoff 다.
---

# relay:handoff

설계 세션이 구현 이슈를 **진행자 세션**에 넘기고 끝나는 스킬이다(ADR 0005). 진행자 세션은 Run 을 소유한 최상위 코디네이터로 떠서 이슈의 태스크를 모두 돌고 PR 을 연다. 설계 세션은 Run 을 만들지 않고, 감독하지 않으며, relay 스킬을 읽지 않는다.

## 불변식

- orca 명령을 쓰기 전에 **Skill 도구로 Orca 스킬 `orca-cli` 를 불러** Orca 가이드를 읽는다. 이 스킬은 명령 문법을 적지 않는다 — 동사 이름과 relay 가 정한 값만 적는다. 충돌하면 Orca 가이드가 옳다.
- **두 검사를 끝까지 돌려 실패를 한 번에 보고한다.** `FAIL` 이 하나라도 있으면 진행자 세션을 띄우지 않는다.
- 진행자 세션은 이슈 하나에 하나다. 띄운 뒤에는 설계 세션이 끝난다 — Run 을 감독하거나 진행자에게 답하지 않는다. 진행자가 멈추면 멈춤 보고(이슈 코멘트)가 남고, 사람이 이슈를 고친 뒤 같은 이슈로 다시 handoff 한다.
- `$RELAY` 는 이 스킬을 불러왔을 때 표시되는 *Base directory* 에서 두 단계 위(플러그인 루트)다 — `python "$RELAY/scripts/relay_cli.py" --help`.

## 1. 구현 이슈를 쓴다

이슈가 없거나 템플릿을 따르지 않으면 `relay:spec` 으로 쓴다.

## 2. 두 검사를 돌린다

둘 다 끝까지 돌리고 결과를 모아 사용자에게 한 번에 보여 준다. 하나가 실패해도 다른 하나를 건너뛰지 않는다.

```bash
python "$RELAY/scripts/relay_cli.py" doctor                        # 머신 점검
python "$RELAY/scripts/relay_cli.py" handoff-check --issue <이슈 URL>  # 기동 전 검사
```

- **`doctor`** — 이 머신의 상태(에이전트 CLI·설정 파일·Orca 스킬·플러그인 사본). `FAIL plugin` 이면 이 세션이 읽은 스킬이 설치본보다 낡았다 — `/reload-plugins` 나 세션 재시작을 요청하고 멈춘다.
- **`handoff-check`** — 이 이슈 하나: 태스크 수 ≤5, 태스크마다 템플릿 필수 절(변경 대상 파일, 인수 조건의 `게이트 명령:`), 구현 이슈의 「사람이 할 일」 절, 작성자 권한. 마지막 `task` 줄들이 진행자가 돌 태스크다. 종료코드 2 는 이슈를 읽지 못한 것이다(URL·`gh` 인증·트래커 접근).
- `FAIL` 이 하나라도 있으면 진행자를 띄우지 않는다. 각 `→` 줄(고치는 방법)을 그대로 전하고, 사람이 고친 뒤 두 검사를 다시 돌린다.
- 사람 판단이 필요한 `WARN`(미검증 버전 `WARN version:*` 등)은 여기서 사람과 정한다. 미검증 버전이면 `relay_cli.py smoke --dir <trust 등록된 디렉터리>` 를 권하고, smoke 가 실패한 CLI 로는 띄우지 않는다. 그 밖의 `WARN` 은 보고만 하고 진행한다(진행자는 PR 본문 `warnings:` 에 적는다).

## 3. 진행자 세션을 띄운다

1. 기동 인자를 결정기에 묻는다 — `python "$RELAY/scripts/relay_cli.py" model coordinator`. `launch` 의 `model`·`effort` 를 쓴다(설정이 없으면 `opus`/`low`).
2. **같은 이름의 이슈 워크트리가 이미 있는지** Orca 가이드대로 워크트리 목록에서 확인한다. 이름은 `I-<n>-<슬러그>` 다(`<슬러그>` 는 영문 소문자·숫자·하이픈, 부모 이슈 제목에서 짓는다).
   - **없으면** `worktree create` 로 이슈 워크트리와 진행자를 한 번에 띄운다. relay 값: `--name I-<n>-<슬러그> --no-parent --base-branch main --agent claude --model <model> --effort <effort> --prompt "<기동 줄>"`.
   - **있으면 재개다.** 그 워크트리에 `agent launch` 로 진행자를 띄운다. relay 값: `--agent claude --model <model> --effort <effort> --prompt "<기동 줄>"`. 워크트리를 새로 만들지 않는다 — 끝난 태스크의 커밋이 그 브랜치에 있다.
3. 기동 줄은 이 한 줄이다:

   ```
   relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그> — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다.
   ```

   - **스킬 호출 지시를 빼지 않는다.** 지시문은 description 보다 확실히 따른다(2026-11-03 eval).
   - spec 전문을 기동 줄에 넣지 않는다. 정본은 이슈이고, 진행자가 태스크마다 스냅숏을 뜬다.
4. 영수증(Orca 가이드대로 읽는다)에서 워크트리와 진행자 터미널을 확인하고 사용자에게 한 줄로 보고한다: 이슈, 워크트리 이름, 진행자 model/effort, 검사의 `WARN`. 그리고 **끝난다.**

## Orca 기본과 다른 점

| relay 가 하는 것 | Orca 기본 | 근거 |
|---|---|---|
| `--base-branch main` 을 늘 준다 | 생략하면 저장소의 기본 base 를 쓴다 | `defaultBaseRef` 가 `null` 인 저장소에서는 엉뚱한 지점에서 분기된다(ADR 0010) |
| `--no-parent` 를 준다 | 부르는 쪽 워크트리를 부모로 기록한다 | 이슈 워크트리는 설계 세션의 하위 작업이 아니라 독립된 Run 이다 |
| 진행자에 `--model`·`--effort` 를 늘 준다 (`model coordinator`) | 사용자가 고르지 않았으면 생략한다 | 잦고 긴 진행 루프는 effort 를 낮춰 둔다. 기본값은 2026-11-02 사용자 결정, 바꾸려면 모델 설정 파일 |
