// WanderSaga Frontend Controller with Edge WebSocket & Fallback SSE

let currentBookingId = null;
let eventSource = null;
let activeWs = null;

// DOM Elements
const form = document.getElementById('booking-form');
const submitBtn = document.getElementById('submit-btn');
const bookingIdEl = document.getElementById('current-booking-id');
const statusPill = document.getElementById('overall-status-pill');
const activeStepBadge = document.getElementById('active-step-badge');
const decisionPanel = document.getElementById('decision-panel');
const btnConfirm = document.getElementById('btn-confirm');
const btnCancel = document.getElementById('btn-cancel');
const logConsole = document.getElementById('log-console');
const clearLogsBtn = document.getElementById('clear-logs-btn');

// Checkbox elements
const needFlightCheck = document.getElementById('need-flight');
const needTrainCheck = document.getElementById('need-train');

// Service card elements
const cards = {
  flight: {
    el: document.getElementById('card-flight'),
    status: document.getElementById('status-flight'),
    valStatus: document.getElementById('val-flight-status'),
    valId: document.getElementById('val-flight-id'),
  },
  train: {
    el: document.getElementById('card-train'),
    status: document.getElementById('status-train'),
    valStatus: document.getElementById('val-train-status'),
    valId: document.getElementById('val-train-id'),
  },
  hotel: {
    el: document.getElementById('card-hotel'),
    status: document.getElementById('status-hotel'),
    valStatus: document.getElementById('val-hotel-status'),
    valId: document.getElementById('val-hotel-id'),
  },
};

// Log appending helper
function addLog(msg, type = 'info') {
  const line = document.createElement('div');
  line.className = `log-line ${type}`;

  const time = new Date().toLocaleTimeString('zh-TW', { hour12: false });
  line.innerHTML = `
    <span class="log-time">[${time}]</span>
    <span class="log-msg">${msg}</span>
  `;
  logConsole.appendChild(line);
  logConsole.scrollTop = logConsole.scrollHeight;
}

clearLogsBtn.addEventListener('click', () => {
  logConsole.innerHTML = '';
});

// Presets
document.getElementById('preset-all').addEventListener('click', () => {
  needFlightCheck.checked = true;
  needTrainCheck.checked = true;
  addLog('已套用預設情境：全包自由行 (機票 + 火車 + 飯店)', 'info');
});

document.getElementById('preset-train-only').addEventListener('click', () => {
  needFlightCheck.checked = false;
  needTrainCheck.checked = true;
  addLog('已套用預設情境：國內鐵道漫遊 (火車 + 飯店，無機票)', 'info');
});

document.getElementById('preset-flight-only').addEventListener('click', () => {
  needFlightCheck.checked = true;
  needTrainCheck.checked = false;
  addLog('已套用預設情境：商務直飛客 (機票 + 飯店，無火車)', 'info');
});

// Reset UI state for a new booking
function resetUI() {
  decisionPanel.classList.remove('show');

  for (const key of ['flight', 'train', 'hotel']) {
    cards[key].el.className = 'service-card';
    cards[key].status.textContent = '等待處理';
    cards[key].valStatus.textContent = '-';
    cards[key].valId.textContent = '-';
  }

  statusPill.className = 'status-pill running';
  statusPill.textContent = '流程進行中...';
  activeStepBadge.textContent = '初始化 BPMN 引擎...';
}

// Form Submit Handler
form.addEventListener('submit', (e) => {
  e.preventDefault();

  if (eventSource) {
    eventSource.close();
  }
  if (activeWs) {
    activeWs.close();
    activeWs = null;
  }

  resetUI();
  submitBtn.disabled = true;

  const payload = {
    passengerName: document.getElementById('passenger-name').value,
    destination: document.getElementById('destination').value,
    flightNeeded: needFlightCheck.checked,
    trainTicketNeeded: needTrainCheck.checked,
  };

  // Mark bypassed cards immediately
  if (!payload.flightNeeded) cards.flight.el.classList.add('bypassed');
  if (!payload.trainTicketNeeded) cards.train.el.classList.add('bypassed');

  addLog(`送出訂票請求: ${payload.passengerName} ➔ ${payload.destination}`, 'info');

  // Try WebSocket first (recommended for Cloudflare stateless edge sessions)
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const wsUrl = `${protocol}//${location.host}/api/ws`;

  let usedWs = false;
  try {
    const ws = new WebSocket(wsUrl);
    activeWs = ws;

    ws.onopen = () => {
      usedWs = true;
      ws.send(JSON.stringify({ action: 'start', payload }));
    };

    ws.onmessage = (msgEvent) => {
      const ev = JSON.parse(msgEvent.data);
      if (ev.type === 'booking:created') {
        currentBookingId = ev.bookingId;
        bookingIdEl.textContent = currentBookingId;
        addLog(`流程已實例化！Instance ID: ${currentBookingId} (Edge Session)`, 'success');
        return;
      }
      handleWorkflowEvent(ev);
    };

    ws.onerror = () => {
      if (!usedWs) {
        activeWs = null;
        startHttpSaga(payload);
      }
    };
  } catch {
    startHttpSaga(payload);
  }
});

// Fallback HTTP POST + SSE Runner
async function startHttpSaga(payload) {
  try {
    const res = await fetch('/api/bookings', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });

    const data = await res.json();
    currentBookingId = data.bookingId;
    bookingIdEl.textContent = currentBookingId;
    addLog(`流程已實例化！Instance ID: ${currentBookingId}`, 'success');

    // Connect Server-Sent Events
    eventSource = new EventSource(`/api/bookings/${currentBookingId}/events`);
    eventSource.onmessage = (e) => {
      handleWorkflowEvent(JSON.parse(e.data));
    };
    eventSource.onerror = () => {
      if (eventSource) eventSource.close();
    };
  } catch (err) {
    addLog(`啟動失敗: ${err.message}`, 'error');
    submitBtn.disabled = false;
    statusPill.className = 'status-pill canceled';
    statusPill.textContent = '啟動錯誤';
  }
}

// Unified Workflow Event Handler
function handleWorkflowEvent(ev) {
  switch (ev.type) {
    case 'element:entered':
      const name = ev.elementName ? `"${ev.elementName}"` : ev.elementId;
      activeStepBadge.textContent = `${name} (${ev.elementId})`;
      addLog(`📍 BPMN 進入節點: ${name}`, 'bpmn');
      break;

    case 'worker:start':
      handleWorkerStart(ev.topic);
      break;

    case 'worker:done':
      handleWorkerDone(ev.topic, ev.variables);
      break;

    case 'user:waiting':
      decisionPanel.classList.add('show');
      statusPill.textContent = '等待用戶核對確認...';
      addLog(`👤 流程停駐於 User Task (Activity_034u6ma) - 請用戶做成決策`, 'warning');
      break;

    case 'compensation:start':
      handleCompensationStart(ev.topic);
      break;

    case 'compensation:done':
      handleCompensationDone(ev.topic, ev.variables);
      break;

    case 'process:completed':
      handleProcessCompleted(ev.endEventId, ev.variables);
      break;

    default:
      break;
  }
}

// Worker UI Handlers
function handleWorkerStart(topic) {
  if (topic === 'BookFlight') {
    cards.flight.el.classList.add('active');
    cards.flight.status.textContent = '🛫 航空公司開票中...';
    addLog(`[Worker: BookFlight] 正在向航空系統連線訂位...`, 'info');
  } else if (topic === 'BookTrain') {
    cards.train.el.classList.add('active');
    cards.train.status.textContent = '🚆 鐵路局劃位中...';
    addLog(`[Worker: BookTrain] 正在向鐵路局請求座位...`, 'info');
  } else if (topic === 'BookHotel') {
    cards.hotel.el.classList.add('active');
    cards.hotel.status.textContent = '🏨 飯店保留房型中...';
    addLog(`[Worker: BookHotel] 正在向渡假飯店保留客房...`, 'info');
  }
}

function handleWorkerDone(topic, vars) {
  if (topic === 'BookFlight') {
    cards.flight.el.className = 'service-card confirmed';
    cards.flight.status.textContent = '✅ 機票已開立';
    cards.flight.valStatus.textContent = vars.FlightBookingStatus;
    cards.flight.valId.textContent = vars.FlightBookingID;
    addLog(`[Worker: BookFlight] 開票完成！票號: ${vars.FlightBookingID}`, 'success');
  } else if (topic === 'BookTrain') {
    cards.train.el.className = 'service-card confirmed';
    cards.train.status.textContent = '✅ 車票已劃位';
    cards.train.valStatus.textContent = vars.TrainBookingStatus;
    cards.train.valId.textContent = vars.TrainBookingID;
    addLog(`[Worker: BookTrain] 劃位完成！票號: ${vars.TrainBookingID}`, 'success');
  } else if (topic === 'BookHotel') {
    cards.hotel.el.className = 'service-card confirmed';
    cards.hotel.status.textContent = '✅ 飯店已保留';
    cards.hotel.valStatus.textContent = vars.HotelBookingStatus;
    cards.hotel.valId.textContent = vars.HotelBookingID;
    addLog(`[Worker: BookHotel] 訂房完成！確認碼: ${vars.HotelBookingID}`, 'success');
  }
}

function handleCompensationStart(topic) {
  addLog(`🔄 [Saga 補償開始] 執行 ${topic}...`, 'warning');
  if (topic === 'CancelHotelBooking') {
    cards.hotel.el.className = 'service-card active';
    cards.hotel.status.textContent = '🔄 向飯店退訂中...';
  } else if (topic === 'CancelFlightBooking') {
    cards.flight.el.className = 'service-card active';
    cards.flight.status.textContent = '🔄 向航空公司辦理全額退票...';
  } else if (topic === 'CancelTrainBooking') {
    cards.train.el.className = 'service-card active';
    cards.train.status.textContent = '🔄 向鐵路局退票中...';
  }
}

function handleCompensationDone(topic, vars) {
  if (topic === 'CancelHotelBooking') {
    cards.hotel.el.className = 'service-card compensated';
    cards.hotel.status.textContent = '❌ 已退房退費';
    cards.hotel.valStatus.textContent = vars.HotelBookingStatus;
    addLog(`[Saga 補償完成] 飯店訂單已全額撤銷！`, 'error');
  } else if (topic === 'CancelFlightBooking') {
    cards.flight.el.className = 'service-card compensated';
    cards.flight.status.textContent = '❌ 已退票退款';
    cards.flight.valStatus.textContent = vars.FlightBookingStatus;
    addLog(`[Saga 補償完成] 機票已全額刷退！`, 'error');
  } else if (topic === 'CancelTrainBooking') {
    cards.train.el.className = 'service-card compensated';
    cards.train.status.textContent = '❌ 已退票取消';
    cards.train.valStatus.textContent = vars.TrainBookingStatus;
    addLog(`[Saga 補償完成] 火車票已完成撤銷！`, 'error');
  }
}

function handleProcessCompleted(endEventId, vars) {
  if (endEventId === 'Event_07xntzc') {
    statusPill.className = 'status-pill completed';
    statusPill.textContent = '✅ 假期訂位成功！';
    activeStepBadge.textContent = 'Trip completed (Event_07xntzc)';
    addLog('🎉 恭喜！整個旅遊訂票 Saga 流程已順利以「確認出發」結束。', 'success');
  } else {
    statusPill.className = 'status-pill canceled';
    statusPill.textContent = '🛑 假期已取消 (全額退費)';
    activeStepBadge.textContent = 'Trip Canceled (Event_0b7jeb0)';
    addLog('🛑 Saga 補償全部執行完畢，流程已安全以「取消」結束。', 'warning');
  }

  submitBtn.disabled = false;
  if (eventSource) eventSource.close();
  if (activeWs) {
    activeWs.close();
    activeWs = null;
  }
}

// User Decision Actions
btnConfirm.addEventListener('click', async () => {
  decisionPanel.classList.remove('show');
  addLog('用戶做出決策：確認出發 (confirm = true)', 'info');
  await sendDecision(true);
});

btnCancel.addEventListener('click', async () => {
  decisionPanel.classList.remove('show');
  addLog('用戶做出決策：取消整筆假期 (confirm = false) ➔ 啟動 Saga 逆向補償！', 'warning');
  await sendDecision(false);
});

async function sendDecision(confirm) {
  if (activeWs && activeWs.readyState === WebSocket.OPEN) {
    activeWs.send(JSON.stringify({ action: 'decision', confirm }));
  } else {
    try {
      await fetch(`/api/bookings/${currentBookingId}/decision`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ confirm }),
      });
    } catch (err) {
      addLog(`決策提交失敗: ${err.message}`, 'error');
    }
  }
}
