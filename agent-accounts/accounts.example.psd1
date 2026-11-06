# 이 파일을 accounts.psd1 로 복사해 쓴다. accounts.psd1 은 git 에 올라가지 않는다.
@{
    # CLI 정의. 새 CLI 는 여기에 한 항목을 더한다.
    #   Env       : 계정 폴더를 가리킬 환경변수
    #   Default   : 기본 계정 폴더. Share 항목을 여기서 링크로 가져온다.
    #   Share     : 기본 계정과 공유할 파일·폴더 (폴더=junction, 파일=symlink)
    #   LoginFile : 있으면 "로그인됨"으로 보는 파일
    #   Seed      : 새 계정 폴더에 처음 한 번 써 둘 파일
    Clis = @{
        claude = @{
            Env       = 'CLAUDE_CONFIG_DIR'
            Default   = '~/.claude'
            Share     = @('CLAUDE.md', 'skills', 'commands', 'hooks', 'agents', 'plugins')
            LoginFile = '.credentials.json'
            Seed      = @{}
        }
        codex = @{
            Env       = 'CODEX_HOME'
            Default   = '~/.codex'
            Share     = @('AGENTS.md', 'skills')
            LoginFile = 'auth.json'
            Seed      = @{ 'config.toml' = 'cli_auth_credentials_store = "file"' }
        }
    }

    # 계정 목록. 이름마다 <cli>-<이름> 별칭이 생긴다. Add-AgentAccount 가 자동으로 고친다.
    Accounts = @{
        claude = @()
        codex  = @()
    }
}
