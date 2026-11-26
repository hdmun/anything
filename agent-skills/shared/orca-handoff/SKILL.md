---
name: orca-handoff
description: 현재 대화를 handoff 문서로 정리하고, orca-cli로 새 워커 세션을 띄워서 작업을 이어가게 합니다.
argument-hint: "다음 세션에서 할 일 (예: 새 worktree에서 로그인 버그 수정)"
disable-model-invocation: true
---

현재 대화를 handoff 문서로 정리하고, Orca의 새 워커 세션이 그 문서를 이어받게 합니다. 인자는 새 세션이 할 일입니다. 이 세션에서 그 작업을 직접 수행하지 않습니다.

## 1. handoff 문서 작성

새 에이전트가 작업을 이어갈 수 있도록 현재 대화를 요약한 handoff 문서를 한국어로 작성합니다. 작업 폴더가 아니라 OS 임시 폴더의 `orca-handoff\<yyyyMMdd-HHmmss>-<slug>.md`에 저장합니다.

- 인자가 있으면 다음 세션의 목표로 보고, 문서를 그 목표에 맞춰 작성합니다.
- "suggested skills" 섹션에 다음 세션이 호출할 스킬을 적습니다.
- spec, 계획, ADR, 이슈, 커밋, diff처럼 다른 산출물에 이미 있는 내용은 복사하지 않고 경로나 URL로 참조합니다.
- API 키, 비밀번호, 개인 식별 정보는 제거합니다.

## 2. 새 세션 실행

orca-cli 스킬을 불러와서, 그 가이드의 handoff 절차로 새 세션을 띄웁니다. 명령과 플래그의 문법은 orca-cli 가이드를 따르고, 아래 값은 이 스킬의 규칙을 따릅니다.

- 프롬프트: `다음 handoff 문서를 읽고 작업을 이어가세요: <문서 절대경로>. 문서의 suggested skills 섹션에 적힌 스킬을 먼저 호출하세요.` 문서 본문이나 작업 내용을 프롬프트에 직접 넣지 않습니다.
- 에이전트: 사용자가 지정하지 않으면 지금 이 세션과 같은 에이전트를 씁니다. Claude Code는 `claude`, Codex는 `codex`, agy는 `antigravity`입니다.
- 위치: 기본값은 현재 워크스페이스(`agent launch --worktree active`)입니다. 인자에 "새 worktree"가 있으면 새 worktree를 만들고, `--no-parent`와 함께 `--repo`에 현재 repo를 명시합니다.
- 호스트: 수신 세션이 로컬 임시 파일을 읽어야 하므로 로컬 호스트에서만 실행합니다. 원격 대상을 요청받으면 실행하지 않고 그 이유를 알립니다.
- claude이고 현재 세션에 `CLAUDE_CONFIG_DIR`이 설정되어 있으면, `agent launch` 대신 `terminal create --worktree <대상> --shell pwsh.exe --command "$env:CLAUDE_CONFIG_DIR='<값>'; claude '<프롬프트>'"`로 띄웁니다. `agent launch`는 이 변수를 넘기지 않아서, 새 세션이 다른 설정 폴더로 실행되기 때문입니다. 이 경우 `terminal read --screen`으로 한 번 확인하고, 폴더 신뢰 확인 화면이 보이면 대신 승인하지 말고 사용자에게 안내합니다.

## 3. 보고

새 세션의 handle, 워크스페이스 id, 프롬프트 전달 결과, handoff 문서 경로를 보고하고 멈춥니다. 수신 세션의 작업은 기다리지 않습니다.
