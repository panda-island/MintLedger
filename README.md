# MintLedger

MintLedger 是一款離線優先、以繁體中文設計的 iPhone 與 Apple Watch 記帳 App。所有資料預設只保存在使用者裝置，並使用 iOS 26 原生 Liquid Glass 呈現互動介面。

## 功能

- 收入／支出、分類、帳戶、備註與日期管理
- 多幣別記帳：在設定選主要幣別，以交易日期的 Frankfurter 每日參考匯率換算，亦可自訂實際成交匯率；完整保存原幣金額、匯率日期與首次入帳資訊，支援 JPY／USD／KWD 等不同小數精度
- 切換主要幣別會換算既有帳目、期初餘額及定期交易設定，先保留本機備份；換算失敗不變更帳本。v2 備份相容舊版 v1 備份，CSV 亦包含原幣與匯率欄位
- 本月收支、總資產、完整每日支出圖表與分類圓餅圖
- 淨資產時間軸趨勢，提供 1 個月／3 個月／1 年／全部範圍，可點選日期查看累計淨資產；依帳戶初始餘額與歷史收支重算，支援負餘額
- 定期交易資料模型與到期自動入帳
- 明細依月份分組統計，可搜尋、篩選、批次刪除及批次更改分類
- 點選單筆明細可查看詳細資料並編輯，金額鍵盤支援加減乘除
- 自動輪替最近 10 份本機備份
- 免費提供 iCloud 私人雲端備份：每天一個版本，自動更新並保留最近 30 天
- `.mintledger` JSON 完整匯出／還原及 CSV 匯出
- App Intent、Siri 與捷徑直接記帳；`alwaysAllowed` 支援裝置鎖定時執行，App 會即時同步新資料
- 4×2 桌面小工具顯示總資產與近期明細，2×1 鎖定畫面小工具顯示總資產
- Apple Watch 可查看總資產與近期明細，並快速新增收入或支出；透過 WatchConnectivity 與 iPhone 雙向同步
- Apple Watch「設定」可啟用 4 位數密碼鎖、改密碼、關閉或立即鎖定；背景返回時重新驗證，連續輸錯 5 次需等 60 秒。密碼僅存於手錶 Keychain，不會同步或備份
- iOS 26 原生 Liquid Glass，iOS 17–25 使用原生材質退路
- 原創 1024×1024 App Icon

## 開發環境

- Xcode 26+
- iOS 17+
- watchOS 10+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

```bash
brew install xcodegen
xcodegen generate
open MintLedger.xcodeproj
```

首次使用 Apple Developer 帳號編譯時，請在 Certificates, Identifiers & Profiles 為 `com.pandaisland.mintledger` 啟用 App Groups 與 iCloud/CloudKit，建立並指派 `iCloud.com.pandaisland.mintledger` 容器；另外建立 `com.pandaisland.mintledger.watchkitapp` Watch App ID，再重新產生各 target 的 provisioning profile。所有 App 功能均免費，不需要建立 App 內購買項目。

## 下載與側載

每次推送到 `main`，GitHub Actions 都會執行測試並產生 `MintLedger-unsigned.ipa` artifact。下載後可用 AltStore 或 Sideloadly 以自己的 Apple ID 重新簽署並側載。

> 無簽章 IPA 無法直接安裝，iCloud、App 內購買與 Widget App Group 也必須使用包含相應權限的正式 provisioning profile。沒有 Mac 時，可用 GitHub Actions 的 macOS runner 封存、簽署及上傳 App Store Connect。

## 隱私

查詢匯率使用 [Frankfurter](https://frankfurter.dev/) 的免費 API，只傳送幣別代碼及查詢日期，不傳送金額、備註或帳戶資料。匯率為每日參考價，非銀行即時報價；已記錄的匯率不會隨行情自動變動，離線時可輸入自訂匯率。

MintLedger 沒有分析或廣告 SDK。主 App、捷徑與 Widget 只透過 App Group 分享本機 JSON，Apple Watch 與 iPhone 之間則使用 Apple 的 WatchConnectivity 傳輸帳本快照與新增帳目；使用免費雲端備份時，完整備份只會上傳到目前使用者自己的 CloudKit 私人資料庫，並占用該使用者的 iCloud 配額。帳本資料使用 `completeUntilFirstUserAuthentication` 檔案保護，使使用者開機後首次解鎖後，鎖定畫面的捷徑仍能新增交易。

- [產品網站](https://panda-island.github.io/MintLedger-Site/)
- [使用支援](https://panda-island.github.io/MintLedger-Site/support/)
- [隱私權政策](https://panda-island.github.io/MintLedger-Site/privacy/)
- [EULA](https://panda-island.github.io/MintLedger-Site/eula/)

## 授權

MIT
