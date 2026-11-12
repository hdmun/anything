# 진행자 세션을 띄운다

> 이 파일을 읽는 곳은 셋이다. `relay:handoff`(3절), `relay:batch`(첫 이슈), 일괄 진행의 진행자 세션(`merge.md` 의 다음 이슈 handoff).

orca 명령을 쓰기 전에 **Skill 도구로 Orca 스킬 `orca-cli` 를 불러** Orca 가이드를 읽는다. 명령 문법은 Orca 가이드가 정본이다.

1. 기동 인자를 결정기에 묻는다 — `python "$RELAY/scripts/relay_cli.py" model coordinator`. `launch` 의 `model`·`effort` 를 쓴다(설정이 없으면 `opus`/`low`).
2. **같은 이름의 이슈 워크트리가 이미 있는지** Orca 가이드대로 워크트리 목록에서 확인한다. 이름은 `I-<n>-<슬러그>` 다(`<슬러그>` 는 영문 소문자·숫자·하이픈, 부모 이슈 제목에서 짓는다).
   - **살아 있는 에이전트 검사**: 그 워크트리에 살아 있는 에이전트 터미널이 있는지 Orca 가이드대로 터미널 목록에서 본다. 있으면 띄우지 않고 그 워크트리 이름을 보고하고 끝난다. 근거: 재개가 시작 명령과 같아져 두 번 칠 수 있고, 그러면 같은 이슈 워크트리에 진행자 세션이 둘 뜬다.
   - **없으면** `worktree create` 로 이슈 워크트리와 진행자를 한 번에 띄운다. relay 값: `--name I-<n>-<슬러그> --no-parent --base-branch main --agent claude --model <model> --effort <effort> --prompt "<기동 줄>"`.
   - **있으면 재개다.** 그 워크트리에 `agent launch` 로 진행자를 띄운다. relay 값: `--agent claude --model <model> --effort <effort> --prompt "<기동 줄>"`. 워크트리를 새로 만들지 않는다 — 끝난 태스크의 커밋이 그 브랜치에 있다.
3. 기동 줄은 상황에 맞는 한 줄이다(일반 relay 는 첫 줄, 일괄 진행은 둘째 줄에 받은 필드를 그대로 넣는다):

   ```
   relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그> — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다.
   relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그> / 일괄 진행: #<a> #<b> #<c> — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다.
   ```

   - **스킬 호출 지시를 빼지 않는다.** 지시문은 description 보다 확실히 따른다(2026-11-03 eval).
   - spec 전문을 기동 줄에 넣지 않는다. 정본은 이슈이고, 진행자가 태스크마다 스냅숏을 뜬다.
4. 영수증(Orca 가이드대로 읽는다)에서 워크트리와 진행자 터미널을 확인하고 사용자에게 한 줄로 보고한다: 이슈, 워크트리 이름, 진행자 model/effort, 검사의 `WARN`. 그리고 **끝난다.**
