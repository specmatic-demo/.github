export type ShipmentStatus =
  | 'CREATED'
  | 'PICKED_UP'
  | 'IN_TRANSIT'
  | 'OUT_FOR_DELIVERY'
  | 'DELIVERED'
  | 'FAILED';

export type ShipmentStatusChanged = {
  eventId: string;
  orderId: string;
  shipmentId: string;
  status: ShipmentStatus;
  occurredAt: string;
  locationCode?: string;
};

export type ShipmentStatusRealtime = {
  eventId: string;
  orderId: string;
  shipmentId: string;
  status: ShipmentStatus;
  publishedAt: string;
  eta?: string;
};

export type NotificationDispatchRequest = {
  userId: string;
  channel: 'EMAIL' | 'SMS' | 'PUSH' | 'IN_APP';
  title: string;
  body: string;
};
