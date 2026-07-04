# CORE_RULES.md — YTMusic

本檔只記錄本專案相對於 `~/CORE_RULES.md` 的補充規則；共用語言、查證、plan/memory、刪除、secrets 與驗證規則以 `~/CORE_RULES.md` 為準。

`AGENTS.md` 與 `CLAUDE.md` 應為指向本檔的 symlink。

## 專案類型

Swift / SPM，macOS 13+ 原生 App（WKWebView 包 YouTube Music）。

## 建置與驗證

- 編譯：`swift build`
- Smoke tests：`swift run SmokeTests`（真的起 WKWebView 驗證注入的 JS，必須全過才能宣稱完成）
- 打包 .app：`bash scripts/bundle.sh`，產物在 `build/YTMusic.app`
- 安裝：`cp -R build/YTMusic.app /Applications/`
- UI 變更後使用者回報的畫面問題，先確認對方跑的是新 build（`/Applications` 內的版本可能是舊的），再開始查程式碼。

## 架構速覽

- `Sources/App/AppDelegate.swift`：視窗建立（fullSizeContentView、深色背景）與主選單。
- `Sources/Views/WebView.swift`：單例 `WebViewManager`，WKWebView 設定與所有 WKUserScript 注入點。
- `Sources/Helpers/JavaScriptBridge.swift`：Swift ↔ JS 雙向橋接；`monitorScript` 是注入網頁的監聽腳本，`script(for:)` 是控制指令。queue 的抓取與跳播都走 `window.__ytmusicCodexGetQueueRows`，兩邊索引必須用同一份列表。
- `Sources/Services/MenuBarService.swift`：menu bar 選單全部用 frame-based NSView 手排（非 Auto Layout）；`menuNeedsUpdate` 每次開啟重建整份 menu，即時更新走 weak refs（playButton、progressSlider 等）。
- `SmokeTests/main.swift`：對 `monitorScript` 與指令 JS 的行為測試。

## 已知陷阱（改 code 前必讀）

- **SwiftUI safe area 白條**：視窗用 `fullSizeContentView` 時，`NSHostingView` 內容仍會避開標題列，留下一條白色。ContentView 必須 `.ignoresSafeArea()`，且 WKWebView 要設 `underPageBackgroundColor` 深色 + `setValue(false, forKey: "drawsBackground")`。
- **YT Music 的 shadow DOM**：document 層級注入的 CSS（如隱藏捲軸）穿不進 shadow root。必須在 `.atDocumentStart` patch `Element.prototype.attachShadow`，把 style 塞進每個新建的 shadow root。
- **Queue DOM 結構**（用 Chrome 實測過）：`ytmusic-player-queue > #contents` 放主要列，`#automix-contents` 放自動播放列；每首歌可能被 `ytmusic-playlist-panel-video-wrapper-renderer` 包住，內含 `#primary-renderer`（歌曲版）＋`#counterpart-renderer`（影片版）**兩列同一首歌**。`getQueueRows` 必須：以 selected 列的 `closest('ytmusic-player-queue')` 為唯一來源，每個 wrapper 只取顯示中那列。不可依 parentElement 分組（影片模式下每列 wrapper 不同，會只剩 1 列）；不可用 title/artist 全域去重 —— 合法重複歌曲必須保留，SmokeTests 有測試鎖定。
- **索引一致性**：`fetchQueue` 與 `playQueueItem` 都必須經過 `__ytmusicCodexGetQueueRows`，任何過濾/排序改動兩邊要同步，否則點擊會跳錯歌。
- **SmokeTests 依賴 YTMusicCore 的 public API**（`JavaScriptBridge.script(for:)`、`monitorScript`、`ArtworkRequestTracker`），改名或改存取層級前先看 `SmokeTests/main.swift`。
- **選單即時更新**：`refreshMenuContentsIfVisible()` 在 menu 開啟時整份重建，會重設 hover 與捲動狀態；捲動位置靠 `lastQueueScrollOffset` 還原，新增有狀態的 view 時要考慮重建。
- **捲軸佔位空隙**：捲軸隱藏後右側仍留白，是 YT Music 用 CSS 變數 `--ytmusic-scrollbar-width: 12px` 保留的空間，注入 `html { --ytmusic-scrollbar-width: 0px !important; }` 歸零（已在 WebView.swift 的 hideScrollbarScript 內）。
- **紅綠燈疊到網頁 header**：`ignoresSafeArea` 後 YT Music 的 nav bar 延伸到標題列下，會被視窗紅綠燈蓋住，注入 `ytmusic-nav-bar { padding-left: 72px !important; }` 右移避開。注入的 CSS 一律要加 `!important`：user script 的 style 在 YTM stylesheet 之前載入，同 specificity 時會輸。
- **Menu bar 圖示**：`makeStatusIcon()` 用 NSBezierPath 畫 YT Music 風格（圓形挖空播放三角），必須 `isTemplate = true` 才會自動配合 menu bar 深淺色。
- **捲動時 hover 殘留**：NSScrollView 捲動時是「列在動、滑鼠沒動」，NSTrackingArea 不會對捲走的列送 `mouseExited`，hover 高亮會殘留。必須在 `boundsDidChangeNotification`（`queueDidScroll`）裡用 `window.mouseLocationOutsideOfEventStream` 對每一列 `syncHover` 校正。
