# 앱 (apps.md)

**셋업**이 설치하는 앱·**런타임**·전역 도구의 **선언**이다. 진행 방법은 [SETUP.md](SETUP.md) 를 따른다. 이 파일에는 무엇을·왜·확인 기준만 적는다. 설치 방법은 셋업할 때 공식 문서에서 찾는다.

개발툴은 여기에 두지 않는다. 셋업은 개발툴을 설치하지 않고 확인만 한다([dev-tools.md](dev-tools.md)). 개발툴 가운데 여기에 남은 것은 기반 도구(Git·PowerShell 7·Python·Go·nvm·Node·pnpm)뿐이다. 저장소 도구와 셋업 밖 개발툴 설치가 이 도구들에 기댄다.

## 기본 규칙

- **확인**: 원천마다 아래 기준으로 본다. 기준을 통과하면 `그대로`다.
  - winget·winget msstore: 그 원천의 설치 목록에 원천 힌트의 ID 가 정확히 일치하는 항목으로 있다.
  - nvm: `nvm` 명령이 있고, 버전 줄에 맞는 Node 가 설치돼 있으며 지금 쓰는 Node 다.
  - 공식 배포: 표 아래 그 앱의 절에 적은 기준을 쓴다.
- **버전**: 이미 설치된 앱은 버전을 올리지 않는다. 버전 줄 칸이 있는 앱만 그 줄 안의 버전이어야 한다. 업그레이드는 셋업 밖에서 한다.
- **버전 다름**: 설치된 버전이 버전 줄이나 앱 절에 적은 기대 버전과 다르면 셋업이 스스로 올리거나 내리지 않는다. 계획에 `버전 다름: <설치됨> / <선언>` 으로 보이고, 사람이 `그대로 둠` 과 `맞춤` 가운데 고른다. `그대로 둠` 을 고르면 결과는 `그대로`다.
- **범위**: winget 앱은 범위 칸의 범위(`user`/`machine`)로 설치한다. msstore 와 그 밖의 원천에는 범위 칸이 없다.
- **승격**: 승격 칸이 `필요`인 앱과, 범위가 `machine` 인 winget 앱은 승격 항목이다(**승격 단계**에서 맞춘다).
- **의존**: 표의 순서대로 진행한다. 앞 항목이 `실패`면 그 항목에 의존하는 항목은 시도하지 않고 `실패: <앞 항목> 실패`로 기록한다. Node 는 nvm 에, pnpm 은 Node 에 의존한다.

## 목록

| 앱 | 원천 | 원천 힌트 | 범위 | 버전 줄 | 승격 | 왜 |
|---|---|---|---|---|---|---|
| Git | winget | `Git.Git` | user | | | 기반 도구: 저장소·git 훅·셋업 밖 도구 설치의 바탕 |
| PowerShell 7 | winget | `Microsoft.PowerShell` | user | | | 기반 도구: 저장소 도구와 `tools/` 스크립트가 pwsh 로 돈다 |
| 7-Zip | winget | `7zip.7zip` | machine | | | |
| Everything | winget | `voidtools.Everything` | machine | | | |
| Obsidian | winget | `Obsidian.Obsidian` | user | | | |
| Chrome | 공식 배포 | Google Chrome 설치 프로그램(안정 채널) | | | 필요 | |
| Discord | winget | `Discord.Discord` | user | | | |
| Python | winget | `Python.Python.3.13` | user | 3.13 | 필요 | 기반 도구: codex-statusline 이 의존한다. py 런처 설치에 관리자 권한이 필요하다 |
| Go | winget | `GoLang.Go` | machine | | | 기반 도구: 개발툴의 `go install` 이 쓴다 |
| iCloud | winget msstore | `9PKTQ5699M62` | | | | |
| nvm | 공식 배포 | nvm-windows 2.x 설치 프로그램 | | | | 기반 도구: Node 버전 관리(nvm-windows 2.x) |
| Node | nvm | | | 26 | | 기반 도구: pnpm 과 전역 패키지의 바탕 |
| pnpm | 공식 배포 | npm 전역 패키지 `pnpm` | | | | 기반 도구: 개발툴의 `pnpm add -g` 가 쓴다 |
| RaiDrive | 공식 배포 | RaiDrive Mount | | | 필요 | |
| D2Coding | 공식 배포 | NAVER D2Coding 글꼴 | | | | 터미널·편집기 글꼴 |
| NVIDIA 드라이버 | 공식 배포 | NVIDIA 그래픽 드라이버 | | | | |

## Chrome

- 확인: Windows 의 설치된 프로그램 목록에 이름이 정확히 `Google Chrome` 인 항목이 있다. `Google Chrome Beta` 같은 다른 채널은 통과하지 않는다.
- winget 목록으로 확인하지 않는다. winget 이 이미 설치된 안정 채널 Chrome 을 다른 ID(Beta)로 잘못 잡는 경우가 있다.
- 모든 사용자용으로 설치한다(승격 단계에서).

## nvm

- 확인: `nvm` 명령이 있다. 기대 버전은 2.x 다. 1.x 가 설치돼 있으면 기본 규칙의 **버전 다름**으로 다룬다.
- 새로 설치할 때는 2.x 설치 프로그램을 일반 권한으로 실행한다.
- 1.x → 2.x 업그레이드는 셋업 밖에서 한다. 2.x 설치 프로그램이 1.1.7 이상의 1.x 를 옮겨 준다.

## pnpm

- 확인: `pnpm` 명령이 있고, 사용자 환경 변수 `PNPM_HOME` 이 있으며 그 폴더가 사용자 PATH 에 있다. 어떤 방법으로 설치했는지는 보지 않는다(독립 실행 스크립트로 설치한 pnpm 도 통과한다).
- 없을 때만 npm 전역 패키지로 설치한다. 그 뒤 `PNPM_HOME` 을 공식 문서의 방법으로 정한다. Node 에 의존한다.
- 주의: `PNPM_HOME` 의 PATH 추가는 [SETUP.md](SETUP.md) 의 규칙대로 `tools/add-user-path.ps1` 로 한다.

## RaiDrive

- 확인: Windows 의 설치된 프로그램 목록에 이름이 `RaiDrive` 로 시작하는 항목이 있다.
- 설치 프로그램이 재부팅이 필요하다고 끝나면 `할 일: 재부팅 뒤 셋업을 다시 실행`이다.

## D2Coding

- 확인: 현재 사용자 글꼴 목록에 이름이 `D2Coding` 으로 시작하는 글꼴이 있고, 그 글꼴 파일이 실제로 있다.
- 현재 사용자 글꼴로 설치한다(관리자 없이). 공식 릴리스의 모든 굵기를 담은 글꼴 묶음 파일을 쓴다.

## NVIDIA 드라이버

- 확인: 디스플레이 장치 가운데 NVIDIA 장치가 없으면 `그대로`다. NVIDIA 장치가 있으면 그 장치의 드라이버 제공자가 NVIDIA 여야 `그대로`다.
- 에이전트는 드라이버를 설치하지 않는다. 기준과 다르면 `할 일: NVIDIA 드라이버 설치`로 기록한다.

