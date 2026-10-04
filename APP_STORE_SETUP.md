# MintLedger 無 Mac 上架設定

## Apple Developer 後台

1. 在 Certificates, Identifiers & Profiles 建立或確認明確 App ID：`app.mulberry1261.emerald6299`。
2. 為主 App ID 指派 App Group：`group.063105cc445c1ae9.1`。
3. 建立 iCloud Container：`iCloud.app.mulberry1261.emerald6299`。
4. 編輯主 App ID，開啟 iCloud，選擇 CloudKit，並指派上述容器。
5. Widget App ID `app.mulberry1261.emerald6299.Widget` 只需指派同一個 App Group。
6. 建立 Apple Distribution 憑證並匯出成 `.p12`。舊第三方帳號的憑證與描述檔不能沿用到你的新 Team。

## App Store Connect

1. 接受「付費 App 協議」，填妥銀行與稅務資料。
2. 建立 Bundle ID 相同的新 App。
3. 在「營利／App 內購買項目」新增「非消耗型」商品：
   - 參考名稱：`iCloud 雲端備份永久版`
   - 產品 ID：`app.mulberry1261.emerald6299.cloudbackup.lifetime`
   - 台灣價格：`NT$60`
   - 顯示名稱：`iCloud 雲端備份永久版`
   - 說明：`一次購買，永久開啟自動 iCloud 備份與還原功能。`
4. 建立 App Store Connect API Key，角色至少為 Developer，下載只會出現一次的 `.p8` 私鑰，並記下 Key ID 與 Issuer ID。

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

先用開發／TestFlight 版本成功建立一份備份，CloudKit 會在 Development 環境建立 `LedgerBackup` 與 `LedgerBackupIndex` 結構。確認欄位後，在 CloudKit Console 將 schema 部署到 Production，正式 App 才能寫入備份。
