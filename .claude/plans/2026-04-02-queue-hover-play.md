# Queue Hover Play Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓 menubar playlist 的縮圖在滑鼠移入時切成播放按鈕視覺，接近 app 內建 queue 的互動。

**Architecture:** 保持 `MenuBarService.swift` 為主要修改檔，新增輕量自訂 AppKit view 來處理 artwork hover overlay，不重做整個 menu row 結構。row 的選取與 hover 視覺分離，避免影響現有 queue 點擊行為。

**Tech Stack:** Swift 6、AppKit、NSMenu 自訂 view

---

### Task 1: 定義改動範圍

**Files:**
- Modify: `Sources/Services/MenuBarService.swift`

- [ ] 確認 queue row 現有結構與可插入 hover view 的位置
- [ ] 保持變更集中在 menu row 視覺與互動

### Task 2: 實作 artwork hover overlay

**Files:**
- Modify: `Sources/Services/MenuBarService.swift`

- [ ] 新增縮圖 hover 自訂 view
- [ ] 滑鼠移入時顯示遮罩與播放圖示
- [ ] 正在播放列保留播放中狀態，但 hover 時給出可點擊提示

### Task 3: 驗證

**Files:**
- Verify: `Sources/Services/MenuBarService.swift`

- [ ] 執行 `swift build`
- [ ] 執行 `bash scripts/bundle.sh`
- [ ] 回報新的 `.app` 路徑
