---
name: rename-session
description: Analyze session conversation history and recommend concise session titles formatted as "(YYYY.MM.DD) 핵심 주제". Use when the user asks to recommend, name, or rename the chat/session (e.g. "세션 제목 추천해줘", "방 제목 지어줘", "rename session", "suggest session title").
---

# Rename Session

Analyze the current session's conversation history and recommend 3–4 high-signal session title candidates formatted strictly as `(YYYY.MM.DD) 핵심 주제`.

## Format Rule

- **Strict Prefix**: `(YYYY.MM.DD) ` (Opening parenthesis, current date formatted as 4-digit year, 2-digit month, 2-digit day, closing parenthesis, space).
- **Core Subject**: 3–7 words summarizing the main achievement or task.

## Workflow

1. **Extract Session Core**:
   - Primary goal or user request.
   - Key technologies, files, or tools touched.
   - Outcome achieved (e.g. feature implemented, bug resolved, skill created).

2. **Generate Candidates**:
   - **핵심 요약형**: `(YYYY.MM.DD) 핵심 작업 요약` (예: `(2026.10.17) rename-session 스킬 구현`)
   - **태그형**: `(YYYY.MM.DD) [태그] 작업 내용` (예: `(2026.10.17) [Skill] 세션 제목 추천 스킬 추가`)
   - **액션 중심형**: `(YYYY.MM.DD) 동사 기반 완료 내용` (예: `(2026.10.17) 세션 날짜 및 주제 자동 명명 기능 구축`)
   - **영문/기술 중심형**: `(YYYY.MM.DD) 기술 및 모듈명` (예: `(2026.10.17) Antigravity rename-session Skill`)

3. **Output Constraints**:
   - Limit to at most 4 candidates.
   - Subject text must be under 30 characters.
   - Do not use vague terms like "코드 수정", "작업 진행".
   - Mark one recommended choice with `(추천)`.
