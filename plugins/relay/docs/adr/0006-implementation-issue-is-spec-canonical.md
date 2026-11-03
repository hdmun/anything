---
status: accepted
---

# 구현 이슈가 spec 의 정본이고, `.ai/specs/` 는 고정 사본이다

ADR 0005 로 진행자 세션의 입력이 트래커의 구현 이슈가 되면서, 설계자가 쓰던 `.ai/specs/T-NNN-*.md` 를 그대로 두면 같은 spec 이 이슈와 파일 두 곳에 놓인다. 그래서 **정본은 구현 이슈**로 하고, 진행자 세션이 태스크를 시작할 때 이슈 본문을 워크트리의 `.ai/specs/` 에 **spec 스냅숏**으로 커밋한다. 스냅숏 머리말에 이슈 URL 과 `updatedAt` 을 적어 사본임을 밝힌다. 리뷰어는 이 스냅숏을 git 에서 읽어 SPEC_VIOLATION 을 판정하고, spec 을 고치면 이슈를 고친 뒤 스냅숏을 다시 커밋하므로 수정 이력이 브랜치 diff 로 남는다.

## Considered Options

- **이슈만(리뷰어도 `gh` 로 읽음)**: 리뷰어(codex)에 트래커 인증이 필요하고, 읽는 시점마다 내용이 달라질 수 있으며, spec 수정 이력이 브랜치와 묶이지 않는다. 기각.
- **T-NNN 파일을 정본으로 유지(진행자가 이슈를 옮겨 적음)**: 정본이 둘이 되어 어긋난다. 기각.

## Consequences

- 스냅숏은 태스크 시작 시점에 고정된다. 진행자는 이슈의 변화를 감시하지 않고, spec 수정으로 판정했을 때만 다시 뜬다. PR 을 만들 때 이슈 `updatedAt` 이 스냅숏과 다르면 PR 본문에 "태스크 도중 이슈가 바뀜: 반영 안 됨"을 적는다.
- 공개 저장소의 프롬프트 주입 대책: 스냅숏에는 이슈 본문만 넣고 코멘트는 넣지 않는다. 이슈 작성자의 `author_association` 이 `OWNER`·`MEMBER`·`COLLABORATOR` 가 아니면 진행하지 않고 멈춤 보고를 한다(남의 이슈 본문은 쓰기 권한자만 고칠 수 있다).
- 트래커 종류는 저장소의 `docs/agents/issue-tracker.md` 를 따른다. 없으면 local-markdown(`.scratch/<feature>/issues/<NN>-<slug>.md`)으로 본다. local-markdown 이어도 스냅숏은 똑같이 뜬다.
- 스냅숏 파일명과 리뷰 리포트(`.ai/reviews/<id>.rN.json`, git 에 남김)는 같은 태스크 ID 를 쓰고, `review.py` 의 `REPORT_RE` 가 그 ID 체계를 받아들여야 한다. ID 체계 자체는 구현 이슈를 태스크로 나누는 방식과 함께 정한다.
