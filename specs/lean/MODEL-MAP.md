# Model map：驗證主張的帳本

> 沒記在這裡的主張，就不算涵蓋。本檔是人工 gate；`verify-lean.sh` 只檢查機械性的部分。

- **Verified at commit**：`4b08b40`（2026-10-24，branch `master`；工作區另有未 commit 的 `specs/`）
- **Rules of record**：[RULES.md](RULES.md)（2026-10-24 由 owner 確認，轉錄自 Quint 訪談）
- **Toolchain**：Lean `v4.35.0`（`lean-toolchain`）；Mathlib：**不使用**（只用 core）

## 被驗證的原始碼（模型宣稱描述的程式）

| 檔案 | 行 | 建模內容 |
|---|---|---|
| `Models/BookHolidaySagaPatternV3.bpmn` | 4-19 | 啟動表單（`flightNeeded`、`trainTicketNeeded`），listener 把所有 status 設為 "No Booking Made" → `initItem`/`initState` |
| 同上 | 123-179 | parallel split、兩個 XOR（條件與 default flow）、兩個 merge XOR、parallel join `Gateway_1hfufm4` → `initItem.branchDone/book`、`completeBook` 的 join 分支 |
| 同上 | 23-41、139-148 | Book Hotel / Flight / Train 三個 external task，以及 output mapping → `Task`、`step .fetch/.sideEffect/.complete .book` |
| 同上 | 43-74 | user task「Check Booking Details」→ `Phase.review` |
| 同上 | 75-85 | 「Do you want to cancel」XOR（`confirm` / `not confirm`）→ `step .userConfirm` / `.userCancel` |
| 同上 | 86-91 | 補償 throw event `Event_1y70am0`，以及連回 user task 的 `Flow_0u9r45z` → `userCancel`、`completeCancel` |
| 同上 | 92-121、100-102、111-113、149-151 | 三個補償 handler（`isForCompensation`）、`${XBookingID}` input mapping、補償 boundary events → `ItemSt.sub`、`step .fetch .cancel`（解析 target） |
| 同上 | 20-22、80-82 | 唯一的 end event → `Phase.ended` |
| `BookingSystemWorkers/FlightBooking.js` | 12-25、28-38 | BookFlight／CancelFlightBooking handler；**19-21 雙 UUID** → `Config.buggy`、`sideEffect .book`（`ret = n+1`） |
| `BookingSystemWorkers/TrainBooking.js` | 12-21、24-32 | BookTrain／CancelTrainBooking handler（同一個 `id`） |
| `BookingSystemWorkers/BookHotel.js` | 12-21、23-30 | BookHotel／CancelHotelBooking handler（同一個 `id`） |
| 三個 worker | 6 | `config`：沒有 `handleFailure`／`handleBpmnError`，沒有 `workerId`，lock 為預設 50 秒 → `handlerFail`、`lockExpire` |
| camunda-external-task-client-js 2.3.1 `lib/Client.js` | `executeTask` | handler 例外只會 `emit("handler:error")` → task 等 lock 過期後再被 fetch；retries 不變 |
| Camunda 7.21 `ExternalTaskEntity.complete` | `ensureVariablesSet` | 變數往上傳到 process scope → `completeBook` 寫入的 `ref` 補償時讀得到 |
| Camunda 7.21 Compensation Events 文件 | — | 訂閱在完成時建立、觸發後即移除；throw 會等所有 handler；handler 並行執行 → `userCancel`、`completeCancel`、任意 handler 順序 |

## Lean 模型 ↔ Quint 模型對照（L2：獨立建模後比對）

| 面向 | Lean（`Specs/Model.lean`） | Quint（`bookHoliday.qnt`） | 差異的影響 |
|---|---|---|---|
| 狀態分組 | 依 saga 項目分組（`ItemSt`：engine 變數、2 個 task、該項目的 ledger） | 依元件分組（`engine`／`tasks`／`supplier`） | 只是表示法不同；`State.agree` 逐欄比對（`lastEvent` 除外，它是輸入），22 條 trace 每一步都一致。**注意（對抗審查 #7）**：Lean 的欄位與 Quint 幾乎一一對應，所以「22 條 trace 一致」主要證明兩個模型**彼此一致**，不能當成獨立確認；兩個模型共有的抽象錯誤（見下方 R1/R2），它看不出來 |
| lock 過期 | `redelivery` 開啟時，**任何** locked task 都可能過期（副作用前或後） | 只允許副作用**之後**過期；副作用前的解鎖只能透過 `handlerFails`，而它需要失敗開關 | **Lean 的行為集合較大**（更貼近真實：lock 什麼時候都可能過期）。Quint trace 是 Lean 行為的子集，所以重播仍然成立；group C 的全稱定理涵蓋更多行為，結論更強 |
| cancel 的 target 解析 | 在 fetch 時讀 `ref` | 同樣在 fetch 時 | Camunda 實際上是在補償 handler 的 asyncBefore job 啟動該 activity 時解析 input mapping（V3:92/103/114），比 fetch 早。兩者等價，因為補償開始後 `ref` 不會再變：只有 `completeBook` 會寫 `ref`，而依 `Struct.booksOnlyBooking`，Booking 階段以外沒有 book task。這個等價性**沒有寫成獨立定理**，只是依附在上述 invariant 上（對抗審查 #8） |
| `lastEvent` | 不在狀態中，事件是 transition 的標籤 | 是一個 state var | 重播時把 Quint 的 `lastEvent` 當作 Lean 的事件序列 |
| 規則定義 | `Specs/Rules.lean`，集合相等寫成 `holdsExactly` | 直接比對 `Set` | 語意相同（ledger 的 ref 都是新產生的，不會重複） |

**發現（L7：只記錄，不改 Quint）**：兩邊在所有 22 條 trace 上逐狀態一致，模型內部沒有找到 Quint 建模錯誤。唯一的差異是上表的 lock 過期時機。這不影響 Quint 的任何結論，但表示 Quint 的 `redelivery` instance 沒有探索「副作用前就 crash」的路徑；Lean 的 group C 定理涵蓋了這類路徑。

**兩個模型共有的抽象缺口（對抗審查 #1/#2，兩邊都看不出來）**：
- **R1：`complete()` 失敗後重新執行。** client 2.3.1 的 `TaskService.complete` 會吞掉錯誤（只 `emit("complete:error")`），task 因此維持 locked，50 秒後被重新 fetch，handler 會再訂一次。即使基礎設施沒有故障，這也可能發生：Flight 與 Train 同時完成、同時到達 parallel join `Gateway_1hfufm4`（V3:159），Camunda 會以 OptimisticLockingException 回滾其中一筆 complete。在 Lean 中，這條路徑等同 `lockExpire`（副作用之後），所以只在 `redelivery = true` 時可達。
- **R2：「訂位失敗」的定義是副作用之前就乾淨地拒絕。** 供應商呼叫成功、但 handler 之後才拋例外（例如 timeout）的情況，在模型中屬於 `redelivery`，不屬於 `bookFailure`。

## Rule coverage：headline theorems

### Statement snapshot（phase 2，2026-10-24 凍結；SHA-256 前 16 碼：`Proofs.lean` = `8d3a2aa432193fc5`、`Rules.lean` = `89ebef4e6ac5416e`、`Model.lean` = `a01294f4771a6b1d`、`Trace.lean` = `249efeed915836be`）

| # | Rule | Theorem | 精確敘述 |
|---|---|---|---|
| A1 | BR1 | `ce1_confirm_after_cancel` | `(cfg : Config) : Violable cfg BR1` |
| A2 | BR4/5/2/7 | `ce2_redelivery_duplicate` | `(cfg : Config) (h : cfg.redelivery = true) : Violable cfg BR4 ∧ Violable cfg BR5 ∧ Violable cfg BR2 ∧ Violable cfg BR7` |
| A3 | BR8 | `ce3_book_failure_stuck` | `(cfg : Config) (h : cfg.bookFailure = true) : Violable cfg BR8` |
| A4 | BR8 | `ce4_cancel_failure_stuck` | `(cfg : Config) (h : cfg.cancelFailure = true) : Violable cfg BR8` |
| A5 | BR5/6/2/7 | `ce5_flight_ref_mismatch` | `(cfg : Config) (h : cfg.flightRefBug = true) : Violable cfg BR5 ∧ Violable cfg BR6 ∧ Violable cfg BR2 ∧ Violable cfg BR7` |
| B1 | BR8 | `stuck_is_permanent` | `(cfg : Config) {s t : State} (hr : Reachable cfg s) (hs : StuckHolding s) (h : Reach cfg s t) : StuckHolding t ∧ t.phase = s.phase` |
| C1 | BR3 | `br3_always` | `(cfg : Config) : Invariant cfg BR3` |
| C2 | BR4 | `br4_of_no_redelivery` | `(cfg : Config) (h : cfg.redelivery = false) : Invariant cfg BR4` |
| C3 | BR6 | `br6_of_no_flight_bug` | `(cfg : Config) (h : cfg.flightRefBug = false) : Invariant cfg BR6` |
| C4 | BR8 | `br8_of_no_failures` | `(cfg : Config) (h1 : cfg.bookFailure = false) (h2 : cfg.cancelFailure = false) : Invariant cfg BR8` |
| C5 | BR2 | `br2_of_reliable` | `(cfg : Config) (h1 : cfg.redelivery = false) (h2 : cfg.flightRefBug = false) : Invariant cfg BR2` |
| C6 | BR5 | `br5_of_reliable` | 同 C5，結論為 `Invariant cfg BR5` |
| C7 | BR7 | `br7_of_reliable` | 同 C5，結論為 `Invariant cfg BR7` |
| D1 | 全部 | `quint_matrix` | 6 × 8 個 cell 的合取：✗ 為 `Violable cfgX BRk`，✓ 為 `Invariant cfgX BRk`（逐格對照 Quint REPORT §4，見 `Proofs.lean`） |
| E1–E22 | 各自 | `quint_<instance>_<BRk>` | `TraceConfirmed tr_<instance>_<BRk> BRk`（`Specs/Traces.lean`，由 `gen_traces.py` 自動產生） |

定義參考：
- `Violable cfg P := ∃ s, Reachable cfg s ∧ ¬ P s`
- `Invariant cfg P := ∀ s, Reachable cfg s → P s`
- `Reachable cfg s := ∃ s0, Init cfg s0 ∧ Reach cfg s0 s`
- `TraceConfirmed tr P := checkTrace tr = true ∧ ∃ s, tr.final = some s ∧ Reachable tr.cfg s ∧ ¬ P s`，其中 `checkTrace` 要求初始選擇合法，並且每一步之後 Lean 狀態都與 Quint 狀態一致（`State.agree`）

Helper lemmas（不是 headline）：`reach_of_replay`、`traceConfirmed_of_check`；`Specs/Lemmas.lean`（`step_inv`、`Struct`、`NoDown`、`Q`、`R`、`Exact`、`blocked_step`、`held_booking_step`）；`Specs/Reachability.lean`（`q_reachable`、`r_reachable`、`exact_reachable`、`stuck_step`、`violable_of_replay`、`init_initState`）。

### 業務語言版本（給 owner 簽核）

| # | 一句話 |
|---|---|
| A1 | **不論是哪一種基礎設施假設**，都存在一條實際走得到的執行：使用者取消、補償清空所有訂位後，再按確認，流程就走到唯一的 end event，但旅程並沒有成立（違反 BR1）。 |
| A2 | 只要 worker 可能在 `complete` 前 crash 或 lock 過期（不管其他假設如何），就走得到「同一項目有兩筆有效訂位」（BR4）、「表單顯示和供應商不符」（BR5）、「取消後仍殘留訂位」（BR2）、「結束時半訂半不訂」（BR7）的狀態。 |
| A3 | 只要訂位可能失敗，就走得到「流程卡在訂位階段、某個 task 永遠無法完成、而另一筆訂位被佔住」的狀態（違反 BR8）。 |
| A4 | 只要取消可能失敗，就走得到「流程卡在補償階段、某筆訂位永遠無法取消」的狀態（違反 BR8）。 |
| A5 | 只要 Flight 的雙 UUID bug 存在（不需要任何故障），就走得到違反 BR5、BR6、BR2、BR7 的狀態。 |
| B1 | 一旦卡住且佔住訂位，之後不論發生什麼：phase 永遠不變（表單不會再出現、流程不會結束），而且**至少有一筆**訂位一直被佔住。在 Compensating 中，這筆至少是拒絕取消的那個項目；其他項目的訂位可能會被釋放。（R4） |
| C1 | 在**任何**假設下，供應商都不會收到使用者沒要求的項目的訂位（BR3）。 |
| C2 | 只要**副作用執行後絕不重新執行**（沒有 crash、lock 逾時、`complete()` 失敗、副作用後拋例外；見 R1），**不論**訂位或取消是否在副作用前就失敗、Flight bug 是否存在，每個項目最多只有一筆有效訂位（BR4）。也就是說，重複訂位**只**可能來自副作用後的重新執行。 |
| C3 | 只要 Flight bug 被修好，**不論**是否有重送或失敗，被取消的 ref 一定是真的訂過的（BR6）。也就是說，「取消到不存在的訂位」**只**來自這個 bug。 |
| C4 | 只要沒有供應商會永久拒絕，**不論**是否有重送或 Flight bug，都不會出現 BR8 所定義的「卡住且佔住訂位」狀態。依 BR8 的定義，這幾乎是定義上就成立；它**不是**「流程一定會往前走」的 liveness 保證。（R3） |
| C5–C7 | 只要**同時**滿足「副作用後絕不重新執行」（R1）與「Flight bug 已修」，即使訂位或取消會在副作用前失敗（R2）：補償完成後一定沒有孤兒訂位（BR2）、表單顯示一定正確（BR5）、結束時一定是全有或全無（BR7）。 |
| D1 | Quint REPORT §4 那張 6×8 矩陣的每一格都是定理：22 個 ✗ 是真的違規，26 個 ✓ 在所有可達狀態都成立（不只是抽樣 10000 條沒找到）。`redelivery = false` 那幾列的 ✓，前提都是 R1「副作用後絕不重新執行」；實務上 V3 的 parallel join 會破壞這個前提（CE-6）。 |
| E1–E22 | Quint 模擬器實際輸出的 22 條反例 trace，每一條的每一步都是 Lean 模型允許的轉移，而且每一步之後兩個模型的狀態完全一致，最後一個狀態確實違反所標示的規則。 |

## Non-vacuity witnesses（`Specs/Examples.lean`，都用 kernel `decide` 檢查）

| Theorem | Witness | 說明 |
|---|---|---|
| C6（BR5 前提 `phase = review`） | `ideal` 的 happy path 可走到 Review | BR5 的 antecedent 可滿足 |
| C5/C7（BR2/BR7 前提） | `ideal` 的 CE-1 路徑：canceled 且 Ended，`nothingBooked` 成立 | 前提可滿足，結論在此點成立 |
| C3（BR6 前提 status = canceled） | `ideal` 的 CE-1 路徑 | 同上 |
| C1/C2 | `asIs` 訂了 flight：`ever ≠ []` 且 `|active| = 1` | 量詞不空 |
| B1（`Reachable ∧ StuckHolding`） | `bookFailure` 的 CE-3 路徑；之後還能再走一步 | 前提可滿足，`Reach s t` 不只有 refl |
| C4 | `ideal` 訂了 train：持有訂位但沒卡住 | BR8 不是 trivially 成立 |
| BR1 positive | `ideal` 的 happy path 確認結束時 `fullyBooked` | 規則本身可以被滿足 |
| A1–A5 | `Specs/Scenarios.lean` 的最小事件序列 | phase 4 的存在性證明會直接用到 |

## Abstraction ledger：丟掉的細節，以及為什麼不影響結論

| 丟掉的細節 | 位置 | 理由 |
|---|---|---|
| UUID 字串與 `create_UUID()` 的隨機性 | FB:41-49、TB:34-42、BH:33-41 | 規則只依賴 ID 的相等性與「新產生」；`nextRef` 遞增已保證唯一。實際 UUID 有碰撞的機率，但不在範圍內 |
| `setTimeout` 2 秒、console log | `setTimeout`：FB:14、FB:30；log：FB:24、FB:37、TB:20、TB:31、BH:20、BH:29 | 不改變任何狀態轉移 |
| lock 時長、輪詢間隔、`asyncResponseTimeout`、`maxTasks` | worker config 第 6 行 | 時間不在範圍內（RULES.md）。是否發生 lock 過期由 `redelivery` 開關決定。`maxTasks:1` 只限制每次 poll 取回的數量；因為沒有設定 `maxParallelExecutions`，handler 執行中仍會繼續 poll（對抗審查 #8 更正）。Lean 允許任意 interleaving，是實際行為的超集 |
| `asyncBefore` 的 job 與交易邊界 | V3 多處 | engine 的每個 transition 視為原子；engine 自身 crash 或 rollback 不在範圍內 |
| `location` 表單欄位、`holidayGoer` assignee | V3:7、V3:43 | 不影響任何規則 |
| output mapping `${X}` 的冗餘寫法 | V3:26 等 | 依 F3，變數本來就在 process scope；Hotel 缺 `HotelBookingID` mapping **不影響**補償讀到 ID |
| 補償 handler 的實際啟動順序 | Camunda 文件 | 模型允許任意 interleaving（是實際行為的超集），全稱定理因此更強 |
| zombie handler 晚到的 `complete` | worker 共用 `workerId`（Client.js defaultOptions） | **不完全等同**「執行兩次」（對抗審查 #3）：原 handler 晚到的 `complete` 會被接受，之後重新 fetch 的那個 handler 可能在 book task 已經不存在、甚至補償或 Ended 之後才訂位。Lean 無法表達這條路徑（task 完成後 `sideEffect` 一律不可用）。受影響的規則（BR2/4/5/7）在 `redelivery = true` 時本來就已是 ✗，所以沒有定理需要改，但這類路徑的違規比模型呈現的更嚴重 |
| 多個 process instance | — | instance 之間沒有共享的業務狀態（Q8） |

## Explicitly not covered

- 時間相關的 liveness：使用者久未回應時訂位被無限期佔住、lock 過期的實際時機。BR8 只涵蓋「永久故障」造成的卡住。
- zombie handler：lock 過期後原 handler 晚到的 `complete` 被接受（共用 `workerId`），新 handler 可能在 task 完成之後才訂位（甚至在補償或 Ended 之後）。Lean 無法表達。
- R1／R2：`complete()` 失敗（包括 parallel join 的 OptimisticLockingException）與「副作用後才拋例外」，在模型中只能經由 `redelivery` 表達。因此所有 `redelivery = false` 的 ✓ 都帶有前提：**副作用執行後，絕不會發生重新執行**。
- Ledger 中 ref 沒有重複（freshness）：`holdsExactly` 本來就是集合語意，不受重複影響。BR4 的 `length ≤ 1` 比 Quint 的 `size ≤ 1` 更強，所以 ✓ 不受影響；✗ 的 witness 都是具體狀態，由 `decide` 檢查，例如 `active = [2,1]`，元素互不相同（對抗審查 #6）。
- engine crash、DB 隔離、交易 rollback；REST 啟動時缺少變數的情況。
- 真實供應商 API 的語意（ledger 是抽象）；UUID 碰撞。
- V1、V2、BookHoliday.bpmn。
- 模型與程式碼之間的連結是**人工審查**（本檔 + 對抗式審查），不是自動產生的。Lean 從沒看過 JS 或 BPMN 本身。

## Bounded port audit（逐條轉移比對模型與原始碼）

| 轉移（`step`） | 原始碼 | Guards（條件與方向） | 順序與結果 | 邊界 |
|---|---|---|---|---|
| `fetch k i` | client `poll`→`fetchAndLock`；V3 input mapping `${XBookingID}` | 只在 task 為 `available` 時；cancel 會讀 `ref` | 結果為 `locked false target 0`；其他狀態一律 `none` | cancel target 的解析時點與 Camunda 不同，但等價（見對照表） |
| `sideEffect .book i` | FB:12-21、TB:12-17、BH:12-17 | `locked false` 且供應商沒有永久故障 | `active`／`ever` 都加入 `n`，`ret = n`；有 bug 時 `ret = n+1` 且 `nextRef += 2`（FB:19-21） | stub 一定成功；永久故障是 R2 定義的乾淨拒絕 |
| `sideEffect .cancel i` | FB:28-33、TB:24-27、BH:23-25 | `locked false` 且供應商沒有拒絕取消 | 從 `active` 移除 `target` | target 不在 `active` 時是 no-op（對應 CE-5） |
| `handlerFail k i` | Client.js `executeTask` 的 catch | 只在 `locked false`（副作用前）且有對應的失敗開關 | 回到 `available`，retries 不變 | R2 |
| `lockExpire k i` | lock 過期；`TaskService.complete` 吞掉錯誤 | `locked`（任何 `done`）且 `redelivery` | 回到 `available`；ledger 保留 | R1：涵蓋 crash、逾時、complete 失敗 |
| `complete .book i` | REST complete → engine；V3:159 join；V3:74 | `locked true` | status = Confirmed、`ref`、`sub`、`branchDone`；第二個分支到達時 Hotel 變為 `available`；完成 Hotel 後進入 Review | join 只在兩個分支都完成時觸發（`Struct.join`） |
| `complete .cancel i` | 補償 handler 完成；V3:86-91 | `locked true` | status = Canceled；所有 cancel 都 absent 時回到 Review（`Flow_0u9r45z`） | 任意完成順序 |
| `userConfirm` | V3:80-82 | `phase = review` | 進入 Ended | 唯一的 end event |
| `userCancel` | V3:83-90 | `phase = review` | 觸發所有 `sub` 並清空；沒有 `sub` 時直接回到 Review | 第二次取消是 no-op（F4） |

每個 guard 的方向都與原始碼一致；沒有任何分支被 default 吞掉（`step` 的 `| _ => none` 只用於「task 不在可執行狀態」）。丟掉的細節都列在 abstraction ledger。

## Dashboard（`verify-lean.sh`，Rule 4）

- **Baseline**（`metrics-baseline.txt`，第一次全綠）：11 個檔案、3671 行（3128 行 code）；main（`Proofs.lean`）有 140 行 code、16 個 public theorem、`cases` 46、`induction` 1、`have` 6、`rw` 3、`simp` 5。
- **Current**（Rule-2 清理後）：3627 行（3088 行 code，**−40**）；移除了與 `Struct.everNeeded` 重複的 `I3`／`I3_inv`，以及沒用到的 `filter_length_le`。main 的各項指標不變。沒有任何指標退步。
- 備註：大部分 proof 的工作量集中在 `Specs/Lemmas.lean`（shape-by-shape 的 `simp_all`，乾淨 build 約 3.5 分鐘）。`Struct` 與 `Exact` 刻意寫成「逐項目展開」的形式，避免 `∀ i` 無法被 `simp` 實例化的問題。

## Verification gate checklist

- [x] `RULES.md` 已確認並記錄出處、驗收標準與 sign-off
- [x] 被驗證的原始碼對應到 `file:line`；abstraction ledger 已填，並依對抗式審查 #3/#8 修正
- [x] Statement snapshot 已記錄（phase 2），phase 4 之後**逐字未變**（以腳本比對 `/tmp/Proofs.phase2.lean` 與最終版的 theorem 簽名）
- [x] 每條有前提的 headline theorem 都有 non-vacuity witness
- [x] 獨立的對抗式審查紀錄（subagent `fcde47b0`，見 Review log；同一個 model family，不是不同 model）
- [x] Owner 讀過頂層敘述並簽核（2026-10-24，R5）
- [x] `verify-lean.sh` 全綠：build／direct compile／coverage（36/36）／guardrails／axioms 全部 PASS
- [x] Dashboard baseline 與目前數值（見上方 Dashboard）
- [x] Bounded port audit（見上方表格）

## Review log

| 日期 | Reviewer | 類型 | 發現 | 處理 |
|---|---|---|---|---|
| 2026-10-24 | lead（自查） | self-review（較弱） | 22 條 trace 用 `#eval` 檢查全部一致；Lean 的 lock 過期是 Quint 的超集 | 已記錄在上方「發現」 |
| 2026-10-24 | subagent `fcde47b0`（全新 context） | 獨立對抗式審查（同一個 model family） | 窮舉 BFS：沒有 redelivery 的 8 種設定全部跑到飽和（218–2330 個狀態），所有 ✓ 格和 B1 都沒有反例；有 redelivery 時只做有界搜尋（深度 16–22，最多 27k 個狀態），也沒找到。**#1 major**：`complete()` 失敗會導致重新執行，例如 join 的 OLE（R1）。**#2 major**：bookFailure 指的是副作用前就拒絕（R2）。#3 zombie 描述不精確。#4 C4 幾乎是依定義成立，不應讀成 liveness。#5 B1 的業務文字寫得太強。#6 list 與 set 的差異。#7 兩個模型的獨立性弱，`gen_traces` 只從檔名取設定。#8 ledger 的行號與敘述錯誤 | #3、#6、#7、#8 已修正（`gen_traces.py` 現在會 assert ITF 模組前綴）；#1、#2、#4、#5 由 owner 決定（R1–R4），**定理敘述不變** |
| 2026-10-24 | owner | human | 讀過業務語言版本 | 簽核（R5） |

## Re-sync log

| 日期 | Commit | 變動的原始碼 | 受影響的規則 | 動到的定理 | 備註 |
|---|---|---|---|---|---|
| 2026-10-24 | 4b08b40 | （初版） | — | — | — |
| 2026-10-24 | 4b08b40 | 沒有變動原始碼；Phase 4 完成證明 | — | 36 條 headline 全部證明（敘述不變） | 新增 `Lemmas.lean`、`Reachability.lean`；`Examples.lean` 新增 CE-6 witness |
