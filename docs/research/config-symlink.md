# 설정 파일을 symlink 로 연결할 때 앱별 동작과 Developer Mode 조건 (Windows 11)

이슈: hdmun/anything#38 (맵 #36) · 조사일 2026-11-07

용어는 `pc-setup/CONTEXT.md` 를 따른다. **선언** = 저장소에 둔 정본 설정 파일, **셋업** = PC 를 선언에 맞추는 멱등 실행, **부트스트랩** = 셋업을 처음 돌리기 전 단계.

로컬 확인 환경: Windows 11 Pro 10.0.26200(25H2), PowerShell 7.6.9, Windows PowerShell 5.1.26100, Git for Windows 2.47.0, OpenSSH_for_Windows 9.5p2, Windows Terminal 1.24.12741.0. 관리자 권한이 **없는** 셸에서 실행했다. 실측은 모두 새로 만든 `%TEMP%\symtest-*` 디렉터리 안에서만 했고 끝나면 지웠다. 실제 설정 파일·레지스트리·시스템 설정은 바꾸지 않았다.

## 결론 요약

| 설정 파일 | symlink 괜찮은가 | 깨지거나 불편한 점 | 근거 |
|---|---|---|---|
| `$PROFILE` (`Documents\PowerShell\Microsoft.PowerShell_profile.ps1`) | **괜찮다.** PowerShell 은 읽기만 한다 | 프로필 안의 `$PSScriptRoot` 는 **링크가 있는 폴더**를 가리킨다(저장소 폴더가 아님). 저장소의 다른 파일을 상대 경로로 dot-source 하면 깨진다. 문서 폴더가 OneDrive 로 리디렉션되면 경로가 바뀐다(아래 OneDrive 절) | 로컬 실측, [about_Profiles](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles) |
| `~/.gitconfig` | **괜찮다.** `git config --global` 로 써도 링크가 유지되고 대상 파일이 바뀐다 | 없음. 다만 `--global` 로 쓰는 개인값(이메일 등)이 저장소 파일에 들어간다 | git `lockfile.h`(심링크를 풀어서 잠금), 로컬 실측 |
| `~/.ssh/config` | **괜찮다.** ssh 가 링크를 따라 읽는다 | 권한 검사는 **링크 자신의 ACL** 로 한다. `~/.ssh` 안에 만든 링크는 그 폴더 ACL 을 물려받아 통과한다 | Win32-OpenSSH `readconf.c`·`misc.c`, 로컬 실측 |
| Windows Terminal `settings.json` | **조건부.** 1.10/1.11 부터 저장 시 링크를 유지한다 | (1) 링크 대상이 바뀌어도 자동으로 다시 읽지 않는다. 터미널을 다시 켜야 한다. 설정 UI 의 Save 도 저장은 되지만 화면에 반영되지 않는다. (2) 터미널이 파일 전체를 다시 써서 주석·서식이 사라지고, 새 동적 프로필이 생기면 스스로 파일을 고친다. 저장소에 diff 가 생긴다 | microsoft/terminal #10787·PR #10908, #1812, #17282, `til/io.h`, `CascadiaSettingsSerialization.cpp` |
| VS Code `settings.json`·`keybindings.json` | **괜찮다(1.83.1 이후).** symlink 이면 원자적 쓰기를 끄고 대상에 바로 쓴다 | 1.83.0 에서만 저장 시 링크가 일반 파일로 바뀌는 회귀가 있었다(1.83.1 에서 수정). 외부에서 대상이 바뀌면 감시기가 실제 경로를 따라가 반영한다 | microsoft/vscode #194856·PR #195216, `diskFileSystemProvider.ts`, `fileUserDataProvider.ts`, `nodejsWatcherLib.ts` |

한 줄 결론: **파일 연결에는 symlink 가 맞다.** hardlink 는 앱의 원자적 저장과 `git checkout` 양쪽에서 끊긴다. 관리자 없이 symlink 를 만들려면 Developer Mode 가 켜져 있어야 하고, Developer Mode 를 켜는 일 자체는 관리자 권한이 필요하다. 그래서 켜기는 **부트스트랩**의 관리자 단계에 넣고, 링크 만들기는 일반 권한의 **셋업**에서 PowerShell 7 로 한다(Windows PowerShell 5.1 의 `New-Item` 은 Developer Mode 를 켜도 실패한다).

## 1. 앱별 상세

### 1.1 PowerShell 프로필 (`$PROFILE`)

- 경로(문서): Current user, Current Host = `$HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`. "In Windows, the location of the `Documents` folder can be changed by folder redirection or OneDrive." ([about_Profiles](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles))
- PowerShell 은 프로필을 실행만 하고 쓰지 않는다. 링크가 바뀔 일이 없다. 편집기로 고칠 때는 그 편집기의 저장 방식을 따른다(VS Code 는 링크를 유지한다, 1.5 절 참고).
- 로컬 실측: 저장소 쪽 `repo\profile.ps1` 을 가리키는 링크 `home\profile.ps1` 을 dot-source 하면 `$PSScriptRoot = <tmp>\home`, `$PSCommandPath = <tmp>\home\profile.ps1` 이다. 즉 **링크 위치**가 나온다. 프로필이 `. "$PSScriptRoot\other.ps1"` 처럼 저장소 안의 다른 파일을 부르면 깨진다.
- 대안: `$PROFILE` 에 한 줄짜리 일반 파일(stub)을 두고 저장소의 프로필을 dot-source 한다(`. "$HOME\<repo>\pc-setup\...\profile.ps1"`). 그러면 저장소 파일 안의 `$PSScriptRoot` 는 저장소 폴더를 가리킨다. 링크가 필요 없고 OneDrive 리디렉션에도 안전하다.

### 1.2 `~/.gitconfig`

- git 은 설정 파일을 쓸 때 `<파일>.lock` 을 만든 뒤 rename 한다. 이때 링크를 따라간다: "Usually symbolic links in the destination path are resolved. This means that (1) the lockfile is created by adding ".lock" to the resolved path, and (2) upon commit, the resolved path is overwritten." `LOCK_NO_DEREF` 를 줄 때만 예외인데, 설정 쓰기(`config.c` 의 `repo_hold_lock_file_for_update_timeout(..., 0, ...)`)는 이 플래그를 주지 않는다. ([git/lockfile.h](https://github.com/git/git/blob/master/lockfile.h), [git/config.c](https://github.com/git/git/blob/master/config.c))
- 로컬 실측: `GIT_CONFIG_GLOBAL` 을 임시 링크로 지정하고 `git config --global core.autocrlf false` 를 실행했다. 링크는 `SymbolicLink` 그대로였고 대상 파일에 값이 들어갔다.
- 주의: `git config --global user.email ...` 같은 개인값도 저장소 파일(대상)에 쓰인다. 공개 저장소이므로 문제가 된다.
- 대안(문서): `include.path`. "The contents of the included file are inserted immediately, as if they had been found at the location of the include directive. If the value of the variable is a relative path, the path is considered to be relative to the configuration file in which the include directive was found." `--global` 쓰기는 `~/.gitconfig` 로 간다. ([git-config](https://git-scm.com/docs/git-config) Includes·`--global` 절) → `~/.gitconfig` 를 일반 파일로 두고 `[include] path = ~/<repo>/pc-setup/.../gitconfig` 만 넣으면, 공유 설정은 저장소에서 오고 개인값은 로컬 파일에 남는다. 맵의 "개인값은 gitignore 파일 + 견본" 원칙과도 맞는다.

### 1.3 `~/.ssh/config` (OpenSSH for Windows)

- ssh 는 설정을 읽기만 한다(쓰지 않는다). `known_hosts` 는 쓰지만 이번 대상이 아니다.
- 권한 검사(코드): 사용자 설정 `~/.ssh/config` 는 `SSHCONF_CHECKPERM` 으로 읽는다. Windows 구현은 "the config file is owned by a user, administrators group, or LOCALSYSTEM account and nobody else except Administrators group, LOCALSYSTEM, and file owner account has the write permission" 을 확인하고, 아니면 `fatal("Bad owner or permissions on %s")` 이다. ([PowerShell/openssh-portable readconf.c](https://github.com/PowerShell/openssh-portable/blob/latestw_all/readconf.c), [ssh.c](https://github.com/PowerShell/openssh-portable/blob/latestw_all/ssh.c))
- 검사 대상이 링크인지 대상인지: `check_secure_file_permission` 은 `resolved_path_utf16()` → `realpath()`(내부는 `_wfullpath`, 심링크를 풀지 않음) → `GetNamedSecurityInfoW` 순서다. ([w32-sshfileperm.c](https://github.com/PowerShell/openssh-portable/blob/latestw_all/contrib/win32/win32compat/w32-sshfileperm.c), [misc.c](https://github.com/PowerShell/openssh-portable/blob/latestw_all/contrib/win32/win32compat/misc.c))
- 로컬 실측: 대상 파일에만 Everyone 쓰기 권한을 주면 `GetNamedSecurityInfoW(링크)` 결과에 Everyone 이 **없다**. 링크에만 `icacls /L` 로 Everyone 을 주면 결과에 **있다**. 즉 `GetNamedSecurityInfoW` 는 링크 자신의 ACL 을 돌려준다. → ssh 는 **링크의 ACL** 을 검사한다. `~/.ssh` 안에 만든 링크는 그 폴더 ACL(사용자·SYSTEM·Administrators)을 물려받으므로 통과한다. 저장소가 어디 있든(대상 ACL 이 느슨해도) 상관없다.
- 로컬 실측: 링크로 만든 임시 설정을 `ssh -G -F <링크> dummyhost` 로 읽으면 `hostname 192.0.2.10` 이 나온다(읽기 정상). 단 `-F` 로 준 파일은 권한 검사를 하지 않으므로(`ssh.c` 에서 `-F` 는 `SSHCONF_CHECKPERM` 없이 읽음) 권한 부분은 위 코드·ACL 실측으로 판단했다. 실제 `~/.ssh/config` 를 링크로 바꿔 보는 시험은 하지 않았다.
- 대안 `Include`: `Include` 로 불러온 파일도 `flags | SSHCONF_CHECKPERM` 으로 읽는다(`readconf.c`). 이 경우 검사 대상은 **저장소 쪽 파일의 ACL** 이다. 저장소가 `%USERPROFILE%` 아래면 상속 ACL 이 통과 조건을 만족하지만, `D:\` 처럼 `Authenticated Users` 쓰기 권한이 있는 곳이면 `Bad owner or permissions` 로 실패한다.
- 참고: 호스트·사용자 이름이 들어가므로 `.ssh/config` 는 저장소에 두더라도 gitignore 대상(견본만 커밋)이다.

### 1.4 Windows Terminal `settings.json`

- 경로(문서): 스토어/winget 설치(패키지) = `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json`, Preview = `...WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json`, 비패키지(Scoop 등) = `%LOCALAPPDATA%\Microsoft\Windows Terminal\settings.json`. ([Windows Terminal installation](https://learn.microsoft.com/en-us/windows/terminal/install))
- **저장 시 링크 유지**: 예전에는 설정 편집기가 링크를 지우고 일반 파일로 바꿨다([#10787](https://github.com/microsoft/terminal/issues/10787) "Settings editor erases the symbolic link rather than following it"). [PR #10908](https://github.com/microsoft/terminal/pull/10908)(2021-08 병합, Preview 1.10.2383 / 1.11.2421 에 포함)이 고쳤다: "if the path as a symlink we resolve the path and use: 1. target's directory to create a temp-file in 2. target itself to be replaced with the tempfile." 현재 코드도 같다: `write_utf8_string_to_file_atomic` 의 주석 "GH#10787: rename() will replace symbolic links themselves and not the path they point at." 와 `is_symlink(path) ? canonical(path) : path`. ([src/inc/til/io.h](https://github.com/microsoft/terminal/blob/main/src/inc/til/io.h))
- **다시 읽기(hot reload)는 링크를 따라가지 않는다**: [#1812](https://github.com/microsoft/terminal/issues/1812)(profiles.json 이 symlink 일 때 reload 안 됨)에 대해 메인테이너 DHowett: "We can't subscribe to know when a file has been changed -- we must subscribe to know when its _directory_ changed. The risk in following the symbolic link is that we will probably start listening for file changes in somewhere crazy". [#17282](https://github.com/microsoft/terminal/issues/17282)(열림): 링크일 때 설정 UI 의 Save 가 "Nothing happens" 처럼 보인다. DHowett "it _is_ saving but it is not reloading", 다른 사용자 "you have to relaunch the whole Terminal app to see the changes". → `git pull` 이나 저장소 파일 직접 편집 후에는 **터미널을 다시 켜야** 반영된다.
- **터미널이 스스로 파일을 다시 쓴다**: 로드할 때 `mustWriteToDisk |= loader.DisableDeletedProfiles(); mustWriteToDisk |= loader.FixupUserSettings(); mustWriteToDisk |= loader.AddDynamicProfileFolders();` 이고, 참이면 `WriteSettingsToDisk()` 로 전체 JSON 을 다시 직렬화해서 쓴다(주석: "If we created the file, or found new dynamic profiles, write the user settings string back to the file."). ([CascadiaSettingsSerialization.cpp](https://github.com/microsoft/terminal/blob/main/src/cascadia/TerminalSettingsModel/CascadiaSettingsSerialization.cpp)) → 링크 대상(저장소 파일)에 터미널이 만든 diff(동적 프로필 추가, 주석·서식 정리)가 생길 수 있다. 셋업 검증(#46)에서 "저장소 작업 트리가 깨끗한가"를 기준으로 쓰면 이 diff 때문에 흔들린다.
- **hardlink 는 끊긴다**: [#14730](https://github.com/microsoft/terminal/issues/14730)(열림) "Terminal overwriting hard link to settings.json ... The hard link is broken shortly after it is created." 원자적 저장(임시 파일 + rename)이므로 당연한 결과다.
- 대안: JSON fragment. 사용자 단위 경로 `C:\Users\<user>\AppData\Local\Microsoft\Windows Terminal\Fragments\{app-name}\{file-name}.json` 에 두면 터미널이 읽기만 한다. 단 "Split the JSON file into two lists: one for profiles and one for schemes" — 프로필과 색 구성표만 넣을 수 있고 전역 설정(기본 프로필, 키 바인딩 등)은 안 된다. ([JSON Fragment Extensions](https://learn.microsoft.com/en-us/windows/terminal/json-fragment-extensions))
- 이 머신: stable 패키지 경로에 일반 파일이 있다(링크 아님). Preview·비패키지 경로에는 파일이 없다.

### 1.5 VS Code `settings.json`·`keybindings.json`

- 경로: `%APPDATA%\Code\User\settings.json`, `keybindings.json` (이 머신에서 확인, 둘 다 일반 파일).
- **회귀와 수정**: 1.83.0 에서 "`VSCODE_USER/settings.json` is replaced by vscode with a regular file"([#194856](https://github.com/microsoft/vscode/issues/194856), Windows 에서도 재현 댓글, `keybindings.json`·`locale.json` 도 같음). [PR #195216](https://github.com/microsoft/vscode/pull/195216) "files - disable atomic writes for symlinks" 가 `release/1.83` 에 병합되어 마일스톤 "September 2023 Recovery 1"(= 1.83.1)로 나갔다.
- **현재 코드**: 설정·키 바인딩·tasks·extensions 파일은 원자적 쓰기 대상이다(`enforceAtomicWriteFile` → `{ postfix: '.vsctmp' }`, [fileUserDataProvider.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/userData/common/fileUserDataProvider.ts)). 하지만 `canWriteFileAtomic` 이 symlink 면 `false` 를 돌려준다: "atomic writes are unsupported for symbolic links because we need to ensure that the `rename` operation is atomic and that only works if the link is on the same disk." Windows 에서는 그때 `'r+'` 로 열고 `ftruncate` 해서 **제자리에** 쓴다(링크를 따라감). ([diskFileSystemProvider.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/files/node/diskFileSystemProvider.ts))
- **외부 변경 감지**: 파일 감시기가 `realpath` 로 실제 경로를 구해서 감시한다("correcting a path to watch that seems to be a symbolic link"). → `git pull` 로 대상이 바뀌면 반영된다. ([nodejsWatcherLib.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/files/node/watcher/nodejs/nodejsWatcherLib.ts))
- **hardlink 는 끊긴다**: 일반 파일(hardlink 포함)은 `.vsctmp` 임시 파일 + rename 으로 저장되므로 저장할 때마다 링크가 끊긴다(코드에서 추론, 실측 안 함).
- 참고: VS Code 프로필을 쓰면 기본 프로필 외의 설정은 `User\profiles\<id>\` 아래에 따로 있다(같은 `profile.settingsResource` 목록으로 관리됨).

## 2. Developer Mode 와 symlink 만들기 권한

- 권한(문서): symlink 를 만들려면 `SeCreateSymbolicLinkPrivilege`("Create symbolic links") 가 필요하다. "By default, members of the Administrators group have this right." Client Computer Effective Default = Administrators. ([Create symbolic links 정책](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/create-symbolic-links)) UAC 때문에 관리자 계정이어도 **상승하지 않은** 셸에는 이 권한이 없다(로컬: 비상승 셸의 `whoami /priv` 에 이 권한이 안 나온다).
- Developer Mode 예외(문서): `CreateSymbolicLinkW` 의 `SYMBOLIC_LINK_FLAG_ALLOW_UNPRIVILEGED_CREATE`(0x2) — "Specify this flag to allow creation of symbolic links when the process is not elevated. Developer Mode must first be enabled on the machine before this option will function." ([CreateSymbolicLinkW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-createsymboliclinkw)) Windows 10 Insider build 14972(Creators Update)부터이고, `mklink` 도 이 플래그를 써서 "the mklink command will now successfully create a symlink if the user is not running as an administrator". ([Symlinks in Windows 10!](https://blogs.windows.com/windowsdeveloper/2016/12/02/symlinks-windows-10/))
- **플래그는 호출하는 프로그램이 직접 줘야 한다.** Developer Mode 가 켜져 있어도 플래그를 안 주는 도구는 관리자를 요구한다. 로컬 실측(비상승, Developer Mode 켜짐):

  | 방법 | 결과 |
  |---|---|
  | PowerShell 7.6.9 `New-Item -ItemType SymbolicLink` | 성공 |
  | `cmd /c mklink` | 성공 |
  | Windows PowerShell 5.1 `New-Item -ItemType SymbolicLink` | **실패**: "Administrator privilege required for this operation." |
  | Git Bash `ln -s` (기본값) | 링크가 아니라 **복사본**이 생김 |
  | Git Bash `MSYS=winsymlinks:nativestrict ln -s` | 성공 |

  PowerShell 쪽 이슈 [PowerShell/PowerShell#7967](https://github.com/PowerShell/PowerShell/issues/7967) "Symbolic link creation always requires elevation on Windows" 는 닫혔지만 고친 PR 이 연결돼 있지 않고, 7.3.9·7.4.2 에서 여전히 실패한다는 댓글과 7.4 에서 된다는 댓글이 섞여 있다. 그러니 셋업은 PowerShell 7 최신을 전제로 하되, 첫 링크를 만들 때 실패하면 Developer Mode 를 안내하는 오류를 내는 편이 안전하다.
- 켜는 방법(문서, [Settings for developers](https://learn.microsoft.com/en-us/windows/advanced-settings/developer-mode)):
  - 설정 앱: Windows 11 25H2 이상은 **설정 > 시스템 > 고급 > For developers** 의 Developer Mode 토글. 25H2 이전은 **For developers** 페이지. "Enabling Developer mode requires administrator access."
  - 레지스트리: `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock\AllowDevelopmentWithoutDevLicense` (DWORD) = `1`. 관리자 PowerShell 에서 `reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" /t REG_DWORD /f /v "AllowDevelopmentWithoutDevLicense" /d "1"`. Home 에디션은 gpedit 이 없으므로 이 방법을 쓴다. 문서 주석: 이 방법은 SSH 서버나 원격 배포는 켜지 않는다(symlink 와 무관).
  - 그룹 정책: App Package Deployment 의 "Allows development of UWP apps and installation from an IDE" + "Allow all trusted apps to install".
- 확인(읽기 전용, 관리자 불필요): `(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock').AllowDevelopmentWithoutDevLicense -eq 1`. 이 머신 값: `AllowDevelopmentWithoutDevLicense=1`, `AllowAllTrustedApps=1`.
- 미확인: 레지스트리만 바꾼 직후 재부팅·재로그온 없이 바로 비상승 symlink 가 되는지(이 머신은 이미 켜져 있어 시험 못 함).
- 대안: 셋업 전체를 관리자 상승으로 돌리면 Developer Mode 없이도 만들 수 있다. 다만 그러면 셋업이 매번 UAC 를 요구하고, 상승 셸에서 만든 파일의 소유자·ACL 이 달라질 수 있어(추정, OpenSSH 권한 검사와 관련) 권하지 않는다.

## 3. 문서 폴더가 OneDrive 로 리디렉션된 경우

- 영향 받는 것은 다섯 중 `$PROFILE` 하나다. `.gitconfig`·`.ssh` 는 `%USERPROFILE%` 바로 아래, Windows Terminal·VS Code 는 `%LOCALAPPDATA%`·`%APPDATA%` 아래라 OneDrive 폴더 백업(Known Folder Move: 바탕 화면·문서·사진 등) 대상이 아니다.
- 경로가 바뀐다: `$PROFILE` 은 실제 문서 폴더를 따른다. 리디렉션되면 `C:\Users\<user>\OneDrive\Documents\PowerShell\...` 이 된다. 셋업은 경로를 하드코딩하지 말고 `$PROFILE`(또는 `[Environment]::GetFolderPath('MyDocuments')`)로 구해야 한다. 이 머신: `MyDocuments = C:\Users\<user>\Documents`(리디렉션 안 됨), `HKCU\...\User Shell Folders\Personal` 도 같은 값, OneDrive 폴더(`C:\Users\<user>\OneDrive`)는 따로 있다.
- OneDrive 는 링크를 동기화하지 않는다(문서): "OneDrive doesn't support syncing by using symbolic links or junction points." ([Restrictions and limitations in OneDrive and SharePoint](https://support.microsoft.com/en-us/office/restrictions-and-limitations-in-onedrive-and-sharepoint-64883a5d-228e-48f5-b3d2-eb39e07630fa)) 문서는 링크를 만나면 정확히 어떻게 되는지는 말하지 않는다(미확인, OneDrive 폴더에서는 시험하지 않음).
- PowerShell 문서도 권하지 않는다: "We don't recommend redirecting the `Documents` folder to a network share or including it in OneDrive. Redirecting the folder can cause modules to fail to load and create errors in your profile scripts." ([about_Profiles](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles))
- 정리: 문서 폴더가 OneDrive 안이면 `$PROFILE` 은 링크 대신 **일반 파일 stub**(저장소 프로필을 dot-source 하는 한 줄)으로 둔다. stub 은 OneDrive 가 다른 PC 로 동기화하므로 PC 마다 같은 경로(예: `$HOME\<repo>\...`)를 쓰도록 한다. 저장소 자체는 OneDrive 밖에 둔다.

## 4. symlink · hardlink · 복사 비교

| | symlink | hardlink | 복사 |
|---|---|---|---|
| 만들 때 권한 | `SeCreateSymbolicLinkPrivilege` 또는 Developer Mode + 플래그 | 필요 없음 | 필요 없음 |
| 제약 | 파일·디렉터리 모두, 다른 볼륨 가능 | 파일만, **같은 볼륨만** ([Hard Links and Junctions](https://learn.microsoft.com/en-us/windows/win32/fileio/hard-links-and-junctions)) | 없음 |
| 앱의 원자적 저장(임시 파일 + rename) | 앱이 링크를 풀어 주면 유지(WT·VS Code·git 은 풀어 준다). 안 풀어 주면 일반 파일로 바뀜(로컬 실측: `Move-Item -Force` 로 덮으면 링크가 사라짐) | **끊긴다.** 로컬 실측: rename 으로 덮은 뒤 원본=`h`, 링크 쪽=`z` 로 갈라짐. WT #14730, VS Code `.vsctmp` | 해당 없음(앱은 자기 사본만 고침) |
| 저장소 쪽 `git pull`·`checkout` | 유지(같은 경로에 새 파일이 생겨도 링크는 경로를 가리킴) | **끊긴다.** git 은 기존 파일을 지우고(`unlink_or_warn`) `O_CREAT \| O_EXCL` 로 새로 만든다([git/entry.c](https://github.com/git/git/blob/master/entry.c)). 로컬 실측: checkout 뒤 저장소=v1, hardlink=v2, symlink=v1 | 셋업을 다시 돌려야 반영 |
| 앱이 바꾼 내용 | 저장소 파일이 바로 바뀜(diff 로 보임) | 끊기기 전까지만 공유 | 저장소에 안 남음. 셋업이 덮어쓰면 PC 쪽 변경이 사라짐 |
| 깨짐을 알아채기 | `(Get-Item $p).LinkType` / `.Target` 로 바로 확인 | 링크 수를 따로 봐야 해서 어렵다 | 해시 비교 필요 |
| OneDrive 폴더 안 | 동기화 안 됨(문서) | 문서에 언급 없음 | 문제없음 |
| 적용 시점 | 앱이 다시 읽을 때(WT 는 재시작 필요) | 같음 | 셋업 실행 때 |

- Windows `ReplaceFileW`(.NET `File.Replace`)는 대상이 symlink 면 실패한다(로컬 실측: "이 응용 프로그램에서 기호화된 링크에 대한 현재 작업을 지원하지 않습니다"). 링크가 일반 파일로 바뀌지는 않는다.
- 디렉터리를 연결할 때는 #33 결론대로 junction(권한 불필요)을 쓴다. 이번 대상은 모두 단일 파일이라 junction 은 해당 없다.

## 5. 권장

1. 파일 연결은 **symlink** 를 쓴다. hardlink 는 쓰지 않는다(앱 저장과 `git checkout` 양쪽에서 조용히 끊긴다).
2. Developer Mode 켜기는 **부트스트랩**의 관리자 단계에 넣는다(레지스트리 `AllowDevelopmentWithoutDevLicense=1`). **셋업**은 일반 권한으로 돌고, 시작할 때 이 값을 읽어서 꺼져 있으면 부트스트랩을 안내하며 멈춘다.
3. 링크는 **PowerShell 7** 에서 `New-Item -ItemType SymbolicLink` 로 만든다. Windows PowerShell 5.1 `New-Item` 과 Git Bash `ln -s` 는 쓰지 않는다(필요하면 `cmd /c mklink`). 멱등 검사는 `LinkType -eq 'SymbolicLink'` 이고 `Target` 이 선언한 경로와 같은지로 한다.
4. 파일별:
   - VS Code `settings.json`·`keybindings.json`: symlink 그대로.
   - `~/.ssh/config`: symlink(링크 ACL 로 검사되므로 저장소 위치와 무관). 내용은 개인값이라 저장소에서는 gitignore + 견본.
   - `~/.gitconfig`: symlink 보다 **일반 파일 + `[include] path`** 가 낫다. `git config --global` 로 쓰는 개인값이 공개 저장소 파일로 새지 않는다.
   - `$PROFILE`: symlink 도 되지만 **일반 파일 stub + dot-source** 가 낫다(`$PSScriptRoot` 문제 없음, OneDrive 리디렉션에도 안전).
   - Windows Terminal `settings.json`: symlink 는 되지만 (a) 변경 후 재시작 필요, (b) 터미널이 저장소 파일을 다시 써서 diff 가 생긴다. 이걸 받아들일지, 프로필·색 구성표만 fragment 로 두고 나머지는 복사할지는 #45 에서 정한다.
