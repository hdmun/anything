@{
    Items = @(
        @{ Path = '~/.gitconfig'; Method = 'GitInclude'; Source = 'config/gitconfig' }
        @{ Path = '$env:LOCALAPPDATA/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'; Method = 'Link'; Source = 'config/windows-terminal.json' }
        @{ Path = '~/.nanorc'; Method = 'Link'; Source = 'config/nanorc' }
    )
}
