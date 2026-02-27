import express, { type Request, type Response } from 'express';
import { Kafka, type Consumer, type Producer } from 'kafkajs';
import type {
  NotificationDispatchRequest,
  ShipmentStatus,
  ShipmentStatusChanged,
  ShipmentStatusRealtime
} from './types';

const host = process.env.SHIPMENT_TRACKER_HOST || '0.0.0.0';
const port = Number.parseInt(process.env.SHIPMENT_TRACKER_PORT || '9012', 10);
const kafkaBrokers = (process.env.SHIPMENT_TRACKER_KAFKA_BROKERS || 'localhost:9092')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);
const kafkaTopic = process.env.SHIPMENT_STATUS_CHANGED_TOPIC || 'shipment.status.changed';
const realtimeKafkaTopic = process.env.SHIPMENT_STATUS_REALTIME_TOPIC || 'shipment.status.realtime';
const notificationBaseUrl = process.env.NOTIFICATION_BASE_URL || 'http://localhost:5113';

const app = express();
app.use(express.json({ limit: '1mb' }));

const kafka = new Kafka({
  clientId: 'shipment-tracker-service',
  brokers: kafkaBrokers
});
const consumer: Consumer = kafka.consumer({ groupId: 'shipment-tracker-service-group' });
const producer: Producer = kafka.producer();

const relayedEvents: ShipmentStatusRealtime[] = [];
const maxRelayedEvents = 100;
let kafkaConnected = false;

function isShipmentStatus(value: unknown): value is ShipmentStatus {
  return (
    value === 'CREATED' ||
    value === 'PICKED_UP' ||
    value === 'IN_TRANSIT' ||
    value === 'OUT_FOR_DELIVERY' ||
    value === 'DELIVERED' ||
    value === 'FAILED'
  );
}

function isShipmentStatusChanged(value: unknown): value is ShipmentStatusChanged {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return false;
  }

  const payload = value as Record<string, unknown>;
  return (
    typeof payload.eventId === 'string' &&
    typeof payload.orderId === 'string' &&
    typeof payload.shipmentId === 'string' &&
    isShipmentStatus(payload.status) &&
    typeof payload.occurredAt === 'string' &&
    (typeof payload.locationCode === 'undefined' || typeof payload.locationCode === 'string')
  );
}

function rememberEvent(event: ShipmentStatusRealtime): void {
  relayedEvents.push(event);
  if (relayedEvents.length > maxRelayedEvents) {
    relayedEvents.shift();
  }
}

function buildHeartbeatEvent(): ShipmentStatusRealtime {
  return {
    eventId: `heartbeat-${Date.now()}`,
    orderId: 'heartbeat-order',
    shipmentId: 'heartbeat-shipment',
    status: 'IN_TRANSIT',
    publishedAt: new Date().toISOString(),
    eta: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
  };
}

function toRealtimeEvent(value: ShipmentStatusChanged): ShipmentStatusRealtime {
  return {
    eventId: value.eventId,
    orderId: value.orderId,
    shipmentId: value.shipmentId,
    status: value.status,
    publishedAt: new Date().toISOString(),
    eta: value.status === 'IN_TRANSIT' || value.status === 'OUT_FOR_DELIVERY'
      ? new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
      : undefined
  };
}

async function publishRealtimeEvent(event: ShipmentStatusRealtime): Promise<void> {
  await producer.send({
    topic: realtimeKafkaTopic,
    messages: [{ key: event.shipmentId, value: JSON.stringify(event) }]
  });
}

async function sendNotification(event: ShipmentStatusRealtime): Promise<void> {
  const request: NotificationDispatchRequest = {
    userId: `order-${event.orderId}`,
    channel: 'PUSH',
    title: `Shipment ${event.status}`,
    body: `Shipment ${event.shipmentId} for order ${event.orderId} is ${event.status}`
  };

  const response = await fetch(`${notificationBaseUrl}/notifications`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json'
    },
    body: JSON.stringify(request)
  });

  if (!response.ok) {
    throw new Error(`notification call failed with status ${response.status}`);
  }
}

async function handleStatusChanged(event: ShipmentStatusChanged): Promise<void> {
  const realtimeEvent = toRealtimeEvent(event);
  await publishRealtimeEvent(realtimeEvent);
  rememberEvent(realtimeEvent);
  await sendNotification(realtimeEvent);
}

function startHeartbeatPublisher(): void {
  setInterval(() => {
    const heartbeatEvent = buildHeartbeatEvent();
    void publishRealtimeEvent(heartbeatEvent)
      .then(() => rememberEvent(heartbeatEvent))
      .catch((error: unknown) => {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`heartbeat publish failed: ${message}`);
      });
  }, 3000);
}

async function startKafkaConsumer(): Promise<void> {
  await consumer.connect();
  await producer.connect();
  kafkaConnected = true;
  await consumer.subscribe({ topic: kafkaTopic, fromBeginning: false });

  const startupEvent = buildHeartbeatEvent();
  await publishRealtimeEvent(startupEvent);
  rememberEvent(startupEvent);
  startHeartbeatPublisher();

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) {
        return;
      }

      let payload: unknown;
      try {
        payload = JSON.parse(message.value.toString('utf8')) as unknown;
      } catch {
        return;
      }

      if (!isShipmentStatusChanged(payload)) {
        return;
      }

      await handleStatusChanged(payload);
    }
  });
}

app.get('/health', (_req: Request, res: Response) => {
  res.status(200).json({
    status: 'UP',
    kafkaConnected
  });
});

app.get('/_meta/shipments/relayed-events', (_req: Request, res: Response) => {
  res.status(200).json({
    count: relayedEvents.length,
    events: relayedEvents
  });
});

void startKafkaConsumer().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  kafkaConnected = false;
  console.error(`kafka consumer startup failed: ${message}`);
});

app.listen(port, host, () => {
  console.log(`shipment-tracker-service listening on http://${host}:${port}`);
});
