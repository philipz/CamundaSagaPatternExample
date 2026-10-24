# 要驗證的業務規則（owner 已確認）

> Phase 0 產出。本檔是**轉錄**自 owner 已確認的成品，不是重新推導：
> - 規則 BR1–BR8：轉錄自 [specs/quint/REPORT.md §3](../quint/REPORT.md)，該表由 owner 在 2026-10-24 本對話的 Quint 訪談 Q4（全收）、Q5(b)、Q13(a)、Q14(a) 確認。
> - 系統假設與允許的抽象：轉錄自 [specs/quint/README.md「建模決策紀錄」](../quint/README.md) Q1–Q14。
> - Lean 專屬決策（證明範圍、模型來源、trace 重播等）：見下方「Grilling log」L1–L8，由 owner 在 2026-10-24 確認。

- **Module / entry point（唯讀）**：`Models/BookHolidaySagaPatternV3.bpmn`、`BookingSystemWorkers/{FlightBooking,TrainBooking,BookHotel}.js`，以及這些程式依賴的 Camunda 7.21 / camunda-external-task-client-js 2.3.1 語意
- **Owner**：本 repo 的使用者（對話中的 human）
- **Confirmed by**：owner，2026-10-24，於本對話（Quint 訪談 Q1–Q14；Lean 訪談 L1–L8）
- **Status**：`confirmed`
- **Acceptance**：
  1. 每條規則至少有一條 headline theorem。
  2. Quint 矩陣（REPORT §4）的 48 格**每一格**都有對應定理：✗ 格要證明「存在可達的違規狀態」；✓ 格要證明「所有可達狀態都成立」（L1(b)）。
  3. `specs/quint/traces/` 中 22 條模擬器 trace，每條都由 kernel 檢查：逐步合法、與 Lean 狀態逐步一致、最後一個狀態違反所標示的規則（L3(b)）。
  4. BR8 要另外證明卡死狀態是永久的（L4(b)）。
  5. 零 `sorry`、零新 axiom、`verify-lean.sh` 全綠、axiom audit 全部在 allowlist 內。
  6. `MODEL-MAP.md` 完整，並有獨立的對抗式審查紀錄。
- **Sign-off**：owner，2026-10-24，簽核 MODEL-MAP.md「業務語言版本」A1–A5、B1、C1–C7、D1、E1–E22（套用 R1–R4 之後）

## Scope

**In scope**：BR1–BR8；V3 流程的狀態機（parallel split/join、Book×3、user task、補償 throw 與 loop、end event）；external task 的 fetch → 副作用 → complete 生命週期；四個假設開關（`redelivery`、`bookFailure`、`cancelFailure`、`flightRefBug`）。

**Out of scope（明確排除）**：時間（timeout、lock 時長、user task 逾時）；多個 process instance；DB 與交易 rollback；REST 啟動參數缺漏；V1/V2/BookHoliday.bpmn；效能；zombie handler 晚到的 `complete` 以獨立事件呈現的情況（併入 crash/重送處理，見 Quint README）。

## 規則

符號說明：
- 「供應商有效訂位」指抽象 ledger 的 `active`（Quint Q2(a)）。
- 「需要」：flight 由 `flightNeeded`、train 由 `trainTicketNeeded` 決定；hotel 恆為需要。

### BR1：以「確認」結束代表旅程完整成立
- **Statement**：流程到達 end event 時，每個需要的項目狀態都是 Confirmed，且供應商端剛好持有流程所記錄的那一筆訂位；不需要的項目在供應商端沒有訂位。
- **Source of truth**：Quint REPORT §3 BR1；Q5(b)「取消後再確認、走到唯一的 end event，算違規」。
- **Positive example**：訂好 F/T/H 後直接確認，結束時三項都是 Conf，且 `active = {ref}`。
- **Negative example**：CE-1。訂好 → 取消 → 補償完成 → 確認 → Ended，但三項都是 Canceled。
- **Boundaries**：只在 `phase = Ended` 時檢查；只需要 hotel 的情境也要成立。

### BR2：取消並補償完成後，沒有孤兒訂位
- **Statement**：使用者曾選取消，且流程已回到 Review 或已結束時，所有供應商都沒有有效訂位。
- **Source**：REPORT §3 BR2；Q14(a)。
- **Positive**：CE-1 走到第 19 步時，`active` 全部為空。
- **Negative**：CE-2（重複訂的第一張票還在）、CE-5（真正的 flight 訂位還在）。
- **Boundaries**：補償進行中（Compensating）不檢查；第二次取消（no-op）之後也要成立。

### BR3：不訂未被要求的項目
- **Statement**：任何項目只要曾在供應商端建立過訂位，該項目一定是使用者要求的。
- **Source**：REPORT §3 BR3。
- **Positive**：只需要 hotel 時，F/T 的 `everBooked` 永遠為空。
- **Negative（假想）**：`flightNeeded = false`，供應商卻出現 flight 訂位。
- **Boundaries**：任何時刻、任何設定都要成立。

### BR4：每個項目最多一筆有效訂位
- **Statement**：任何時刻，每個項目在供應商端的有效訂位數 ≤ 1。
- **Source**：REPORT §3 BR4。
- **Positive**：正常訂一次後，`|active| = 1`。
- **Negative**：CE-2，`active(T) = {1,2}`。
- **Boundaries**：任何時刻都檢查。

### BR5：畫面顯示等於供應商的真實狀態
- **Statement**：在 Review（使用者看得到表單）時，每個項目：若狀態為 Confirmed，供應商端剛好持有流程記錄的 ref；否則供應商端沒有訂位。
- **Source**：REPORT §3 BR5；Q13(a)。
- **Positive**：happy path 的 Review 時點。
- **Negative**：CE-5，畫面顯示 `F:Conf/2`，供應商端是 `F{1}`。
- **Boundaries**：只在 `phase = Review` 時檢查。

### BR6：取消動作針對真正建立過的訂位
- **Statement**：任何項目狀態為 Canceled 時，流程記錄的 ref 一定曾在該供應商建立過。
- **Source**：REPORT §3 BR6。
- **Positive**：CE-1 取消後，ref 都在 `everBooked` 中。
- **Negative**：CE-5，取消的 ref 2 從沒訂過。
- **Boundaries**：任何時刻都檢查。

### BR7：結束時全有或全無
- **Statement**：流程結束時，若不是「完整成立」（同 BR1 的定義），就必須是「所有供應商都沒有有效訂位」。
- **Source**：REPORT §3 BR7。
- **Positive**：CE-1 的結束狀態（全無）。
- **Negative**：CE-2、CE-5 結束時仍殘留部分訂位。
- **Boundaries**：只在 `phase = Ended` 時檢查。

### BR8：不會永久卡住且同時佔住訂位
- **Statement**：不存在這樣的狀態：流程停在 Booking 或 Compensating、有一個待處理且尚未執行副作用的 task，其供應商永久拒絕處理，而且仍有任何有效訂位。另外要證明（L4(b)）：一旦進入這種狀態，之後所有可達狀態都維持同樣的處境，phase 也不會改變。
- **Source**：REPORT §3 BR8；Q6、Q12。
- **Positive**：沒有永久故障時，不會出現這種狀態。
- **Negative**：CE-3（flight 或 hotel 永久故障，train 被佔住）、CE-4（hotel 拒絕取消）。
- **Boundaries**：暫時失敗不算違規。

## 系統假設（轉錄自 Quint Q1–Q14，作為允許的抽象）

| # | 決策 |
|---|---|
| Q1 | 只建模 V3 + 3 個 worker |
| Q2 | 加入抽象的供應商 ledger |
| Q3 | 故障：重送 + 訂位失敗 + 取消失敗，各用一個開關 |
| Q7 | 共享狀態（engine 的 external-task 表）；Lean 中以單一 transition relation 表示 |
| Q8 | 1 個 process instance |
| Q9 | Flight 的雙 UUID 當成真實 bug，用 `flightRefBug` 開關控制 |
| Q12 | 失敗分為暫時與永久；永久故障在 init 時選定，之後不變 |
| R1 | **`redelivery` 的定義**：副作用（呼叫供應商）執行之後的**任何**重新執行，包括 worker crash、lock 逾時、`complete()` 失敗（client 會吞錯誤；例如 parallel join 的 OptimisticLockingException）、副作用之後才拋例外。因此所有 `redelivery = false` 的結論，都以「副作用後絕不重新執行」為前提 |
| R2 | **`bookFailure`／`cancelFailure` 的定義**：handler 在呼叫供應商**之前**就乾淨地失敗（拒絕或拋例外），沒有任何副作用。副作用之後的失敗歸入 `redelivery`（R1） |

## Grilling log（Lean 專屬決策）

| # | 問題 | Owner 答案 | 日期 |
|---|---|---|---|
| L1 | 證明範圍 | (b) 反例存在性 + ✓ 格的全稱定理（也就是歸因） | 2026-10-24 |
| L2 | 模型來源 | (a) 從 BPMN/JS 獨立建模，再與 Quint 對照 | 2026-10-24 |
| L3 | 重播 Quint trace | (b) 22 條模擬器 trace 全部由 kernel 檢查 | 2026-10-24 |
| L4 | BR8 | (b) 加證永久性 | 2026-10-24 |
| L5 | 規則轉錄 | 原樣轉錄 | 2026-10-24 |
| L6 | 簽核與審查 | 照流程：業務語言簽核 + 全新 context 的 subagent 對抗審查 | 2026-10-24 |
| L7 | Lean 與 Quint 不一致時 | (a) 只列為發現，不改 Quint 檔案 | 2026-10-24 |
| L8 | 產出 | `specs/lean/` 的配置照提案；REPORT 用繁體中文 | 2026-10-24 |
| R1 | 對抗審查 #1：`complete()` 失敗後重新執行 | (a) 敘述不變；擴大 `redelivery` 的定義；報告新增 CE-6（join 衝突） | 2026-10-24 |
| R2 | 對抗審查 #2：「失敗」的定義 | 接受「副作用前乾淨失敗」 | 2026-10-24 |
| R3 | 對抗審查 #4：C4 的定位 | (a) 只修業務文字，不當作 liveness | 2026-10-24 |
| R4 | 對抗審查 #5：B1 的業務文字 | 接受修正版 | 2026-10-24 |
| R5 | 簽核 | 簽核 | 2026-10-24 |

## Open questions

（無）

## Sign-off

| 日期 | 簽核內容 | 結果 |
|---|---|---|
| 2026-10-24 | phase 2 定理敘述（業務語言版本，見 MODEL-MAP.md，含 R1–R4 修正） | **owner 簽核** |

## Change policy

程式碼變動導致定理失敗時，**絕不為了變綠而弱化已確認的定理**。停下來，回報是哪條規則或敘述改變，並取得 owner 重新確認。
