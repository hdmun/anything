## Git

- 커밋 메시지: Conventional Commits (`feat|fix|docs|chore|refactor|test(scope): 설명`). 설명은 한국어, `~한다` 체.
- 커밋 메시지는 ADHD가 있는 사람도 한눈에 이해하도록 쓴다. 제목은 "무엇이 어떻게 바뀌었는지"를 한 줄로 쓰고, 본문이 필요하면 짧은 불릿으로 나눈다. 모호한 표현·긴 문단·비유는 피한다.
- scope는 대상 패키지/디렉터리 이름 (예: `relay`).
- 브랜치: `hdmun/<주제>` 형식. `main`에 직접 작업하지 않고 브랜치에서 작업한 뒤 머지한다.
- 커밋은 사용자 승인 없이 해도 된다. 푸시는 사용자가 요청할 때만 한다.
- 브랜치에 커밋이 2개 이상이면 `main` 기준으로 rebase한 뒤 non-ff 머지(`git merge --no-ff`)한다. 커밋이 1개면 `git merge --ff-only`로 머지한다.
- 한 커밋에는 한 가지 논리적 변경만 담는다.
- force push, `reset --hard` 등 되돌리기 어려운 명령은 사전 확인 후 실행한다.
- relay 일괄 진행의 진행자 세션은 예외다. 사람의 일괄 진행 시작 명령이 그 진행 목록의 이슈 브랜치 푸시(rebase 뒤 `--force-with-lease` 포함)·원격 이슈 브랜치 삭제·PR 머지 요청이다. main 에 직접 푸시하거나 force push 하지 않는다.
