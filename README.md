# WanderSaga - BPMN Saga Pattern Example

> 基於 **`@bpmnkit/engine`** 與 **Cloudflare Workers** 的微服務 Saga 補償模式現代化無伺服器邊緣實現。

🌐 **線上 PoC 示範**：**[https://wandersaga.philipz.workers.dev/](https://wandersaga.philipz.workers.dev/)**

---

## 📖 專案簡介 (Overview)

本專案展示如何透過 **BPMN 2.0** 規範與 **Saga 補償模式 (Saga Pattern)** 來編排非同步分散式微服務（機票預訂、火車劃位、飯店保留）。

專案已從早期依賴龐大 Java / Spring Boot Camunda 7 伺服器與 Docker 的架構，全面遷移至以 **`@bpmnkit/engine`** 為核心的**純 JavaScript/TypeScript 現代邊緣架構**。在**不依賴任何外部持久性資料庫**的前提下，直接於 Cloudflare 邊緣節點上秒級執行流程流轉、人工決策核對與全自動逆向退訂補償。

![Overview](./img/Overview.png)

---

## 🏗️ 架構演進與技術棧 (Architecture & Tech Stack)

| 維度 | 早期架構 (Camunda 7) | 現行邊緣架構 (WanderSaga) |
| :--- | :--- | :--- |
| **流程執行引擎** | Camunda Platform Run (Java / Spring Boot JAR) | **`@bpmnkit/engine`**（純 TS、Zero-dependency、邊緣原生） |
| **部署與運行環境** | 本地 Docker 容器 (`camunda-bpm-platform:run-latest`) | **Cloudflare Workers** (全球 V8 Isolate 邊緣節點) |
| **靜態資源託管** | Spring Boot 靜態目錄 | **Cloudflare Workers Static Assets** (全球 CDN 快取) |
| **微服務通訊** | HTTP REST `fetchAndLock` 長輪詢 (高延遲/頻寬開銷) | **同駐邊緣微服務 + WebSocket Edge Session** (零輪詢開銷) |
| **前端與即時進度** | Camunda Cockpit / Tasklist | **客製化現代旅遊 Web 儀表板** (Glassmorphism + 即時日誌) |
| **可觀測性** | 日誌檔案與資料庫記錄 | **Cloudflare Workers Observability** (100% 邊緣請求追蹤) |

---

## 🔄 Saga 補償模式與 BPMN 流程 (Workflow Design)

流程定義於 [`Models/BookHolidaySagaPatternV3.bpmn`](./Models/BookHolidaySagaPatternV3.bpmn)：

![Book a holiday saga](./Models/BookHolidaySagaPatternV2.png)

### 執行生命週期解析：
1. **平行預訂階段 (Parallel Booking)**：
   - 流程啟動後，依據輸入參數同時向三個微服務派發工作：
     - 🛫 **BookFlight** (`camunda:topic="BookFlight"`)
     - 🚆 **BookTrain** (`camunda:topic="BookTrain"`)
     - 🏨 **BookHotel** (`camunda:topic="BookHotel"`)
   - 每個完成的任務皆由 BPMN 引擎自動關聯其對應的補償邊界事件 (`bpmn:CompensateEventDefinition`)。
2. **人工核對決策 (User Task)**：
   - 三個微服務全數保留配額後，流程停駐於 `Activity_034u6ma`（Check Booking Details）。
   - 前端跳出浮層對話框，供使用者進行最終確認。
3. **路徑分岐 (Exclusive Gateway)**：
   - **確認出發 (`confirm = true`)**：走向 Happy Path，抵達 `Trip completed` 結束事件。
   - **取消行程 (`confirm = false`)**：流程拋出 `Cancel Bookings` 中間補償事件 (`bpmn:IntermediateThrowEvent`)，引擎**自動依已完成項目的逆序**呼叫補償處理器：
     1. 🔄 `CancelHotelBooking`（飯店取消退房）
     2. 🔄 `CancelFlightBooking`（機票全額退費）
     3. 🔄 `CancelTrainBooking`（火車退票劃位撤銷）
   - 最終安全抵達 `Trip Canceled` 結束事件。

---

## 🚀 快速開始 (Quick Start)

### 1. 環境需求
- Node.js >= 20
- npm >= 9

### 2. 安裝依賴
```sh
npm install
```

### 3. 本地啟動 Web 旅遊訂票互動系統
```sh
npm start
# 預設啟動於 http://localhost:3000
```
若 Port 3000 已被其他應用佔用，可自由指定其他 Port：
```sh
PORT=8080 npm start
# 或
npm start -- --port 8080
```

### 4. 本地 CLI 模擬執行 (不用開瀏覽器)
```sh
# 測試 1：正向出發 (Happy Path)
npm run simulate

# 測試 2：取消行程並觸發 Saga 逆向補償
npm run simulate:cancel

# 測試 3：進階自訂參數 (不訂機票並取消)
node run-saga.mjs --cancel --no-flight
```

---

## 🧪 自動化測試套件 (Automated Tests)

本專案將 [specs/quint/REPORT.md](specs/quint/REPORT.md) 與 [specs/lean/REPORT.md](specs/lean/REPORT.md) 的形式化反例全部轉化為可自動執行的整合測試：

```sh
npm test
```

目前共包含 **32 個測試，全數通過 (32 pass, 0 fail, 0 todo)**：
- **CE-1 ~ CE-6**：補償路徑不可達、重送冪等性、失敗中斷、ID 一致性、Join 異步衝突反例驗證。
- **R1 / ENV-1**：Worker ID 隔離與 ESM 模組格式契約。
- **BPMNKit Saga 本地模擬測試**：驗證真實流程引擎在 Happy Path、全額退訂補償與部分預訂補償下的生命週期。

---

## ☁️ 部署至 Cloudflare Workers

本專案配置檔為 [`wrangler.jsonc`](./wrangler.jsonc)，支援一鍵發布至 Cloudflare 邊緣網路：

```sh
# 部署至 Cloudflare Workers
npm run deploy

# 本地模擬邊緣執行環境
npm run worker:dev

# 即時追蹤遠端線上日誌
npx wrangler tail
```

---

## 📁 目錄結構 (Repository Structure)

```text
├── Models/                     # BPMN 2.0 流程定義檔 (BookHolidaySagaPatternV3.bpmn)
├── public/                     # 前端靜態單頁應用 (HTML5 / Vanilla CSS / JS)
│   ├── index.html              # 旅遊訂票與即時儀表板頁面
│   ├── style.css               # 深色太空風格與 Glassmorphism 樣式
│   └── app.js                  # WebSocket/SSE 串流與 User Task 控制器
├── src/                        # Cloudflare Worker 進入點
│   ├── index.js                # Hono 邊緣路由、WebSocket Session 與微服務註冊
│   ├── bpmn.js                 # 邊緣原生 BPMN 解析與轉譯適配器
│   └── model.js                # BPMN XML 靜態模組
├── tests/                      # 自動化反例與 Saga 整合測試 (32 tests)
│   ├── bpmnkit-saga.test.mjs   # @bpmnkit/engine 流程整合測試
│   └── helpers/                # BPMN 解析與沙箱測試輔助工具
├── run-saga.mjs                # 本地 CLI 互動模擬器
├── server.mjs                  # 本地 Node.js 開發伺服器
├── wrangler.jsonc              # Cloudflare Workers 與 Observability 配置
└── package.json                # 專案相依性與指令腳本
```
