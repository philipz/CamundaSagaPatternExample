import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadBpmnForBpmnKit } from './tests/helpers/bpmnkit.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = path.join(__dirname, 'public');
const V3_PATH = path.join(__dirname, 'Models', 'BookHolidaySagaPatternV3.bpmn');
const PORT = process.env.PORT || 3000;

// Delay helper to make UI animations clear and observable
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Store active bookings: bookingId -> BookingContext
const bookings = new Map();

/**
 * Creates and initializes a new BPMN Saga workflow instance for a booking.
 */
function createSagaBooking(bookingId, inputVars) {
  const { engine, processId } = loadBpmnForBpmnKit(V3_PATH);

  const booking = {
    id: bookingId,
    instance: null,
    sseClients: new Set(),
    pendingUserJob: null,
    variables: { ...inputVars },
    endEventId: null,
  };

  const broadcast = (event) => {
    const data = JSON.stringify(event);
    for (const client of booking.sseClients) {
      client.write(`data: ${data}\n\n`);
    }
  };

  // 1. External Worker: BookFlight
  engine.registerJobWorker('BookFlight', async (job) => {
    broadcast({ type: 'worker:start', topic: 'BookFlight' });
    await delay(700);
    const flightId = 'FL-' + Math.random().toString(36).substring(2, 8).toUpperCase();
    job.complete({
      FlightBookingStatus: 'Confirmed',
      FlightBookingID: flightId,
    });
    broadcast({
      type: 'worker:done',
      topic: 'BookFlight',
      variables: { FlightBookingStatus: 'Confirmed', FlightBookingID: flightId },
    });
  });

  // 2. External Worker: BookTrain
  engine.registerJobWorker('BookTrain', async (job) => {
    broadcast({ type: 'worker:start', topic: 'BookTrain' });
    await delay(500);
    const trainId = 'TR-' + Math.random().toString(36).substring(2, 8).toUpperCase();
    job.complete({
      TrainBookingStatus: 'Confirmed',
      TrainBookingID: trainId,
    });
    broadcast({
      type: 'worker:done',
      topic: 'BookTrain',
      variables: { TrainBookingStatus: 'Confirmed', TrainBookingID: trainId },
    });
  });

  // 3. External Worker: BookHotel
  engine.registerJobWorker('BookHotel', async (job) => {
    broadcast({ type: 'worker:start', topic: 'BookHotel' });
    await delay(800);
    const hotelId = 'HT-' + Math.random().toString(36).substring(2, 8).toUpperCase();
    job.complete({
      HotelBookingStatus: 'Confirmed',
      HotelBookingID: hotelId,
    });
    broadcast({
      type: 'worker:done',
      topic: 'BookHotel',
      variables: { HotelBookingStatus: 'Confirmed', HotelBookingID: hotelId },
    });
  });

  // 4. User Task: Check Booking Details (Activity_034u6ma)
  engine.registerJobWorker('userTask', async (job) => {
    booking.pendingUserJob = job;
    broadcast({ type: 'user:waiting', activityId: job.id });
  });

  // 5. Compensation Worker: CancelFlightBooking
  engine.registerJobWorker('CancelFlightBooking', async (job) => {
    broadcast({ type: 'compensation:start', topic: 'CancelFlightBooking' });
    await delay(600);
    job.complete({ FlightBookingStatus: 'Canceled' });
    broadcast({
      type: 'compensation:done',
      topic: 'CancelFlightBooking',
      variables: { FlightBookingStatus: 'Canceled' },
    });
  });

  // 6. Compensation Worker: CancelTrainBooking
  engine.registerJobWorker('CancelTrainBooking', async (job) => {
    broadcast({ type: 'compensation:start', topic: 'CancelTrainBooking' });
    await delay(500);
    job.complete({ TrainBookingStatus: 'Canceled' });
    broadcast({
      type: 'compensation:done',
      topic: 'CancelTrainBooking',
      variables: { TrainBookingStatus: 'Canceled' },
    });
  });

  // 7. Compensation Worker: CancelHotelBooking
  engine.registerJobWorker('CancelHotelBooking', async (job) => {
    broadcast({ type: 'compensation:start', topic: 'CancelHotelBooking' });
    await delay(650);
    job.complete({ HotelBookingStatus: 'Canceled' });
    broadcast({
      type: 'compensation:done',
      topic: 'CancelHotelBooking',
      variables: { HotelBookingStatus: 'Canceled' },
    });
  });

  // Start process instance
  const instance = engine.start(processId, inputVars);
  booking.instance = instance;

  instance.onChange((ev) => {
    if (ev.type === 'element:entered') {
      if (ev.elementId === 'Event_07xntzc' || ev.elementId === 'Event_0b7jeb0') {
        booking.endEventId = ev.elementId;
      }
      broadcast({
        type: 'element:entered',
        elementId: ev.elementId,
        elementName: ev.elementName,
      });
    } else if (ev.type === 'process:completed') {
      broadcast({
        type: 'process:completed',
        endEventId: booking.endEventId,
        variables: instance.variables_snapshot,
      });
    }
  });

  bookings.set(bookingId, booking);
  return booking;
}

// Simple request body parser
async function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', (chunk) => (body += chunk));
    req.on('end', () => {
      try {
        resolve(body ? JSON.parse(body) : {});
      } catch (e) {
        reject(e);
      }
    });
    req.on('error', reject);
  });
}

// HTTP Server
const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host}`);
  const pathname = parsedUrl.pathname;

  // ── Static Files ────────────────────────────────────────────────────────────
  if ((req.method === 'GET' || req.method === 'HEAD') && (pathname === '/' || pathname === '/index.html')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    if (req.method === 'HEAD') return res.end();
    return fs.createReadStream(path.join(PUBLIC_DIR, 'index.html')).pipe(res);
  }
  if ((req.method === 'GET' || req.method === 'HEAD') && pathname === '/style.css') {
    res.writeHead(200, { 'Content-Type': 'text/css; charset=utf-8' });
    if (req.method === 'HEAD') return res.end();
    return fs.createReadStream(path.join(PUBLIC_DIR, 'style.css')).pipe(res);
  }
  if ((req.method === 'GET' || req.method === 'HEAD') && pathname === '/app.js') {
    res.writeHead(200, { 'Content-Type': 'application/javascript; charset=utf-8' });
    if (req.method === 'HEAD') return res.end();
    return fs.createReadStream(path.join(PUBLIC_DIR, 'app.js')).pipe(res);
  }

  // ── API: POST /api/bookings (Start a new booking saga) ───────────────────────
  if (req.method === 'POST' && pathname === '/api/bookings') {
    try {
      const body = await parseBody(req);
      const bookingId = 'BK-' + Math.floor(100000 + Math.random() * 900000);

      createSagaBooking(bookingId, {
        passengerName: body.passengerName || '旅客',
        destination: body.destination || '東京',
        flightNeeded: body.flightNeeded !== false,
        trainTicketNeeded: body.trainTicketNeeded !== false,
      });

      res.writeHead(201, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ bookingId, status: 'active' }));
    } catch (err) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ error: err.message }));
    }
  }

  // ── API: GET /api/bookings/:id/events (Server-Sent Events) ───────────────────
  const eventsMatch = pathname.match(/^\/api\/bookings\/([^/]+)\/events$/);
  if (req.method === 'GET' && eventsMatch) {
    const bookingId = eventsMatch[1];
    const booking = bookings.get(bookingId);

    if (!booking) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ error: 'Booking not found' }));
    }

    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*',
    });

    booking.sseClients.add(res);

    req.on('close', () => {
      booking.sseClients.delete(res);
    });
    return;
  }

  // ── API: POST /api/bookings/:id/decision (Confirm or Cancel User Task) ───────
  const decisionMatch = pathname.match(/^\/api\/bookings\/([^/]+)\/decision$/);
  if (req.method === 'POST' && decisionMatch) {
    const bookingId = decisionMatch[1];
    const booking = bookings.get(bookingId);

    if (!booking || !booking.pendingUserJob) {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ error: 'No pending user decision for this booking' }));
    }

    try {
      const body = await parseBody(req);
      const confirm = body.confirm === true;
      const job = booking.pendingUserJob;
      booking.pendingUserJob = null;

      // Resumes process execution through gateway
      job.complete({ confirm });

      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, confirm }));
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ error: err.message }));
    }
  }

  // 404 Fallback
  res.writeHead(404, { 'Content-Type': 'text/plain' });
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`✈️  WanderSaga Web Application is running at: http://localhost:${PORT}`);
});
