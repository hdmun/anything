# Hyper-V VM 검증 체크리스트

새 PC 경로(빈 Windows → 부트스트랩 → 셋업)를 Hyper-V VM 에서 손으로 검증할 때 따른다.

## 언제

- [ ] 처음 한 번 검증하거나, 부트스트랩·승격 단계·재부팅 처리에 큰 변경이 있었을 때 진행한다.
- [ ] 큰 변경 뒤에는 검증 PC 에서도 셋업을 다시 돌린다([verify-pc-checklist.md](verify-pc-checklist.md)).

## 1. 이미지 준비 (처음 한 번)

예상 시간: 1~2시간.

- [ ] Windows 11 ISO 를 받는다.
- [ ] Hyper-V 관리자에서 2세대 VM 을 만든다(보안 부팅·TPM 켬, 메모리·디스크는 셋업 앱이 들어갈 만큼, 예: 8GB·128GB).
- [ ] Windows 11 을 설치하고 OOBE 를 마친다(로컬 계정, 관리자 그룹 사용자 = 새 PC 와 같은 UAC 조건).
- [ ] Windows Update 를 끝까지 적용한다.
- [ ] 체크포인트 `clean` 을 찍는다. 이후 검증은 항상 `clean` 에서 시작한다.

## 2. 부트스트랩

- [ ] 시작 시각을 적는다.
- [ ] VM 안 **일반 권한** Windows PowerShell 5.1 창을 연다.
- [ ] 검증할 브랜치의 raw URL 로 부트스트랩을 실행한다(`pc-setup/bootstrap.ps1` 의 브랜치 지정 형식).
  `main` 브랜치:
  ```powershell
  irm https://raw.githubusercontent.com/hdmun/anything/main/pc-setup/bootstrap.ps1 | iex
  ```
  다른 브랜치(`<branch>` 자리에 브랜치 이름):
  ```powershell
  & ([scriptblock]::Create((irm https://raw.githubusercontent.com/hdmun/anything/<branch>/pc-setup/bootstrap.ps1))) -Branch <branch>
  ```
- [ ] UAC 확인 창이 뜰 때마다 센다(이 단계는 1회여야 한다).
- [ ] 끝 시각을 적는다.

## 3. 재부팅과 셋업 다시 실행

- [ ] 끝 요약에 `할 일: 재부팅 후 셋업 다시 실행` 이 있으면 VM 을 재부팅한다.
- [ ] 재부팅 뒤 **일반 권한** 창에서 셋업을 다시 실행한다.
  ```powershell
  pwsh $HOME\anything\pc-setup\setup.ps1
  ```
- [ ] `할 일` 이 없어질 때까지 재부팅과 다시 실행을 되풀이한다(재부팅 횟수를 적는다).
- [ ] Ubuntu 항목이 끝나는지 확인한다.

## 4. 확인

- [ ] 끝 요약의 `실패` 가 0개인지 확인한다.
- [ ] 셋업 첫 실행의 UAC 1회(부트스트랩과 합쳐 총 2회)와 끝 요약의 `승격 요청` 이 일치하는지 확인한다.
- [ ] msstore 앱 2개(Docker Desktop·iCloud)가 설치됐는지 확인한다.
  ```powershell
  winget list --id XP8CBJ40XLBWKX
  winget list --id 9PKTQ5699M62
  ```
- [ ] WSL 의 Ubuntu 24.04 가 실행되는지 확인한다.
  ```powershell
  wsl -d Ubuntu-24.04 -- echo ok
  ```

## 5. 재실행 (멱등)

- [ ] **일반 권한** 창에서 셋업을 한 번 더 실행한다.
  ```powershell
  pwsh $HOME\anything\pc-setup\setup.ps1
  ```
- [ ] 끝 요약의 `바꿈`·`실패` 가 0개이고 UAC 가 1회인지 확인한다.
- [ ] 끝나면 체크포인트 `after-setup` 을 찍는다.

## 6. 결과 기록

- [ ] 해당 구현 이슈의 PR 에 아래 항목을 댓글로 남긴다.
- [ ] 브랜치·커밋
- [ ] 단계별 끝 요약(붙여 넣기)
- [ ] UAC 횟수(부트스트랩·셋업 첫 실행·재실행)
- [ ] 재부팅 횟수
- [ ] 걸린 시간(합격 조건이 아니라 기록만 한다)
- [ ] 문제와 처리
