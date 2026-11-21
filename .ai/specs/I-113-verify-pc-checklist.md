> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/113
> updatedAt: 2026-11-15T08:58:42Z

# 검증 PC 체크리스트를 쓴다 (Claude 세션이 따라 하는 순서)

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 도구다. 새 PC 경로는 Hyper-V VM 이 검증한다. **이미 쓰던 PC 경로**(앱이 이미 있고, 일반 설정 파일이 `.bak` 으로 백업된 뒤 링크로 바뀌고, nvm v1 을 v2 로 옮기는 경우)는 집의 다른 PC 인 **검증 PC** 에서 검증한다([집의 다른 PC 로 셋업을 검증하는 방식 정하기](https://github.com/hdmun/anything/issues/71)). 검증 PC 는 시험용이 아니라 실제로 셋업되어 계속 쓰는 PC 다. Windows 를 다시 설치하지 않는다. 선언의 출발점인 이 PC 에서는 `-Check` 만 돌린다.

검증 PC 에서는 사람이 Claude Code 만 손으로 설치하고 로그인한다. 그 PC 의 **Claude 세션**이 이 체크리스트를 따라 진행하고, 사람은 보고 확인과 UAC 확인 창을 맡는다. 원격 접속 경로(SSH 서버 등)는 열지 않는다. Claude 세션은 일반 권한 창에서 띄운다(부트스트랩·셋업은 관리자 창이면 멈춘다).

그래서 이 문서의 독자는 **검증 PC 의 Claude 세션**이다. 각 단계는 그 세션이 실행할 명령과, 사람에게 묻거나 맡길 지점을 분명히 적는다.

## 범위 밖 (건드리지 말 것)

- 셋업·부트스트랩 코드와 선언 파일.
- `pc-setup/README.md`(다음 태스크), `pc-setup/test/vm-checklist.md`(앞 태스크, 링크만 건다).
- PC 별 선언(만들지 않는다. 검증 PC 에 계속 다른 값이 필요하면 새 티켓에서 논의한다).

## 변경 대상 파일

- `pc-setup/test/verify-pc-checklist.md` — 신규
- `pc-setup/tests/Docs.Tests.ps1` — 수정 (이 문서 테스트와, 앞 태스크 `vm-checklist.md` 의 상대 링크 검사를 더한다)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.** 문서의 `##` 제목과 순서:

```
# 검증 PC 체크리스트
## 이 문서를 읽는 Claude 세션에게
## 0. 사람: Claude Code 설치
## 1. 미리보기 보고
## 2. 사람: 보고 확인
## 3. 셋업 전 정리 (해당할 때만)
## 4. 부트스트랩
## 5. 재부팅과 셋업 다시 실행
## 6. 재실행 (멱등)
## 7. 결과 기록
```

## 동작 명세

### 정상 경로

각 단계는 `- [ ]` 체크 항목이다. 명령은 코드 블록으로 쓴다. 사람이 해야 하는 일은 "사람:"으로 시작한다.

- **이 문서를 읽는 Claude 세션에게**: 역할(진행은 세션, 확인과 UAC 는 사람), 지켜야 할 것(일반 권한 창, 사람 확인 없이 지우지 않기, `-Skip` 은 사람이 정한 것만, 막히면 멈추고 묻기), 검증할 브랜치 이름은 사람이 알려 준다는 것.
- **0. 사람: Claude Code 설치**: 공식 설치 방법으로 Claude Code 를 설치하고 로그인한다. Git for Windows 가 먼저 필요하면 Git 도 손으로 설치한다(구현 때 확인할 사항으로 남은 것, 확인되면 문서에 사실로 적는다). 이렇게 손으로 설치한 Claude Code 는 셋업에서 설치된 것으로 보이고, 첫 셋업에서 PATH 맞춤만 `바꿈` 으로 나올 수 있다.
- **1. 미리보기 보고**: 바뀔 항목과 셋업 전 정리 대상을 사람에게 보고한다.
  - Git 과 pwsh 7 이 있으면: 검증할 브랜치를 `$HOME\anything` 에 clone 하고(폴더가 이미 있으면 그 폴더의 브랜치와 상태를 보고하고 사람에게 묻는다) `pwsh $HOME\anything\pc-setup\setup.ps1 -Check` 를 일반 권한으로 실행해 `다름`·`할 일`·`확인 못 함` 목록을 보고한다. 부트스트랩은 그 폴더가 있으면 clone 도 pull 도 하지 않고 그대로 쓴다.
  - 없으면: 브랜치의 선언 파일(`windows-settings.psd1`·`apps.psd1`·`config-files.psd1`·`repo-tools.psd1`)을 raw URL 로 읽고, `winget list`·레지스트리·파일 확인으로 항목마다 있는지 보고한다.
  - 셋업 전 정리 대상이 있는지도 본다(3번의 세 조건).
  - 보고 모양: 단계별로 `다름` 항목 목록, 셋업 전 정리 대상, 예상 UAC 횟수(부트스트랩: Git·pwsh 가운데 없는 것이 있으면 1회, 둘 다 있으면 0회 / 셋업 1회).
- **2. 사람: 보고 확인**: 선언이 틀렸으면 선언을 고치는 커밋을 브랜치에 먼저 하고 push 한다(1번부터 다시). 이번 실행에서만 피할 항목은 `-Skip <Id,...>` 로 정한다. 같은 `-Skip` 을 재실행에도 넘긴다. 셋업 전 정리 각 항목을 할지 정한다.
- **3. 셋업 전 정리 (해당할 때만, 사람이 확인한 뒤)**:
  - nvm-windows 가 있으면: `npm ls -g --depth=0` 결과를 기록 → `winget uninstall CoreyButler.NVMforWindows` → 남아 있으면 `C:\nvm4w`, `%LOCALAPPDATA%\nvm`, 환경 변수 `NVM_HOME`·`NVM_SYMLINK` 정리. 그 뒤 부트스트랩에서 scoop nvm v2 와 Node 26 이 설치된다([런타임 버전 관리 방식 정하기](https://github.com/hdmun/anything/issues/62)).
  - pnpm 단독 설치본이 있으면(`%LOCALAPPDATA%\pnpm` 에 `pnpm.exe` 등): 실행 파일(`pnpm`·`pnpm.CMD`·`pnpx*`)과 `.tools` 만 지운다. 폴더(`PNPM_HOME`)는 남긴다(전역 패키지와 `store` 자리, codex 도 여기에 설치된다). 실행 파일을 지우는 이유: PATH 에 남은 단독 설치본이 winget pnpm 을 가릴 수 있다.
  - 로컬 `~/.gitconfig` 에 저장소 `pc-setup/config/gitconfig` 와 겹치는 섹션(`[user]`·`[filter "lfs"]`·`[core]`)이 있으면 지운다.
  - npm 전역 패키지(`%APPDATA%\npm`)는 지우지 않는다. claude·codex 가 두 벌이 될 수 있지만 `apps/claude-code.ps1` 이 `~/.local/bin` 을 사용자 PATH 맨 앞에 넣어 새 판이 먼저 실행된다([런타임 전역 패키지 선언 정하기](https://github.com/hdmun/anything/issues/67)).
- **4. 부트스트랩**: 일반 권한 Windows PowerShell 5.1 에서 브랜치의 raw URL 로 부트스트랩을 실행한다. 브랜치·`-Skip` 을 넘기는 호출 모양은 `pc-setup/bootstrap.ps1` 이 정한 형식을 그대로 쓴다. 사람에게 UAC 확인 창을 누르라고 알리고 횟수를 센다. 출력 전체를 파일로 남긴다(7번에 쓴다).
- **5. 재부팅과 셋업 다시 실행**: 끝 요약에 `할 일: 재부팅 후 셋업 다시 실행` 이 있으면 사람에게 재부팅을 부탁한다. 재부팅 뒤 사람이 Claude 세션을 다시 열면, 세션은 이 문서의 5번부터 이어서 `pwsh $HOME\anything\pc-setup\setup.ps1 [-Skip ...]` 을 실행한다. 할 일이 없어질 때까지 되풀이한다.
- **6. 재실행 (멱등)**: 셋업을 한 번 더 실행한다. `바꿈`·`실패` 가 0개이고 UAC 가 1회여야 한다. 아니면 결과를 그대로 기록하고 사람에게 알린다.
- **7. 결과 기록**: 요약을 만든다. 담을 것: 브랜치·커밋, 1번 미리보기 보고, 셋업 전 정리에서 한 일, 단계별 끝 요약(붙여 넣기), 승격 요청 횟수(부트스트랩·셋업 첫 실행·재실행)와 실제 UAC 횟수, 재부팅 횟수, 걸린 시간, 문제와 처리. `gh auth status` 가 로그인돼 있으면 해당 구현 이슈의 PR 에 `gh pr comment` 로 직접 올린다. 아니면 요약을 사람에게 주고 사람이 붙여 넣는다. 요약에 이 PC 의 개인값(IP·PC 이름·토큰)을 넣지 않는다(공개 저장소).

### 엣지 케이스

`Docs.Tests.ps1` 에 아래를 각각 테스트로 둔다(문서 모양만 본다).

- `pc-setup/test/verify-pc-checklist.md` 가 있고 `##` 제목이 「시그니처」의 열 개, 그 순서다.
- 3번 절에 세 조건(`nvm-windows`, `pnpm`, `.gitconfig`)과 「npm 전역 패키지는 지우지 않는다」 문장이 있다.
- `vm-checklist.md` 와 `verify-pc-checklist.md` 의 상대 링크(`](` 뒤가 `http` 로 시작하지 않는 것, 앵커는 떼고 본다)가 가리키는 파일이 모두 있다.

### 에러 처리

해당 없음(문서).

## 기존 코드 참조

- `pc-setup/test/vm-checklist.md` — 앞 태스크가 쓴 같은 꼴의 문서.
- `pc-setup/bootstrap.ps1` — 브랜치·`-Skip` 호출 모양, 끝 요약의 승격 요청 횟수.
- `pc-setup/setup.ps1` — `-Check`·`-Skip`, 결과 말.
- `pc-setup/apps.psd1`, `pc-setup/config/gitconfig` — 셋업 전 정리 조건이 가리키는 항목.

## 인수 조건

- [ ] 「엣지 케이스」 테스트가 모두 있고 통과한다.
- [ ] 문서의 모든 단계가 `- [ ]` 체크 항목이고, 사람이 하는 일은 "사람:"으로 시작한다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 정리 단계를 조건 없이 실행하라고 쓰는 것, 사람 확인 없이 지우게 쓰는 것.
- 원격 접속(SSH 서버 열기 등)을 안내하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
