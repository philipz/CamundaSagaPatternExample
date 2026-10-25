#!/usr/bin/env node

import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadBpmnForBpmnKit } from './tests/helpers/bpmnkit.mjs';

const REPO_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)));
const V3_PATH = path.join(REPO_ROOT, 'Models', 'BookHolidaySagaPatternV3.bpmn');

// Parse CLI flags
const args = process.argv.slice(2);
const shouldCancel = args.includes('--cancel') || args.includes('-c');
const skipFlight = args.includes('--no-flight');
const skipTrain = args.includes('--no-train');

const flightNeeded = !skipFlight;
const trainTicketNeeded = !skipTrain;
const confirm = !shouldCancel;

console.log('='.repeat(60));
console.log('✈️  Camunda Saga Pattern with @bpmnkit/engine (Local Runner)');
console.log('='.repeat(60));
console.log(`📋 執行情境: ${confirm ? '✅ 正向確認訂位 (Happy Path)' : '❌ 取消假期觸發 Saga 補償 (Compensation)'}`);
console.log(`   - 預訂機票 (flightNeeded): ${flightNeeded ? '是' : '否'}`);
console.log(`   - 預訂火車 (trainTicketNeeded): ${trainTicketNeeded ? '是' : '否'}`);
console.log(`   - 預訂飯店 (Hotel): 是 (必要項目)`);
console.log(`   - 確認出遊 (confirm): ${confirm ? '是' : '否 (將觸發逆向取消)'}`);
console.log('='.repeat(60));

const { engine, processId } = loadBpmnForBpmnKit(V3_PATH);

// Helper for sleep to simulate realistic network delay
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Register external workers
engine.registerJobWorker('BookFlight', async (job) => {
  console.log('   🛫 [Worker: BookFlight] 正在向航空公司請求訂票...');
  await delay(150);
  const flightId = 'FL-' + Math.random().toString(36).substring(2, 8).toUpperCase();
  console.log(`   ✅ [Worker: BookFlight] 訂票成功! 機票號: ${flightId}`);
  job.complete({
    FlightBookingStatus: 'Confirmed',
    FlightBookingID: flightId,
  });
});

engine.registerJobWorker('BookTrain', async (job) => {
  console.log('   🚆 [Worker: BookTrain] 正在向鐵路局請求劃位...');
  await delay(120);
  const trainId = 'TR-' + Math.random().toString(36).substring(2, 8).toUpperCase();
  console.log(`   ✅ [Worker: BookTrain] 劃位成功! 車票號: ${trainId}`);
  job.complete({
    TrainBookingStatus: 'Confirmed',
    TrainBookingID: trainId,
  });
});

engine.registerJobWorker('BookHotel', async (job) => {
  console.log('   🏨 [Worker: BookHotel] 正在向飯店系統保留房間...');
  await delay(180);
  const hotelId = 'HT-' + Math.random().toString(36).substring(2, 8).toUpperCase();
  console.log(`   ✅ [Worker: BookHotel] 訂房成功! 訂單號: ${hotelId}`);
  job.complete({
    HotelBookingStatus: 'Confirmed',
    HotelBookingID: hotelId,
  });
});

// Compensation workers
engine.registerJobWorker('CancelFlightBooking', async (job) => {
  console.log('   🔄 [Compensation: CancelFlightBooking] 正在向航空公司申請全額退票...');
  await delay(100);
  console.log('   ❌ [Compensation: CancelFlightBooking] 機票已成功取消並退款！');
  job.complete({ FlightBookingStatus: 'Canceled' });
});

engine.registerJobWorker('CancelTrainBooking', async (job) => {
  console.log('   🔄 [Compensation: CancelTrainBooking] 正在向鐵路局退票...');
  await delay(100);
  console.log('   ❌ [Compensation: CancelTrainBooking] 火車票已成功取消！');
  job.complete({ TrainBookingStatus: 'Canceled' });
});

engine.registerJobWorker('CancelHotelBooking', async (job) => {
  console.log('   🔄 [Compensation: CancelHotelBooking] 正在向飯店取消訂單...');
  await delay(100);
  console.log('   ❌ [Compensation: CancelHotelBooking] 飯店訂單已成功退訂！');
  job.complete({ HotelBookingStatus: 'Canceled' });
});

console.log('\n🚀 啟動 Saga 流程實例...\n');

const instance = engine.start(processId, {
  confirm,
  flightNeeded,
  trainTicketNeeded,
});

instance.onChange((ev) => {
  if (ev.type === 'element:entered') {
    const label = ev.elementName ? `"${ev.elementName}"` : ev.elementId;
    console.log(`📍 [節點進入] ${label} (${ev.elementId})`);
  } else if (ev.type === 'process:completed') {
    console.log('\n🎉 [流程完成] Process instance has finished successfully.');
  }
});

// Wait for all asynchronous jobs to complete
while (instance.state === 'active') {
  await delay(50);
}

console.log('\n' + '='.repeat(60));
console.log('📊 最終執行結果摘要');
console.log('='.repeat(60));
console.log('實例狀態:', instance.state);
console.log('變數清單:');
console.dir(instance.variables_snapshot, { depth: null, colors: true });
console.log('='.repeat(60));
