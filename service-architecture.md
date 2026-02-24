# Service Architecture Overview

This document describes a hypothetical internal microservice landscape with mixed protocols and contract types.

## Mermaid Diagram

```mermaid
flowchart LR
  WBFF["Web BFF<br/>Exposes: GraphQL<br/>Consumes: HTTP/gRPC APIs + MQTT notifications"]

  CUST["Customer Service<br/>Exposes: HTTP + Kafka events/replies<br/>Consumes: HTTP + Kafka requests"]
  CATA["Catalog Service<br/>Exposes: HTTP + gRPC<br/>Consumes: HTTP requests"]
  ORD["Order Service<br/>Exposes: HTTP + Kafka + JMS command/reply<br/>Consumes: HTTP + Kafka + JMS replies"]
  PAY["Payment Service<br/>Exposes: HTTP + gRPC<br/>Consumes: HTTP/gRPC calls"]
  SHIP["Shipping Service<br/>Exposes: HTTP + JMS reply<br/>Consumes: HTTP/JMS commands"]
  PRICE["Pricing Service<br/>Exposes: gRPC + Kafka events/replies<br/>Consumes: gRPC + Kafka requests"]
  NOTIF["Notification Service<br/>Exposes: Kafka reply/events + MQTT notifications<br/>Consumes: Kafka requests + MQTT acks"]
  ANALYTICS["Analytics Pipeline<br/>Consumes: Kafka domain events<br/>Exposes: analytics datasets/APIs"]

  WBFF --> CUST
  WBFF --> CATA
  WBFF --> ORD
  WBFF --> PRICE
  WBFF --> NOTIF

  ORD --> PAY
  ORD --> SHIP

  ORD -. "JMS command" .-> SHIP
  SHIP -. "JMS fulfillment reply" .-> ORD

  CUST -. "Kafka profile events" .-> ANALYTICS
  ORD -. "Kafka order events" .-> ANALYTICS
  PRICE -. "Kafka pricing events" .-> ANALYTICS
  NOTIF -. "Kafka notification events" .-> ANALYTICS
```

## Service Descriptions

### Web BFF
- Purpose: Client-facing aggregation layer for web UI journeys.
- Depends on: [Customer Service](#customer-service), [Catalog Service](#catalog-service), [Order Service](#order-service), [Pricing Service](#pricing-service), [Notification Service](#notification-service).
- Exposes: GraphQL API to frontend clients.
- Consumes: HTTP/OpenAPI APIs from Customer, Catalog, and Order; gRPC APIs from Pricing; AsyncAPI/MQTT notification streams from Notification Service.
- Protocols:
  - Inbound: GraphQL over HTTP
  - Outbound: HTTP, gRPC, MQTT

### Customer Service
- Purpose: Owns customer profiles, preferences, and account state.
- Depends on: Internal customer datastore (no upstream service in this list).
- Exposes: REST endpoints (`customer-service/http/openapi.yaml`), Kafka domain events (`customer.profile.updated`), and Kafka reply messages for preference sync (`customer.preference.sync.reply`).
- Consumes: HTTP requests from [Web BFF](#web-bff), Kafka request messages for preference sync (`customer.preference.sync.request`).
- Protocols:
  - Inbound: HTTP/REST, Kafka
  - Outbound: HTTP responses, Kafka events and Kafka request/reply responses

### Catalog Service
- Purpose: Owns product catalog and availability-facing product views.
- Depends on: Internal catalog/index stores (no upstream service in this list).
- Exposes: REST APIs and internal gRPC APIs for low-latency reads.
- Consumes: Requests from [Web BFF](#web-bff).
- Protocols:
  - Inbound: HTTP/REST, gRPC
  - Outbound: Synchronous responses

### Order Service
- Purpose: Owns order lifecycle (create, update, status transitions).
- Depends on: [Payment Service](#payment-service), [Shipping Service](#shipping-service).
- Exposes: REST APIs (`order-service/http/openapi.yaml`), Kafka order events (`order.created`, `order.status.changed`), JMS dispatch commands (`queue.shipping.dispatch.command`), and Kafka validation replies (`order.validation.reply`).
- Consumes: HTTP commands from [Web BFF](#web-bff), JMS fulfillment replies (`queue.order.fulfillment.reply`) from [Shipping Service](#shipping-service), and Kafka validation requests (`order.validation.request`).
- Protocols:
  - Inbound: HTTP/REST, Kafka, JMS
  - Outbound: HTTP/gRPC to Payment, HTTP to Shipping, Kafka events/request-reply, JMS request/reply

### Payment Service
- Purpose: Handles payment authorization, capture, and refund flows.
- Depends on: Internal payment processors/adapters.
- Exposes: REST + gRPC payment operations.
- Consumes: Payment calls from [Order Service](#order-service).
- Protocols:
  - Inbound: HTTP/REST, gRPC
  - Outbound: Synchronous responses

### Shipping Service
- Purpose: Manages shipment creation, dispatch, and tracking lifecycle.
- Depends on: Internal/legacy fulfillment integrations.
- Exposes: REST shipment APIs (`shipping-service/http/openapi.yaml`) and JMS fulfillment replies (`queue.order.fulfillment.reply`).
- Consumes: Shipment requests from [Order Service](#order-service) via HTTP and JMS dispatch commands (`queue.shipping.dispatch.command`).
- Protocols:
  - Inbound: HTTP/REST, JMS
  - Outbound: HTTP responses, JMS request/reply responses

### Pricing Service
- Purpose: Computes prices, discounts, and pricing context.
- Depends on: Internal pricing rules/data sources.
- Exposes: gRPC pricing API (`pricing-service/rpc/pricing.proto`), Kafka price-change events (`pricing.price.changed`), and Kafka quote replies (`pricing.quote.reply`).
- Consumes: Price lookup calls from [Web BFF](#web-bff) and Kafka quote requests (`pricing.quote.request`).
- Protocols:
  - Inbound: gRPC, Kafka
  - Outbound: gRPC responses, Kafka events and Kafka request/reply responses

### Notification Service
- Purpose: Orchestrates user notifications across channels/devices.
- Depends on: Internal template/channel providers.
- Exposes: Kafka dispatch replies (`notification.dispatch.reply`), Kafka notification-sent events (`notification.sent`), and MQTT user notification topic (`notification/user`).
- Consumes: Kafka dispatch requests (`notification.dispatch.request`) from upstream services and MQTT delivery acknowledgements (`notification/ack`) from clients/devices.
- Protocols:
  - Inbound: Kafka, MQTT
  - Outbound: Kafka events/request-reply responses, MQTT notifications

### Analytics Pipeline
- Purpose: Builds analytical datasets from cross-service event streams.
- Depends on: Event producers ([Customer Service](#customer-service), [Order Service](#order-service), [Pricing Service](#pricing-service), [Notification Service](#notification-service)).
- Exposes: Curated analytics outputs (dashboards/datasets/APIs).
- Consumes: Domain event streams (not request/reply channels) from producer services.
- Protocols:
  - Inbound: Kafka (event streams)
  - Outbound: Platform-specific analytics interfaces
