import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { createEngineFromXml } from './bpmn.js';
import { V3_BPMN_XML } from './model.js';

const app = new Hono();
const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// In-memory store for active bookings
const bookings = new Map();

/**
 * Creates and initializes a new BPMN Saga workflow instance for a booking.
 */
function createSagaBooking(bookingId, inputVars) {
  const { engine, processId } = createEngineFromXml(V3_BPMN_XML);

  const booking = {
    id: bookingId,
    instance: null,
    listeners: new Set(),
    pendingUserJob: null,
    variables: { ...inputVars },
    endEventId: null,
    state: 'active',
  };

  const broadcast = (event) => {
    for (const listener of booking.listeners) {
      try {
        listener(event);
      } catch {
        // ignore
      }
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
      booking.state = 'completed';
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

// ── WebSocket Endpoint for Single-Session Edge Execution ────────────────────
app.get('/api/ws', (c) => {
  const upgradeHeader = c.req.header('Upgrade');
  if (!upgradeHeader || upgradeHeader.toLowerCase() !== 'websocket') {
    return c.text('Expected Upgrade: websocket', 426);
  }

  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair);

  server.accept();

  let booking = null;

  server.addEventListener('message', async (event) => {
    try {
      const msg = JSON.parse(event.data);

      if (msg.action === 'start') {
        const bookingId = 'BK-' + Math.floor(100000 + Math.random() * 900000);
        booking = createSagaBooking(bookingId, {
          passengerName: msg.payload?.passengerName || '旅客',
          destination: msg.payload?.destination || '東京',
          flightNeeded: msg.payload?.flightNeeded !== false,
          trainTicketNeeded: msg.payload?.trainTicketNeeded !== false,
        });

        // Send bookingId to client
        server.send(JSON.stringify({ type: 'booking:created', bookingId }));

        // Forward all workflow events through this WebSocket
        booking.listeners.add((ev) => {
          try {
            server.send(JSON.stringify(ev));
          } catch {
            // ignore
          }
        });
      } else if (msg.action === 'decision') {
        if (booking && booking.pendingUserJob) {
          const confirm = msg.confirm === true;
          const job = booking.pendingUserJob;
          booking.pendingUserJob = null;
          job.complete({ confirm });
        }
      }
    } catch (e) {
      server.send(JSON.stringify({ type: 'error', message: e.message }));
    }
  });

  return new Response(null, {
    status: 101,
    webSocket: client,
  });
});

// ── API: POST /api/bookings (Fallback HTTP API) ──────────────────────────────
app.post('/api/bookings', async (c) => {
  try {
    const body = await c.req.json().catch(() => ({}));
    const bookingId = 'BK-' + Math.floor(100000 + Math.random() * 900000);

    createSagaBooking(bookingId, {
      passengerName: body.passengerName || '旅客',
      destination: body.destination || '東京',
      flightNeeded: body.flightNeeded !== false,
      trainTicketNeeded: body.trainTicketNeeded !== false,
    });

    return c.json({ bookingId, status: 'active' }, 201);
  } catch (err) {
    return c.json({ error: err.message }, 400);
  }
});

// ── API: GET /api/bookings/:id/events (SSE API) ──────────────────────────────
app.get('/api/bookings/:id/events', (c) => {
  const bookingId = c.req.param('id');
  const booking = bookings.get(bookingId);

  if (!booking) {
    return c.json({ error: 'Booking not found' }, 404);
  }

  return streamSSE(c, async (stream) => {
    const queue = [];
    let resolveWait = null;

    const listener = (event) => {
      queue.push(event);
      if (resolveWait) {
        resolveWait();
        resolveWait = null;
      }
    };

    booking.listeners.add(listener);

    try {
      while (!stream.aborted) {
        if (queue.length === 0) {
          if (booking.state === 'completed') {
            break;
          }
          await Promise.race([
            new Promise((r) => {
              resolveWait = r;
            }),
            stream.sleep(500),
          ]);
        }

        while (queue.length > 0) {
          const ev = queue.shift();
          await stream.writeSSE({ data: JSON.stringify(ev) });
          if (ev.type === 'process:completed') {
            await stream.sleep(200);
            return;
          }
        }
      }
    } finally {
      booking.listeners.delete(listener);
    }
  });
});

// ── API: POST /api/bookings/:id/decision ────────────────────────────────────
app.post('/api/bookings/:id/decision', async (c) => {
  const bookingId = c.req.param('id');
  const booking = bookings.get(bookingId);

  if (!booking || !booking.pendingUserJob) {
    return c.json({ error: 'No pending user decision for this booking' }, 400);
  }

  try {
    const body = await c.req.json().catch(() => ({}));
    const confirm = body.confirm === true;
    const job = booking.pendingUserJob;
    booking.pendingUserJob = null;
    job.complete({ confirm });
    return c.json({ success: true, confirm });
  } catch (err) {
    return c.json({ error: err.message }, 500);
  }
});

export default app;
