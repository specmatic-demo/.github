# Service Architecture Overview

This document is derived from the current `specmatic.yaml` files in each project. It reflects only declared system-under-test contracts and declared dependencies.

## Mermaid Diagram

```mermaid
flowchart LR
  WBFF["Web BFF<br/>SUT: GraphQL"]
  CUST["Customer Service<br/>SUT: HTTP + Kafka AsyncAPI"]
  CATA["Catalog Service<br/>SUT: HTTP OpenAPI"]
  ORD["Order Service<br/>SUT: HTTP OpenAPI"]
  PAY["Payment Service<br/>SUT: HTTP OpenAPI"]
  SHIP["Shipping Service<br/>SUT: HTTP OpenAPI + Kafka AsyncAPI"]
  PRICE["Pricing Service<br/>SUT: gRPC/protobuf"]
  NOTIF["Notification Service<br/>SUT: MQTT AsyncAPI"]
  ANALYTICS["Analytics Pipeline<br/>SUT: HTTP OpenAPI + MQTT AsyncAPI"]

  WBFF -->|"HTTP/OpenAPI"| CUST
  WBFF -->|"HTTP/OpenAPI"| CATA
  WBFF -->|"HTTP/OpenAPI"| ORD
  WBFF -->|"gRPC/protobuf"| PRICE
  WBFF -->|"MQTT/AsyncAPI"| NOTIF

  ORD -->|"HTTP/OpenAPI"| PAY
  ORD -->|"HTTP/OpenAPI"| SHIP
  ORD -->|"MQTT/AsyncAPI"| NOTIF

  CUST -->|"MQTT/AsyncAPI"| NOTIF
  PAY -->|"MQTT/AsyncAPI"| NOTIF
  SHIP -->|"MQTT/AsyncAPI"| NOTIF
```

## Service Table

| Service | SUT (spec + type + protocol) | Depends on (spec + type + protocol) |
|---|---|---|
| `web-bff` | <ul><li>`contracts/services/web-bff/graphql/schema.graphql` (GraphQL SDL, HTTP)</li></ul> | <ul><li>`contracts/services/customer-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/catalog-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/order-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/pricing-service/rpc/pricing.proto` (gRPC/protobuf, gRPC)</li><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> |
| `customer-service` | <ul><li>`contracts/services/customer-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/customer-service/events/asyncapi.yaml` (AsyncAPI, Kafka)</li></ul> | <ul><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> |
| `catalog-service` | <ul><li>`contracts/services/catalog-service/http/openapi.yaml` (OpenAPI, HTTP)</li></ul> | <ul><li>none</li></ul> |
| `order-service` | <ul><li>`contracts/services/order-service/http/openapi.yaml` (OpenAPI, HTTP)</li></ul> | <ul><li>`contracts/services/payment-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/shipping-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> |
| `payment-service` | <ul><li>`contracts/services/payment-service/http/openapi.yaml` (OpenAPI, HTTP)</li></ul> | <ul><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> |
| `shipping-service` | <ul><li>`contracts/services/shipping-service/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/shipping-service/events/asyncapi.yaml` (AsyncAPI, Kafka)</li></ul> | <ul><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> |
| `pricing-service` | <ul><li>`contracts/services/pricing-service/rpc/pricing.proto` (gRPC/protobuf, gRPC)</li></ul> | <ul><li>none</li></ul> |
| `notification-service` | <ul><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> | <ul><li>none</li></ul> |
| `analytics-pipeline` | <ul><li>`contracts/services/analytics-pipeline/http/openapi.yaml` (OpenAPI, HTTP)</li><li>`contracts/services/notification-service/events/asyncapi.yaml` (AsyncAPI, MQTT)</li></ul> | <ul><li>none</li></ul> |
