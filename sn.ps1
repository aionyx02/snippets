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
    # 相對路徑以 PowerShell 的 $PWD 為準；.NET 的 GetFullPath 用的是 process 目錄，兩者常不同步。
    $dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($dir)
    if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
    [IO.Path]::GetFullPath($dir)
}

# 解析檔頭的 tags／desc，並取出第一個 code block（沒有時用整個內文）。
function Read-SnFile([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $tags = ''; $desc = ''; $body = $text
    # 檔頭內容可為空（--- 緊接 ---）。開頭的 --- 也可能只是水平線（從別處搬來的筆記），
    # 所以非空的檔頭至少要有一行 key: 才算數，否則整份當內文。
    if ($text -match '\A---[ \t]*\r?\n(?:(?<fm>[\s\S]*?)\r?\n)?---[ \t]*(\r?\n|\z)(?<body>[\s\S]*)\z') {
        $fm = $Matches.fm
        $rest = $Matches.body
        if (-not $fm -or $fm -match '(?m)^\s*[\w-]+\s*:') {
            $body = $rest
            foreach ($line in $fm -split '\r?\n') {
                if ($line -match '^\s*tags\s*:\s*(.*)$') { $tags = $Matches[1].Trim() }
                elseif ($line -match '^\s*desc\s*:\s*(.*)$') { $desc = $Matches[1].Trim() }
            }
        }
    }
    # code block 可為空；收尾 fence 可比開頭長；fence 可縮排 0～3 格（例如在編號清單裡），
    # 內容去掉同樣寬度的縮排（CommonMark）。
    $m = [regex]::Match($body, '(?m)^(?<i> {0,3})(?<f>`{3,}|~{3,})[^\r\n]*\r?\n(?:(?<code>[\s\S]*?)\r?\n)?[ ]{0,3}\k<f>[`~]*[ \t]*\r?$')
    $code = if ($m.Success) { $m.Groups['code'].Value } else { $body.Trim() }
    $indent = $m.Groups['i'].Length
    if ($indent) { $code = $code -replace "(?m)^ {1,$indent}", '' }
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
        '--expect', 'ctrl-e,ctrl-o,ctrl-x',
        '--height', '60%', '--layout', 'reverse', '--border', '--info', 'inline',
        '--header', 'Enter 複製 · Ctrl-E 編輯 · Ctrl-O 印出 · Ctrl-X 刪除',
        '--preview', 'type {1}', '--preview-window', 'right,55%,wrap'
    )
    if ($Query) { $fzfArgs += '--query', $Query, '--select-1' }
    # 預覽要交給 fzf 內建的 cmd：它會依 cmd 的規則替 {1} 加引號。
    # 環境中有 $SHELL（例如從 Git Bash 啟動）時 fzf 會改用它，type 就不是印檔案了，所以暫時拿掉。
    # 不能改用 --with-shell 'cmd /s/c'：那樣 fzf 不會套用 cmd 的引號規則，
    # 含空格的路徑會變成「檔案名稱、目錄名稱或磁碟區標籤語法錯誤」。
    # 副作用：FZF_DEFAULT_OPTS 裡自訂的 execute(...) 在 sn 中也會改由 cmd 執行。
    $hadShell = Test-Path Env:SHELL
    $shell = $env:SHELL
    try {
        Remove-Item Env:SHELL -ErrorAction SilentlyContinue
        $out = @(Invoke-SnUtf8 { $entries | fzf @fzfArgs })
    } finally {
        if ($hadShell) { [Environment]::SetEnvironmentVariable('SHELL', $shell) }
    }
    if ($out.Count -lt 2) { return }
    @($out[0], ($out[1] -split "`t")[0])
}

# $env:EDITOR 可能帶參數（例如 subl -w），拆成程式與參數再呼叫。
# 程式路徑含空格時須以雙引號包住，例如 "C:\Program Files\Sublime Text\subl.exe" -w。
function Open-SnEditor([string]$Path) {
    $editor = $env:SN_EDITOR
    if (-not $editor) { $editor = $env:EDITOR }
    if (-not $editor) { $editor = 'nvim' }
    if ($editor -match '^\s*"([^"]+)"\s*(.*)$') { $exe = $Matches[1]; $rest = $Matches[2] }
    else { $exe, $rest = $editor.Trim() -split '\s+', 2 }
    $editorArgs = @("$rest" -split '\s+' | Where-Object { $_ })
    & $exe @editorArgs $Path
}

# 名稱轉成資料夾內的完整路徑，失敗時寫錯誤並不回傳。逐段檢查：
#   空段（x/ 會變成 x\.md）、檔名不允許的字元（含 : 所以也擋掉 C:\）、
#   結尾是 . 或空格（Windows 會默默去掉，建出來的名稱就對不上；.. 也在此被擋）。
# 先擋掉再交給 GetFullPath：7 遇到 ? * 不會丟例外，要到寫檔才失敗。
function Resolve-SnPath([string]$Name, [string]$Dir) {
    $Name = ($Name -replace '\\', '/') -replace '\.md$', ''
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $bad = @($Name -split '/' | Where-Object { $_ -eq '' -or $_.IndexOfAny($invalid) -ge 0 -or $_ -match '[. ]$' })
    if ($bad.Count) {
        Write-Error "名稱不合法：$Name（用 / 分隔子資料夾；不可含 : * ? `" < > |，各段不可為空或以 . 或空格結尾）"; return
    }
    [IO.Path]::GetFullPath((Join-Path $Dir ($Name + '.md')))
}

# 移到資源回收筒而非直接刪除：data\ 不進 git，誤刪時這是唯一的退路。
# 刪完順手清掉變空的子資料夾（不含資料夾本身）。
function Remove-SnFile([string]$Path, [string]$Dir) {
    Add-Type -AssemblyName Microsoft.VisualBasic
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
    $parent = [IO.Path]::GetDirectoryName($Path)
    while ($parent.Length -gt $Dir.Length -and -not [IO.Directory]::EnumerateFileSystemEntries($parent).GetEnumerator().MoveNext()) {
        [IO.Directory]::Delete($parent)
        $parent = [IO.Path]::GetDirectoryName($parent)
    }
    Write-Host "已移到資源回收筒：$(Get-SnName $Path $Dir)" -ForegroundColor DarkGray
}

# 把資料夾打包成 zip，回傳 zip 路徑；失敗時寫錯誤、刪掉寫到一半的 zip，並不回傳。
# $Out 可以是 .zip 檔名或既有資料夾（放進去、用預設檔名），也接受檔案總管「複製路徑」帶的引號；
# 空白或空字串用預設（桌面）。以 \ 或 / 結尾代表資料夾，不存在就報錯（不會變成 x\.zip）。
# 不可放在資料夾或工具目錄內：前者會把自己打包進去，後者會進 git、解除安裝時也會一起被刪。
# .NET 方法丟的例外只會中止那一行，函式會照樣回傳路徑，呼叫端就以為匯出成功了，所以解析路徑與寫檔都包在 try 裡。
# 前置檢查放在 try 外：$ErrorActionPreference='Stop' 時，它們的 Write-Error 才不會被 catch 再包一層。
function Export-SnData([string]$Dir, [string]$Out) {
    $name = 'snippets-{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date)
    $Out = "$Out".Trim().Trim('"', "'").Trim()
    if (-not $Out) { $Out = Join-Path ([Environment]::GetFolderPath('Desktop')) $name }
    # 只接受檔案系統路徑：HKCU:\x 之類會解析成 HKEY_CURRENT_USER\x，.NET 再把它當成相對路徑，寫到意想不到的地方。
    $provider = $null
    try { $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out, [ref]$provider, [ref]$null) }
    catch { Write-Error "匯出失敗，路徑無效：$Out（$($_.Exception.Message)）"; return }
    if ($provider.Name -ne 'FileSystem') { Write-Error "匯出失敗，路徑必須在磁碟上：$Out"; return }
    if ([IO.Directory]::Exists($full)) { $full = Join-Path $full $name }
    elseif ($Out -match '[\\/]$') {
        if ([IO.File]::Exists($full.TrimEnd('\', '/'))) { Write-Error "不是資料夾：$($full.TrimEnd('\', '/'))" }
        else { Write-Error "資料夾不存在：$full" }
        return
    }
    elseif (-not $full.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) { $full += '.zip' }
    $Out = $full
    foreach ($inside in $Dir, $PSScriptRoot) {
        if ($Out.StartsWith($inside.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            Write-Error "匯出位置不可在 $inside 裡面：$Out"; return
        }
    }
    if ([IO.File]::Exists($Out) -or [IO.Directory]::Exists($Out)) { Write-Error "已存在同名的檔案或資料夾：$Out"; return }
    $created = $false
    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # 不用 CreateFromDirectory：5.1（.NET Framework）的版本會以 \ 分隔路徑。逐檔加入，名稱自己用 /。
        # 編碼必須是 [Text.Encoding]::UTF8 這個實例：.NET Framework 只在等於它時才設定 zip 的 UTF-8 旗標，
        # 另外 new 的 UTF8Encoding($false) 不算，中文檔名會被其他工具當成 Big5 讀成亂碼。
        $zip = [IO.Compression.ZipFile]::Open($Out, 'Create', [Text.Encoding]::UTF8)
        $created = $true
        try {
            foreach ($f in [IO.Directory]::GetFiles($Dir, '*.md', 'AllDirectories')) {
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f, ((Get-SnName $f $Dir) + '.md'), 'Optimal')
            }
        } finally { $zip.Dispose() }
        $Out
    } catch {
        if ($created) { Remove-Item -LiteralPath $Out -Force -ErrorAction SilentlyContinue }
        Write-Error "匯出失敗：$($_.Exception.Message)"
    }
}

# 解除安裝：永久刪除所有 snippet 與工具目錄（含 .git），並從目前的 shell 移除 sn。
# 先說明、可選擇匯出，再確認兩次。profile 裡載入 sn 的那幾行不動（檔案不存在時會略過）。
function Uninstall-Sn([string]$Dir) {
    $tool = $PSScriptRoot
    # 列舉失敗（例如拒絕存取的子資料夾）時 $all 會是空的、防呆就放行了；
    # 而 SNIPPETS_DIR 指到 $HOME、D:\ 這類大範圍時最容易發生，所以任何例外都直接取消。
    try { $all = @([IO.Directory]::GetFiles($Dir, '*', 'AllDirectories')) }
    catch { Write-Error "無法完整讀取 $Dir，為避免誤刪已取消：$($_.Exception.Message)"; return }
    $md = @($all | Where-Object { $_.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase) })
    $other = @($all | Where-Object { -not $_.EndsWith('.md', [StringComparison]::OrdinalIgnoreCase) })
    # 資料夾裡只該有 snippet；有別的檔案代表 SNIPPETS_DIR 可能指錯地方（例如 D:\Project），整個拒絕。
    if ($other.Count) {
        Write-Error ("snippet 資料夾裡有不是 .md 的檔案，為避免誤刪已取消：$Dir`n  " + (($other | Select-Object -First 5) -join "`n  "))
        return
    }

    Write-Host '解除安裝會永久刪除以下內容（不經資源回收筒，無法復原）：' -ForegroundColor Yellow
    Write-Host "  1. 所有 snippet（$($md.Count) 個）：$Dir"
    Write-Host "  2. 工具本身（含 .git）：$tool"
    Write-Host '  GitHub 上的 repo 不受影響。profile 裡載入 sn 的那幾行不會動，檔案不存在時會自動略過；要清乾淨請自行刪除。'
    Write-Host ''

    if ($md.Count -and (Read-Host '要先把 snippet 匯出成 zip 嗎？[Y/n]') -notmatch '^[nN]') {
        $default = Join-Path ([Environment]::GetFolderPath('Desktop')) ('snippets-{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date))
        $out = Read-Host "匯出到哪裡？可填 .zip 檔名或既有資料夾（直接 Enter：$default）"
        if (-not "$out".Trim()) { $out = $default }
        $zip = Export-SnData $Dir $out
        if (-not $zip) { Write-Host '匯出失敗，已取消解除安裝，什麼都沒刪。'; return }
        Write-Host "已匯出：$zip"
    }

    if ((Read-Host '第一次確認：確定要永久刪除上面列出的全部內容？[y/N]') -notmatch '^[yY]$') {
        Write-Host '已取消，什麼都沒刪。'; return
    }
    if ((Read-Host '第二次確認：輸入 uninstall 以永久刪除') -cne 'uninstall') {
        Write-Host '輸入不符，已取消，什麼都沒刪。'; return
    }

    # 目前目錄在要刪的地方裡面時，資料夾會被鎖住刪不掉。
    foreach ($target in $Dir, $tool) {
        if (($PWD.ProviderPath.TrimEnd('\') + '\').StartsWith($target.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { Set-Location $HOME }
    }
    foreach ($target in $Dir, $tool) {
        if ([IO.Directory]::Exists($target)) { Remove-Item -LiteralPath $target -Recurse -Force }
    }
    $left = @($Dir, $tool | Where-Object { [IO.Directory]::Exists($_) })
    if ($left.Count) { Write-Error "有些內容沒刪乾淨，請手動處理：$($left -join '、')"; return }

    foreach ($f in 'sn', 'Get-SnName', 'Get-SnDir', 'Read-SnFile', 'Invoke-SnUtf8', 'Select-SnFile', 'Open-SnEditor',
                    'Resolve-SnPath', 'Remove-SnFile', 'Export-SnData', 'Uninstall-Sn', 'Show-SnHelp') {
        Remove-Item "function:\$f" -ErrorAction SilentlyContinue
    }
    Remove-Variable SnCommands -Scope Global -ErrorAction SilentlyContinue
    Write-Host '已解除安裝。'
}

$SnCommands = [ordered]@{
    new  = 'sn new <名稱>    建立並編輯（已存在則直接編輯），例如 sn new git/squash'
    rm   = 'sn rm <名稱>     刪除（移到資源回收筒）'
    grep = 'sn grep <regex>  全文搜尋內容，再從符合的檔案中挑選'
    dir  = 'sn dir           印出資料夾路徑，例如 cd (sn dir)'
    export = 'sn export [路徑]  把所有 snippet 匯出成 zip；路徑可為 .zip 檔名或既有資料夾，預設存到桌面'
    uninstall = 'sn uninstall     解除安裝：可先匯出，確認兩次後永久刪除所有 snippet 與工具本身'
    help = 'sn help          顯示本說明'
}

function Show-SnHelp {
    Write-Host 'sn [關鍵字...]    fzf 挑選（比對名稱、tags、desc）；只有一筆符合時直接複製'
    foreach ($v in $SnCommands.Values) { Write-Host $v }
    Write-Host ''
    Write-Host '挑選畫面：Enter 複製第一個 code block · Ctrl-E 編輯 · Ctrl-O 印到 stdout · Ctrl-X 刪除'
    Write-Host '指令與 sn new／sn rm 的名稱都可以按 Tab 補全；Ctrl+Space 列出全部選項'
}

function sn {
    <#
    .SYNOPSIS
        存取 snippet。
    .DESCRIPTION
        sn [關鍵字...]      以 fzf 挑選（比對名稱、tags、desc）；只有一筆符合時直接複製
        sn grep <regex>     先以 rg 全文搜尋內容，再從符合的檔案中挑選
        sn new <名稱>       建立並編輯，名稱可含子資料夾，例如 sn new git/squash；已存在則直接編輯
        sn rm <名稱>        刪除（移到資源回收筒）
        sn dir              印出資料夾路徑，例如 cd (sn dir)
        sn export [路徑]    把所有 snippet 匯出成 zip；路徑可為 .zip 檔名或既有資料夾，預設存到桌面
        sn uninstall        解除安裝：可先匯出，確認兩次後永久刪除所有 snippet 與工具本身
        sn help             列出指令與按鍵

        挑選畫面：Enter 複製第一個 code block、Ctrl-E 編輯、Ctrl-O 印到 stdout（可接管線）、Ctrl-X 刪除。
        編輯器依序取 $env:SN_EDITOR、$env:EDITOR，都沒有時用 nvim。
    #>
    # 參數只是為了讓 Tab 補全有地方掛，其餘的字落在 $args；全部合起來就是 fzf 的關鍵字。
    # 刻意寫成一般函式、參數名以 _ 開頭：關鍵字如 -C、-v 才不會被前綴比對成參數
    # 或 -Verbose 之類的通用參數。
    param([string]$_Sub, [string]$_Arg)
    $dir = Get-SnDir
    $cmd = $_Sub
    $restText = ((@($_Arg) + @($args)) -join ' ').Trim()

    switch ($cmd) {
        'help' { Show-SnHelp; return }
        'dir' { return $dir }
        'export' {
            $zip = Export-SnData $dir $restText
            if ($zip) { Write-Host "已匯出：$zip" }
            return
        }
        'uninstall' { Uninstall-Sn $dir; return }
        'rm' {
            if (-not $restText) { Write-Error '用法：sn rm <名稱>'; return }
            $path = Resolve-SnPath $restText $dir
            if (-not $path) { return }
            if (-not [IO.File]::Exists($path)) { Write-Error "沒有這個 snippet：$restText"; return }
            Remove-SnFile $path $dir
            return
        }
        'new' {
            if (-not $restText) { Write-Error '用法：sn new <名稱>，例如 sn new git/squash'; return }
            $path = Resolve-SnPath $restText $dir
            if (-not $path) { return }
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
            if (-not $restText) { Write-Error '用法：sn grep <regex>'; return }
            if (-not (Get-Command rg -CommandType Application -ErrorAction SilentlyContinue)) {
                Write-Error 'sn grep 需要 ripgrep：winget install BurntSushi.ripgrep.MSVC'; return
            }
            # --no-ignore --hidden：與 sn 列出的檔案一致。否則 rg 會套用上層 repo 的 .gitignore（data/），
            # 連帶忽略任何叫 data 的子資料夾，也會略過 .trash 之類的隱藏資料夾。
            $files = @(Invoke-SnUtf8 { rg --files-with-matches --ignore-case --no-ignore --hidden --glob '*.md' -- $restText $dir } | Sort-Object)
            # rg 結束碼：1 是沒有符合，2 是錯誤（例如 regex 寫錯，rg 已自行印出原因）。
            if ($LASTEXITCODE -ge 2) { return }
            if (-not $files.Count) { Write-Host "沒有內容符合：$restText"; return }
            $query = ''
        }
        default {
            $files = @([IO.Directory]::GetFiles($dir, '*.md', 'AllDirectories') | Sort-Object)
            if (-not $files.Count) { Write-Host "還沒有 snippet，用 sn new <名稱> 建立第一個（資料夾：$dir；sn help 看全部指令）"; return }
            $query = ((@($_Sub) + @($restText)) -join ' ').Trim()
        }
    }

    $pick = Select-SnFile $files $dir $query
    if (-not $pick) { return }
    $key, $path = $pick
    switch ($key) {
        'ctrl-e' { Open-SnEditor $path }
        'ctrl-o' { (Read-SnFile $path).Code }
        'ctrl-x' { Remove-SnFile $path $dir }
        default {
            # 5.1 的 Set-Clipboard 收到空字串會丟例外（剛 sn new 完還沒寫內容時最常見）。
            $code = (Read-SnFile $path).Code
            if (-not $code) { Write-Host "沒有內容可複製：$(Get-SnName $path $dir)"; return }
            Set-Clipboard -Value $code
            Write-Host "已複製 $(Get-SnName $path $dir)" -ForegroundColor DarkGray
        }
    }
}

# Tab 補全：第一個字補子指令（附說明），sn new／sn rm 後面補既有名稱與資料夾。
# 只註冊 scriptblock，按 Tab 時才執行，不影響載入速度。
Register-ArgumentCompleter -CommandName sn -ParameterName _Sub -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete)
    $hits = @($SnCommands.Keys | Where-Object { $_.StartsWith($wordToComplete, [StringComparison]::OrdinalIgnoreCase) })
    foreach ($k in $hits) { New-Object Management.Automation.CompletionResult $k, $k, 'ParameterValue', $SnCommands[$k] }
    # 不是子指令就是搜尋關鍵字；同 _Arg，原樣回傳以擋掉 PowerShell 改補目前目錄的檔名。
    if (-not $hits.Count -and $wordToComplete) {
        New-Object Management.Automation.CompletionResult $wordToComplete, $wordToComplete, 'ParameterValue', '搜尋關鍵字'
    }
}
Register-ArgumentCompleter -CommandName sn -ParameterName _Arg -ScriptBlock {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
    $sub = $fakeBoundParameters['_Sub']
    if ($sub -ne 'new' -and $sub -ne 'rm') { return }
    $dir = Get-SnDir
    $names = foreach ($f in [IO.Directory]::GetFiles($dir, '*.md', 'AllDirectories')) { Get-SnName $f $dir }
    $folders = foreach ($d in [IO.Directory]::GetDirectories($dir, '*', 'AllDirectories')) { (Get-SnName $d $dir) + '/' }
    $prefix = $wordToComplete.Trim("'", '"').Replace('\', '/')
    # 照字面比對前綴：-like 會把使用者打的 [ 當成萬用字元，樣式不合法時整個補全器失效。
    $hits = @(@($folders) + @($names) | Sort-Object | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) })
    foreach ($n in $hits) {
        # 含空格或 PowerShell 特殊字元的名稱要加單引號，否則 a (1) 的 (1) 會被當成子運算式、$x 會被展開。
        $text = if ($n -match '[\s$`''"(){}@;,&|<>#\[\]]') { "'" + ($n -replace "'", "''") + "'" } else { $n }
        New-Object Management.Automation.CompletionResult $text, $n, 'ParameterValue', $n
    }
    # 沒有結果時 PowerShell 會改補目前目錄的檔名，那些都不是 snippet 名稱；原樣回傳以擋掉。
    if (-not $hits.Count -and $wordToComplete) {
        $tip = if ($sub -eq 'new') { '新名稱' } else { '沒有符合的 snippet' }
        New-Object Management.Automation.CompletionResult $wordToComplete, $wordToComplete, 'ParameterValue', $tip
    }
}
