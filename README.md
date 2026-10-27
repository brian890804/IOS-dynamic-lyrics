# 靈動歌詞 (Dynamic Lyrics) 完整專案指南

本專案實作了以 **ActivityKit (Live Activity)** + **背景保活 (Background Audio)** 驅動的 iOS 車機 CarPlay / 動態島高頻即時歌詞系統，解決傳統 WidgetKit 小工具被 iOS 限制每小時刷新次數而無法作為即時歌詞的限制。

---

## 專案目錄結構

```text
IOS-dynamic-lyrics/
├── ios-app/                                   # 原生 iOS Swift 專案代碼
│   ├── DynamicLyrics/
│   │   ├── DynamicLyricsApp.swift             # App 主介面與定時進度控制器
│   │   ├── LyricAttributes.swift              # ActivityKit 狀態結構定義 (Attributes & ContentState)
│   │   ├── LrcParser.swift                    # LRC 時間戳正則解析與進度匹配演算法
│   │   ├── LyricService.swift                 # Lrclib API 歌詞拉取服務 (免註冊免費)
│   │   ├── LiveActivityManager.swift          # Live Activity 啟動、更新與結束生命週期管理
│   │   ├── BackgroundAudioManager.swift       # Audio Session (MixWithOthers) 靜音保活機制
│   │   └── Info.plist                         # 包含 NSSupportsLiveActivities 與 UIBackgroundModes
│   └── LyricWidget/
│       └── LyricWidget.swift                  # CarPlay 儀表板小工具 & iPhone 動態島 Widget 視圖
│
├── simulator-web/                             # 電腦本機即時測試模擬器 (免 Mac/免實機)
│   ├── server.js                              # Node.js 伺服器 (串接 Lrclib API)
│   ├── index.html                             # 視覺化 CarPlay / 動態島 / 時間軸即時模擬面板
│   └── package.json
└── README.md
```

---

## 〇、裝到 iPhone 並在 CarPlay 顯示 Spotify 歌詞（不需要 Mac）

### 需求
- iPhone **iOS 18 以上**；要在 **CarPlay** 上看到歌詞需 **iOS 26 以上**（iOS 26 起 CarPlay 才會顯示 Live Activity）
- 一個 Spotify 帳號（Spotify Developer 的開發模式 App 可能要求擁有者為 Premium，以 Spotify 最新規定為準）

### 步驟 1：申請 Spotify Client ID（免費、約 2 分鐘）
iOS 不允許一個 App 讀取另一個 App 正在播什麼，必須透過 Spotify 官方 Web API，而 API 要求每個 App 註冊。
1. 到 <https://developer.spotify.com/dashboard> 登入 → **Create app**
2. **Redirect URIs** 填入：`dynamiclyrics://spotify-callback`
3. **Which API/SDKs are you planning to use** 勾選 **Web API**
4. 建立後複製 **Client ID**（不需要 Client Secret）
5. 本專案已在 `project.yml` / `Info.plist` 的 `SpotifyClientID` 內建一組 Client ID；換成自己的就改這兩處，或在 App 內直接貼上覆寫

### 步驟 2：用 GitHub Actions 打包 IPA
推送到 `main` 或在 Actions 頁手動執行 **Build iOS IPA**，完成後下載 `DynamicLyrics-Unsigned-IPA`。

### 步驟 3：側載安裝
IPA 未簽名，用 [Sideloadly](https://sideloadly.io/) 或 AltStore 搭配你的 Apple ID 安裝（免費 Apple ID 簽的 App **7 天後需重簽**）。

### 步驟 4：第一次使用
1. 打開「靈動歌詞」→（Client ID 已預先帶入）**登入 Spotify** 並同意授權
2. 看到「同步中」後即可切到 Spotify 播歌；鎖定畫面 / 動態島 / CarPlay 會顯示即時歌詞
3. ⚠️ 上車前請先**在前景打開一次 App**：iOS 只允許 App 在前景建立 Live Activity，建立後背景換歌只會更新內容
4. 不要從 App 切換器滑掉 App，否則背景同步會停止

> 歌詞顯示在 CarPlay 的儀表板 / Live Activity 區域，不會疊在 Spotify 自己的 CarPlay 畫面上（iOS 不允許第三方 App 覆蓋其他 App 的畫面）。

---

## 一、在電腦上 Local 環境測試（免 Mac / 免 iOS 實機）

我們已經為你打造了一套**本機互動式模擬器**，在 Linux / Windows / Mac 上都可以直接執行並即時測試歌詞抓取與 CarPlay 渲染效果：

### 1. 啟動模擬器伺服器
在終端機中執行：
```bash
cd simulator-web
node server.js
```

### 2. 開啟瀏覽器測試
開啟瀏覽器連線至：
👉 **`http://localhost:3000`**

### 3. 可在模擬器上驗證的功能
1. **即時歌詞抓取**：輸入歌名與歌手（預設周杰倫《夜曲》，亦可切換《晴天》或 Ed Sheeran《Shape of You》），點擊「抓取 LRC 歌詞」，即時自 Lrclib 抓取時間軸。
2. **CarPlay 儀表板小工具動態卡片**：比照 iOS CarPlay 儀表板的版面比例，當前歌詞高亮放大、下一句歌詞半透明預覽。
3. **iPhone 動態島即時緊湊視圖**：即時預覽 Compact 狀態下的動態島滾動文字。
4. **進度條拖拉 (Seek) 與快轉**：任意拖拉進度，驗證秒數匹配演算法是否無縫切換到對應歌詞行。
5. **事件日誌**：觀察 `ActivityKit Update` 與 `BackgroundAudio` 的觸發頻率。

---

## 二、在 Mac Xcode 模擬器 / iPhone 實機上測試

當你切換到 macOS 開發環境時，按照以下步驟建立專案：

### 步驟 1：建立 Xcode 專案
1. 開啟 Xcode，選擇 **Create New Project** -> **iOS App**（語言選 Swift，Interface 選 SwiftUI）。
2. 專案名稱設為 `DynamicLyrics`。

### 步驟 2：新增 Widget Extension (勾選 Live Activity)
1. 在 Xcode 點選 **File** -> **New** -> **Target...**。
2. 選擇 **Widget Extension**。
3. 務必勾選 **Include Live Activity**。
4. 命名為 `LyricWidget`。

### 步驟 3：導入代碼檔案
- 將 `ios-app/DynamicLyrics/` 中的 Swift 檔放入主 App Target：
  - [LyricAttributes.swift](file:///home/wein/workspace/IOS-dynamic-lyrics/ios-app/DynamicLyrics/LyricAttributes.swift)（**注意：此檔案需勾選同時屬於 App Target 與 Widget Target**）
  - [LrcParser.swift](file:///home/wein/workspace/IOS-dynamic-lyrics/ios-app/DynamicLyrics/LrcParser.swift)
  - [LyricService.swift](file:///home/wein/workspace/IOS-dynamic-lyrics/ios-app/DynamicLyrics/LyricService.swift)
  - [LiveActivityManager.swift](file:///home/wein/workspace/IOS-dynamic-lyrics/ios-app/DynamicLyrics/LiveActivityManager.swift)
  - [BackgroundAudioManager.swift](file:///home/wein/workspace/IOS-dynamic-lyrics/ios-app/DynamicLyrics/BackgroundAudioManager.swift)
  - [DynamicLyricsApp.swift](file:///home/wein/workspace/IOS-dynamic-lyrics/ios-app/DynamicLyrics/DynamicLyricsApp.swift)
- 將 `ios-app/LyricWidget/LyricWidget.swift` 替換 Widget Extension 目錄內的預設 Widget 程式碼。

### 步驟 4：設定背景保活權限 (Background Modes)
1. 點選主 Target -> **Signing & Capabilities** -> 點選 **+ Capability**。
2. 選擇 **Background Modes**。
3. 勾選 **Audio, AirPlay, and Picture in Picture**。
4. 在主 App 的 `Info.plist` 確認包含：
   - `NSSupportsLiveActivities` = `YES`
   - `NSSupportsLiveActivitiesFrequentUpdates` = `YES`

### 步驟 5：在 Xcode 模擬器中測試 CarPlay
1. 執行專案於 iPhone 模擬器（例如 iPhone 15 Pro，iOS 17+）。
2. 在模擬器頂部選單點選 **I/O** -> **External Displays** -> 選擇 **CarPlay**。
3. 模擬器會彈出第二個 CarPlay 車機視窗。
4. 在手機 App 點擊「開始播放並啟動靈動歌詞」，切到鎖定畫面或觀察 CarPlay 儀表板小工具頁面，即可看到即時歌詞滾動！