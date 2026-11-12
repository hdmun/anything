> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/79
> updatedAt: 2026-11-11T09:54:43Z

# relay:batch 스킬과 머지 절차 문서

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

**일괄 진행**: 사람이 `/relay:batch <구현 이슈 URL>` 을 치면, 그 이슈의 진행 목록(blocking 으로 이어진 열린 구현 이슈)을 차례로 PR 머지와 이슈 닫힘까지 사람 없이 옮긴다. 이어 가는 방식은 연쇄 handoff 다(relay ADR 0011): 머지에 성공한 진행자 세션이 다음 구현 이슈의 진행자 세션을 띄우고, 마지막 행동으로 자기 이슈 워크트리를 지운다. 구현 이슈 하나가 멈추면 진행 목록의 나머지도 시작하지 않는다. 재개는 같은 시작 명령을 다시 치는 것이다.

이 태스크는 **문서**를 쓴다. 쓰는 명령은 이미 있다.

| 명령 | 하는 일 | 만든 곳 |
|---|---|---|
| `batch-plan --issue <URL>` | 진행 목록·순서·모든 이슈 검사(검사기). 출력 마지막 줄이 `기동 줄 필드: / 일괄 진행: #a #b` | 이 이슈 앞 태스크 |
| `merge-check --issue <URL> --worktree <dir>` | 머지 조건 1~3(검사기) | 이 이슈 앞 태스크 |
| `batch-report --issue <URL> --list "<필드 값>" --out <파일>` | 완료 보고 본문(결정기) | 이 이슈 앞 태스크 |
| `publish push\|pr\|comment` | 유출 검사 후 푸시·PR·코멘트(결정기, `stop` 이면 내보내지 않음). `publish pr` 은 열린 PR 이 있으면 `exists` | 「relay 일괄 진행 준비」 |
| `handoff-check` | 기동 전 검사(「사람이 할 일」 절 포함) | 「relay 일괄 진행 준비」 |

relay 문서의 규칙(어기면 `test_docs.py` 가 실패한다):

- orca 명령 문법을 적지 않는다. Orca 가이드가 정본이다(ADR 0003). 동사 이름과 relay 가 정한 값만 적는다. `orca worktree …`·`orca terminal …` 같은 글자가 문서에 있으면 실패한다.
- 정책 판정은 `relay_cli.py` 가 한다(ADR 0001). 문서에서 다시 계산하지 않는다.
- 금지 토큰(`test_docs.py` `FORBIDDEN`)을 쓰지 않는다. 예: 낱말 `release`·`retain`, `nested-depth`, `기동 실패 예산`.
- 문서에 실제 IP·PC 이름·웹훅 URL 을 쓰지 않는다.

결정 출처: [#52](https://github.com/hdmun/anything/issues/52) 머지 조건, [#53](https://github.com/hdmun/anything/issues/53) 머지 방법, [#57](https://github.com/hdmun/anything/issues/57) 연쇄 handoff·워크트리 삭제, [#58](https://github.com/hdmun/anything/issues/58) 멈춤·재개, [#59](https://github.com/hdmun/anything/issues/59) 스킬 위치·기동 줄·규칙 예외, [#60](https://github.com/hdmun/anything/issues/60) 6절 PR 본문 사본, [#61](https://github.com/hdmun/anything/issues/61) 완료 보고·워크트리를 남기는 경우, [#68](https://github.com/hdmun/anything/issues/68) 자기 워크트리 삭제 실측, [#69](https://github.com/hdmun/anything/issues/69) 머지 재시도 한도 없음.

## 범위 밖 (건드리지 말 것)

- `scripts/` 아래 코드: 앞 태스크와 「relay 일괄 진행 준비」에서 끝났다. 문서에 맞추려고 코드를 고치지 않는다(어긋나면 `ask`).
- `plugins/relay/CONTEXT.md`, `plugins/relay/docs/adr/`: 이미 반영됐다.
- eval 케이스(`plugins/relay/evals/`) 수정과 실행. 일반 기동 줄은 바꾸지 않으므로 eval 프롬프트는 그대로 맞는다.
- 자동 머지 뒤 되돌리기(revert), 병렬 실행, `ready-for-agent` 라벨 감시: 지도에서 범위 밖으로 정했다.
- `.claude-plugin/marketplace.json`, Orca 설정.

## 변경 대상 파일

- `plugins/relay/skills/batch/SKILL.md` — 신규
- `plugins/relay/skills/handoff/references/launch.md` — 신규
- `plugins/relay/skills/handoff/SKILL.md` — 수정
- `plugins/relay/skills/relay/references/merge.md` — 신규
- `plugins/relay/skills/relay/references/finish.md` — 수정
- `plugins/relay/skills/relay/references/stop.md` — 수정
- `plugins/relay/skills/relay/references/start.md` — 수정
- `plugins/relay/skills/relay/SKILL.md` — 수정
- `plugins/relay/skills/spec/SKILL.md` — 수정
- `plugins/relay/tests/test_docs.py` — 수정
- `plugins/relay/.claude-plugin/plugin.json` — 수정
- `plugins/relay/README.md` — 수정
- `agent-rules/project/20-git.md` — 수정
- `AGENTS.md` — 수정 (`sh agent-rules/build.sh` 가 다시 만든 결과만)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

기동 줄 두 가지. 첫 줄(일반)은 지금 `skills/handoff/SKILL.md` 에 있는 줄과 글자까지 같다. 둘째 줄이 일괄 진행이다.

```
relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그> — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다.
relay: 구현 이슈 <이슈 URL> / 슬러그: <슬러그> / 일괄 진행: #<a> #<b> #<c> — Skill 도구로 relay 스킬을 먼저 부르고 그 절차로 진행한다.
```

- `일괄 진행:` 필드에는 같은 저장소 이슈 번호를 진행 목록 순서대로 적고, 자기 이슈도 넣는다. 진행자 세션은 다음 handoff 때 이 필드를 **그대로** 넘긴다.
- 진행자 세션은 이 필드가 있을 때만 머지하고 다음 이슈를 handoff 한다.

`skills/batch/SKILL.md` 머리말:

```
---
name: batch
description: '<한 줄 — 아래 동작 명세 3>'
disable-model-invocation: true
---
```

머지 명령(값은 relay 가 정한다):

```
gh pr merge <PR> --merge --match-head-commit <게이트를 돌린 HEAD SHA> --subject "Merge branch '<브랜치>'" --body "<PR URL>"
git -C <worktree> push origin --delete <브랜치>
```

## 동작 명세

### 정상 경로

**1. `skills/handoff/references/launch.md` (신규) — 진행자 세션을 띄우는 공유 절차**

- 첫머리: 이 파일을 읽는 곳은 셋이다. `relay:handoff`(3절), `relay:batch`(첫 이슈), 일괄 진행의 진행자 세션(`merge.md` 의 다음 이슈 handoff).
- 지금 `skills/handoff/SKILL.md` 「## 3. 진행자 세션을 띄운다」의 1~4 를 옮긴다(`model coordinator` → 같은 이름의 이슈 워크트리 확인 → `worktree create` 또는 `agent launch` → 영수증 보고).
- 2 의 「있으면 재개다」 분기 앞에 **살아 있는 에이전트 검사**를 넣는다: 그 워크트리에 살아 있는 에이전트 터미널이 있는지 Orca 가이드대로 터미널 목록에서 본다. 있으면 띄우지 않고 그 워크트리 이름을 보고하고 끝난다. 근거: 재개가 시작 명령과 같아져 두 번 칠 수 있고, 그러면 같은 이슈 워크트리에 진행자 세션이 둘 뜬다.
- 3 의 기동 줄: 위 「시그니처」의 두 줄을 이 순서로 적는다(첫 줄이 일반). 일반 relay 는 첫 줄, 일괄 진행은 둘째 줄에 받은 필드를 그대로 넣는다. 스킬 호출 지시를 빼지 않는다는 문장과 spec 전문을 넣지 않는다는 문장은 그대로 옮긴다.
- orca 명령을 쓰기 전에 Skill 도구로 `orca-cli` 를 부른다는 문장을 둔다.

**2. `skills/handoff/SKILL.md` (수정)**

- 「## 3. 진행자 세션을 띄운다」 본문을 이렇게 줄인다: "`references/launch.md` 를 Read 하고 그 절차대로 한다. 기동 줄은 일반 줄(일괄 진행 필드 없음)이다."
- 「Orca 기본과 다른 점」 표, 불변식, 1·2절, description 은 그대로 둔다.

**3. `skills/batch/SKILL.md` (신규) — `relay:batch`**

- `description`(작은따옴표로 감싼 한 줄): relay 일괄 진행을 시작하거나 재개한다. 사람이 `/relay:batch <구현 이슈 URL>` 로만 부른다. 진행 목록을 만들고 모든 이슈를 검사한 뒤 첫 이슈의 진행자 세션을 띄우고 끝난다. 구현 이슈 하나만 PR 까지 넘기는 일은 `relay:handoff` 라고 적는다.
- `disable-model-invocation: true` 근거 한 줄: 연쇄하는 진행자 세션이 이 스킬을 불러 진행 목록을 도중에 다시 만드는 일을 막는다. 잘못 발동하면 사람 확인 없는 머지가 된다.
- 불변식:
  - orca 명령을 쓰기 전에 Skill 도구로 `orca-cli` 를 불러 Orca 가이드를 읽는다.
  - 검사를 끝까지 돌려 실패를 한 번에 보고한다. `FAIL` 이 하나라도 있으면 아무 이슈도 띄우지 않는다.
  - 순서를 보여 준 뒤 확인을 기다리지 않는다.
  - 첫 이슈를 띄우면 끝난다. 감독하지 않는다. 그 뒤는 진행자 세션들이 `merge.md` 대로 한다.
  - `$RELAY` 정의(Base directory 에서 두 단계 위).
- 순서:
  1. `python "$RELAY/scripts/relay_cli.py" doctor` 한 번. `FAIL` 이면 `→` 줄과 함께 보고하고 끝난다. `WARN` 처리는 `relay:handoff` 2절과 같다(미검증 버전은 smoke 를 권하고 사람과 정한다. 사람이 이 자리에 있다).
  2. `python "$RELAY/scripts/relay_cli.py" batch-plan --issue <URL>`. 종료코드 1 이면 모든 `FAIL` 과 `→` 줄을 그대로 보고하고 끝난다. 2 면 입력 오류를 보고하고 끝난다.
  3. 살아 있는 에이전트 검사: 진행 목록의 이슈마다 이슈 워크트리(`I-<n>-` 로 시작하는 이름)가 있는지 Orca 가이드대로 워크트리 목록에서 본다. 있으면 그 워크트리에 살아 있는 에이전트 터미널이 있는지 본다. 하나라도 있으면 시작하지 않고 그 워크트리들을 보고하고 끝난다.
  4. 한 줄로 보여 준다: `일괄 진행: #a #b #c — 첫 이슈 #a 를 띄운다`.
  5. 첫 이슈를 `$RELAY/skills/handoff/references/launch.md` 절차로 띄운다. 기동 줄은 일괄 진행 줄이고, 필드는 `batch-plan` 출력의 `기동 줄 필드:` 값 그대로다. 첫 이슈의 워크트리가 이미 있으면 `launch.md` 의 재개 분기다(살아 있는 에이전트 검사는 3 에서 했다).
  6. 영수증을 한 줄로 보고하고 끝난다.
- 「재개」 한 단락: 재개는 같은 명령이다. `batch-plan` 이 진행 목록을 매번 새로 만들고, 머지된 이슈는 닫혀서 빠진다. 멈춘 이슈는 이슈 워크트리가 남아 있어 재개로 뜬다.
- 사람용 한 단락: 머지·연쇄·멈춤·완료 보고는 진행자 세션이 `skills/relay/references/merge.md` 대로 한다. 성공하면 Orca 에 아무것도 남지 않고, 멈추면 이슈 워크트리가 남고 미읽음이 뜬다.

**4. `skills/relay/references/merge.md` (신규) — 기동 줄에 `일괄 진행:` 이 있을 때만**

머리 문장: 이 파일은 SKILL.md 의 단계 절차 중 일부다(다른 references 와 같은 형식). 들어오는 곳은 `finish.md` 다: `publish pr` 이 `created` 또는 `exists` 를 냈고 기동 줄에 `일괄 진행:` 이 있을 때.

1. **머지 조건**: `python "$RELAY/scripts/relay_cli.py" merge-check --issue <구현 이슈 URL> --worktree <worktree>`. 종료코드 1 이면 멈춤 보고(PR 은 연 채) 「머지 조건 어긋남: <FAIL 검사 이름들>」 — (h).
   - 머지를 막지 않는 것(기록만): 판정 `dismiss`·`accept`(PR 본문 「기각한 지적」), `MINOR` 만 남은 리뷰(「남은 MINOR」), doctor `WARN`(`warnings:`), 도중의 사람 개입 이력.
2. **머지 직전**(횟수 제한 없음):
   1. `git -C <worktree> fetch origin main`. `origin/main` 이 HEAD 의 조상이 아니면 `git -C <worktree> rebase origin/main`. 충돌이면 `git -C <worktree> rebase --abort` 뒤 멈춤 보고 「main 과 충돌: <파일>」. 충돌 해결을 구현자에게 맡기지 않는다(리뷰를 거치지 않은 코드가 된다).
   2. rebase 했으면 `publish push --worktree <worktree> --force-with-lease`. `stop` 이면 멈춤 보고. main 은 어떤 경우에도 force push 하지 않는다.
   3. 지금 HEAD SHA 와 `origin/main` SHA(= base)를 적어 둔다. 모든 태스크 스냅숏의 「인수 조건」 `게이트 명령:` 을 `gate.md`(f) 의 방법대로 돌린다. main 이 그대로여도 돌린다(앞 태스크의 게이트는 그 시점에만 통과했다). 의존성 매니페스트·lockfile 이 바뀌었으면 의존성을 먼저 동기화한다. 실패하면 멈춤 보고 「합친 결과 게이트 실패」.
   4. `git -C <worktree> fetch origin main`. `origin/main` 이 3 의 base 와 다르면 1 로 돌아간다. 같으면 위 「시그니처」의 `gh pr merge` 를 3 의 HEAD SHA 로 부른다. 실패하면 멈춤 보고 「gh 머지 실패: <첫 줄>」. squash·rebase merge, `--auto`, `--delete-branch` 는 쓰지 않는다. `--delete-branch` 는 gh 2.96 에서 이슈 워크트리 안의 main checkout 이 실패해 원격 브랜치도 지우지 못한다.
3. **머지 뒤 확인**:
   1. 머지 커밋(`gh pr view <PR> --json mergeCommit`)의 첫 부모를 fetch 뒤 `git rev-parse <머지 커밋>^1` 로 본다. 2-3 의 base 와 다르면 머지 커밋을 detached 로 체크아웃해 모든 태스크의 게이트를 다시 돈다. 실패하면 **main 깨짐** 멈춤 보고: 이미 닫힌 이 이슈에 코멘트로 단다. 이슈를 다시 열지 않는다. revert 하지 않는다. 재개 줄은 「main 을 고친 뒤 <다음 열린 이슈 URL> 로 시작 명령」이다. 원격·로컬 브랜치와 워크트리를 남긴다.
   2. 원격 브랜치 삭제: 위 「시그니처」의 `git push origin --delete`. 내용을 내보내지 않는 푸시라 유출 검사가 없다.
   3. 구현 이슈와 하위 이슈마다 `gh issue view <URL> --json state` 로 상태를 본다. 열려 있으면 `publish comment` 로 「<PR URL> 로 머지됨」을 단 뒤 `gh issue close <URL>` 로 닫는다.
4. **다음 이슈**: 기동 줄 필드에서 자기 이슈 뒤에 있는 이슈 중 열린 첫 이슈다(`gh issue view --json state`).
   - **없으면 마지막이다 → 완료 보고**: `batch-report --issue <자기 이슈 URL> --list "<필드 값>" --out <파일>` 뒤 `publish comment --worktree <worktree> --issue <자기 이슈 URL> --body-file <파일>`. `stop` 이거나 실패하면 6 을 하지 않는다(워크트리를 남긴다). 세션 출력에 이유와 올리려던 본문을 적고 끝난다(유출 검사에 걸렸으면 걸린 값은 뺀다). 다시 시작할 것이 없으므로 멈춤 보고가 아니다.
   - **있으면 handoff**: `doctor` 와 `handoff-check --issue <다음 이슈 URL>` 를 끝까지 돌린다. 둘 다 통과하면 `$RELAY/skills/handoff/references/launch.md` 절차로 띄운다(일괄 진행 기동 줄, 필드는 받은 그대로, 슬러그는 다음 이슈 제목에서). 검사 `FAIL` 이나 기동 실패면 **다음 이슈**에 멈춤 보고를 단다(`stop.md` 일괄 진행 형식). 6 을 하지 않고(워크트리를 남긴다) 끝난다. 다음 이슈는 워크트리가 없어 Orca 미읽음이 뜨지 않기 때문이다.
   - 중간 이슈의 머지는 따로 알리지 않는다(코멘트 없음).
5. 원칙 한 줄: **사람에게 알릴 수단이 없으면 워크트리를 남긴다.**
6. **마지막 행동 — 자기 이슈 워크트리 삭제**: Orca 가이드의 워크트리 삭제 동사(`worktree rm`)에 `--worktree current --delete-branch` 를 준다. `--force` 는 주지 않는다. 이 뒤에는 아무것도 하지 않는다(Orca 가 이 세션을 먼저 끄므로 결과를 받지 못한다, ADR 0011·#68 실측). Orca 가 거부하면(커밋하지 않은 파일) 세션은 살아 있다. 세션 출력에 거부 이유를 적고 끝난다. GitHub 코멘트는 달지 않고, 일괄 진행도 멈추지 않는다(다음 이슈는 이미 돌고 있다). Orca 가 머지를 증명하지 못한 로컬 브랜치는 남을 수 있다.

**5. `finish.md` (수정)**

- 「머지는 사람이 한다(자동 머지 금지)」 문단: 「기동 줄에 `일괄 진행:` 이 없으면 머지는 사람이 한다. 있으면 PR 을 연 뒤 `merge.md` 로 간다.」 이유 문장은 일반 relay 의 이유로 남긴다.
- 경로 A 본문 템플릿에서 `warnings:` 줄 바로 뒤에 「사람이 할 일」 사본을 넣는다. 구현 이슈(하위 이슈가 있으면 부모, 없으면 이슈 자체)의 절에서 `머지 전:`·`머지 뒤:` 줄과 항목을 그대로 옮긴다. 체크하는 정본은 이슈 본문이고 PR 본문은 읽기용 사본이라는 문장을 둔다.

  ```
  사람이 할 일:
  - 머지 전: 없음
  - 머지 뒤:
    - [ ] <이슈의 항목 그대로>
  ```

- 「기각한 지적」 뒤에 「남은 MINOR」 절을 둔다: 태스크마다 마지막 리뷰 리포트의 `MINOR` 지적을 `- I-<n> <file>:<line> <summary>` 로 적는다. 없으면 절을 뺀다.
- `publish pr` 결과: 일괄 진행이면 `created`·`exists` 모두 `merge.md` 로 간다(재개 때 `exists` 면 PR 을 새로 만들지 않고 머지 단계부터 다시 한다). 일반 relay 면 보고하고 끝난다.
- 「보고」 절: 일괄 진행이면 여기서 보고하지 않고 `merge.md` 로 간다.

**6. `stop.md` (수정)**

- 「멈춤 보고」 3 의 코멘트 형식에 일괄 진행판을 더한다. 기동 줄에 `일괄 진행:` 이 있으면 재개 줄을 바꾸고 한 줄을 더한다:

  ```
  남은 진행 목록: #<n>, #<n> (시작하지 않음)
  재개: <고칠 것> 뒤 시작 명령 /relay:batch <URL>
  ```

  - `남은 진행 목록` 은 필드에서 이 이슈 뒤의 열린 이슈다. 없으면 `없음`.
  - `<URL>` 은 보통 이 이슈다. main 깨짐이면 다음 열린 이슈다.
  - 다음 handoff 실패로 **다음 이슈**에 다는 보고도 같은 형식이다. 이때 남은 진행 목록은 다음 이슈 뒤의 열린 이슈다.
- 유출 검사로 멈춘 경우의 재개 두 길(오탐 / 진짜 값)에 일괄 진행판을 적는다: `relay:handoff` 대신 시작 명령.
- 트리거 표에 머지 단계의 멈춤을 더한다: `merge-check` FAIL, main 과 충돌, 합친 결과 게이트 실패, `gh pr merge` 실패(셋 다 PR 은 연 채), main 깨짐(닫힌 이슈에 코멘트), 다음 handoff 실패(다음 이슈에 코멘트, 자기 워크트리를 남김).
- 한 줄: 일괄 진행에서 멈추면 진행 목록 전체가 멈춘다. 멈춘 진행자 세션은 다음 이슈를 handoff 하지 않고, 자기 워크트리를 지우지 않는다.

**7. `start.md` (수정)**

- (c) 0: 기동 줄에 `/ 일괄 진행: …` 필드가 있으면 그 값을 적어 둔다. `finish.md`·`merge.md`·`stop.md` 가 쓴다. 없으면 일반 relay 다.

**8. relay `SKILL.md` (수정)**

- `description`: 「PR 까지 옮기는」 뒤에 「(일괄 진행이면 머지와 다음 이슈 handoff 까지)」를 넣는다. 작은따옴표 YAML 그대로다.
- 「진입」: 기동 줄에 `/ 일괄 진행: #a #b` 필드가 붙을 수 있다는 문장을 더한다.
- 불변식의 「머지는 사람이 한다(자동 머지 금지)」 줄 → 「기동 줄에 `일괄 진행:` 이 없으면 머지는 사람이 한다(자동 머지 금지). 있으면 `references/merge.md` 의 머지 조건·머지 방법대로 진행자가 머지한다.」 PR 이 구현 이슈마다 하나라는 문장은 그대로 둔다.
- 불변식에 한 줄을 더한다: 「일괄 진행이면 사람의 시작 명령이 진행 목록의 이슈 브랜치 푸시(rebase 뒤 `--force-with-lease` 포함)·원격 이슈 브랜치 삭제·PR 머지 요청이다. 저장소 규칙의 「푸시는 요청할 때만」·「force push 는 사전 확인」은 이 셋에 대해 이미 허락된 것으로 본다. main 에 직접 푸시하거나 force push 하지 않는다.」
- 단계 목록 표에 행을 더한다: `머지 (일괄 진행)` | 머지 조건·머지·연쇄 handoff·워크트리 삭제 | `references/merge.md`.
- 파이프라인 흐름 그림의 마지막 줄 뒤에 「일괄 진행이면: 머지 → (마지막이면 완료 보고 / 아니면 다음 이슈 handoff) → 자기 워크트리 삭제」 한 줄.

**9. `skills/spec/SKILL.md` (수정)** — 「일괄 진행」 절을 「끝내기」 앞에 더한다.

- 함께 돌릴 구현 이슈는 blocking 으로 잇는다. 의존이 없어도 같은 진행 목록에 넣으려면 blocking 하나를 건다. 다른 저장소 이슈와 잇지 않는다.
- 하위 이슈의 blocking 은 형제 하위 이슈끼리만 건다.
- `머지 전:` 에 할 일이 있는 이슈가 진행 목록에 있으면 일괄 진행은 시작하지 않는다. 머지 뒤로 옮길 수 있으면 옮긴다.
- 여러 이슈를 이었으면 마지막에 `python "$RELAY/scripts/relay_cli.py" batch-plan --issue <URL>` 도 돌린다(읽기만 한다). 시작은 사람이 `/relay:batch <URL>` 로 한다. 모델은 이 스킬을 부를 수 없다.

**10. `agent-rules/project/20-git.md` (수정)** — 「force push, `reset --hard` …」 줄 바로 뒤에 이 불릿을 더한다. 그다음 `sh agent-rules/build.sh` 로 `AGENTS.md` 를 다시 만든다.

```
- relay 일괄 진행의 진행자 세션은 예외다. 사람의 일괄 진행 시작 명령이 그 진행 목록의 이슈 브랜치 푸시(rebase 뒤 `--force-with-lease` 포함)·원격 이슈 브랜치 삭제·PR 머지 요청이다. main 에 직접 푸시하거나 force push 하지 않는다.
```

**11. `test_docs.py` (수정)**

- 검사하는 문서 집합에 `skills/batch/`·`skills/spec/`·`skills/handoff/references/` 를 넣는다: `SkillCallsExistingCommands`, `OrcaGuideIsTheSource`, `SupervisionStaysInOrca`, `Frontmatter`.
- `skills/batch/SKILL.md` 머리말에 `disable-model-invocation: true` 가 있다.
- 기동 줄 테스트 둘(`test_handoff_launch_line_tells_the_session_to_load_relay`, `test_coordinator_prompts_copy_the_handoff_launch_line`)은 `skills/handoff/references/launch.md` 에서 `relay: 구현 이슈 <이슈 URL>` 로 시작하는 **첫** 줄을 읽게 고친다. 그 줄은 지금과 같아야 한다.
- `launch.md` 에 `/ 일괄 진행:` 이 든 기동 줄이 있다.
- `merge.md` 에 `--match-head-commit`, `--force-with-lease`, `--worktree current --delete-branch`, `merge-check`, `batch-report` 가 있다. `gh pr merge` 가 든 줄에 `--delete-branch`·`--squash`·`--rebase`·`--auto` 가 없다.
- handoff 쪽 단언(`--no-parent`, `--base-branch main`, `--agent claude`, `agent launch`)은 handoff SKILL.md 와 references 를 이은 텍스트에서 본다.
- relay 스킬 문서에 「머지는 사람이 한다」가 `일괄 진행:` 조건과 함께 있다(`SKILL.md` 불변식).

**12. 버전과 README**

- `plugin.json`: `version` 3.0.1 → 3.1.0. `description` 에 「일괄 진행(relay:batch)이면 머지까지」 구절을 더한다.
- `README.md`:
  - 스킬 목록에 `relay:spec`(구현 이슈 쓰기)·`relay:batch`(일괄 진행)를 더한다.
  - `relay_cli` 명령 목록에 `publish`·`batch-plan`·`merge-check`·`batch-report` 를 더한다.
  - 템플릿 경로를 `skills/spec/references/spec-template.md` 로 고친다.
  - 멈춤 표의 「총 라운드 5 도달」 행에서 라운드 한도를 지운다.

### 엣지 케이스

- 진행 목록이 이슈 하나: 그 이슈가 마지막이다. 머지 → 완료 보고 → 워크트리 삭제. handoff 는 없다.
- 필드에서 자기 뒤의 이슈가 모두 닫혀 있음(사람이 따로 머지함): 마지막과 같다(완료 보고).
- 재개로 떴는데 PR 이 이미 열려 있음: `publish pr` 이 `exists` → `merge.md` 1 부터 다시.
- 머지 조건이 어긋난 채 재개: 다시 멈춘다. 사람은 PR 을 직접 머지하고 시작 명령을 다시 치거나, PR 을 닫고 이슈 워크트리를 지운 뒤 처음부터 한다(`stop.md` 의 재개 설명에 이 두 길을 적는다).
- 앞 이슈의 `머지 뒤:` 할 일이 다음 이슈의 전제: 새 규칙 없이 다음 이슈의 기준선 게이트가 빨개져 멈추고, 사람이 그 일을 한 뒤 재개한다.

### 에러 처리

- 문서 작업이라 코드 오류 경로는 없다. 앞 태스크의 명령 이름·인자·출력이 이 spec 과 다르면 문서를 맞추지 말고 `ask` 로 묻는다.

## 기존 코드 참조

- `plugins/relay/skills/handoff/SKILL.md` 「## 3. 진행자 세션을 띄운다」 — `launch.md` 로 옮길 내용.
- `plugins/relay/skills/relay/references/finish.md` 「경로 A — GitHub: PR」 — PR 본문 템플릿.
- `plugins/relay/skills/relay/references/stop.md` 「멈춤 보고」 — 코멘트 형식과 트리거 표.
- `plugins/relay/skills/relay/references/gate.md` — 게이트를 돌리는 방법(종료코드, 의존성 동기화).
- `plugins/relay/tests/test_docs.py:33` `SkillCallsExistingCommands`, `FORBIDDEN` 목록, `:188` `Frontmatter` — 넓힐 문서 검사.
- `plugins/relay/docs/adr/0011-batch-run-chains-coordinator-handoffs.md` — 끝 순서와 워크트리를 남기는 경우.

## 인수 조건

- [ ] `skills/batch/SKILL.md` 가 있고 머리말에 `disable-model-invocation: true` 가 있다.
- [ ] `skills/handoff/references/launch.md` 의 첫 기동 줄이 지금의 일반 기동 줄과 같고, 일괄 진행 기동 줄이 그 아래에 있다.
- [ ] `merge.md` 가 위 순서(머지 조건 → 머지 직전 → 머지 뒤 확인 → 완료 보고 또는 다음 이슈 → 워크트리 삭제)를 담고, `test_docs` 단언을 통과한다.
- [ ] `AGENTS.md` 의 Git 절에 relay 일괄 진행 예외 줄이 있다.
- [ ] `plugin.json` 의 `version` 이 3.1.0 이다.
- [ ] 게이트 명령: `python -m unittest discover -s plugins/relay/tests -q && sh agent-rules/build.sh --check` — 저장소 루트에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 문서에 `orca worktree …`·`orca terminal …` 처럼 orca 명령을 글자 그대로 적는 것.
- `gh pr merge --delete-branch`, squash·rebase merge, `--force` 워크트리 삭제를 문서에 넣는 것.
- 머지 재시도 횟수, 라운드 한도 같은 한도를 문서에 다시 넣는 것.
- `relay:batch` 를 모델이 부를 수 있게 하는 것.
- 일반 기동 줄의 글자를 바꾸는 것, eval 프롬프트를 고치는 것.
- `AGENTS.md` 를 손으로 고치는 것, 루트에 `CLAUDE.md` 를 만드는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
