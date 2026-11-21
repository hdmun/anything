> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/112
> updatedAt: 2026-11-15T08:58:40Z

# Hyper-V VM 검증 체크리스트를 쓴다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 도구다. 새 PC 경로(빈 Windows → **부트스트랩** → **셋업**)는 사람이 Hyper-V VM 에서 손으로 검증한다. 실제 UAC 확인 창, 재부팅, Store 앱, Windows 기능, GitHub raw URL 도 이 검증에서 본다. Windows Sandbox 로 자동 검증하는 방법은 쓰지 않기로 했다([pc-setup 부트스트랩과 Sandbox 하네스](https://github.com/hdmun/anything/issues/88) 「결정 (2026-11-15)」). VM 검증 순서는 [셋업 검증 방법 정하기](https://github.com/hdmun/anything/issues/46) 「VM 검증 (층 4)」를 따른다. 자동화(PowerShell Direct)는 하지 않는다.

이 PC 에는 Hyper-V 가 이미 켜져 있다(`Microsoft-Hyper-V-All` Enabled, 2026-11-11 확인). 그래서 VM 검증은 이 PC 를 바꾸지 않는다([집의 다른 PC 로 셋업을 검증하는 방식 정하기](https://github.com/hdmun/anything/issues/71)).

VM 검증은 처음 한 번 하고, 그 뒤에는 큰 변경(부트스트랩, **승격 단계**, 재부팅 처리) 뒤에 한다. 큰 변경 뒤에는 검증 PC 에서도 셋업을 다시 돌린다.

기준 수치(같은 티켓 「완료 조건 수치」): 새 PC 첫 실행의 승격 요청 2회(부트스트랩 1 + 셋업 1), 재실행 1회. 두 번째 고치는 실행에서 `바꿈`·`실패` 0개. 시간은 합격 조건이 아니고 기록만 한다.

## 범위 밖 (건드리지 말 것)

- VM 을 만들거나 다루는 스크립트. 문서만 쓴다.
- `pc-setup/README.md`, `pc-setup/test/verify-pc-checklist.md`: 다른 태스크.
- 셋업·부트스트랩 코드.

## 변경 대상 파일

- `pc-setup/test/vm-checklist.md` — 신규
- `pc-setup/tests/Docs.Tests.ps1` — 신규

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.** 문서의 `##` 제목과 순서:

```
# Hyper-V VM 검증 체크리스트
## 언제
## 1. 이미지 준비 (처음 한 번)
## 2. 부트스트랩
## 3. 재부팅과 셋업 다시 실행
## 4. 확인
## 5. 재실행 (멱등)
## 6. 결과 기록
```

## 동작 명세

### 정상 경로

각 절은 사람이 위에서 아래로 따라 하는 `- [ ]` 체크 항목이다. 명령은 코드 블록으로 쓴다.

- **언제**: 처음 한 번, 그 뒤 큰 변경(부트스트랩·승격 단계·재부팅 처리) 뒤. 그때 검증 PC 에서도 셋업을 다시 돌린다(`verify-pc-checklist.md` 링크).
- **1. 이미지 준비**(1~2시간): Windows 11 ISO 받기 → Hyper-V 관리자에서 2세대 VM(보안 부팅·TPM 켬, 메모리·디스크는 셋업 앱이 들어갈 만큼, 예: 8GB·128GB) → 설치와 OOBE(로컬 계정, 관리자 그룹 사용자 = 새 PC 와 같은 UAC 조건) → Windows Update 끝까지 → 체크포인트 `clean`. 이후 검증은 항상 `clean` 에서 시작한다.
- **2. 부트스트랩**: VM 안 **일반 권한** Windows PowerShell 5.1 창에서 검증할 브랜치의 raw URL 로 부트스트랩을 실행한다. 호출 모양은 `pc-setup/bootstrap.ps1` 이 정한 브랜치 지정 형식을 그대로 쓴다(브랜치가 `main` 이면 `irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex`). UAC 확인 창이 뜰 때마다 센다(이 단계는 1회여야 한다). 시작·끝 시각을 적는다.
- **3. 재부팅과 셋업 다시 실행**: 끝 요약에 `할 일: 재부팅 후 셋업 다시 실행` 이 있으면 재부팅하고 `pwsh $HOME\anything\pc-setup\setup.ps1` 을 일반 권한 창에서 다시 실행한다. 할 일이 없어질 때까지 되풀이한다. Ubuntu 항목이 끝나는지 본다.
- **4. 확인**: 끝 요약의 `실패` 0개. 셋업 첫 실행의 UAC 1회(부트스트랩과 합쳐 2회)와 끝 요약의 `승격 요청` 이 일치한다. msstore 앱 2개(Docker Desktop·iCloud)가 설치됐다(`winget list --id XP8CBJ40XLBWKX`, `winget list --id 9PKTQ5699M62`). WSL 의 Ubuntu 24.04 가 실행된다.
- **5. 재실행**: 셋업을 한 번 더 실행한다. `바꿈`·`실패` 0개, UAC 1회. 끝나면 체크포인트 `after-setup` 을 찍는다.
- **6. 결과 기록**: 해당 구현 이슈의 PR 에 댓글로 남긴다. 담을 것: 브랜치·커밋, 단계별 끝 요약(붙여 넣기), UAC 횟수(부트스트랩·셋업 첫 실행·재실행), 재부팅 횟수, 걸린 시간, 문제와 처리.

### 엣지 케이스

`Docs.Tests.ps1` 에 아래를 각각 테스트로 둔다(문서 모양만 본다).

- `pc-setup/test/vm-checklist.md` 가 있고 `##` 제목이 「시그니처」의 일곱 개, 그 순서다.
- 문서에 `clean`·`after-setup` 체크포인트 이름이 있다.
상대 링크 검사는 넣지 않는다. 이 문서가 가리키는 `verify-pc-checklist.md` 를 다음 태스크가 만들고, 그 태스크가 두 문서의 링크 검사를 함께 더한다.

### 에러 처리

해당 없음(문서).

## 기존 코드 참조

- `pc-setup/bootstrap.ps1` — 브랜치 지정 호출 모양과 끝 요약.
- `pc-setup/CONTEXT.md` — 용어.

## 인수 조건

- [ ] 「엣지 케이스」의 두 테스트가 있고 통과한다.
- [ ] 문서의 모든 단계가 `- [ ]` 체크 항목이다.
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- VM 을 자동으로 만들거나 조작하는 스크립트를 쓰는 것.
- 결정에 없는 합격 기준(시간 상한 등)을 더하는 것.
- 테스트를 건너뛰게 만드는 것, 단언을 약하게 고쳐 통과시키는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
