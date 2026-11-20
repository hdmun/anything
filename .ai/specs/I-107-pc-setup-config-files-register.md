> spec 스냅숏 — 정본은 구현 이슈다. 이 파일을 고치지 않는다.
> 이슈: https://github.com/hdmun/anything/issues/107
> updatedAt: 2026-11-20T06:07:53Z

# 설정 파일 선언 3줄과 저장소 설정 파일을 더하고 단계로 등록한다

## 배경

구현자는 이전 대화를 모른다. 여기에 다 적는다.

`pc-setup/` 은 Windows 11 집 PC 를 **선언**대로 맞추는 **셋업** 도구다. 설계는 1번 구현 이슈 [pc-setup 셋업 뼈대와 Windows 설정](https://github.com/hdmun/anything/issues/82)의 「공통 설계」 절에 있다. 이 이슈의 부모는 [pc-setup 설정 파일과 저장소 도구](https://github.com/hdmun/anything/issues/105)이다. 앞 태스크가 **설정 파일** 처리 모듈(`pc-setup/lib/ConfigFiles.psm1`: `Get-ConfigFileItems`·`Invoke-LinkFile`·`Invoke-GitIncludeFile`)을 만들었다.

이 태스크는 실제 선언과 저장소 쪽 설정 파일을 더하고, 설정 파일 단계를 셋업에 등록한다([설정 파일 관리 방식 정하기: symlink·복사](https://github.com/hdmun/anything/issues/45) 와 그 정정. 설정 파일은 [에이전트 설정 디렉터리 경계 정하기](https://github.com/hdmun/anything/issues/64) 뒤로 셋이다).

| 원래 자리 | 연결 방식 | 저장소 파일 |
|---|---|---|
| `~/.gitconfig` | `GitInclude` | `pc-setup/config/gitconfig` |
| Windows Terminal `settings.json` | `Link` | `pc-setup/config/windows-terminal.json` |
| `~/.nanorc` | `Link` | `pc-setup/config/nanorc` |

이 저장소(`hdmun/anything`)는 **공개**다. 저장소 설정 파일에 개인값(사용자 이름이 든 경로, IP 주소, PC 이름, 토큰)이 들어가면 안 된다. 저장소 설정 파일에 들어갈 개인값은 없고, PC 마다 다른 값은 각 PC 의 로컬 파일에 사람이 적는다(같은 티켓 「개인값」).

이 PC 의 원본 파일 상태(2026-11-11 읽기 전용으로 확인):

- `~/.gitconfig`: 일반 파일 10줄, 섹션 `[user]`(`name`·`email`)·`[filter "lfs"]`(`smudge`·`process`·`required`·`clean`)·`[core]`(`longpaths`). `user.email` 은 GitHub noreply 주소라 이미 커밋마다 공개돼 있다(같은 티켓). 이 세 섹션을 그대로 옮긴다.
- `~/.nanorc`: 일반 파일. 주석이 아닌 줄은 `include` 한 줄뿐인데, 그 줄은 사용자 이름이 든 절대 경로를 쓴다. 저장소 파일에는 결정대로 `include "~/scoop/apps/nano/current/syntax/*.nanorc"` 한 줄만 둔다(절대 경로를 옮기지 않는다). scoop nano 가 `~` 를 펼치는지는 사람이 머지 전에 눈으로 확인한다(부모 이슈 「사람이 할 일」).
- WT `settings.json`(`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`): 일반 파일 약 5KB. 사용자 이름, `C:\Users` 경로, IP 모양 글, ssh 명령이 없었다. 프로필 목록에는 VS·Ubuntu 같은 자동 생성 프로필과 `commandline` 프로필 둘(Windows PowerShell·명령 프롬프트)이 있다. 그대로 옮긴다.

이 PC 의 설정 파일 셋은 셋업으로 연결하지 않은 채로 둔다([집의 다른 PC 로 셋업을 검증하는 방식 정하기](https://github.com/hdmun/anything/issues/71)). 그래서 이 PC `-Check` 에서 세 줄이 `다름` 으로 나오는 것이 정상이다. `실패` 는 안 된다.

WT 는 로드할 때 설정 파일을 스스로 다시 쓴다. 링크된 PC 에서 생기는 저장소 diff 는 받아들이고 그때마다 커밋하거나 되돌린다([설정 파일 symlink 연결 시 깨지는 앱과 Developer Mode 조건](https://github.com/hdmun/anything/issues/38)). 이 태스크에서 처리할 것은 없다.

## 범위 밖 (건드리지 말 것)

- `pc-setup/lib/ConfigFiles.psm1` 의 동작. 버그를 찾으면 `ask` 로 묻는다.
- 이 PC 의 `~/.gitconfig`·`~/.nanorc`·WT 설정을 바꾸는 것(읽어서 옮기기만 한다).
- 저장소 도구 단계: 뒤 태스크.
- VS Code 설정(Settings Sync 가 정본), `~/.ssh/config`(수동 체크리스트), PowerShell 프로필.

## 변경 대상 파일

- `pc-setup/config-files.psd1` — 신규
- `pc-setup/config/gitconfig` — 신규
- `pc-setup/config/nanorc` — 신규
- `pc-setup/config/windows-terminal.json` — 신규
- `pc-setup/lib/Setup.psm1` — 수정 (`$script:DefaultStageProviders` 에 설정 파일 단계 추가)
- `pc-setup/tests/ConfigFiles.Tests.ps1` — 수정 (실제 선언·저장소 설정 파일 테스트 추가)
- `pc-setup/tests/AppsDeclaration.Tests.ps1` — 수정 ('Setup 기본 단계 등록' 테스트만: 기본 단계 수 단언을 `2` → `3` 으로, 셋째 단계가 `설정 파일` 임을 확인. `Get-ConfigFileItems` 모킹(Stage `설정 파일`, Id `FakeConfigFile`)을 더하고 `Results.Count` 를 `3` 으로, `Results[2]` 의 Stage·Id 를 단언한다. 다른 테스트는 건드리지 않는다)

**이 목록 밖의 파일은 생성/수정 금지.**

## 시그니처

**그대로 쓸 것, 임의 변경 금지.**

```powershell
# pc-setup/config-files.psd1
@{
    Items = @(
        @{ Path = '~/.gitconfig'; Method = 'GitInclude'; Source = 'config/gitconfig' }
        @{ Path = '$env:LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'; Method = 'Link'; Source = 'config/windows-terminal.json' }
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = 'config/nanorc' }
    )
}
```

`Path` 는 작은따옴표다(`$env:` 를 셋업이 펼친다).

```powershell
# pc-setup/lib/Setup.psm1 — 단계 목록의 '앱' 단계 뒤에 더한다
{ param($Root) Get-ConfigFileItems -Root $Root }
```

```
# pc-setup/config/nanorc (이 한 줄)
include "~/scoop/apps/nano/current/syntax/*.nanorc"
```

## 동작 명세

### 정상 경로

1. `config-files.psd1` 을 위 시그니처 그대로 만든다.
2. `config/gitconfig`: 이 PC `~/.gitconfig` 의 `[user]`·`[filter "lfs"]`·`[core]` 세 섹션을 키·값 그대로 옮긴다. 다른 섹션이 그 사이 생겼으면 옮기지 않고 `ask` 로 묻는다.
3. `config/nanorc`: 위 한 줄과 끝 줄바꿈만.
4. `config/windows-terminal.json`: 이 PC 의 WT `settings.json` 을 그대로 복사한다. 복사한 뒤 아래 「유출 검사」를 직접 해 보고, 걸리면 그 값을 지우지 말고 `ask` 로 묻는다.
5. `Setup.psm1` 의 `$script:DefaultStageProviders` 에 설정 파일 단계를 앱 단계 바로 뒤에 넣는다. 결과로 단계 순서는 Windows 설정 → 앱 → 설정 파일이다.
6. `Setup.psm1` 이 `ConfigFiles.psm1` 을 불러오게 한다(다른 단계 모듈과 같은 방식).

### 유출 검사 (테스트로 둔다)

`pc-setup/config/` 의 모든 파일에 대해:

- `[A-Za-z]:[\\/]Users[\\/]` 가 없다(사용자 폴더 절대 경로).
- IPv4 모양(`\b\d{1,3}(\.\d{1,3}){3}\b`)이 없다.
- `gitconfig` 의 `email` 값이 `@users.noreply.github.com` 으로 끝난다.

### 엣지 케이스

아래를 `ConfigFiles.Tests.ps1` 에 테스트로 둔다. **열거하지 않은 경우는 범위 밖이다.**

- 저장소 `config-files.psd1` 이 `Get-ConfigFileItems -Root <pc-setup>` 검사를 통과하고, 항목 3개의 `Id` 가 위 순서이며 모두 `Elevated = $false` 다.
- 세 `Source` 파일이 있다.
- `config/nanorc` 의 주석·빈 줄이 아닌 줄이 정확히 `include "~/scoop/apps/nano/current/syntax/*.nanorc"` 하나다.
- `config/windows-terminal.json` 이 `ConvertFrom-Json` 으로 읽힌다.
- 유출 검사 세 가지.
- `Setup.psm1` 의 기본 단계 목록으로 만든 항목의 `Stage` 순서가 `Windows 설정` → `앱` → `설정 파일` 이다(항목이 없는 단계는 건너뛰고 본다).

### 에러 처리

- 없음(선언과 파일 추가).

## 기존 코드 참조

- `pc-setup/lib/ConfigFiles.psm1` — 앞 태스크의 `Get-ConfigFileItems`.
- `pc-setup/lib/Setup.psm1` — `$script:DefaultStageProviders` 와 다른 단계 모듈을 불러오는 줄.
- `pc-setup/windows-settings.psd1`, `pc-setup/apps.psd1` — 선언 파일 모양(`@{ Items = @( ... ) }`, 한 줄 한 항목).

## 인수 조건

- [ ] 엣지 케이스 목록이 각각 테스트로 있다.
- [ ] `pwsh -NoProfile -File pc-setup/setup.ps1 -Check` 가 이 PC 에서 `[설정 파일]` 세 줄을 출력하고 `실패` 0개로 끝난다(`다름` 은 허용).
- [ ] 이 PC 의 `~/.gitconfig`·`~/.nanorc`·WT `settings.json` 이 바뀌지 않았다(링크가 아니고 내용도 그대로).
- [ ] 게이트 명령: `pwsh -NoProfile -Command "Invoke-Pester -Path pc-setup/tests -CI" && pwsh -NoProfile -File pc-setup/setup.ps1 -Check` — 저장소 루트(Git Bash)에서 돌리고 종료코드로 판정한다

## 하지 말아야 할 것

- 이 PC 에서 셋업을 `-Check` 없이 돌리는 것, 이 PC 의 원본 설정 파일을 링크로 바꾸는 것.
- `nanorc` 에 사용자 이름이 든 절대 경로를 넣는 것.
- 유출 검사 테스트를 약하게 고쳐 통과시키는 것, 걸린 값을 임의로 지우는 것.
- 테스트를 건너뛰게 만드는 것.

## 판단이 필요하면

스스로 판단하지 말고 **dispatch preamble에 적힌 `ask` 명령을 그대로** 써서 코디네이터에게 물어보고 답을 받은 뒤 진행하세요.
파일에 메모를 남기고 중단하지 마세요. `AskUserQuestion`류의 로컬 프롬프트는 코디네이터가 볼 수 없으므로 절대 쓰지 마세요.
