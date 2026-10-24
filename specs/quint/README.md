# Book Holiday Saga — Quint 模型

`BookHolidaySagaPatternV3.bpmn` 加上 3 個 Node.js external-task worker 的可執行規格。
分析結果請見 [REPORT.md](REPORT.md)。

## 檔案

| 檔案 | 內容 |
|---|---|
| [bookHoliday.qnt](bookHoliday.qnt) | 主模型：型別、狀態、pure functions、guarded actions、`step`、業務規則 BR1–BR8、witnesses |
| [bookHolidayInstances.qnt](bookHolidayInstances.qnt) | 6 個可執行 instance：`ideal`／`asIs`／`redelivery`／`bookFailure`／`cancelFailure`／`allFaults` |
| [bookHoliday_test.qnt](bookHoliday_test.qnt) | 確定性情境：happy path，以及每個反例 CE-1…CE-5 的最小重現 |
| [run_all.sh](run_all.sh) | 重跑「instance × 規則」驗證矩陣，並把反例匯出到 `traces/` |
| [summarize_trace.py](summarize_trace.py) | 把 ITF trace 轉成精簡的 Markdown 步驟表 |
| `traces/*.md`、`traces/*.itf.json` | 模擬器找到的反例（固定 seed，可重現） |

## 如何重跑

```sh
cd specs/quint
quint typecheck bookHoliday.qnt
quint test bookHoliday_test.qnt --main=bookHoliday_test        # 7 個情境
quint test bookHoliday_test.qnt --main=bookHoliday_asIs_test   # 1 個情境（CE-5）
./run_all.sh            # 預設 10000 samples × 30 steps，seed 0x5a6a；約 2 分鐘
# 單一檢查範例：
quint run bookHolidayInstances.qnt --main=ideal --invariant=BR1_confirmedEndIsFullyBooked --max-steps=30
```

全程只用 `quint run`（隨機抽樣模擬）。**沒有**跑 `quint verify`（窮舉式模型檢查）。

## 涵蓋範圍

- **流程**：V3 的 parallel split 與兩個 XOR（是否需要 flight／train）、parallel join、Book Hotel、user task「Check Booking Details」、確認或取消的 XOR、補償 throw event，以及補償後連回 user task 的 loop（`Flow_0u9r45z`）、唯一的 end event。
- **Camunda 7.21 語意**：補償訂閱在活動完成時建立、觸發一次即移除（再丟一次是 no-op）；throw event 會等所有 handler 完成；handler 之間是並行的（模型允許任意順序）；external-task 變數會寫進 process-instance scope。
- **Worker**：fetchAndLock → 對供應商的副作用 → `complete` 拆成三個原子步驟；lock 過期或 crash 時 task 重新變成可 fetch；handler 拋例外時不呼叫 `handleFailure`，所以會無限重試、不產生 incident。
- **假設開關（`const`）**：`ALLOW_REDELIVERY`、`ALLOW_BOOK_FAILURE`、`ALLOW_CANCEL_FAILURE`、`FLIGHT_REF_BUG`。
- **供應商 ledger**：stub worker 接上真實 API 後的抽象，記錄 `active`／`everBooked`／永久故障。
- **規則**：BR1–BR8（定義見 REPORT.md §3）。BR8（liveness）以「卡住且仍佔住訂位」這個可達狀態來表達。

## 未涵蓋的部分（不要過度信任這份模型）

- **只有 1 個 process instance**：不涉及跨 instance 的競爭（instance 之間沒有共享的業務狀態）。
- **沒有時間**：user task 沒有 timeout、lock 的 50 秒、2 秒 sleep 都不建模。「使用者一直不回應，訂位就被佔住」只在報告中文字說明。
- **zombie handler**：lock 過期後，原 handler 可能稍晚仍呼叫 `complete`，而三個 worker 共用 `workerId`，這次呼叫可能成功。模型把它和 crash 合併處理，只保留「副作用被執行了兩次」這個結果。
- **asyncBefore 的交易邊界**：不建模 job、DB rollback，也不建模 engine 自身的 crash。
- **透過 REST 啟動但沒帶 `flightNeeded`／`trainTicketNeeded` 的情況**：表達式會出錯，但交易會 rollback，不產生業務狀態。
- **其他版本**：V1、V2、BookHoliday.bpmn 都不在範圍內。
- **規則限制**：BR8 只抓「供應商永久故障」；暫時失敗只會延遲，不算違規。
- **覆蓋率**：sampled 模擬不等於窮舉。目前矩陣中的 ✓ 代表在 10000 條、深度 30 的 trace 中沒找到反例，不是證明。

## 何時更新

[BookHolidaySagaPatternV3.bpmn](../../Models/BookHolidaySagaPatternV3.bpmn) 或任何 worker 改動時，**先改模型、重跑 `run_all.sh` 和 `quint test`，再改程式**。
模型是 ground truth，不要為了配合有問題的程式碼去改模型。要依這份規格實作修正時，可以用 `quint-execute-spec`。

## Source-file correspondence

```
bookHoliday.qnt  Engine / phase / compSubs / userCanceled
                 ↔ Models/BookHolidaySagaPatternV3.bpmn
                   (StartEvent_1 listener, Gateway_09mc27b/1lmf9zu/1vonxjj/0xpf3bu/1qt5pcl/1hfufm4,
                    Activity_034u6ma, Gateway_1vtaf28, Event_1y70am0, Flow_0u9r45z, Event_07xntzc,
                    boundary events Event_0g83clx/Event_119ysv4/Event_18hendr)
bookHoliday.qnt  Book(Flight)/Cancel(Flight), FLIGHT_REF_BUG ↔ BookingSystemWorkers/FlightBooking.js
bookHoliday.qnt  Book(Train)/Cancel(Train)                   ↔ BookingSystemWorkers/TrainBooking.js
bookHoliday.qnt  Book(Hotel)/Cancel(Hotel)                   ↔ BookingSystemWorkers/BookHotel.js
bookHoliday.qnt  tasks / fetchAndLock / handlerFails / lockExpires
                 ↔ camunda-external-task-client-js 2.3.1 lib/Client.js (poll, executeTask)
bookHoliday.qnt  Supplier                                    ↔ （抽象；目前程式碼不存在）
```

## 建模決策紀錄（訪談結論）

| # | 決策 |
|---|---|
| Q1 | 只建模 V3 加上 3 個 worker |
| Q2 | 加入抽象的供應商 ledger |
| Q3 | 故障：重送 + 訂位失敗 + 取消失敗，各用一個開關 |
| Q4 | BR1–BR8 全部納入 |
| Q5 | 取消後再確認、走到唯一的 end event，**算違規** |
| Q6 | BR8 用可達的卡死狀態表達 |
| Q7 | 用 plain Quint（共享狀態），不用 Choreo |
| Q8 | 1 個 instance |
| Q9 | Flight 的雙 UUID 當成真實 bug 建模，以開關控制 |
| Q10 | 產出位置：`specs/quint/`，報告用繁體中文 |
| Q11 | 型別草圖照提案（`Supplier` 欄位合併成一個 record，內容不變） |
| Q12 | 失敗分暫時與永久；永久故障導致卡住且佔住訂位，就違反 BR8 |
| Q13 | BR5 只在 `Review` 時檢查 |
| Q14 | BR2 在補償完成時檢查（`Review` 或 `Ended`） |
