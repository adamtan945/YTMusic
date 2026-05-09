# Smoke Tests Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 為本次修掉的 4 個 review findings 補最小可跑的 smoke test，避免之後回歸。

**Architecture:** 新增 `testTarget` 與兩層測試。`WKWebView` smoke test 驗證 JS bridge 的 track fingerprint、queue 對應與 video 重新綁定；純 Swift 單元測試驗證封面 request token 不會接受舊回應。

**Tech Stack:** Swift 5.9、XCTest、WebKit

---

### Task 1: 建立測試邊界

**Files:**
- Modify: `Package.swift`
- Create: `Tests/YTMusicTests/JavaScriptBridgeSmokeTests.swift`
- Create: `Tests/YTMusicTests/MenuBarServiceTests.swift`

- [ ] 決定最小可測 API
- [ ] 先讓 test target 與 failing tests 建立起來

### Task 2: TDD 補最小可測介面

**Files:**
- Modify: `Sources/Helpers/JavaScriptBridge.swift`
- Modify: `Sources/Services/MenuBarService.swift`

- [ ] 抽出可在測試中直接執行的 command script
- [ ] 抽出封面 request token helper

### Task 3: 驗證

**Files:**
- Verify: `Tests/YTMusicTests/JavaScriptBridgeSmokeTests.swift`
- Verify: `Tests/YTMusicTests/MenuBarServiceTests.swift`

- [ ] 執行 `swift test`
- [ ] 執行 `swift build`
- [ ] 回報仍未覆蓋的實站風險
