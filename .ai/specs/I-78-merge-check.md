> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/78
> updatedAt: 2026-11-11T02:31:23Z

# merge-check·batch-report: 머지 조건과 완료 보고를 코드로 판정한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

일괄 진행에서 진행자 세션은 PR 을 연 뒤 사람 확인 없이 머지한다. 머지해도 되는 조건(**머지 조건**, [#52](https://github.com/hdmun/anything/issues/52))은 기계로 판정한다. 머지 절차 문서(`merge.md`, 이 이슈의 다른 태스크)는 머지 직전에 이 태스크의 검사기 `merge-check` 를 부른다. 하나라도 어긋나면 PR 을 연 채 멈춤 보고를 남긴다.

머지 조건:

1. 모든 태스크가 `Relay-Done` 으로 끝났다. 진행자는 리뷰 `pass` 리포트 커밋과 판정 `dismiss`·`accept` 기록 커밋에 `Relay-Done: I-<n>` 트레일러를 붙인다(정본 `scripts/relaylib/resume.py`).
2. 태스크마다 이슈의 **지금 본문**이 spec 스냅숏의 본문과 같다. 비교 기준은 `updatedAt` 이 아니라 본문이다. 코멘트·라벨·배정만 바뀌어도 `updatedAt` 이 바뀌기 때문이다.
3. 구현 이슈(하위 이슈가 있으면 부모)의 「사람이 할 일」 `머지 전:` 이 `없음` 이다. 부모는 스냅숏을 뜨지 않으므로 2 로는 잡히지 않는다.
4. 머지될 결과(main + 브랜치)에서 게이트 통과. 진행자가 `merge.md` 대로 직접 돌린다. **이 태스크의 범위가 아니다.**

**완료 보고**([#61](https://github.com/hdmun/anything/issues/61)): 진행 목록의 마지막 구현 이슈를 머지한 진행자 세션이 그 이슈에 코멘트 하나를 단다. 이슈마다 이슈 번호, 머지한 PR 링크, 「머지 뒤 할 일 N개」(없으면 `없음`)를 적는다. 자유 문장은 쓰지 않는다(유출 검사에 걸릴 일을 줄인다). 앞선 이슈의 PR 과 할 일 개수는 GitHub 에서 읽는다. 이 태스크는 그 본문을 만드는 결정기 `batch-report` 를 만든다. 코멘트를 올리는 것은 「relay 일괄 진행 준비」의 `publish comment` 다.

spec 스냅숏 파일 형식(정본 `scripts/relaylib/issue.py` `render`, 경로 `<worktree>/.ai/specs/I-<n>-<슬러그>.md`):

```
> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: <URL>
> updatedAt: <시각>

# <제목>

<본문>
```

`gh issue view <URL> --json closedByPullRequestsReferences` 는 그 이슈를 닫은 PR 목록(`url`, `number` 등)을 돌려준다(gh 2.96 에서 필드 확인). PR 본문의 `Closes #n` 으로 닫힌 이슈에 채워진다.

## 범위 밖 (건드리지 말 것)

- 게이트 실행, rebase, `gh pr merge`, handoff, 워크트리 삭제: `merge.md`(다른 태스크).
- 코멘트 올리기: `publish comment`.
- 「사람이 할 일」 절 해석 규칙: `handoff.human_todo` 를 그대로 쓴다.
- `snapshot`·`resume`·`batch-plan` 명령.

## 변경 대상 파일

- `plugins/relay/scripts/relaylib/merge.py` — 신규
- `plugins/relay/scripts/relaylib/issue.py` — 수정 (`snapshot_body` 추가)
- `plugins/relay/scripts/relay_cli.py` — 수정
- `plugins/relay/tests/test_merge.py` — 신규
- `plugins/relay/tests/test_issue.py` — 수정

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```
python relay_cli.py merge-check  --issue <구현 이슈 URL> --worktree <dir> [--base origin/main] [--json]   (검사기)
python relay_cli.py batch-report --issue <마지막 구현 이슈 URL> --list "<기동 줄 일괄 진행 필드의 값>" --out <파일>   (결정기)
```

```python
# plugins/relay/scripts/relaylib/issue.py
def snapshot_body(text):
    """spec 스냅숏 파일 내용 → 본문(render 의 역). 형식이 다르면 None."""

# plugins/relay/scripts/relaylib/merge.py
def check(issue_ref, worktree, run, git, base="origin/main"):
    """머지 조건 1~3 → {"checks": [...]}. run(argv) -> (rc, stdout), git(worktree, *args) -> stdout."""

def exit_code(checks):
    """FAIL 이 하나라도 있으면 1, 아니면 0."""

def parse_list(text):
    """"#12 #14 #15" 또는 "12,14,15" → [12, 14, 15]. 형식 오류면 ValueError."""

def report(issue_ref, numbers, run):
    """완료 보고 → {"body": 텍스트, "issues": [{"number": n, "pr": URL 또는 None, "after": 개수 또는 None}]}"""
```

- `merge-check` 텍스트 출력은 기존 `_print_checks` 형식이고, `--json` 이면 `check()` 결과를 JSON 한 줄로 낸다.
- `batch-report` 는 `--out` 에 본문을 UTF-8·LF 로 쓰고, stdout 에 `{"action": "report", "path": <out>, "issues": [...]}` 한 줄을 낸다.

## 동작 명세

### 정상 경로

**`merge-check`**

1. `handoff.check(issue_ref, run)` 로 태스크 목록(`tasks`)과 `human` 을 얻는다.
2. `done:<태스크 ID>`: `git log --format=%(trailers:key=Relay-Done,valueonly) <base>..HEAD` 의 값에 그 ID 가 있으면 ok, 없으면 FAIL 「Relay-Done 이 없다」.
3. `snapshot:<태스크 ID>`: `<worktree>/.ai/specs/<ID>-*.md` 가 정확히 하나여야 한다(아니면 FAIL 「스냅숏 파일이 N개다」). 그 파일의 `snapshot_body` 와 태스크 이슈의 지금 본문(`issue.fetch`)을 비교한다. 둘 다 CRLF 를 LF 로 바꾸고 끝의 줄바꿈을 뗀 뒤 같으면 ok, 다르면 FAIL 「태스크 도중 이슈 본문이 바뀌었다 — 반영되지 않은 채 머지하지 않는다」. `snapshot_body` 가 `None` 이면 FAIL 「스냅숏 형식을 읽지 못했다」.
4. `before-merge:<구현 이슈 ID>`: `human` 이 있고 `before` 가 비어 있으면 ok. `before` 에 항목이 있으면 FAIL 「`머지 전:` 에 할 일 N개」. `human` 이 `None` 이면 FAIL 「「사람이 할 일」 절을 읽지 못했다」.
5. 검사를 모두 돌린 뒤 결과를 낸다. FAIL 이 있으면 종료코드 1.

**`batch-report`**

1. `parse_list(--list)` 로 번호 목록을 얻는다. 저장소(owner/repo)는 `--issue` URL 에서 얻는다.
2. 번호마다:
   - PR: `gh issue view <이슈 URL> --json closedByPullRequestsReferences` 의 마지막 항목 `url`. 없으면 `None`.
   - 머지 뒤 할 일: `issue.fetch` 본문 → `handoff.human_todo` → `after` 의 개수. 문제가 있거나 읽지 못하면 `None`.
3. 본문(이 형식 그대로):

   ```
   relay 완료 보고 — 일괄 진행 #12 #14 #15

   - #12: <PR URL> · 머지 뒤 할 일 2개
   - #14: <PR URL> · 머지 뒤 할 일 없음
   - #15: 머지된 PR 없음 · 머지 뒤 할 일 읽지 못함
   ```

4. `--out` 에 쓰고 결정 JSON 을 낸다.

### 엣지 케이스

입력 경우를 아래로 한정한다. 경우마다 테스트 하나 이상(가짜 `run`·`git`, 임시 워크트리 디렉터리). **열거하지 않은 경우는 범위 밖이다.**

`snapshot_body`:

| 입력 | 결과 |
|---|---|
| `render` 가 만든 텍스트 | 원래 본문 (왕복 테스트) |
| 본문이 빈 이슈의 `render` | `""` |
| 본문 안에 `# ` 로 시작하는 줄이 있음 | 첫 `# ` 제목 줄 뒤를 모두 본문으로 본다. 본문 속 `# ` 줄은 본문에 남는다 |
| 머리말(`> ` 줄)이 없는 텍스트 | `None` |
| CRLF 로 저장된 스냅숏 | LF 와 같은 결과 |

`merge-check`:

| 경우 | 결과 |
|---|---|
| 하위 이슈 없음, 모두 정상 | 종료코드 0 |
| 하위 이슈 2개 중 하나만 `Relay-Done` | `done:I-<나머지>` FAIL |
| 스냅숏 파일이 없음 / 둘 | `snapshot:*` FAIL 「스냅숏 파일이 N개다」 |
| 태스크 이슈 본문 끝에 줄바꿈만 더해짐 | ok |
| 태스크 이슈 본문 한 글자가 바뀜 | `snapshot:*` FAIL |
| 이슈의 `updatedAt` 만 바뀌고 본문은 같음 | ok |
| 부모의 `머지 전:` 에 1개 | `before-merge:*` FAIL |
| 위 FAIL 이 여럿 함께 | 모두 보고한다 |

`parse_list`: `"#12 #14"`, `"12,14"`, `"#12, #14"` → `[12, 14]`. 빈 문자열, `"#12 abc"` → `ValueError`(CLI 종료코드 2).

`batch-report`: `closedByPullRequestsReferences` 가 빈 배열 → `머지된 PR 없음`. 한 이슈를 읽지 못함 → 그 줄만 `머지 뒤 할 일 읽지 못함`, 나머지 이슈는 계속한다.

### 에러 처리

- 구현 이슈를 읽지 못함 → `IssueError` → 종료코드 2.
- `git` 실패 → `relay_cli.InputError` → 종료코드 2.
- `--list` 형식 오류 → `ValueError` → 종료코드 2.

## 기존 코드 참조

- `plugins/relay/scripts/relaylib/issue.py:76` — `render`: `snapshot_body` 는 이것의 역이다.
- `plugins/relay/scripts/relaylib/resume.py` — `TRAILER`·`done_tasks`. `plugins/relay/scripts/relay_cli.py:147` `cmd_resume` 이 트레일러를 읽는 방법.
- `plugins/relay/scripts/relaylib/handoff.py:71` — `check`(반환값 `tasks`·`human`)와 `human_todo`.
- `plugins/relay/scripts/relay_cli.py:367` — `cmd_handoff_check`: 검사기 출력과 종료코드.

## 인수 조건

- [ ] 엣지 케이스 세 표와 `parse_list`·`batch-report` 경우가 모두 테스트로 있다.
- [ ] `snapshot_body(render(x))` 가 `x` 의 본문을 돌려준다(왕복 테스트).
- [ ] `merge-check` 가 `updatedAt` 이 아니라 본문으로 판정한다(테스트).
- [ ] 게이트 명령: `python -m unittest discover -s plugins/relay/tests -q && sh agent-rules/build.sh --check` — 저장소 루트에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- `updatedAt` 으로 본문 변경을 판정하는 것.
- 실제 GitHub·실제 git 원격을 부르는 테스트.
- 완료 보고에 자유 문장(요약, 감상)을 넣는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
