# Book Holiday Saga：Lean 4 形式化驗證報告

> **問題**：[specs/quint/REPORT.md](../quint/REPORT.md) 中的反例是否正確？
> **方法**：Kadie 的 nine rules（lean-formal-verification skill）。步驟依序為：轉錄 owner 已確認的規則 → 從 BPMN/JS 獨立建模 → 先寫定理敘述 → 對抗式審查 → owner 簽核 → 證明 → guardrail 與 axiom 稽核。
> **工具**：Lean 4.35.0，只用 core（沒有 Mathlib）。全部 36 條 headline theorem 都由 kernel 檢查，零 `sorry`、沒有任何自訂 axiom、沒有 `native_decide`。
> **日期**：2026-10-24。原始碼 commit `4b08b40`（工作區有尚未 commit 的 `specs/`）。

---

## 1. 結論

| 問題 | 答案 | 依據（定理） |
|---|---|---|
| Quint 找到的 22 個反例是真的嗎？ | **是，22/22**。每條模擬器 trace 的每一步都是 Lean 模型允許的轉移，每一步之後兩個模型的狀態**逐欄位一致**，最後一個狀態也確實違反所標示的規則 | `quint_<instance>_<BRk>` × 22（`Specs/Traces.lean`） |
| 5 類反例（CE-1…CE-5）是不是只在特定設定才成立？ | **不是**。每一類在「**任何**帶有觸發假設的設定」下都可達（16 種設定組合全部涵蓋），不只限於 Quint 的那個 instance | `ce1_…` – `ce5_…` |
| Quint 的 26 個 ✓（抽樣 10000 條 trace 都沒找到反例）是真的成立嗎？ | **是**。改成對所有可達狀態證明成立，而且是在「排除責任故障」的最弱假設下 | `br3_always`、`br4_of_no_redelivery`、`br6_of_no_flight_bug`、`br8_of_no_failures`、`br2/5/7_of_reliable` |
| 整張 6×8 矩陣呢？ | **48 格全部是定理**（22 個 ✗ = `Violable`、26 個 ✓ = `Invariant`） | `quint_matrix` |
| Quint 宣稱的「每類違規只能歸因到單一假設」對嗎？ | **對，而且證明的是「若且唯若」**（16 種設定組合，每格要嘛 `Violable` 要嘛 `Invariant`）：BR4 ✗ ⇔ 有重新執行；BR6 ✗ ⇔ Flight bug；BR8 ✗ ⇔ 有永久故障；BR2/5/7 ✗ ⇔ 有重新執行或 Flight bug；BR1 在所有設定都 ✗；BR3 在所有設定都 ✓ | group A + C |
| BR8 的「卡住」是永久的嗎？ | **是**。一旦卡住且佔住訂位，之後所有可達狀態的 phase 都不會改變，而且至少有一筆訂位一直被佔住 | `stuck_is_permanent` |
| 有沒有 Quint 沒發現的問題？ | **有一個：CE-6**（parallel join 衝突導致重複訂位，見 §4），是對抗式審查發現的 | `Examples.lean` 的 CE-6 witness |

**一句話**：Quint 的反例與歸因**全部正確**，而且 Lean 把抽樣結果升級成了證明。但 `redelivery = false` 那幾列的 ✓，前提是「副作用之後絕不重新執行」（R1）；V3 的 parallel join 在實務上會打破這個前提（CE-6）。

---

## 2. 驗證主張的範圍（請照這個範圍理解結論）

- Lean 證明的是**模型**的性質。模型與程式碼的對應是**人工審查**的結果，記錄在 [MODEL-MAP.md](MODEL-MAP.md)：`file:line` 對照、abstraction ledger、bounded port audit，以及一次獨立的對抗式審查。Lean 本身從沒讀過 JS 或 BPMN。
- **系統假設**（owner 已確認，[RULES.md](RULES.md)）：
  - 只有 1 個 process instance，不涉及時間。
  - **R1**：`redelivery` 指副作用之後的任何重新執行，包括 crash、lock 逾時、`complete()` 失敗、副作用後才拋例外。
  - **R2**：`bookFailure`／`cancelFailure` 指副作用之前就乾淨地失敗。
- **模型的獨立性有限**（對抗審查 #7）：Lean 模型雖然是從原始碼重新推導的，但欄位結構與 Quint 幾乎一一對應。所以「22 條 trace 逐步一致」主要證明兩個模型**彼此一致**；兩者共有的抽象缺口（R1/R2，以及 zombie handler）只能靠人工審查找出來，而這次審查確實找到了。

---

## 3. Headline theorems 與證明狀態

| # | 定理 | 業務語言（owner 已簽核） | 狀態 | Axioms |
|---|---|---|---|---|
| A1 | `ce1_confirm_after_cancel` | 在**任何**設定下，取消並補償完成後再按確認，流程會走到唯一的 end event，但旅程並沒有成立（BR1） | ✅ | propext, Quot.sound |
| A2 | `ce2_redelivery_duplicate` | 只要可能重新執行，就走得到違反 BR4、BR5、BR2、BR7 的狀態 | ✅ | propext, Quot.sound |
| A3 | `ce3_book_failure_stuck` | 只要訂位可能失敗，就走得到「卡在訂位階段，同時佔住另一筆訂位」（BR8） | ✅ | propext, Quot.sound |
| A4 | `ce4_cancel_failure_stuck` | 只要取消可能失敗，就走得到「補償卡住，訂位無法釋放」（BR8） | ✅ | propext, Quot.sound |
| A5 | `ce5_flight_ref_mismatch` | Flight 雙 UUID bug 單獨存在就足以違反 BR5、BR6、BR2、BR7 | ✅ | propext, Quot.sound |
| B1 | `stuck_is_permanent` | 卡住之後，phase 永遠不變，而且至少一筆訂位一直被佔住 | ✅ | 標準三個 |
| C1 | `br3_always` | 任何設定下都不會訂未被要求的項目 | ✅ | 標準三個 |
| C2 | `br4_of_no_redelivery` | 副作用後不重新執行，每項最多一筆有效訂位 | ✅ | 標準三個 |
| C3 | `br6_of_no_flight_bug` | 修好 Flight bug 後，取消一定針對真的訂位 | ✅ | 標準三個 |
| C4 | `br8_of_no_failures` | 沒有永久故障就不會出現 BR8 定義的卡住狀態（依定義成立，**不是** liveness） | ✅ | 標準三個 |
| C5–C7 | `br2/5/7_of_reliable` | 不重新執行、且沒有 Flight bug 時：補償後沒有孤兒訂位、表單顯示正確、結束時全有或全無 | ✅ | 標準三個 |
| D1 | `quint_matrix` | Quint 矩陣 48 格全部是定理 | ✅ | 標準三個 |
| E1–E22 | `quint_<inst>_<BRk>` | 22 條 Quint trace 逐步重播，與 Lean 一致，且違反所標示的規則 | ✅ | propext, Quot.sound |

「標準三個」指 `propext`、`Classical.choice`、`Quot.sound`，都在 allowlist 內。完整的 axiom 輸出見 `verify-result.json` / `lake env lean Audit.lean`。

### 證明架構

- `Specs/Lemmas.lean`：
  - `step_inv`：反演引理，列出 9 種轉移形狀與各自的 guard。
  - `Struct`：11 條結構 invariant，**在所有設定下都成立**。例如：book task 只存在於 Booking、cancel task 只存在於 Compensating、join 的簿記、被佔住的訂位不會被拒絕取消的供應商釋放。
  - 各規則專用的 invariant：`NoDown`（BR8）、`Q`（BR4：副作用至多一次）、`R`（BR6：ref 一定在 `ever` 中），以及最大的 `Exact`（BR2/5/7：在每個 phase，精確描述每個項目在供應商端持有什麼）。
- `Specs/Reachability.lean`：把上述 invariant 提升到「所有可達狀態」；`stuck_step` 是單步的卡死保持引理；`violable_of_replay` 把具體的事件序列轉成存在性證明。
- 存在性證明（A、E）：先對 `Config` 的 4 個 Bool 做 case split，每個 case 用 kernel `decide` 執行具體的 replay。最小 witness 在 `Specs/Scenarios.lean`；trace 由 `gen_traces.py` 從 Quint 的 ITF 自動產生，並 assert ITF 模組前綴與檔名一致。

---

## 4. 新發現：CE-6，parallel join 衝突導致重複訂位（Quint 沒有發現）

**來源**：對抗式審查 #1。我讀了原始碼確認了以下兩點：
- [TaskService.js 2.3.1 `complete()`](https://unpkg.com/camunda-external-task-client-js@2.3.1/lib/TaskService.js) 會 catch 錯誤，只 `emit("complete:error")`，不會往外拋。
- [Camunda 7.21 Transactions in Processes](https://docs.camunda.org/manual/7.21/user-guide/process-engine/transactions-in-processes/) 說明：沒有 async 邊界時，例外會讓交易回滾到上一個 wait state；並行到達 join 時會發生 optimistic locking 衝突。

**情境**（需要 flight 和 train 時）：
1. Book Flight 與 Book Train 的 worker 幾乎同時呼叫 `complete()`。兩筆交易都推進到 parallel join `Gateway_1hfufm4`（[V3:159](../../Models/BookHolidaySagaPatternV3.bpmn#L159)），互相衝突，其中一筆因 OptimisticLockingException 而**回滾**。
2. JS client 吞掉這個錯誤。task 維持 locked，50 秒後被重新 fetch，handler **用新的 UUID 再訂一次**。
3. 結果和 CE-2 一樣：重複訂位（BR4），之後的 BR5/BR2/BR7 也會跟著違反。**而且完全不需要任何基礎設施故障。**

**Lean 中的呈現**：失敗的 `complete()` 就是「副作用之後的 `lockExpire`」（R1）。`Examples.lean` 用 kernel 檢查了兩件事：
- 在 `idealCfg` 下，`ce6Events` 不可執行。
- 在 `redeliveryCfg` 下，同一個事件序列可執行且違反 BR4。

所以，Quint 與 Lean 中 `ideal` 的 ✓ 都**以 R1 為前提**。對 V3 而言，這個前提在 flight 與 train 都需要時並不成立。

**根因與修正**：
- V2 在三個 Book task 上用的是 `camunda:asyncAfter`。task 完成的交易因此停在 activity 之後，join 改由 job executor 執行，遇到 OLE 會自動重試，不會回滾 external task 的完成。V3 改成 `asyncBefore`，反而引入了這個問題。
- 建議：
  - Book Flight／Book Train 恢復 `asyncAfter="true"`，或在 join 前加上 async 邊界。
  - 搭配 Quint 報告 P1 的冪等鍵：同一個 `processInstanceId + activityId` 重複訂位時，回傳原本那筆。

---

## 5. 其他審查發現的處理

| # | 發現 | 處理 |
|---|---|---|
| 2 | 「失敗」只代表副作用前就乾淨地失敗 | owner 決定 R2，寫進 RULES.md |
| 3 | zombie handler（三個 worker 共用 `workerId`）可能在 task 完成後、甚至補償或結束後才訂位，Lean 無法表達 | 列入 Not covered；受影響的規則在 `redelivery` 下本來就是 ✗，但實際違規比模型呈現的更嚴重 |
| 4 | C4 依定義成立 | owner 決定 R3：業務文字明確說明它不是 liveness。審查者的窮舉 BFS（沒有 redelivery 的 8 種設定都跑到飽和，沒有 Ended 以外的死結）只作為佐證 |
| 5 | B1 的業務文字寫得太強 | owner 決定 R4：已修正 |
| 6 | list 與 set 的語意差異 | `holdsExactly` 本身就是集合語意；BR4 的 `length` 比 `size` 更強；✗ 的 witness 都是具體的不重複清單 |
| 7 | 模型的獨立性弱；`gen_traces` 從檔名取設定 | 已在 §2 誠實說明；generator 現在會 assert |
| 8 | MODEL-MAP 的行號和敘述錯誤 | 已修正 |

---

## 6. Guardrail 與稽核（`verify-lean.sh`，Rule 3/4）

```
SUMMARY
  build          : PASS      (rm -rf .lake && lake build，從零開始)
  direct compile : PASS      (Specs/Proofs.lean)
  coverage       : PASS      (headline-theorems.txt 36/36 都有 #print axioms)
  guardrails     : PASS      (11 個檔案：無 sorry / axiom / bodyless opaque / native_decide / unsafe / extern)
  axioms         : PASS      (只有 propext, Classical.choice, Quot.sound)
  RESULT         : PASS
```

- Dashboard：baseline 為 3128 行 code，Rule-2 清理後是 3088 行（−40），沒有任何指標退步（見 [MODEL-MAP.md](MODEL-MAP.md)）。
- Statement stability：phase 2 凍結的 theorem 簽名，在 phase 4 後以腳本比對，**逐字相同**。
- Non-vacuity：每條有前提的 headline 在 `Examples.lean` 都有 kernel 檢查過的 witness。

### Verification gate（skill 規定的 7 項）

| 項目 | 狀態 |
|---|---|
| RULES.md 已確認，含出處、驗收標準、反例 | ✅ |
| MODEL-MAP 含 `file:line`、ledger、Not covered | ✅ |
| 每條 headline 都有規則、snapshot、witness、審查 | ✅ |
| Statement stability | ✅ |
| 腳本全綠（build、compile、scan、axiom、completeness） | ✅ |
| Dashboard baseline 與目前數值 | ✅ |
| Owner 簽核頂層敘述 | ✅（2026-10-24，R5） |

附註：對抗式審查是由**全新 context** 的 subagent 執行，但與作者屬於同一個 model family，不是 skill 建議的「不同 model」。

**判定**：在 RULES.md 與 MODEL-MAP.md 列出的假設與範圍內，**verified**。

---

## 7. 沒有涵蓋的部分

- **時間相關的 liveness**：使用者一直不回應時訂位被無限期佔住；lock 過期的實際時機。C4 不是 liveness 保證。
- **zombie handler** 的完整行為；engine 自身 crash、DB 隔離與交易細節；多個 instance；REST 啟動時缺少變數。
- **CE-6 的觸發機率**：Lean 只證明「一旦 `complete()` 失敗就會重複訂位」，沒有證明 OLE 一定會發生。後者依據 Camunda 文件與審查者的分析，**沒有在實際 engine 上重現**。
- 真實供應商 API 的語意（ledger 是抽象）；V1、V2、BookHoliday.bpmn。

---

## 8. 給 Quint 報告的回饋（L7：只記錄，沒有修改 Quint 檔案）

1. REPORT §4 的 `ideal` 說明「基礎設施完美」應改為「**副作用後絕不重新執行**」，並註明 CE-6 會在 V3 打破這個前提。
2. REPORT §8 的優先順序建議新增：**P0／P1：Book Flight／Train 恢復 `asyncAfter`**（CE-6），與冪等鍵一起處理。
3. Quint 模型可以考慮讓 lock 過期也能發生在副作用之前（Lean 是超集），以及加入 `completeFails` 事件。這些都需要 owner 決定後才改。

---

## 9. 重現方式

```sh
cd specs/lean
export PATH="$HOME/.elan/bin:$PATH"
rm -rf .lake && lake build                 # 約 3.5 分鐘（Specs/Lemmas.lean 佔大部分）
lake env lean Audit.lean                   # 36 條 #print axioms
bash ~/.agents/skills/lean-formal-verification/scripts/verify-lean.sh \
  --dir specs/lean --main Specs/Proofs.lean --audit Audit.lean \
  --theorems headline-theorems.txt --baseline specs/lean/metrics-baseline.txt   # 在 repo 根目錄執行
python3 gen_traces.py --prove > Specs/Traces.lean   # Quint traces 更新後重新產生
```

| 檔案 | 內容 |
|---|---|
| [RULES.md](RULES.md) | 規則 BR1–BR8、假設 Q*/R1/R2、訪談與簽核紀錄 |
| [MODEL-MAP.md](MODEL-MAP.md) | 對照、snapshot、業務語言版本、ledger、port audit、dashboard、審查紀錄 |
| [Specs/Model.lean](Specs/Model.lean) | 狀態與 transition relation |
| [Specs/Rules.lean](Specs/Rules.lean) | BR1–BR8 |
| [Specs/Proofs.lean](Specs/Proofs.lean) | headline theorems A–D |
| [Specs/Traces.lean](Specs/Traces.lean) | 22 條 Quint trace 與 E 組定理（自動產生） |
| [Specs/Lemmas.lean](Specs/Lemmas.lean) | 反演引理與各 invariant |
| [Specs/Reachability.lean](Specs/Reachability.lean) | 可達性推論與卡死保持 |
| [Specs/Scenarios.lean](Specs/Scenarios.lean) | 最小反例情境 |
| [Specs/Examples.lean](Specs/Examples.lean) | non-vacuity witness 與 CE-6 |
