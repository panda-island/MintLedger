# MintLedger

MintLedger 是一款離線優先、以繁體中文設計的 iPhone 記帳 App。它不需要帳號，所有資料預設只保存在本機，並使用 iOS 26 原生 Liquid Glass 呈現互動介面。

## 功能

- 收入／支出、分類、帳戶、備註與日期管理
- 本月收支、總資產、完整每日支出圖表與分類圓餅圖
- 定期交易資料模型與到期自動入帳
- 明細依月份分組統計，可搜尋、篩選、批次刪除及批次更改分類
- 點選單筆明細可查看詳細資料並編輯，金額鍵盤支援加減乘除
- 自動輪替最近 10 份本機備份
- `.mintledger` JSON 完整匯出／還原及 CSV 匯出
- App Intent、Siri 與捷徑直接記帳；`alwaysAllowed` 支援裝置鎖定時執行，App 會即時同步新資料
- 4×2 桌面小工具顯示總資產與近期明細，2×1 鎖定畫面小工具顯示總資產
- iOS 26 原生 Liquid Glass，iOS 17–25 使用原生材質退路
- 原創 1024×1024 App Icon

## 開發環境

- Xcode 26+
- iOS 17+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
xcodegen generate
open MintLedger.xcodeproj
```

首次在自己的 Apple Developer 帳號編譯時，請將 `project.yml` 中的 bundle ID 與兩個 entitlements 內的 App Group 改成你的唯一識別碼，執行 `xcodegen generate`，再於 Xcode 的 Signing & Capabilities 選擇 Team。

## 下載與側載

每次推送到 `main`，GitHub Actions 都會執行測試並產生 `MintLedger-unsigned.ipa` artifact。下載後可用 AltStore 或 Sideloadly 以自己的 Apple ID 重新簽署並側載。

> 無簽章 IPA 無法直接安裝。Widget 的 App Group entitlement 通常需要 Apple Developer Program 與一致的 provisioning profile；若使用免費 Personal Team 重新簽署，主 App 可側載，但共享 Widget 資料可能因 entitlement 限制而無法運作。

## 隱私

MintLedger 沒有分析 SDK、廣告 SDK 或網路請求。主 App、捷徑與 Widget 只透過 `group.com.a0973.MintLedger` App Group 分享本機 JSON。帳本資料使用 `completeUntilFirstUserAuthentication` 檔案保護，使使用者開機後首次解鎖後，鎖定畫面的捷徑仍能新增交易。

## 授權

MIT
