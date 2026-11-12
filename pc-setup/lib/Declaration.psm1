class DeclarationException : System.Exception {
    [string[]]$Problems   # '<파일 이름>:<줄>: <문제>' 모양
    DeclarationException([string[]]$problems) : base(($problems -join "`n")) { $this.Problems = $problems }
}

function Read-Declaration {
    <# 선언 파일 하나를 실행 없이 읽고 검사한다.
       성공: 항목 [pscustomobject[]] — 선언의 키를 그대로 속성으로 갖고, 더해서 Line(항목 시작 줄 번호, 1부터)을 갖는다.
       문제: 모두 모아 DeclarationException 을 던진다. #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Schema
    )

    $fileName = Split-Path -Leaf $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw [DeclarationException]::new(@("${fileName}:0: 파일이 없다"))
    }

    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $tokens = $null
    [System.Management.Automation.Language.ParseError[]]$errors = @()
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($resolvedPath, [ref]$tokens, [ref]$errors)

    if ($errors -and $errors.Count -gt 0) {
        $problems = [string[]]($errors | ForEach-Object {
            "${fileName}:$($_.Extent.StartLineNumber): 문법 오류: $($_.Message)"
        })
        throw [DeclarationException]::new($problems)
    }

    $shapeError = "${fileName}:1: 최상위는 @{ Items = @( ... ) } 이어야 한다"

    if ($null -ne $ast.ParamBlock -or $null -ne $ast.BeginBlock -or $null -ne $ast.ProcessBlock -or $null -ne $ast.DynamicParamBlock) {
        throw [DeclarationException]::new(@($shapeError))
    }

    if ($null -eq $ast.EndBlock -or $ast.EndBlock.Statements.Count -ne 1) {
        throw [DeclarationException]::new(@($shapeError))
    }

    $stmt = $ast.EndBlock.Statements[0]
    if ($stmt -isnot [System.Management.Automation.Language.PipelineAst] -or $stmt.PipelineElements.Count -ne 1) {
        throw [DeclarationException]::new(@($shapeError))
    }

    if ($stmt.PipelineElements[0] -isnot [System.Management.Automation.Language.CommandExpressionAst]) {
        throw [DeclarationException]::new(@($shapeError))
    }

    $topHt = $stmt.PipelineElements[0].Expression
    if ($topHt -isnot [System.Management.Automation.Language.HashtableAst]) {
        throw [DeclarationException]::new(@($shapeError))
    }

    if ($topHt.KeyValuePairs.Count -ne 1) {
        throw [DeclarationException]::new(@($shapeError))
    }

    $topKv = $topHt.KeyValuePairs[0]
    $topKey = $null
    try {
        $topKey = [string]$topKv.Item1.SafeGetValue()
    } catch {
        throw [DeclarationException]::new(@($shapeError))
    }

    if ($topKey -cne 'Items') {
        throw [DeclarationException]::new(@($shapeError))
    }

    $valStmt = $topKv.Item2
    if ($valStmt -isnot [System.Management.Automation.Language.PipelineAst] -or $valStmt.PipelineElements.Count -ne 1) {
        throw [DeclarationException]::new(@($shapeError))
    }

    $valExpr = $valStmt.PipelineElements[0].Expression
    if ($valExpr -isnot [System.Management.Automation.Language.ArrayExpressionAst]) {
        throw [DeclarationException]::new(@($shapeError))
    }

    $itemAsts = [System.Collections.Generic.List[System.Management.Automation.Language.HashtableAst]]::new()
    foreach ($itemStmt in $valExpr.SubExpression.Statements) {
        if ($itemStmt -isnot [System.Management.Automation.Language.PipelineAst] -or $itemStmt.PipelineElements.Count -ne 1) {
            throw [DeclarationException]::new(@($shapeError))
        }
        $itemExpr = $itemStmt.PipelineElements[0].Expression
        if ($itemExpr -is [System.Management.Automation.Language.HashtableAst]) {
            $itemAsts.Add($itemExpr)
        } elseif ($itemExpr -is [System.Management.Automation.Language.ArrayLiteralAst]) {
            foreach ($elem in $itemExpr.Elements) {
                if ($elem -is [System.Management.Automation.Language.HashtableAst]) {
                    $itemAsts.Add($elem)
                } else {
                    throw [DeclarationException]::new(@($shapeError))
                }
            }
        } else {
            throw [DeclarationException]::new(@($shapeError))
        }
    }

    $allProblems = [System.Collections.Generic.List[string]]::new()
    $validItems = [System.Collections.Generic.List[pscustomobject]]::new()
    $seenIdentifiers = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::Ordinal)

    $allowedKeys = if ($Schema.ContainsKey('Allowed') -and $null -ne $Schema.Allowed) { [string[]]$Schema.Allowed } else { $null }
    $requiredKeys = if ($Schema.ContainsKey('Required') -and $null -ne $Schema.Required) { [string[]]$Schema.Required } else { $null }
    $idKeyName = if ($Schema.ContainsKey('Key') -and -not [string]::IsNullOrEmpty($Schema.Key)) { [string]$Schema.Key } else { $null }
    $enumsTable = if ($Schema.ContainsKey('Enums') -and $null -ne $Schema.Enums) { $Schema.Enums } else { $null }
    $validateScript = if ($Schema.ContainsKey('Validate') -and $null -ne $Schema.Validate -and $Schema.Validate -is [System.Management.Automation.ScriptBlock]) { $Schema.Validate } else { $null }

    foreach ($itemAst in $itemAsts) {
        $itemLine = $itemAst.Extent.StartLineNumber

        try {
            $null = $itemAst.SafeGetValue()
        } catch {
            $allProblems.Add("${fileName}:${itemLine}: 값에 식이 들어 있다")
            continue
        }

        $objProps = [ordered]@{}
        $itemKeyNames = [System.Collections.Generic.List[string]]::new()
        foreach ($kv in $itemAst.KeyValuePairs) {
            $k = [string]$kv.Item1.SafeGetValue()
            $v = $kv.Item2.SafeGetValue()
            $objProps[$k] = $v
            $itemKeyNames.Add($k)
        }
        $objProps['Line'] = $itemLine
        $itemObj = [pscustomobject]$objProps

        # 1. 모르는 키
        if ($null -ne $allowedKeys) {
            foreach ($k in $itemKeyNames) {
                if ($allowedKeys -cnotcontains $k) {
                    $allProblems.Add("${fileName}:${itemLine}: 모르는 키 '$k'")
                }
            }
        }

        # 2. 빠진 필수 키
        if ($null -ne $requiredKeys) {
            foreach ($reqKey in $requiredKeys) {
                if ($itemKeyNames -cnotcontains $reqKey) {
                    $allProblems.Add("${fileName}:${itemLine}: 필수 키 '$reqKey' 가 없다")
                }
            }
        }

        # 3. 중복 식별 키
        if ($null -ne $idKeyName) {
            if ($itemKeyNames -ccontains $idKeyName) {
                $idVal = [string]$objProps[$idKeyName]
                if ($seenIdentifiers.ContainsKey($idVal)) {
                    $firstLine = $seenIdentifiers[$idVal]
                    $allProblems.Add("${fileName}:${itemLine}: '$idKeyName' 값 '$idVal' 이 ${firstLine}번 줄과 겹친다")
                } else {
                    $seenIdentifiers[$idVal] = $itemLine
                }
            }
        }

        # 4. 허용 값 밖
        if ($null -ne $enumsTable) {
            foreach ($k in $itemKeyNames) {
                foreach ($enumKey in $enumsTable.Keys) {
                    if ($enumKey -ceq $k) {
                        $val = [string]$objProps[$k]
                        $allowedList = [object[]]$enumsTable[$enumKey]
                        if ($allowedList -cnotcontains $val) {
                            $allowedStr = $allowedList -join ', '
                            $allProblems.Add("${fileName}:${itemLine}: '$k' 값 '$val' 은 허용되지 않는다 (허용: $allowedStr)")
                        }
                    }
                }
            }
        }

        # 5. Validate
        if ($null -ne $validateScript) {
            $valResult = & $validateScript $itemObj
            if ($valResult) {
                foreach ($msg in [string[]]$valResult) {
                    if (-not [string]::IsNullOrEmpty($msg)) {
                        $allProblems.Add("${fileName}:${itemLine}: $msg")
                    }
                }
            }
        }

        $validItems.Add($itemObj)
    }

    if ($allProblems.Count -gt 0) {
        throw [DeclarationException]::new([string[]]$allProblems.ToArray())
    }

    return ,([pscustomobject[]]$validItems.ToArray())
}

function Expand-SetupPath {
    <# '~' 로 시작하면 $HOME 으로, '$env:<이름>' 은 그 환경 변수 값으로 바꾼다. 경로 구분자는 '\' 로 맞춘다. #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -eq '~') {
        $Path = $HOME
    } elseif ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        $Path = $HOME + $Path.Substring(1)
    }

    $pattern = '\$env:([A-Za-z_][A-Za-z0-9_]*)'
    $matches = [regex]::Matches($Path, $pattern)
    foreach ($m in $matches) {
        $varName = $m.Groups[1].Value
        $val = [System.Environment]::GetEnvironmentVariable($varName)
        if ($null -eq $val) {
            throw "환경 변수 '$varName' 이 없다"
        }
    }
    $Path = [regex]::Replace($Path, $pattern, {
        param($m)
        [System.Environment]::GetEnvironmentVariable($m.Groups[1].Value)
    })

    $Path = $Path.Replace('/', '\')
    return $Path
}

Export-ModuleMember -Function Read-Declaration, Expand-SetupPath
