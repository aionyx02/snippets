# snippets

終端機裡的 snippet 管理：一個 PowerShell 函式 `sn`，用 fzf 挑、Enter 複製。不必開 IDE。

本 repo 只放工具本身。**snippet 內容存在本地的 `data/`，已列入 `.gitignore`，不會上傳。**

## 需求

- PowerShell 5.1 或 7
- [fzf](https://github.com/junegunn/fzf) 0.51+（`--with-shell`）、[ripgrep](https://github.com/BurntSushi/ripgrep)（只有 `sn grep` 用到）

## 安裝

在 profile 裡 dot-source：

```powershell
$snScript = 'D:\Project\snippets\sn.ps1'
if ([IO.File]::Exists($snScript)) { . $snScript }
```

載入時只定義函式，不啟動任何外部程式，不影響 shell 啟動速度。

## 用法

```powershell
sn                    # 列出全部，fzf 挑選
sn git rebase         # 帶關鍵字開啟；只有一筆符合時直接複製
sn grep 'HEAD~\d'     # 全文搜尋內容（regex，不分大小寫），再從符合的檔案中挑
sn new git/squash     # 建立並編輯；已存在就直接編輯
sn rm git/squash      # 刪除，移到資源回收筒
cd (sn dir)           # 到資料夾
sn export             # 把所有 snippet 匯出成 zip（預設存到桌面；可指定 .zip 檔名或既有資料夾）
sn help               # 忘了指令時看這個
```

子指令與 `sn new`／`sn rm` 後面的既有名稱、資料夾都能按 `Tab` 補全；`Ctrl+Space` 會列出全部選項並附上說明。

挑選畫面：

| 鍵 | 動作 |
|---|---|
| `Enter` | 複製第一個 code block 到剪貼簿（沒有 code block 時複製整個內文） |
| `Ctrl-E` | 用編輯器開啟 |
| `Ctrl-O` | 印到 stdout，可存進變數或接管線：`$c = sn` |
| `Ctrl-X` | 刪除，移到資源回收筒（`data/` 不進 git，回收筒是誤刪時唯一的退路） |

fzf 比對的是名稱、tags 與 desc；要搜內容用 `sn grep`。

帶關鍵字且只有一筆符合時，不會開畫面、直接當成按了 Enter（複製）。要接管線就別帶關鍵字，或確定會有多筆符合。

## 檔案格式

一個 snippet 一個 `.md`，子資料夾隨意分。純 Markdown，Sublime／Obsidian／JetBrains 都能直接開：

````markdown
---
tags: git, rebase
desc: 把最近 N 個 commit 壓成一個
---

說明想寫多長都行，只有第一個 code block 會被複製。

```bash
git rebase -i HEAD~3
```
````

## 設定

| 環境變數 | 預設 | 用途 |
|---|---|---|
| `SNIPPETS_DIR` | 本 repo 的 `data/` | snippet 資料夾 |
| `SN_EDITOR` | `$env:EDITOR`，再沒有就 `nvim` | 編輯器，可帶參數（例如 `subl -w`）；路徑含空格要用雙引號包住程式路徑 |

`data/` 不進 git，重灌前記得用 `sn export` 備份。

## 解除安裝

```powershell
sn uninstall
```

1. 列出會被**永久刪除**的內容（不經資源回收筒）：所有 snippet，以及工具目錄本身（含 `.git`；GitHub 上的 repo 不受影響）。
2. 問要不要先匯出成 zip（預設要）；匯出失敗就整個取消。
3. 第一次確認：輸入 `y`。
4. 第二次確認：輸入 `uninstall`（大小寫須相符）。
5. 刪除，並把 `sn` 從目前的 shell 移除。

snippet 資料夾裡只要有任何不是 `.md` 的檔案，就會拒絕執行並列出那些檔案，避免 `SNIPPETS_DIR` 指錯地方時誤刪。

profile 裡載入 `sn` 的那幾行不會被改動；檔案不存在時會自動略過、不會報錯，要清乾淨請自行刪除。
