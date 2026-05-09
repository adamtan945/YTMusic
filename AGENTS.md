# AGENTS.md — YTMusic

本檔為 AI agent（Claude Code、Codex 等）工作指引。詳細專案說明請見 [README.md](./README.md)。

## 專案類型

Swift / SPM

## 簡介

![Version](https://img.shields.io/badge/version-1.1.0-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)

## 目錄結構

```
YTMusic/
├── AGENTS.md             # 本檔，agent 工作指引
├── CLAUDE.md → AGENTS.md # symlink
├── README.md             # 對外說明
├── CHANGELOG.md          # 變更記錄
├── memory/current.md     # 工作進度與最近決策
├── plan/current.md       # 待辦與已完成
└── .claude/
    ├── memory → ../memory
    └── plan   → ../plan
```

## 開發指令

```bash
swift build
swift run
```

## Agent 工作守則

1. **變更前先讀 README.md 與 memory/current.md**：理解專案目的與當前狀態。
2. **規劃變動寫進 plan/current.md**：實作前先有計劃。
3. **重大變更後更新 CHANGELOG.md**：依日期記錄做了什麼、為什麼。
4. **進度同步 memory/current.md**：下次接手時能快速理解狀態。
