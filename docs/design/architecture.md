# Architecture

## 1. High-Level Architecture

```text
                              Client
                                |
                                | HTTP/JSON
                                v
                         +---------------+
                         |  API Gateway  |
                         +---------------+
                           |      |      |
                           |      |      |
                           v      v      v
                        Auth   Concert  Booking Saga
                       Service Service  Orchestrator
                                         |
                          +--------------+--------------+
                          | gRPC         | gRPC         | gRPC
                          v              v              v
                       Concert      Reservation       Payment
                       Service        Service         Service
                                                         |
                                                         | HTTP
                                                         v
                                                   Mock Payment
                                                     Provider

                 +-------------------------------------------+
                 |                                           |
                 |              NATS JetStream               |
                 |                                           |
                 +-------------------------------------------+
                          ^            ^             |
                          |            |             v
                        Events       Events      Notification
                                                  Service
```

---

## 2. Components

| Component                 | Responsibility                                                              |
| ------------------------- | --------------------------------------------------------------------------- |
| API Gateway               | Public entry point, routing, PASETO validation, request context propagation |
| Auth Service              | User authentication, PASETO issuance, refresh token rotation                |
| Concert Service           | Concert and seat management                                                 |
| Reservation Service       | Reservation lifecycle management                                            |
| Payment Service           | Payment lifecycle and external payment provider integration                 |
| Booking Saga Orchestrator | Distributed booking workflow coordination and compensation                  |
| Notification Service      | Asynchronous booking notifications                                          |
| NATS JetStream            | Integration event delivery                                                  |

---

## 3. Communication

| Direction                          | Protocol       | Usage                            |
| ---------------------------------- | -------------- | -------------------------------- |
| Client → System                    | HTTP/JSON      | Public APIs                      |
| Service → Service                  | gRPC           | Synchronous commands and queries |
| Service → Service                  | NATS JetStream | Asynchronous integration events  |
| Payment Service → Payment Provider | HTTP           | External payment processing      |

```text
Immediate result required -> gRPC
Occurred fact propagation -> NATS JetStream
```

---

## 4. Data Ownership

Each service owns its own database.

```text
Auth Service        -> Auth DB
Concert Service     -> Concert DB
Reservation Service -> Reservation DB
Payment Service     -> Payment DB
Booking Saga        -> Saga DB
```

Direct cross-service database access is prohibited.

---

## 5. Booking Flow

```text
Client
  |
  v
API Gateway
  |
  v
Booking Saga
  |
  +--> Hold Seats
  |
  +--> Create Reservation
  |
  +--> Process Payment
  |
  +--> Confirm Reservation
  |
  +--> Confirm Seats
  |
  v
Booking Completed
```

If a step fails, the Saga executes compensation for previously completed steps.

If payment result is unknown due to timeout, the Saga waits for the final payment result instead of treating it as failure.

---

## 6. Event Publishing

Services use Transactional Outbox when database state changes must be followed by an integration event.

```text
Business Transaction
  |
  +--> Update DB
  +--> Insert Outbox
  |
  v
Commit
  |
  v
Outbox Publisher
  |
  v
NATS JetStream
```

PostgreSQL remains the source of truth.

---

## 7. Deployment

Initial deployment uses Docker Compose.

```text
api-gateway

auth-service
concert-service
reservation-service
payment-service
notification-service
booking-orchestrator

auth-db
concert-db
reservation-db
payment-db
saga-db

nats
```

Only the API Gateway is exposed as the main public entry point.

---

## 8. Architectural Rules

1. Each service owns its database.
2. Services do not directly access another service's database.
3. External traffic enters through API Gateway.
4. Internal synchronous communication uses gRPC.
5. Asynchronous integration events use NATS JetStream.
6. Booking transactions are coordinated by the Saga Orchestrator.
7. Transactional Outbox is used for reliable event publishing.
8. PostgreSQL is the source of truth.
9. API Gateway contains no domain business logic.
10. Network timeout does not automatically mean business failure.

---

## 9. Folder Structure

The project uses a mono-repository with an independent Go module for each service.

```text
miniticket/
├── services/
│   ├── api-gateway/
│   ├── auth/
│   ├── concert/
│   ├── reservation/
│   ├── payment/
│   ├── notification/
│   └── booking-orchestrator/
│
├── contracts/
│   ├── concert/
│   │   └── v1/
│   ├── reservation/
│   │   └── v1/
│   └── payment/
│       └── v1/
│
├── docs/
│   ├── requirements/
│   └── design/
│
├── deploy/
│   └── docker/
│
├── scripts/
├── docker-compose.yml
├── go.work
├── Makefile
└── README.md
```

Each service follows a lightweight DDD + Hexagonal Architecture structure.

```text
services/concert/
├── cmd/
│   └── api/
│
├── internal/
│   ├── domain/
│   ├── application/
│   ├── adapter/
│   │   ├── in/
│   │   │   ├── http/
│   │   │   └── grpc/
│   │   └── out/
│   │       ├── postgres/
│   │       └── nats/
│   └── platform/
│
├── migrations/
├── sql/
├── sqlc.yaml
├── go.mod
└── Dockerfile
```

### 9.1 Layer Responsibilities

```text
domain
  -> Business entities, value objects, invariants, domain errors

application
  -> Use cases and application orchestration

adapter/in
  -> HTTP handlers, gRPC servers, message consumers

adapter/out
  -> PostgreSQL repositories, NATS publishers, external service clients

platform
  -> Configuration, database bootstrap, logging, observability
```

### 9.2 Application Layer

Use cases do not require dedicated interfaces by default.

The application layer may initially use a small number of files such as:

```text
application/
├── service.go
├── command.go
├── query.go
└── port.go
```

If the application layer grows, use cases may later be split into behavior-oriented files such as:

```text
application/
├── hold_seats.go
├── release_seats.go
└── confirm_seats.go
```

### 9.3 Ports

Outbound dependencies are defined as interfaces in the application layer.

Typical outbound ports include:

```text
Repository
Event Publisher
External Service Client
```

Inbound use-case interfaces are optional and should only be introduced when a concrete consumer requires them.

### 9.4 Workers

Background processes that belong to the same domain remain in the same service module.

Example:

```text
services/reservation/
├── cmd/
│   ├── api/
│   ├── expiration-worker/
│   └── outbox-worker/
│
└── internal/
    └── ...
```

A worker is a separate process, not necessarily a separate microservice.

### 9.5 Go Modules

Each service owns its own `go.mod`.

```text
services/api-gateway/go.mod
services/auth/go.mod
services/concert/go.mod
services/reservation/go.mod
services/payment/go.mod
services/notification/go.mod
services/booking-orchestrator/go.mod
```

The repository root uses `go.work` for local development.

Services must not import another service's internal or domain packages.

Cross-service communication is allowed only through:

```text
HTTP contracts
gRPC contracts
Integration events
```

### 9.6 Contracts

gRPC contracts are stored separately from service implementation code.

```text
contracts/
├── concert/v1/concert.proto
├── reservation/v1/reservation.proto
└── payment/v1/payment.proto
```

Protocol Buffer definitions represent service contracts and must not be treated as shared domain models.
