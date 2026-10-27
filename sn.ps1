# sn：在終端機裡存取 snippet。以 fzf 挑選，Enter 複製、Ctrl-E 編輯、Ctrl-O 印出。
# 由 PowerShell profile dot-source；載入時只定義函式，不啟動任何外部程式。
# 本檔須存為 UTF-8 with BOM，否則 5.1 會以 ANSI（Big5）解讀中文而產生語法錯誤。
# 須相容 Windows PowerShell 5.1：不使用 ??、?.、三元運算子。
#
# 資料夾：$env:SNIPPETS_DIR，未設定時為本檔旁的 data\（已列入 .gitignore，不會上傳）。
# 一個 snippet 一個 .md 檔，格式見 README.md。

# 使用者看到的名稱：相對於資料夾、去掉 .md、一律用 /。
function Get-SnName([string]$Path, [string]$Dir) {
    ($Path.Substring($Dir.Length).TrimStart('\', '/') -replace '\.md$', '') -replace '\\', '/'
}

function Get-SnDir {
    $dir = $env:SNIPPETS_DIR
    if (-not $dir) { $dir = Join-Path $PSScriptRoot 'data' }
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    [IO.Path]::GetFullPath($dir)
}

# 解析檔頭的 tags／desc，並取出第一個 code block（沒有時用整個內文）。
function Read-SnFile([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $tags = ''; $desc = ''; $body = $text
    if ($text -match '\A---\r?\n(?<fm>[\s\S]*?)\r?\n---[ \t]*(\r?\n|\z)(?<body>[\s\S]*)\z') {
        $fm = $Matches.fm
        $body = $Matches.body
        foreach ($line in $fm -split '\r?\n') {
            if ($line -match '^\s*tags\s*:\s*(.*)$') { $tags = $Matches[1].Trim() }
            elseif ($line -match '^\s*desc\s*:\s*(.*)$') { $desc = $Matches[1].Trim() }
        }
    }
    $m = [regex]::Match($body, '(?m)^(?<f>`{3,}|~{3,})[^\r\n]*\r?\n(?<code>[\s\S]*?)\r?\n\k<f>[ \t]*\r?$')
    $code = if ($m.Success) { $m.Groups['code'].Value } else { $body.Trim() }
    [pscustomobject]@{ Tags = $tags; Desc = $desc; Code = $code }
}

# 以 UTF-8 執行原生程式。5.1 的 $OutputEncoding 預設為 ASCII，中文經管線送進 fzf 會變成問號；
# [Console]::OutputEncoding 決定如何解碼原生程式的輸出。兩者都在結束後還原。
# 5.1 只認全域的 $OutputEncoding，而且函式內另設區域變數反而會讓它退回 ASCII（實測）；
# 7 讀最近的 scope，呼叫端若有區域變數會蓋過全域。所以區域變數只在 7 設。
function Invoke-SnUtf8([scriptblock]$Block) {
    $utf8 = New-Object Text.UTF8Encoding $false
    if ($PSVersionTable.PSVersion.Major -ge 6) { $OutputEncoding = $utf8 }
    $prevPipe = $global:OutputEncoding
    $prev = [Console]::OutputEncoding
    $switched = $prev.CodePage -ne 65001
    try {
        $global:OutputEncoding = $utf8
        if ($switched) { [Console]::OutputEncoding = $utf8 }
        & $Block
    } finally {
        $global:OutputEncoding = $prevPipe
        if ($switched) { [Console]::OutputEncoding = $prev }
    }
}

# 回傳 @(按鍵, 檔案路徑)；取消時不回傳。按鍵為空字串代表 Enter（或 --select-1 自動選取）。
function Select-SnFile([string[]]$Files, [string]$Dir, [string]$Query) {
    $entries = foreach ($f in $Files) {
        $s = Read-SnFile $f
        "{0}`t{1}`t{2}`t{3}" -f $f, (Get-SnName $f $Dir), $s.Tags, $s.Desc
    }
    $fzfArgs = @(
        '--delimiter', "`t", '--with-nth', '2..', '--tabstop', '4',
        '--expect', 'ctrl-e,ctrl-o',
        '--height', '60%', '--layout', 'reverse', '--border', '--info', 'inline',
        '--header', 'Enter 複製 · Ctrl-E 編輯 · Ctrl-O 印出',
        # 明確指定 cmd：環境中有 $SHELL（例如 Git Bash）時 fzf 會改用它，type 就不是印檔案了。
        '--with-shell', 'cmd /s/c', '--preview', 'type {1}', '--preview-window', 'right,55%,wrap'
    )
    if ($Query) { $fzfArgs += '--query', $Query, '--select-1' }
    $out = @(Invoke-SnUtf8 { $entries | fzf @fzfArgs })
    if ($out.Count -lt 2) { return }
    @($out[0], ($out[1] -split "`t")[0])
}

# $env:EDITOR 可能帶參數（例如 subl -w），拆成程式與參數再呼叫。
function Open-SnEditor([string]$Path) {
    $editor = $env:SN_EDITOR
    if (-not $editor) { $editor = $env:EDITOR }
    if (-not $editor) { $editor = 'nvim' }
    $parts = @($editor -split '\s+' | Where-Object { $_ })
    $editorArgs = @($parts | Select-Object -Skip 1)
    & $parts[0] @editorArgs $Path
}

function sn {
    <#
    .SYNOPSIS
        存取 snippet。
    .DESCRIPTION
        sn [關鍵字...]      以 fzf 挑選（比對名稱、tags、desc）；只有一筆符合時直接複製
        sn grep <regex>     先以 rg 全文搜尋內容，再從符合的檔案中挑選
        sn new <名稱>       建立並編輯，名稱可含子資料夾，例如 sn new git/squash；已存在則直接編輯
        sn dir              印出資料夾路徑，例如 cd (sn dir)

        挑選畫面：Enter 複製第一個 code block、Ctrl-E 編輯、Ctrl-O 印到 stdout（可接管線）。
        編輯器依序取 $env:SN_EDITOR、$env:EDITOR，都沒有時用 nvim。
    #>
    $dir = Get-SnDir
    $cmd = if ($args.Count) { [string]$args[0] } else { '' }
    $rest = (@($args | Select-Object -Skip 1) -join ' ').Trim()

    switch ($cmd) {
        'dir' { return $dir }
        'new' {
            $name = ($rest -replace '\\', '/') -replace '\.md$', ''
            if (-not $name) { Write-Error '用法：sn new <名稱>，例如 sn new git/squash'; return }
            if ([IO.Path]::IsPathRooted($name) -or ($name -split '/') -contains '..') {
                Write-Error "名稱必須是資料夾內的相對路徑：$name"; return
            }
            $path = [IO.Path]::GetFullPath((Join-Path $dir ($name + '.md')))
            if (-not [IO.File]::Exists($path)) {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
                $template = @'
---
tags:
desc:
---

```

```
'@
                [IO.File]::WriteAllText($path, ($template -replace '\r\n', "`n") + "`n", (New-Object Text.UTF8Encoding $false))
            }
            Open-SnEditor $path
            return
        }
        'grep' {
            if (-not $rest) { Write-Error '用法：sn grep <regex>'; return }
            $files = @(Invoke-SnUtf8 { rg --files-with-matches --ignore-case --glob '*.md' -- $rest $dir } | Sort-Object)
            if (-not $files.Count) { Write-Host "沒有內容符合：$rest"; return }
            $query = ''
        }
        default {
            $files = @([IO.Directory]::GetFiles($dir, '*.md', 'AllDirectories') | Sort-Object)
            if (-not $files.Count) { Write-Host "還沒有 snippet，用 sn new <名稱> 建立第一個（資料夾：$dir）"; return }
            $query = (@($args) -join ' ').Trim()
        }
    }

    $pick = Select-SnFile $files $dir $query
    if (-not $pick) { return }
    $key, $path = $pick
    switch ($key) {
        'ctrl-e' { Open-SnEditor $path }
        'ctrl-o' { (Read-SnFile $path).Code }
        default {
            Set-Clipboard -Value (Read-SnFile $path).Code
            Write-Host "已複製 $(Get-SnName $path $dir)" -ForegroundColor DarkGray
        }
    }
}
