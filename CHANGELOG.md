# Changelog

## [1.2.0] - 2026-07-04

### Added
- YouTube Music style menu bar status icon (circle with play triangle, template image)
- Glass-card now playing panel in the menu bar: 88px artwork, single control row (shuffle / previous / play / next / repeat), progress and volume sliders
- Full-row hover and click-to-play on the menu bar queue, with speaker icon on the currently playing row
- Transparent drag strip above the web content so the borderless window can be moved
- Capsule scroll indicators on the menu bar queue that hide at the top and bottom edges
- Ad-hoc codesign in the bundle script so Finder and Dock show the app icon

### Changed
- Window chrome is now fully borderless dark: web content extends under the transparent titlebar
- YouTube Music nav bar is pushed 28px down so the hamburger menu sits below the traffic light buttons
- Queue is sourced from a single `ytmusic-player-queue` container, keeping legitimate duplicate songs while dropping cross-render copies

### Fixed
- White strip above the web content caused by SwiftUI safe area insets
- Scrollbars showing inside the player bar and queue panels (CSS now reaches shadow DOM via `attachShadow` patch)
- 12px gap reserved for the hidden scrollbar (`--ytmusic-scrollbar-width` reset to 0)
- Menu bar queue showing duplicated rows (song/video counterpart renderers) or a single row in video mode
- Hover highlight lingering on queue rows while scrolling

### Removed
- Unused `MediaKeyService` placeholder (media keys are handled by the WebView MediaSession)

### 新增
- Menu Bar 常駐圖示改為 YouTube Music 風格（圓形＋播放三角，template 圖自動配合深淺色）
- Menu Bar 播放中區塊改為玻璃卡片：88px 封面、單列控制鍵（隨機／上一首／播放／下一首／重複）、進度與音量滑桿
- 待播清單整列 hover 與點擊跳播，正在播放列顯示喇叭圖示
- 網頁內容上方新增透明拖曳區，無邊框視窗可拖動
- 待播清單上下新增膠囊捲動指示器，捲到頂／底自動隱藏
- bundle script 加入 ad-hoc 簽名，Finder 與 Dock 正常顯示 app icon

### 變更
- 視窗外框改為全深色無邊框：網頁內容延伸到透明標題列下方
- YouTube Music nav bar 下移 28px，漢堡選單落在紅綠燈正下方
- 待播清單改以單一 `ytmusic-player-queue` 容器為來源，保留合法重複歌曲、去除跨區重複渲染

### 修正
- SwiftUI safe area 造成網頁內容上方的白色橫條
- 播放列與待播清單面板出現捲軸（透過 patch `attachShadow` 讓 CSS 進入 shadow DOM）
- 捲軸隱藏後仍保留的 12px 空隙（`--ytmusic-scrollbar-width` 歸零）
- Menu Bar 待播清單重複列（歌曲／影片雙版本渲染）與影片模式下只剩一列的問題
- 捲動時待播清單 hover 高亮殘留

### 移除
- 未使用的 `MediaKeyService` 佔位（媒體鍵由 WebView MediaSession 處理）

## [1.1.0] - 2026-04-02

### Added
- Richer menu bar now playing panel with playback progress, volume slider, repeat, and shuffle controls
- Up next playlist inside the menu bar with thumbnail hover play affordance and preserved scroll position
- Queue thumbnail fallback parsing for lazy-loaded YouTube Music artwork sources
- Smoke test target for JavaScript bridge regressions and playlist behavior

### Changed
- Split the Swift package into a reusable `YTMusicCore` target plus dedicated app and smoke test executables
- Menu bar queue rendering now stays aligned with the visible YouTube Music queue ordering instead of deduping rows
- Queue item interactions are limited to the artwork play affordance to reduce accidental song switches

### Fixed
- Track changes are now detected with a full fingerprint instead of title only, so same-name songs still update correctly
- Queue playback targeting now uses the same row mapping as queue fetch, fixing mismatched playback selection
- Video event listeners are rebound after player element replacement so progress and playback state keep updating
- Artwork requests now ignore stale responses, preventing old covers from overwriting the current track
- Menu bar queue thumbnails now continue loading for later playlist rows instead of stopping after the first few items

### 新增
- Menu Bar 新增更完整的播放中區塊，包含進度列、音量滑桿、重複與隨機播放控制
- Menu Bar 內建待播清單，支援封面 hover 播放按鈕與保留捲動位置
- 補上 YouTube Music lazy-load 封面圖來源 fallback，後段清單也能解析縮圖
- 新增 JavaScript bridge 與播放清單行為的 smoke test target

### 變更
- Swift Package 拆分為可重用的 `YTMusicCore` target，以及獨立的 app 與 smoke test executable
- Menu Bar 待播清單改為跟隨 YouTube Music 畫面上的實際 queue 順序，不再自行去重
- 待播清單互動改成只有封面播放 affordance 可切歌，降低誤觸

### 修正
- 切歌判斷改用完整 track fingerprint，不再因同名歌曲而漏更新
- 待播清單播放索引與抓取索引統一，修正點選歌曲卻播放錯列的問題
- 播放器 video 元素被重建後會重新綁定事件，避免進度與播放狀態失聯
- 封面下載加入過期請求保護，避免舊歌曲封面覆蓋目前播放中的歌曲
- 修正待播清單縮圖只顯示前幾首、後面列缺圖的問題

## [1.0.0] - 2026-03-28

### Added
- YouTube Music web player via WKWebView
- Google account sign-in (Safari UA + persistent session)
- Background playback (closing window doesn't stop music)
- Menu Bar controls with album art, track info, play/pause/next/previous
- Song change macOS system notifications
- Media key support via WebView MediaSession
- Dock icon to restore window
- Keyboard shortcuts ⌘C/V/X/A support
- `scripts/bundle.sh` to build .app bundle
- `scripts/generate_icon.py` to generate App Icon
- `scripts/create_dmg.sh` to create DMG installer
- `scripts/uninstall.sh` for clean removal

### 新增
- WKWebView 載入 YouTube Music 網頁版
- Google 帳號登入（Safari UA + session 持久化）
- 背景播放（關閉視窗不退出 App）
- Menu Bar 常駐圖示（含封面圖、歌名、歌手、播放控制）
- 歌曲切換 macOS 系統通知
- 媒體鍵控制（透過 WebView 內建 MediaSession）
- Dock 圖示重開視窗
- 主選單支援 ⌘C/V/X/A 快捷鍵
- `scripts/bundle.sh` 打包成 .app bundle
- `scripts/generate_icon.py` 生成 App Icon
- `scripts/create_dmg.sh` 建立 DMG 安裝映像
- `scripts/uninstall.sh` 完整移除 App 及資料
