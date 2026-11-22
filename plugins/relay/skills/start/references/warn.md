# `WARN` 처리

> 이 파일은 `relay:start` 2절과 `relay:auto-merge` 1번이 Read 한다. `doctor`·`handoff-check` 의 `WARN` 을 처리한다.

- 사람 판단이 필요한 `WARN`(미검증 버전 `WARN version:*` 등)은 이 자리에서 사람과 정한다.
- 미검증 버전이면 `relay_cli.py smoke --dir <대상 저장소 루트>` 를 권한다. 그 디렉터리는 Orca 에 등록된 워크트리여야 하고, 하위 폴더면 `selector_not_found` 다. smoke 가 실패한 CLI 로는 띄우지 않는다.
- 그 밖의 `WARN` 은 보고만 하고 진행한다(진행자는 PR 본문 `warnings:` 에 적는다).
