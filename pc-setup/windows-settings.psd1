@{
    Items = @(
        @{
            Id    = 'PowerShell51ExecutionPolicy'
            Path  = 'HKCU:\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'
            Name  = 'ExecutionPolicy'
            Type  = 'String'
            Value = 'RemoteSigned'
        }
        @{
            Id    = 'DeveloperMode'
            Path  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
            Name  = 'AllowDevelopmentWithoutDevLicense'
            Type  = 'DWord'
            Value = 1
        }
        @{
            Id    = 'LongPaths'
            Path  = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem'
            Name  = 'LongPathsEnabled'
            Type  = 'DWord'
            Value = 1
        }
        @{
            Id    = 'ShowFileExtensions'
            Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Name  = 'HideFileExt'
            Type  = 'DWord'
            Value = 0
        }
        @{
            Id    = 'ShowHiddenFiles'
            Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
            Name  = 'Hidden'
            Type  = 'DWord'
            Value = 1
        }
        @{
            Id    = 'DarkModeApps'
            Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            Name  = 'AppsUseLightTheme'
            Type  = 'DWord'
            Value = 0
        }
        @{
            Id    = 'DarkModeSystem'
            Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
            Name  = 'SystemUsesLightTheme'
            Type  = 'DWord'
            Value = 0
        }
        @{
            Id    = 'TaskbarSearchIcon'
            Path  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
            Name  = 'SearchboxTaskbarMode'
            Type  = 'DWord'
            Value = 1
        }
    )
}
