# Queue Thumbnail Fix Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修正 menubar playlist 只有前幾首會出現縮圖、後面歌曲缺圖的問題。

**Architecture:** 先用 smoke test 固定「queue row 要能解析 lazy-load 縮圖 URL」這個行為，再補強 `JavaScriptBridge.monitorScript` 的縮圖 URL 萃取邏輯，不改動 menu UI 結構。

**Tech Stack:** Swift 6、WKWebView smoke test、注入式 JavaScript bridge

---

### Task 1: 重現與鎖定行為

**Files:**
- Modify: `SmokeTests/main.swift`

- [ ] 新增 queue thumbnail fallback 的 smoke test
- [ ] 先驗證測試在現況會失敗

### Task 2: 修正 queue thumbnail URL 萃取

**Files:**
- Modify: `Sources/Helpers/JavaScriptBridge.swift`

- [ ] 補上多來源縮圖 URL 萃取 helper
- [ ] 讓 queue item 優先使用實際可用的圖片 URL

### Task 3: 驗證

**Files:**
- Verify: `SmokeTests/main.swift`
- Verify: `Sources/Helpers/JavaScriptBridge.swift`

- [ ] 執行 `swift run SmokeTests`
- [ ] 執行 `swift build`
- [ ] 執行 `bash scripts/bundle.sh`
