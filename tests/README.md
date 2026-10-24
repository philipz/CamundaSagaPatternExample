# 反例測試套件（Node.js）

把 [specs/quint/REPORT.md](../specs/quint/REPORT.md) 與 [specs/lean/REPORT.md](../specs/lean/REPORT.md)
裡的**每一個反例**變成可執行的測試。

- **語言**：JavaScript（ESM），測試框架用 Node 內建 `node:test` + `node:assert`，不需要額外安裝測試框架。
- **不改動任何既有程式碼**：worker 的原始檔透過 `node:vm` 沙箱載入（見下方說明），BPMN 用官方 moddle 解析。
- **目前的 bug 標成 `todo`**：`npm test` 不會因此失敗，但報告會列出每一條已知違規。修正後把 `todo` 拿掉，測試就變成回歸測試。

## 執行

```sh
npm install          # 第一次（若 ~/.npm 有權限問題：npm install --cache .npm）
npm test             # 29 個測試：29 pass、0 todo、0 fail
```

目前結果：

```
ℹ tests 29
ℹ pass 29
ℹ fail 0
ℹ todo 0
```

單一檔案：`node --test tests/ce5-flight-ref.test.mjs`

## 反例對照表

| 反例 | 規則 | 測試檔案 | 測試數 | 目前 |
|---|---|---|---|---|
| **CE-1** 取消後仍以「確認」結束 | BR1 | [ce1-cancel-path.test.mjs](ce1-cancel-path.test.mjs) | 2 | **pass**（已修復） |
| **CE-2** 重送導致重複訂位 | BR4/BR5/BR2/BR7 | [ce2-idempotency.test.mjs](ce2-idempotency.test.mjs) | 3（F/T/H 各一） | **pass**（已修復） |
| **CE-3** 訂位失敗永遠卡住 | BR8 | [ce3-book-failure.test.mjs](ce3-book-failure.test.mjs) | 4（3 worker + 1 BPMN） | **pass**（已修復） |
| **CE-4** 取消失敗補償卡住 | BR8 | [ce4-cancel-failure.test.mjs](ce4-cancel-failure.test.mjs) | 3 | **pass**（已修復） |
| **CE-5** Flight 回寫 ID ≠ 實際訂位 | BR5/BR6/BR2/BR7 | [ce5-flight-ref.test.mjs](ce5-flight-ref.test.mjs) | 1 修復 + 2 對照 | **pass**（已修復） |
| **CE-6** join 衝突導致重複訂位 | BR4 | [ce6-join-async.test.mjs](ce6-join-async.test.mjs) | 2 | **pass**（已修復） |
| **R1** worker 共用預設 `workerId` | — | [r1-worker-id.test.mjs](r1-worker-id.test.mjs) | 1 | **pass**（已修復） |
| **ENV-1** `type: module` 與 `require` 衝突 | — | [env1-module-format.test.mjs](env1-module-format.test.mjs) | 1 | **pass**（已修復） |
| 基準（happy path、BR3、補償接線） | — | [baseline.test.mjs](baseline.test.mjs) | 6 | **pass** |
| 函式庫契約（F7/F8、`complete()` 吞錯） | — | [library-contract.test.mjs](library-contract.test.mjs) | 4 | **pass** |

每一條 `todo` 的訊息都寫明「哪一行、什麼問題」，例如：

```
✖ CE-5 (BR5/BR6): BookFlight must report the ID it actually booked
  # CE-5: FlightBooking.js:21 sets FlightBookingID to a second create_UUID()
  FlightBookingID is 4bf241be-… but the booked (logged) flight is a0054287-…
```

## 兩個測試層

### 1. Worker（`helpers/worker-sandbox.mjs`）

worker 檔有兩個問題讓它不能直接 import：

1. 一載入就 `new Client(config)` 並自動 poll `camunda:8080`；
2. `BookingSystemWorkers/package.json` 是 `"type": "module"`，但 worker 用 `require`（= ENV-1）。

所以測試把**原始檔原文**放進 `node:vm` 沙箱執行，注入假的 `require`：

- 假 `Client`：只記錄 `subscribe(topic, handler)`，不連網
- 假 `Variables`：記錄 handler 要回寫給流程的變數
- `setTimeout`：立即執行（跳過 Flight 的 2 秒 sleep）
- `Math.random` / `Date`：用固定種子，UUID 可重現

這樣測到的是**生產環境那份程式碼**，而且沒有改它一行。

故障注入：`loadWorker(file, { failOnSet: true })` 讓 `Variables#set` 拋例外，等同 handler 在呼叫供應商時失敗（CE-3/CE-4 沒有真實的供應商可以失敗）。

### 2. BPMN（`helpers/bpmn.mjs`）

用官方 `bpmn-moddle` + `camunda-bpmn-moddle` 解析 `Models/BookHolidaySagaPatternV3.bpmn`，提供
`sequenceFlow` 圖上的可達性查詢、`camunda:*` 屬性、補償 boundary event／association、XOR 條件等。

例：CE-1 的斷言是「從補償 throw event 出發，**不經過任何 user task** 也能到達 end event」，
CE-6 的斷言是「Book Flight／Train 必須有 `camunda:asyncAfter`」。

## 為什麼 CE-3/CE-4 的 worker 測試是動態注入，而不是靜態搜尋

handler 目前沒有真正的供應商呼叫，所以「失敗」只能靠注入。斷言的是規則本身：
**handler 內部的任何例外都必須透過 `handleFailure`／`handleBpmnError` 回報，不能讓它逃到
client**。這條規則在接上真實 API 之後同樣成立（client 只會 `emit("handler:error")`，
見 `library-contract.test.mjs`），所以不會因為之後補上真實 API 而失效。

## 前提與限制

- 這些測試**測的是程式碼與 BPMN 模型**，與 Lean 模型裡的定理互相獨立；Lean 證明的是模型，
  這裡驗證的是實作是否違反同一組規則。
- **CE-6 的時序沒有真的重現**：測試斷言的是「join 前的 task 有 `asyncAfter`」這個結構性前提，
  沒有起 Camunda 去真的撞出 `OptimisticLockingException`（依 Q2 的決定，這次不做端對端整合測試）。
- 依 Q2 的決定，**沒有**寫 docker-compose 端對端測試，也**沒有**依 Q9 的表加入 OBS-1（user task timer）。
- `ENV-1` 會 spawn 真的 `node` 執行 worker 檔（4 秒 timeout 後殺掉），是本套件唯一啟動子行程的測試。
- 所有測試都只讀原始碼與 BPMN，不會修改 `Models/` 或 `BookingSystemWorkers/`。
