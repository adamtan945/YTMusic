# Review Fixes Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 4 個 code review 指出的實際行為問題，且把修改限制在既有 Swift 與注入式 JavaScript 邏輯。

**Architecture:** 以最小範圍修補為主，不重整既有結構。`JavaScriptBridge.swift` 統一 queue 與 track 判斷邏輯，並讓 video 事件可在 DOM 重建後重新綁定；`MenuBarService.swift` 則加入封面請求版本保護，避免非同步競態覆蓋最新狀態。

**Tech Stack:** Swift 5.9、AppKit、WKWebView、注入式 JavaScript

---

### Task 1: 建立修補邊界

**Files:**
- Modify: `Sources/Helpers/JavaScriptBridge.swift`
- Modify: `Sources/Services/MenuBarService.swift`
- Note: 目前專案無 test target，先以 `swift build` 做編譯驗證

- [x] 確認 4 個 findings 的根因與影響範圍
- [x] 保持修改只落在 bridge 與 menu bar 封面載入邏輯

### Task 2: 修正 track fingerprint 與 queue 對應

**Files:**
- Modify: `Sources/Helpers/JavaScriptBridge.swift`

- [x] 讓 `nowPlaying` 以完整 fingerprint 判斷，而不是只看 title
- [x] 抽出共用 queue 掃描/去重規則
- [x] 讓 menu 顯示與點擊播放使用完全一致的 queue 索引來源

### Task 3: 修正 video 事件重綁與封面競態

**Files:**
- Modify: `Sources/Helpers/JavaScriptBridge.swift`
- Modify: `Sources/Services/MenuBarService.swift`

- [x] 在 `<video>` 元素替換後重新綁定事件
- [x] 加入封面請求版本檢查，避免舊請求覆蓋新歌曲封面

### Task 4: 驗證

**Files:**
- Verify: `Sources/Helpers/JavaScriptBridge.swift`
- Verify: `Sources/Services/MenuBarService.swift`

- [x] 執行 `swift build`
- [x] 檢查 diff 確認只包含本次修補所需變更
- [x] 回報目前可驗證的結果與尚未自動化覆蓋的風險
