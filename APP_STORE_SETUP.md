# MintLedger 無 Mac 上架設定

## Apple Developer 後台

> Bundle ID 已由舊版更換為正式識別碼。iOS 會把新版視為另一個 App；安裝前請先用舊版匯出 `.mintledger` 備份，安裝新版後再還原。

1. 在 Certificates, Identifiers & Profiles 建立或確認明確 App ID：`com.pandaisland.mintledger`。
2. 為主 App ID 指派 App Group：`group.com.pandaisland.mintledger`。
3. 建立 iCloud Container：`iCloud.com.pandaisland.mintledger`。
4. 編輯主 App ID，開啟 iCloud，選擇 CloudKit，並指派上述容器。
5. Widget App ID `com.pandaisland.mintledger.widget` 只需指派同一個 App Group。
6. 建立 Apple Distribution 憑證並匯出成 `.p12`。舊第三方帳號的憑證與描述檔不能沿用到你的新 Team。

## App Store Connect

1. 建立 Bundle ID 相同的新 App，價格設定為免費。
2. 所有功能（包含 iCloud 備份）均免費，不需要建立 App 內購買項目。
3. 建立 App Store Connect API Key，角色至少為 Developer，下載只會出現一次的 `.p8` 私鑰，並記下 Key ID 與 Issuer ID。

## 審查與商店頁面網址

- 行銷 URL：`https://panda-island.github.io/MintLedger/`
- 支援 URL：`https://panda-island.github.io/MintLedger/support/`
- 隱私權政策 URL：`https://panda-island.github.io/MintLedger/privacy/`
- EULA 說明頁：`https://panda-island.github.io/MintLedger/eula/`

App Store Connect 的自訂 EULA 欄位只接受純文字，不接受 URL。MintLedger 目前採用 Apple 標準 EULA，因此可不填自訂 EULA；網站的 EULA 頁已連結 Apple 標準條款並提供 App 專屬補充說明。

## GitHub Secrets

在公開專案的 Settings → Secrets and variables → Actions 新增：

- `APPLE_TEAM_ID`：Apple Developer Membership 顯示的 Team ID
- `BUILD_CERTIFICATE_BASE64`：Apple Distribution `.p12` 的 Base64 內容
- `P12_PASSWORD`：匯出 `.p12` 時設定的密碼
- `KEYCHAIN_PASSWORD`：自訂一組只供 CI 暫存鑰匙圈使用的強密碼
- `APP_STORE_CONNECT_KEY_ID`：API Key ID
- `APP_STORE_CONNECT_ISSUER_ID`：Issuer ID
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`：`.p8` 私鑰的 Base64 內容

所有值只能放在 GitHub Secrets，不能提交到專案。設定完成後，到 Actions 手動執行 `Upload to App Store Connect`。成功上傳後，build 會先出現在 TestFlight；完成測試、隱私問卷、App 截圖與商品審查資料後，再於 App Store Connect 送審。

## CloudKit 首次發佈

TestFlight 與 App Store 使用的是 CloudKit Production 環境，不能拿來自動建立 Development schema。沒有 Mac 時，可直接在 CloudKit Console 的 Development 環境建立以下結構：

- `LedgerBackup`：`payload`（Asset）、`modifiedAt`（Date/Time）、`size`（Int64）
- `LedgerBackupIndex`：`entries`（Bytes）、`modifiedAt`（Date/Time）

這個設計使用固定 Record ID，不需要新增查詢索引。確認結構後，在 CloudKit Console 將 schema 部署到 Production，再上傳 TestFlight build；否則正式簽署的 App 仍無法建立第一份備份。
