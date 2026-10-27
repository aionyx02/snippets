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
cd (sn dir)           # 到資料夾
```

挑選畫面：

| 鍵 | 動作 |
|---|---|
| `Enter` | 複製第一個 code block 到剪貼簿（沒有 code block 時複製整個內文） |
| `Ctrl-E` | 用編輯器開啟 |
| `Ctrl-O` | 印到 stdout，可接管線：`sn docker \| Set-Content x.sh` |

fzf 比對的是名稱、tags 與 desc；要搜內容用 `sn grep`。

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
| `SN_EDITOR` | `$env:EDITOR`，再沒有就 `nvim` | 編輯器，可帶參數（例如 `subl -w`） |

`data/` 不進 git，重灌前記得自己備份。
