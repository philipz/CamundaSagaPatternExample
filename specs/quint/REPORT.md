# Book Holiday Saga：Quint 形式化分析報告

- **分析對象**：[BookHolidaySagaPatternV3.bpmn](../../Models/BookHolidaySagaPatternV3.bpmn)（部署在 Camunda 7.21），以及 [FlightBooking.js](../../BookingSystemWorkers/FlightBooking.js)、[TrainBooking.js](../../BookingSystemWorkers/TrainBooking.js)、[BookHotel.js](../../BookingSystemWorkers/BookHotel.js)
- **模型**：[bookHoliday.qnt](bookHoliday.qnt)；instance 定義在 [bookHolidayInstances.qnt](bookHolidayInstances.qnt)；最小重現在 [bookHoliday_test.qnt](bookHoliday_test.qnt)
- **方法**：`quint run` 隨機抽樣模擬，每格 10000 條 trace、深度 30、seed `0x5a6a`；另以 `quint test` 跑確定性重現。沒有使用 `quint verify`。
- **日期**：2026-10-24

---

## 1. 摘要

找到 **5 類反例**，違反 8 條業務規則中的 **7 條**。

| 反例 | 違反規則 | 需要的假設 | 嚴重度 | 一句話說明 |
|---|---|---|---|---|
| **CE-1** 取消後仍以「確認」結束 | BR1 | **不需要任何故障**，純 BPMN 設計 | 高 | 補償完成後回到同一張表單，唯一的出口是確認，流程因此「成功結束」，實際上什麼都沒訂到 |
| **CE-2** 重送導致重複訂位 | BR4、BR5、BR2、BR7 | worker 在 `complete` 前 crash 或 lock 過期 | 高 | handler 沒有冪等性，同一 task 被執行兩次，訂了兩張票，流程只知道第二張，第一張永遠不會被取消 |
| **CE-3** 訂位失敗，流程永遠卡住 | BR8 | 某個供應商永久拒絕訂位 | 高 | handler 拋例外後沒有 `handleFailure`，task 被無限重試；已訂好的其他項目被佔住，使用者也到不了取消的步驟 |
| **CE-4** 取消失敗，補償永遠卡住 | BR8 | 某個供應商永久拒絕取消 | 中 | 補償 throw event 會無限期等待，訂位沒有釋放，表單也不會再出現 |
| **CE-5** Flight 回寫的 ID 和實際訂位不同 | BR5、BR6、BR2、BR7 | **不需要任何故障**，照程式碼原樣 | 高 | [FlightBooking.js:19-21](../../BookingSystemWorkers/FlightBooking.js#L19-L21) 產生了兩個 UUID，取消時用的那個從來沒有被訂過 |

**BR3（不訂未被要求的項目）在所有 instance 都成立**：兩個 XOR 條件和 parallel join 的組合是正確的。

---

## 2. 系統模型與假設

| 項目 | 建模方式 |
|---|---|
| 參與者 | 1 個 process instance（engine 的 token）、3 個 worker（各訂閱 2 個 topic）、使用者，以及抽象的供應商 ledger |
| 溝通 | 共享狀態：engine 的 external-task 表，由 worker 以 pull 方式取用（`fetchAndLock`） |
| 原子步驟 | `fetchAndLock` → 對供應商的副作用 → `complete`（engine 寫入變數並推進 token），刻意拆成三步，以暴露 at-least-once 的問題 |
| 故障 | 每種故障各一個 `const` 開關：`ALLOW_REDELIVERY`、`ALLOW_BOOK_FAILURE`、`ALLOW_CANCEL_FAILURE`；程式碼 bug 另有 `FLIGHT_REF_BUG` |
| 時間 | 不建模。BR8 以「永久卡住」的可達狀態表達 |

建模前查證過的 Camunda 語意：

- **F3**：`complete()` 送出的變數由 `execution.setVariables` 往上傳到 process-instance scope。所以 Book Hotel 雖然沒有 `HotelBookingID` 的 output mapping，`CancelHotelBooking` 的 `${HotelBookingID}` 仍然解析得到，**這不是 bug**。（[ExternalTaskEntity.java @7.21.0](https://raw.githubusercontent.com/camunda/camunda-bpm-platform/7.21.0/engine/src/main/java/org/camunda/bpm/engine/impl/persistence/entity/ExternalTaskEntity.java)）
- **F4**：補償訂閱在活動完成時才建立，觸發後即移除；throw event 會等所有 handler 完成才離開；handler 以並行 execution 執行。（[Camunda 7.21 Compensation Events](https://docs.camunda.org/manual/7.21/reference/bpmn20/events/cancel-and-compensation-events/)）
- **F7**：JS client 在 handler 拋例外時只 `emit("handler:error")`，不呼叫 `handleFailure`。task 會鎖到 `lockDuration`（50 秒）過期，然後再次被 fetch；`retries` 從不遞減，所以不會產生 incident。（[Client.js 2.3.1 `executeTask`](https://unpkg.com/camunda-external-task-client-js@2.3.1/lib/Client.js)）

---

## 3. 業務規則定義

| ID | 規則 | Quint 定義 | 何時檢查 |
|---|---|---|---|
| BR1 | 流程以「確認」結束時，每個需要的項目都是 Confirmed，且供應商端真的有這筆訂位 | `BR1_confirmedEndIsFullyBooked` | `Ended` |
| BR2 | 使用者取消、補償完成後，供應商端沒有任何有效訂位 | `BR2_noOrphanAfterCompensation` | `userCanceled` 且 `phase` 為 `Review` 或 `Ended` |
| BR3 | 不訂使用者沒要求的項目 | `BR3_noUnrequestedBooking` | 任何時刻 |
| BR4 | 每個項目在供應商端最多一筆有效訂位 | `BR4_atMostOneActiveBooking` | 任何時刻 |
| BR5 | 「Check Booking Details」顯示的內容等於供應商端的真實狀態 | `BR5_displayMatchesSupplier` | `Review` |
| BR6 | 取消動作針對的是當初真的建立過的訂位 | `BR6_cancelTargetsRealBooking` | 任何時刻 |
| BR7 | 流程結束時要嘛全部訂好、要嘛全部沒訂（saga 的原子性） | `BR7_endIsAllOrNothing` | `Ended` |
| BR8 | 流程不會永久卡住且同時佔住訂位 | `BR8_neverStuckHoldingBookings` | 任何時刻 |

---

## 4. 驗證矩陣

✗ 表示找到反例，✓ 表示 10000 條 trace 中沒找到。這是抽樣結果，不是證明。

| instance | 假設 | BR1 | BR2 | BR3 | BR4 | BR5 | BR6 | BR7 | BR8 |
|---|---|---|---|---|---|---|---|---|---|
| `ideal` | 基礎設施完美，Flight bug 已修 | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| `asIs` | 基礎設施完美，程式碼照原樣 | ✗ | ✗ | ✓ | ✓ | ✗ | ✗ | ✗ | ✓ |
| `redelivery` | 只開重送 | ✗ | ✗ | ✓ | ✗ | ✗ | ✓ | ✗ | ✓ |
| `bookFailure` | 只開訂位失敗 | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `cancelFailure` | 只開取消失敗 | ✗ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| `allFaults` | 全部開啟 | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ | ✗ | ✗ |

怎麼讀這張表：

- **BR1 在每一列都失敗**：在 `ideal` 這個最乾淨的基準下也失敗，所以問題出在 BPMN 設計本身（CE-1），跟任何故障假設都無關。
- `asIs` 和 `ideal` 的差別只在 `FLIGHT_REF_BUG`。多出來的 4 個 ✗ 全部來自 CE-5。
- 每個故障開關在單獨開啟時，都只造成它預期的那一類違規，所以每個反例都能歸因到單一假設。

Witness 覆蓋率：每個 action 都至少在一個 instance 中被觸發過（例如 `allFaults` 下 `w_lockExpired` 為 33.8%、`w_duplicateBooking` 為 32.7%）。在 `ideal` 中，失敗類 witness 為 0%，這是預期的，因為那些 action 被開關停用了。

每一格反例的完整 trace 都在 `traces/<instance>__<BR>.md`，例如 [traces/ideal__BR1.md](traces/ideal__BR1.md)。

---

## 5. 反例詳述

步驟表的記號：
- `F/T/H` 分別代表 Flight／Train／Hotel。
- 「流程」欄是 engine 的流程變數，格式為 `狀態/ref`。
- 「供應商」欄是 ledger 中的有效訂位 ref。

### CE-1：取消後仍以「確認」結束（BR1）——純 BPMN 設計問題

**最小重現**：`ce1_confirmAfterCancelTest`。模擬器也在 `ideal` 中找到同樣的反例（[traces/ideal__BR1.md](traces/ideal__BR1.md)，20 步）。

| # | 事件 | phase | 流程 | 供應商 |
|---|---|---|---|---|
| 0–9 | 依序訂好 T、F、H | Review | F:Conf/2 T:Conf/1 H:Conf/3 | F{2} T{1} H{3} |
| 10 | 使用者選「No」，觸發補償 throw | Compensating | 不變 | 不變 |
| 11–19 | 三個 Cancel task 都完成 | **Review**（經 `Flow_0u9r45z` 連回） | F:Canc T:Canc H:Canc | 全部為空 |
| 20 | 使用者勾選 confirm | **Ended** | 全部 Canc | 全部為空 |

**根因**：
- 補償完成後，`Flow_0u9r45z`（[V3:91](../../Models/BookHolidaySagaPatternV3.bpmn#L91)）把 token 連回 user task。
- 整個流程只有一個 end event（[V3:20-22](../../Models/BookHolidaySagaPatternV3.bpmn#L20-L22)），只能經由 `confirm == true` 到達（[V3:80-82](../../Models/BookHolidaySagaPatternV3.bpmn#L80-L82)）。

**連帶問題**（`ce1b_secondCancelIsNoopTest`）：如果使用者第二次選「No」，因為補償訂閱已在第一次觸發時移除（F4），這次 throw 什麼都不做，直接回到同一張表單。使用者只能無限繞圈，或按「確認」結束。

**影響**：「旅程成立」和「旅程取消」落在同一個 end event，下游系統、報表、歷史紀錄都分不出兩者。旅程已全部取消的使用者，最後必須點「確認」才能結束流程。

**修正建議**：
1. 刪掉 `Flow_0u9r45z`，讓補償 throw 之後接到獨立的「Trip Canceled」end event，或直接用 compensation end event。
2. 如果業務上確實要讓使用者先看到取消結果，就另外放一個唯讀的通知 user task，再接到取消 end event；或至少寫入 `tripOutcome = "Canceled"` 變數，並在 gateway 上擋掉「取消後再確認」。

### CE-2：重送導致重複訂位（BR4、BR5、BR2、BR7）

**最小重現**：`ce2_redeliveryDuplicateTest`。模擬器 trace 見 [traces/redelivery__BR4.md](traces/redelivery__BR4.md)，8 步。

| # | 事件 | 流程 | 供應商 |
|---|---|---|---|
| 1 | fetch `Book(Train)` | T:–/0 | T{} |
| 2 | handler 向供應商訂位（ref 1） | T:–/0 | T{1} |
| 3 | **lock 過期／worker crash**，還沒呼叫 `complete` | T:–/0 | T{1} |
| 4–6 | 再次 fetch，又訂一次（ref 2），`complete` | T:Conf/**2** | T{**1,2**} ← 違反 BR4 |
| 7–12 | 訂 F、H，到達 Review | 畫面顯示 T 只有 ref 2 | T{1,2} ← 違反 BR5 |
| 13–… | 使用者取消，補償完成 | T:Canc/2 | T{**1**} ← 孤兒訂位，違反 BR2 |
| … | 使用者確認，流程結束 | | T{1}，不是全有也不是全無 ← 違反 BR7 |

**根因**：
- External task 是 at-least-once 投遞。三個 handler 都沒有冪等性（[TrainBooking.js:12-21](../../BookingSystemWorkers/TrainBooking.js#L12-L21) 每次執行都產生新的 UUID）。
- engine 只記住最後一次 `complete` 帶回的 ID，所以補償只會取消那一筆。
- 會觸發重送的情境：worker 重啟（compose 中的 worker 沒有設定 restart policy）、網路中斷、handler 執行超過 50 秒的 lock。
- 另一個加重因素：三個 worker 都用預設的 `workerId: "some-random-id"`（[FlightBooking.js:6](../../BookingSystemWorkers/FlightBooking.js#L6) 沒有設定 `workerId`）。lock 過期後，原本那個「殭屍」handler 晚一點呼叫 `complete` 仍可能成功，結果一樣是副作用被執行了兩次。

**修正建議**：
1. 用冪等鍵向供應商訂位，例如 `processInstanceId + activityId`，或 `task.id`。供應商端遇到重複的鍵時，直接回傳原本那筆 ID。
2. `lockDuration` 要大於 handler 最長的執行時間，長時間呼叫時用 `extendLock`。
3. 每個 worker 設定唯一的 `workerId`。

### CE-3：訂位失敗，流程永遠卡住（BR8）

**最小重現**：`ce3_bookFailureStuckTest`，假設 Flight 供應商永久拒絕。模擬器另外找到一條經由 Hotel 的路徑（[traces/bookFailure__BR8.md](traces/bookFailure__BR8.md)）：使用者只需要 Train + Hotel，Train 訂好、兩個分支會合後，Hotel 永久失敗。

| # | 事件 | phase | 供應商 | 待處理 task |
|---|---|---|---|---|
| 1–3 | 訂好 Train | Booking | T{1} | `Book(Flight)` |
| 4–5 | fetch `Book(Flight)`，handler 拋例外 | Booking | T{1} | `Book(Flight)` 等 lock 過期後重新變成可 fetch |
| 6–… | 無限重試；`retries` 不遞減，沒有 incident | **永遠是 Booking** | **T{1} 一直被佔住** | `Book(Hotel)` 永遠不會被建立 |

**根因**：
- 三個 worker 都沒有錯誤處理：沒有 `handleFailure`，也沒有 `handleBpmnError`（F7）。
- BPMN 在訂位階段沒有任何 error boundary event 或 timer。觸發補償的唯一方式，是使用者在 Review 選取消，但 token 永遠到不了 Review。
- 這等於 saga 少了「前進失敗就補償」的分支：補償只能由使用者手動觸發，系統本身不會在失敗時自動補償。
- 而且運維端看不到任何 incident，只會在 worker log 看到不斷重複的 handler 錯誤。

**修正建議**：
1. 把訂位步驟包進 embedded subprocess，在上面掛 error boundary event。worker 遇到業務失敗（例如沒有座位）時呼叫 `handleBpmnError("BookingFailed")`，接到補償 throw，最後走到「Booking Failed」end event。
2. 技術性失敗呼叫 `handleFailure`，讓 `retries` 遞減並設定 `retryTimeout`；retries 用完就產生 incident，交給運維處理。
3. 視需要在訂位階段加上 timer boundary event，超時就自動補償。

### CE-4：取消失敗，補償永遠卡住（BR8）

**最小重現**：`ce4_cancelFailureStuckTest`，假設 Hotel 供應商永久拒絕取消。

| # | 事件 | phase | 供應商 |
|---|---|---|---|
| 0–9 | 三項全部訂好，到達 Review | Review | F{2} T{1} H{3} |
| 10 | 使用者取消 | Compensating | |
| 11–16 | 成功取消 F、T | Compensating | H{3} |
| 17–… | `Cancel(Hotel)` 無限重試 | **永遠是 Compensating** | **H{3} 一直被佔住** |

**根因**：
- 和 CE-3 一樣，cancel handler 沒有錯誤處理（[BookHotel.js:23-30](../../BookingSystemWorkers/BookHotel.js#L23-L30)）。
- Camunda 的補償 throw event 必須等所有 handler 完成才離開（F4，`waitForCompletion=false` 不支援）。
- 使用者看不到表單，也沒有 incident。

**修正建議**：
1. cancel handler 呼叫 `handleFailure`，讓 retries 遞減，用完就產生 incident，讓人工介入。
2. 取消 API 要做成冪等的，重試才安全。
3. 對「無法自動補償」的情況，建立明確的人工處理流程。

### CE-5：Flight 回寫的 ID 和實際訂位不同（BR5、BR6、BR2、BR7）——程式碼照原樣就會發生

**最小重現**：`ce5_flightRefMismatchTest`。模擬器 trace 見 [traces/asIs__BR6.md](traces/asIs__BR6.md)。

| # | 事件 | 流程 | 供應商 |
|---|---|---|---|
| 1–3 | `Book(Flight)`：handler 用 `id`（ref 1）訂位，回寫的是**另一個** UUID（ref 2） | F:Conf/**2** | F{**1**} |
| 4–6 | 訂 Hotel，到達 Review | 畫面顯示 F 的 ID 是 2 | F{1} ← 違反 BR5 |
| 7–… | 使用者取消；`CancelFlightBooking` 讀到 `${FlightBookingID}` = 2 | F:Canc/2 | **F{1} 仍然有效** ← 違反 BR6、BR2 |
| … | 使用者確認，流程結束 | | F{1} ← 違反 BR7 |

**根因**：

```js
// FlightBooking.js:19-21
const id = create_UUID();                                   // log 和（未來的）實際訂位用這個
processVariables.set("FlightBookingStatus", "Confirmed");
processVariables.set("FlightBookingID", create_UUID());     // ← 回寫給流程的是另一個新 UUID
```

Train 和 Hotel 都正確地用同一個 `id`（[TrainBooking.js:15-17](../../BookingSystemWorkers/TrainBooking.js#L15-L17)、[BookHotel.js:15-17](../../BookingSystemWorkers/BookHotel.js#L15-L17)）。目前的 stub 只會造成 log 對不上；一旦接上真實 API，就會變成「取消了一筆不存在的訂位，真正的機票永遠沒被退」。

**修正建議**：改成 `processVariables.set("FlightBookingID", id)`。模型中把 `FLIGHT_REF_BUG = false`（`ideal` instance）就是修正後的行為，此時 BR2、BR5、BR6、BR7 都會恢復成立。

---

## 6. 確認成立或確認不是問題的項目

| 項目 | 結論 |
|---|---|
| BR3：不訂未被要求的項目 | 所有 instance 都成立。`${flightNeeded==true}`／`${trainTicketNeeded==true}` 搭配 default flow 和 parallel join 的組合是正確的；只需要 Hotel 時，join 也會立即觸發（`hotelOnlyTest`） |
| Hotel 缺少 `HotelBookingID` 的 output mapping | 不是 bug（F3）。變數會寫進 process-instance scope，補償時讀得到 |
| 補償是否只取消已完成的項目 | 正確。只有完成過的活動才有補償訂閱，所以沒要求的項目不會被取消 |
| `ideal` 下的 BR2／BR4–BR8 | 在基礎設施完美、程式碼修正後全部成立。剩下的問題只有 CE-1 |

---

## 7. 模型外的觀察（沒有寫成規則，供參考）

1. **使用者一直不回應**：「Check Booking Details」沒有 timer boundary event，使用者不處理的話，三筆訂位會無限期被佔住。模型沒有時間，所以不建模；建議加 timer，超時就自動補償。
2. **透過 REST 啟動但沒帶 `flightNeeded`／`trainTicketNeeded`**：gateway 表達式會拋 `PropertyNotFoundException`，整個啟動交易 rollback（task 是 `asyncBefore`，所以發生在同一個交易內），不會產生業務狀態，但呼叫端會收到錯誤。建議設預設值。
3. **compensation boundary event 上的 `camunda:asyncBefore`**（[V3:100](../../Models/BookHolidaySagaPatternV3.bpmn#L100)、[111](../../Models/BookHolidaySagaPatternV3.bpmn#L111)、[149](../../Models/BookHolidaySagaPatternV3.bpmn#L149)）：對補償的語意沒有作用，可以移除，避免誤導。
4. **只有 Flight 有 2 秒 sleep**：對業務規則沒有影響。

---

## 8. 修正優先順序

| 優先 | 項目 | 修正對象 | 對應反例 |
|---|---|---|---|
| P0 | `FlightBookingID` 改用同一個 `id` | FlightBooking.js（改一行） | CE-5 |
| P0 | 取消路徑接到獨立的 end event，移除 `Flow_0u9r45z` | V3 BPMN | CE-1 |
| P1 | 訂位與取消 API 使用冪等鍵；每個 worker 設唯一的 `workerId`；調整 `lockDuration`／使用 `extendLock` | 3 個 worker | CE-2 |
| P1 | 訂位階段加 error boundary event，失敗時自動補償；worker 加上 `handleBpmnError`／`handleFailure` | BPMN + worker | CE-3 |
| P2 | cancel handler 加 `handleFailure`，產生 incident 並建立人工處理流程 | worker + 運維 | CE-4 |
| P2 | user task 加 timer boundary event | BPMN | 第 7 節第 1 點 |

照 spec-first 的流程：修正前，先在 [bookHoliday.qnt](bookHoliday.qnt) 把修正後的行為建模出來，例如加一條取消 end 路徑、加入失敗時的補償轉移。確認矩陣全部變成 ✓ 之後，再修改 BPMN 和 worker。可以用 `quint-execute-spec` skill 依規格實作。

---

## 9. 重現方式

```sh
cd specs/quint
./run_all.sh                                                   # 第 4 節的矩陣，結果寫到 traces/
quint test bookHoliday_test.qnt --main=bookHoliday_test        # CE-1、CE-1b、CE-2、CE-3、CE-4 與 happy path
quint test bookHoliday_test.qnt --main=bookHoliday_asIs_test   # CE-5
```

本報告的範圍與限制，見 [README.md](README.md) 的「未涵蓋的部分」。
