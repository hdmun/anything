# 설정 파일 (config-files.md)

**셋업**이 저장소 정본에 연결하는 **설정 파일**의 **선언**이다. 진행 방법은 [SETUP.md](SETUP.md) 를 따른다.

## 기본 규칙

- **확인과 맞춤은 반드시 `tools/link-config.ps1` 로 한다.** 링크나 include 줄을 직접 만들지 않는다.
  - 확인: `pwsh -NoProfile -File tools/link-config.ps1 -Source <정본> -Target <원래 자리> -Mode <방식> -Check`
  - 맞춤: 같은 명령에서 `-Check` 를 뺀다.
  - `<정본>` 은 저장소 정본 칸의 경로(`pc-setup` 폴더 기준)를 절대 경로로 바꾼 것이다. `<원래 자리>` 는 원래 자리 칸의 경로를 이 PC 의 절대 경로로 바꾼 것이다.
  - `<방식>` 은 거는 방법이 "링크"면 `Link`, "로컬 파일이 include"면 `GitInclude` 다.
- **출력 읽기**: `그대로` → `그대로`, `다름: …` → 계획의 맞출 항목, `바꿈: …` → `바꿈`, `실패: …` → `실패`. 맞춘 뒤에는 `-Check` 로 다시 확인해 `그대로`가 나와야 `바꿈`이다.
- **의존**: 설정 파일의 원래 자리는 그 앱이 설치된 뒤에 생긴다. 그 앱이 `실패`면 `실패: <앱> 실패`로 기록한다. 그 앱이 **개발툴**([dev-tools.md](dev-tools.md))이고 `할 일`(설치 안 됨)이면 맞추지 않고 `할 일: <앱> 설치 뒤 셋업을 다시 실행`으로 기록한다.
- 승격 항목은 없다. 링크는 개발자 모드가 켜져 있으면 관리자 없이 만들 수 있다([windows-settings.md](windows-settings.md) 의 개발자 모드).

## 목록

| 설정 파일 | 원래 자리 | 거는 방법 | 저장소 정본 |
|---|---|---|---|
| git 사용자 설정 | `~/.gitconfig` | 로컬 파일이 include | `config/gitconfig` |
| Windows Terminal | Windows Terminal 이 읽는 settings.json | 링크 | `config/windows-terminal.json` |
| nano | `~/.nanorc` | 링크 | `config/nanorc` |

## git 사용자 설정

- `~/.gitconfig` 는 이 PC 전용 **로컬 파일**로 남는다. 저장소 정본을 불러오는 include 줄만 맞추고, 그 밖의 줄(이 PC 에만 맞는 값)은 건드리지 않는다.

## Windows Terminal

- 원래 자리는 Windows Terminal 의 설치 방식(winget·Microsoft Store 등)에 따라 다르다. 이 PC 에 설치된 Windows Terminal 이 실제로 읽는 settings.json 을 공식 문서에서 찾아 쓴다.
- 개발툴 Windows Terminal([dev-tools.md](dev-tools.md))에 의존한다.
