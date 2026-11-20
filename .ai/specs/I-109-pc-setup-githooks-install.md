> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/109
> updatedAt: 2026-11-11T11:47:46Z

# .githooks 의 install.ps1 을 만들어 hooksPath 를 상대 경로로 맞춘다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다. 이 이슈의 부모는 [pc-setup 설정 파일과 저장소 도구](https://github.com/hdmun/anything/issues/105)이다. 앞 태스크가 **저장소 도구** 단계(`pc-setup/lib/RepoTools.psm1`, `pc-setup/repo-tools.psd1` 의 rdp-notify 한 줄)를 만들었다.

이 태스크는 둘째 저장소 도구 `.githooks` 를 올린다([셋업이 저장소 도구를 설치하는 방식 정하기](https://github.com/hdmun/anything/issues/41) 「세부」).

- `.githooks/pre-commit` 은 agent-rules 생성 파일과 relay 테스트를 검사한다. 저장소 전체 도구로 본다.
- `install.ps1` 은 이 저장소의 git 설정 `core.hooksPath` 를 **상대 경로** `.githooks` 로 맞춘다. 상대 경로면 git 워크트리마다 자기 체크아웃의 훅을 쓴다. 절대 경로면 모든 워크트리가 한 체크아웃의 훅을 쓴다.
- 이 PC 는 지금 `core.hooksPath` 가 저장소 `.git/config` 에 **절대 경로**로 들어 있다(2026-11-11 읽기 전용 확인). 이 PC 에서는 셋업을 돌리지 않으므로 `-Check` 결과가 `다름` 인 것이 정상이다.
- 승격은 필요 없다(일반 권한).
- 항목 스크립트 규칙: `param([switch]$Check)`, 저장소 경로는 `$PSScriptRoot` 의 부모, 상태를 먼저 보고 다를 때만 고침, 마지막 출력 줄 하나가 결과.

이 PC 의 git 설정을 바꾸지 않는다. 테스트는 `TestDrive:` 에 `git init` 한 임시 저장소로 한다.

## 범위 밖 (건드리지 말 것)

- `.githooks/pre-commit` 의 내용.
- 전역(`--global`)·시스템 git 설정.
- `pc-setup/lib/RepoTools.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.

## 변경 대상 파일

- `.githooks/install.ps1` — 신규
- `pc-setup/repo-tools.psd1` — 수정 (`.githooks` 한 줄 추가)
- `pc-setup/tests/GithooksInstall.Tests.ps1` — 신규
- `pc-setup/tests/RepoTools.Tests.ps1` — 수정 (실제 선언 단언을 Id 2개로)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# .githooks/install.ps1
[CmdletBinding()]
param([switch]$Check)
```

```powershell
# pc-setup/repo-tools.psd1 — rdp-notify 줄 뒤에
@{ Id = '.githooks' }
```

## 동작 명세

### 정상 경로

1. 저장소 루트 = `Split-Path $PSScriptRoot -Parent`.
2. `git -C <루트> config --local --get core.hooksPath` 로 지금 값을 읽는다(종료 코드 1 = 값 없음).
3. 값이 정확히 `.githooks` 면 `그대로`.
4. `-Check` 면 값이 없을 때 `다름 (없음)`, 다른 값일 때 `다름 (.githooks 가 아니다)`. 지금 값(사용자 이름이 든 절대 경로일 수 있다)은 결과 줄에 쓰지 않는다. 게이트 로그·PR 에 섞이지 않게 하려는 것이다.
5. 고치는 실행이면 `git -C <루트> config --local core.hooksPath .githooks` 를 실행하고, 종료 코드 0 이면 `바꿈`, 아니면 `실패: git config 종료 코드 <n>`.

### 엣지 케이스

`TestDrive:` 에 `git init` 한 임시 저장소를 만들고, 그 안의 `.githooks` 폴더에 `install.ps1` 을 복사해 부른다(스크립트가 자기 `$PSScriptRoot` 의 부모를 저장소로 쓰므로). 경우를 아래로 한정한다. 각 경우를 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다**(예: 워크트리별 설정 `extensions.worktreeConfig`, bare 저장소).

| # | `core.hooksPath` | `-Check` | 고치는 실행 |
|---|---|---|---|
| 1 | 없음 | `다름 (없음)` | `바꿈`, 값이 `.githooks` 가 됨 |
| 2 | 절대 경로 | `다름 (.githooks 가 아니다)`, 결과 줄에 그 경로가 없음 | `바꿈` |
| 3 | `.githooks` | `그대로` | `그대로` |
| 4 | 1 의 고치는 실행 뒤 다시 | — | `그대로` |
| 5 | `git` 이 PATH 에 없음(`Mock` 이 아니라 `$env:PATH` 를 비운 하위 프로세스에서) | `실패: git 이 없다` | `실패: git 이 없다` |

- `-Check` 는 git 설정을 바꾸지 않는다(테스트로 값이 그대로인지 본다).
- 저장소 `pc-setup/repo-tools.psd1` 이 검사를 통과하고 Id 가 `rdp-notify`, `.githooks` 순서이며 `Elevated` 는 rdp-notify 만이다(`RepoTools.Tests.ps1` 의 기존 단언을 고친다).

### 에러 처리

- `git` 명령을 찾지 못하면 `실패: git 이 없다`(`Get-Command git -ErrorAction SilentlyContinue` 로 먼저 본다).

## 기존 코드 참조

- `.githooks/pre-commit` — 첫 줄 주석 `# 켜기: git config core.hooksPath .githooks` 와 같은 값을 맞춘다.
- `rdp-notify/install.ps1` — 같은 단계의 항목 스크립트 모양.
- `.gitattributes` — `.githooks/*` 는 `text eol=lf` 다. `install.ps1` 도 LF 로 체크아웃된다. PowerShell 은 LF 를 읽는다.

## 인수 조건

- [ ] 표 1~5 와 실제 선언 단언이 테스트로 있다.
- [ ] 테스트가 이 저장소(`<저장소>/.git/config`)의 `core.hooksPath` 를 바꾸지 않는다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 `[저장소 도구] .githooks: 다름 (.githooks 가 아니다)` 를 출력하고 `실패` 0개로 끝난다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 저장소의 `core.hooksPath` 를 바꾸는 것(이 PC 에서 고치는 실행 금지).
- `--global` 설정을 쓰는 것.
- 결과 줄에 지금 `core.hooksPath` 값을 쓰는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
