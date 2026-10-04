# MintLedger

MintLedger 是一款離線優先、以繁體中文設計的 iPhone 記帳 App。所有資料預設只保存在本機，並使用 iOS 26 原生 Liquid Glass 呈現互動介面。

## 功能

- 收入／支出、分類、帳戶、備註與日期管理
- 本月收支、總資產、完整每日支出圖表與分類圓餅圖
- 定期交易資料模型與到期自動入帳
- 明細依月份分組統計，可搜尋、篩選、批次刪除及批次更改分類
- 點選單筆明細可查看詳細資料並編輯，金額鍵盤支援加減乘除
- 自動輪替最近 10 份本機備份
- 可用一次性 App 內購買永久開啟 iCloud 私人雲端備份：每天一個版本，自動更新並保留最近 30 天
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

首次使用 Apple Developer 帳號編譯時，請在 Certificates, Identifiers & Profiles 為 `com.pandaisland.mintledger` 啟用 App Groups 與 iCloud/CloudKit，建立並指派 `iCloud.com.pandaisland.mintledger` 容器，再重新產生 provisioning profile。App Store Connect 需建立產品 ID `com.pandaisland.mintledger.cloudbackup.lifetime` 的非消耗型 App 內購買，台灣價格設為 NT$60。

## 下載與側載

每次推送到 `main`，GitHub Actions 都會執行測試並產生 `MintLedger-unsigned.ipa` artifact。下載後可用 AltStore 或 Sideloadly 以自己的 Apple ID 重新簽署並側載。

> 無簽章 IPA 無法直接安裝，iCloud、App 內購買與 Widget App Group 也必須使用包含相應權限的正式 provisioning profile。沒有 Mac 時，可用 GitHub Actions 的 macOS runner 封存、簽署及上傳 App Store Connect。

## 隱私

MintLedger 沒有分析或廣告 SDK。主 App、捷徑與 Widget 只透過 App Group 分享本機 JSON；購買雲端備份後，完整備份只會上傳到目前使用者自己的 CloudKit 私人資料庫，並占用該使用者的 iCloud 配額。帳本資料使用 `completeUntilFirstUserAuthentication` 檔案保護，使使用者開機後首次解鎖後，鎖定畫面的捷徑仍能新增交易。

- [使用支援](https://mintledger-support.mingray-ai.chatgpt.site/support/)
- [隱私權政策](https://mintledger-support.mingray-ai.chatgpt.site/privacy/)
- [EULA](https://mintledger-support.mingray-ai.chatgpt.site/eula/)

## 授權

MIT
