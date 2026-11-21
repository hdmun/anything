# 이슈 트래커: GitHub

이 저장소의 이슈와 명세는 GitHub 이슈로 둔다. 모든 작업에 `gh` CLI 를 쓴다.

## 규칙

- **이슈 만들기**: `gh issue create --title "..." --body "..."`. 여러 줄 본문에는 heredoc 을 쓴다.
- **이슈 읽기**: `gh issue view <number> --json number,title,body,labels,comments`.
- **이슈 목록**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` 에 알맞은 `--label`, `--state` 필터를 붙인다.
- **이슈를 부모의 하위 이슈로 만들기**: `gh issue create --parent <parent> ...`, 또는 나중에 `gh issue edit <parent> --add-sub-issue <child>`(`gh` 2.94+). 더 오래된 `gh`: `gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`(아래 **막힘** 처럼 database id). 하위 이슈를 못 쓰면 자식 본문 맨 위에 `Part of #<parent>` 를 둔다.
- **이슈에 댓글 달기**: `gh issue comment <number> --body "..."`
- **라벨 붙이기 / 떼기**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **닫기**: `gh issue close <number> --comment "..."`

저장소는 `git remote -v` 로 알아낸다. 클론 안에서 `gh` 를 실행하면 자동으로 알아낸다.

## 분류 대상으로서의 풀 리퀘스트

**PRs as a request surface: no.** (요청 창구로서의 PR: 쓰지 않음) _(이 저장소가 외부 PR 을 기능 요청으로 다룬다면 `yes` 로 바꾼다. `/triage` 가 이 플래그를 읽는다.)_

`yes` 로 두면 PR 도 이슈와 같은 라벨과 상태를 거치며, `gh pr` 의 대응 명령을 쓴다:

- **PR 읽기**: `gh pr view <number> --comments`, diff 는 `gh pr diff <number>`.
- **분류할 외부 PR 목록**: `gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`.
- **댓글 / 라벨 / 닫기**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub 는 이슈와 PR 이 번호 공간 하나를 같이 쓰므로, 맨 `#42` 는 둘 중 어느 쪽일 수도 있다. `gh pr view 42` 로 확인하고, 안 되면 `gh issue view 42` 로 넘어간다.

## 스킬이 "이슈 트래커에 올린다(publish to the issue tracker)"고 할 때

GitHub 이슈를 만든다.

## 스킬이 "관련 티켓을 가져온다(fetch the relevant ticket)"고 할 때

위 **이슈 읽기** 처럼 읽는다.

## 길잡이(wayfinding) 작업

`/wayfinder` 가 쓴다. **지도(map)** 는 이슈 하나이고, **자식(child)** 이슈가 티켓이다.

- **지도**: `wayfinder:map` 라벨이 붙은 이슈 하나로, 본문에 Notes / Decisions-so-far / Fog 를 담는다. `gh issue create --label wayfinder:map`.
- **자식 티켓**: GitHub 하위 이슈로 지도에 연결한 이슈(**이슈를 부모의 하위 이슈로 만들기** 참고). 하위 이슈를 켜지 않은 곳에서는 지도 본문의 작업 목록에 자식을 넣고, 자식 본문 맨 위에 `Part of #<map>` 을 둔다. 라벨: `wayfinder:<type>`(`research`/`prototype`/`grilling`/`task`). 누가 맡으면 그 티켓은 진행하는 개발자에게 배정한다.
- **막힘(blocking)**: GitHub 의 **기본 이슈 의존성(native issue dependencies)**, 곧 UI 에 보이는 정식 표현을 쓴다. 간선은 `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>` 로 더한다. `<blocker-db-id>` 는 막는 이슈의 숫자 **database id** 다(`gh api repos/<owner>/<repo>/issues/<n> --jq .id`. `#number` 나 `node_id` 가 _아니다_). GitHub 는 `issue_dependencies_summary.blocked_by`(열린 막는 이슈만 센다, 실시간 관문)를 보고한다. 의존성을 쓸 수 없는 곳에서는 자식 본문 맨 위에 `Blocked by: #<n>, #<n>` 줄을 두는 방식으로 대신한다. 막는 이슈가 모두 닫히면 티켓의 막힘이 풀린다.
- **최전선 조회(frontier query)**: 지도의 열린 자식을 나열하고(`gh issue list --state open`, 지도의 하위 이슈 / 작업 목록으로 범위를 좁힌다), 열린 막는 이슈가 있거나(`issue_dependencies_summary.blocked_by > 0`, 또는 `Blocked by` 줄에 열린 이슈) 배정된 사람이 있는 것을 뺀다. 지도 순서에서 처음 것이 이긴다.
- **맡기(claim)**: `gh issue edit <n> --add-assignee @me`. 세션의 첫 쓰기 작업이다.
- **해결(resolve)**: `gh issue comment <n> --body "<answer>"`, 이어서 `gh issue close <n>`, 그다음 지도의 Decisions-so-far 에 맥락 포인터(요지 + 링크)를 덧붙인다.
