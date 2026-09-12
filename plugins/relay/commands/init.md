---
description: 현재 저장소에 relay 역할 파일(.ai/roles/)과 게이트 로그 gitignore 항목을 플러그인 템플릿에서 생성/검증한다
argument-hint: "[--check | --force]"
---

현재 저장소에 relay 파이프라인의 역할 파일을 설치하거나 드리프트를 검증한다.
사용자가 준 인자: `$1`

## 하는 일

역할 파일은 워커(agy·codex)가 읽는 규범이고, **공유 규범 85% + 저장소 고유 15%** 로 이루어진다.
공유분은 플러그인 템플릿이 정본이고, 고유분만 이 저장소의 `.ai/relay-roles.json` 에 산다.

## 절차

### 1. 모드 판별

- `--check` → 검증만. 파일을 쓰지 않는다.
- `--force` → 덮어쓴다.
- 인자 없음 → 없으면 생성, 있고 다르면 거부하고 알린다.

### 2. `.ai/relay-roles.json` 확보

파일이 이미 있으면 그대로 쓴다. **없을 때만** 아래를 저장소에서 추론하고, 추론이 안 되는 것만 사용자에게 한 번에 묻는다.

| 키 | 추론 방법 |
|---|---|
| `default_branch` | `git symbolic-ref --short refs/remotes/origin/HEAD` 의 마지막 조각, 실패하면 현재 브랜치 |
| `rules_doc` | `AGENTS.md` / `CLAUDE.md` / `CONTEXT-MAP.md` 존재 여부. 읽을 것 2번 항목의 한 줄 마크다운으로 쓴다 |
| `gate_cmd_prose` · `gate_cmd_raw` | `package.json` 의 test 스크립트, `go.mod`, `Cargo.toml`, `Makefile` 순으로 본다 |
| `gate_prep` | 의존성 설치가 필요한 생태계면 그 한 줄(`- 워크트리에 …가 없으면 먼저 … 를 실행한다.`), 아니면 빈 문자열 |
| `dep_rule` | 테스트 러너·의존성 정책. 확신이 없으면 묻는다 |
| `gate_logs` | 게이트가 만드는 로그 파일명 배열. 최소 `["gate.log"]` |
| `review_focus` | **반드시 사용자에게 묻는다.** 게이트가 못 잡는 것이 무엇인지는 저장소 주인만 안다 |
| `ask_extra` | 구현자가 추가로 물어야 할 상황 한 줄. 없으면 빈 문자열 |

추론한 값을 사용자에게 표로 보여주고 확인받은 뒤 `.ai/relay-roles.json` 에 쓴다.

### 3. 렌더링

```bash
python "${CLAUDE_PLUGIN_ROOT}/scripts/render_roles.py" --plugin-root "${CLAUDE_PLUGIN_ROOT}" --repo . $1
```

### 4. 결과 보고

- 생성된 파일 경로
- `.gitignore` 에 추가된 게이트 로그 항목
- 저장소의 `AGENTS.md` 또는 `CLAUDE.md` 에 역할 파일 링크가 **없으면** 추가를 제안한다.
  워커는 그 링크를 통해서만 역할 파일에 도달한다 — 링크가 없으면 파일이 있어도 읽히지 않는다.

## 주의

- **생성된 역할 파일을 직접 고치지 않는다.** 맨 위 스탬프가 그렇게 적혀 있다.
  공유 규범을 고쳐야 하면 플러그인의 `templates/` 를 고치고 `--force` 로 재생성한다.
  저장소 고유분을 고쳐야 하면 `.ai/relay-roles.json` 을 고치고 `--force` 로 재생성한다.
- `--check` 는 플러그인 업데이트 직후에 각 저장소에서 돌린다. 종료코드 1이면 드리프트다.
