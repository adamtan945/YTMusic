# Menu Bar 與視窗外觀修正

## 目標
修使用者回報的 7 項問題（編號依原需求）：
1. 播放列/側欄仍出現捲軸 → CSS 注入穿不進 shadow DOM，改 patch `attachShadow` 並提前到 documentStart 注入。
2. Menu bar 無封面與播放清單 → 使用者跑的是舊 build；重建後驗證，並在本次重新設計中確保封面/清單存在。
3+4. Menu bar 快速控制重新設計，玻璃卡片（liquid glass 風格）：NSVisualEffectView 圓角卡片、封面 88px、單列控制鍵（shuffle/prev/play/next/repeat）、進度條、音量列。
6. 播放清單去重 → JS `getQueueRows` 以 title|artist|duration 去重。
7. 播放清單列：正在播放顯示喇叭 icon 覆蓋縮圖；hover 任一列顯示播放 icon 與 highlight，整列可點擊跳播。
8. 視窗頂部白條 → ContentView `.ignoresSafeArea()` + WebView 深色背景。

## 驗證
- `bash scripts/bundle.sh` 建置成功。
- `swift build` / SmokeTests 通過。
- 使用者手動驗證 UI（menu bar 外觀、捲軸、白條）。

## 同步文件
- 邊做邊更新專案 `CORE_RULES.md`（CLAUDE.md symlink 目標）：建置指令、架構速覽、已知陷阱。
