# 🎨 FluxStudio

> **原生 Apple Silicon (MLX) 生成式影像創作工作站**  
> 基於純 Swift 6 / SwiftUI 與 [mflux-community/mflux v0.23.0](https://github.com/mflux-community/mflux) 打造，無任何外部 HTTP Server 或心跳監聽進程，100% 離線純本機運行。

---

## ✨ 核心特色

1. **純原生 macOS 架構 (SwiftUI + Metal)**：
   - 不使用任何 Webview 或 Python Watchdog，直接以 Swift 原生 `Process` 與非同步串流呼叫底層生成管線。
   - 告別 Localhost 端口佔用與閒置自動關閉問題。
2. **多層級 Undo / Redo 影像重繪畫布 (Inpaint & Edit)**：
   - 支援底圖自由載入、自適應平移與縮放 (Pan & Zoom)。
   - 白色遮罩 (Mask) 動態畫筆、橡皮擦、羽化半徑調節。
   - **多層復原 (Undo / Cmd+Z) 與重做 (Redo / Shift+Cmd+Z)** 歷史堆疊。
   - **吸色筆 (Eyedropper)** 即時取色。
   - 一鍵調用 `mflux-generate-fill` 與 `mflux-generate-flux2-edit` 實現高品質局部修改。
3. **專屬硬體標籤與 Apple M2 (16 GB) 深度調優**：
   - 在介面中清楚標示 `[M2 首選]`、`[進階 32GB+]` 與推薦參數。
   - 預設啟用 4-bit 量化 (`--quantize 4`) 與低記憶體模式 (`--low-ram`)，實測 16GB 機型推論峰值記憶體僅 10.19 GB，杜絕系統凍結。
4. **極速模型下載器 (UI + Shell)**：
   - 整合 Rust `hf_transfer` 多線程引擎，極速跑滿下載頻寬。

---

## 💻 支援模型一覽

| 模型名稱 | 參數量 | 特色 | 推薦機型與標籤 |
| :--- | :--- | :--- | :--- |
| **Z-Image Turbo** | 6B | 9 步秒產、極致寫實 | `⚡ [M2 首選 · 9步極速]` |
| **FLUX.2 Klein-4B** | 4B | 4 步極速出圖、支援修圖與生圖 | `⚡ [M2 首選 · 4步極速]` |
| **FLUX.1 Fill** | 12B | 局部重繪 (Inpaint) 專業核心 | `🎨 [M2 推薦 · 修圖專用]` |
| **FLUX.2 Klein-4B Edit** | 4B | 自然語言全圖風格與物件編輯 | `🎨 [M2 推薦 · 4步修圖]` |
| **Lens** | 3.8B | 微軟雙流 MMDiT，輕巧省記憶體 | `⚡ [M2 推薦 · 輕量雙流]` |
| **Boogu Image** | 10B | 中英雙語文字排版與文字渲染 | `🔤 [M2 推薦 · 雙語文字]` |
| **FLUX.3 Klein** | 5.6B+4B | 多圖參考引導、邊界框佈局 | `💎 [進階 · 建議 32GB+]` |
| **Krea 2** | 12B | 藝術風格探索模型 | `💎 [進階 · 建議 32GB+]` |
| **FLUX.1 Schnell / Dev** | 12B | 官方經典開源基石模型 | `💎 [進階 · 建議 32~64GB]` |
| **Qwen Image 2.1** | 7.1B+8B | 8 步 Turbo / 多圖編輯支援 | `🚀 [高階 · 建議 32GB+]` |
| **Qwen Image** | 20B | 20B 龐大模型、世界常識理解強 | `🔥 [旗艦 · 建議 64~128GB]` |
| **Ideogram 4** | 9B | 標籤佈局與藝術字體渲染 | `💎 [進階 · 建議 32GB+]` |

---

## 🛠️ 建置與執行

### 一鍵建置 macOS 應用程式
本專案已配置快取隔離機制（`--scratch-path /tmp/FluxStudio-build`），即使位於 iCloud Drive 亦不會產生雲端同步衝突：

```bash
cd FluxStudio
./build_app.sh
```
編譯完成後將自動安裝至 `/Applications/FluxStudio.app`。

### 高速模型預載
```bash
./scripts/download_models.sh
```

---

## 📜 開源許可證
MIT License
