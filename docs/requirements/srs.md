# Software Requirements Specification (SRS)

## 1. System Overview

MiniTicket is a distributed concert ticket reservation system built using a microservice architecture.

A `Concert` represents a single ticketable performance at a specific date, time, and venue.

Users can authenticate, browse concerts, select seats, temporarily hold seats, complete payment, and manage reservations.

The system is designed primarily to study:

* Go microservices
* API Gateway
* Database per Service
* PostgreSQL transactions and concurrency
* PASETO authentication
* Refresh Token Rotation
* gRPC service-to-service communication
* Event-driven architecture
* NATS JetStream
* Transactional Outbox
* Saga Orchestration
* Idempotency
* Eventual consistency
* Distributed failure recovery

---

## 2. Core Domain Model

```text
User
  └── Session

Concert
  └── Seat

Reservation
  └── ReservationSeat

Payment

BookingSaga
```

A `Concert` is a single scheduled performance.

Example:

```text
Concert
- title: Summer Live
- artist: Example Artist
- venue: Seoul Arena
- starts_at: 2026-09-01T18:00:00+09:00
```

There is no separate `Performance` entity in the initial version.

---

## 3. System Architecture

```text
                        Client
                          |
                          | HTTP/JSON
                          v
                    API Gateway
                 /        |         \
                /         |          \
               v          v           v
        Auth Service  Concert   Booking Saga
                      Service    Orchestrator
                                     |
                          gRPC       |       gRPC
                           +---------+---------+
                           |                   |
                           v                   v
                    Reservation            Payment
                      Service              Service
                           \                   /
                            \                 /
                             v               v
                              NATS JetStream
                                    |
                                    v
                           Notification Service
```

---

## 4. System Components

| ID     | Component                 | Responsibility                                                                                                               |
| ------ | ------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| SRS-01 | API Gateway               | Provides the public entry point, routing, authentication enforcement, request context propagation, and common edge concerns. |
| SRS-02 | Auth Service              | Manages users, authentication, PASETO access tokens, refresh sessions, token rotation, and logout.                           |
| SRS-03 | Concert Service           | Manages concerts, seats, prices, and seat states.                                                                            |
| SRS-04 | Reservation Service       | Manages reservation lifecycle, expiration, confirmation, and cancellation.                                                   |
| SRS-05 | Payment Service           | Processes payments, cancellations, refunds, and communicates with a mock payment provider.                                   |
| SRS-06 | Notification Service      | Consumes booking-related integration events and generates notifications.                                                     |
| SRS-07 | Booking Saga Orchestrator | Coordinates the distributed booking workflow and compensation logic.                                                         |
| SRS-08 | NATS JetStream            | Provides durable asynchronous messaging between services.                                                                    |
| SRS-09 | gRPC                      | Provides synchronous internal service-to-service communication.                                                              |
| SRS-10 | PostgreSQL                | Provides transactional persistent storage independently owned by each service.                                               |

---

## 5. Primary Actor

| Actor    | Description                                                                                                                              |
| -------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Customer | Registers, logs in, browses concerts, selects seats, starts a booking, pays, views booking status, and cancels bookings or reservations. |

---

## 6. Service Ownership

| Component                 | Owned Data                                                     |
| ------------------------- | -------------------------------------------------------------- |
| API Gateway               | No business data                                               |
| Auth Service              | Users, password hashes, refresh sessions, refresh token hashes |
| Concert Service           | Concerts, seats                                                |
| Reservation Service       | Reservations, reservation seat snapshots                       |
| Payment Service           | Payments                                                       |
| Notification Service      | No persistent storage required initially                       |
| Booking Saga Orchestrator | Saga instances and Saga step execution state                   |

Each service owns its own database and must not directly access another service's database.

---

## 7. API Gateway

API Gateway is the single public entry point for external clients.

Responsibilities:

* Route external HTTP requests.
* Validate protected PASETO access tokens.
* Propagate trusted identity context.
* Generate or propagate `request_id` and `trace_id`.
* Apply common request timeout policies.
* Produce structured access logs.
* Optionally apply basic rate limiting.

API Gateway must not contain booking, seat, reservation, or payment business logic.

Typical public routes:

```text
/auth/*
/concerts/*
/bookings/*
```

---

## 8. Authentication Model

Authentication uses:

```text
PASETO Access Token
+
Rotating Refresh Token
```

### Access Token

Access tokens are:

* Short-lived.
* Cryptographically protected.
* Used for protected API requests.
* Validated by the trusted edge without requiring an Auth Service call for every request.

Protected request:

```http
Authorization: Bearer <access_token>
```

Recommended token claims:

```text
user_id
issuer
audience
issued_at
expiration
token_id
```

### Refresh Session

Auth Service persists refresh session state.

```text
Session
- id
- user_id
- token_family_id
- refresh_token_hash
- expires_at
- revoked_at
- created_at
- updated_at
```

Raw refresh tokens must not be stored.

---

## 9. Refresh Token Rotation

Every successful token refresh invalidates the current refresh token and issues a new one.

```text
Refresh Token A
      |
      | refresh
      v
Refresh Token A invalidated
Refresh Token B issued
```

If a previously rotated token is reused:

```text
REUSE DETECTED
      |
      v
Revoke token family
      |
      v
Require login again
```

---

## 10. Communication Model

| Communication  | Usage                                     |
| -------------- | ----------------------------------------- |
| HTTP/JSON      | Client to API Gateway                     |
| gRPC           | Internal synchronous commands and queries |
| NATS JetStream | Internal asynchronous integration events  |

General rule:

```text
Need an immediate result -> gRPC
Publish an occurred fact -> NATS JetStream
```

Example synchronous flow:

```text
Booking Saga Orchestrator
        |
        | gRPC
        +------> Concert Service
        +------> Reservation Service
        +------> Payment Service
```

Example asynchronous flow:

```text
Payment Service
      |
      | PaymentSucceeded
      v
NATS JetStream
      |
      +------> Booking Saga Orchestrator
      +------> Notification Service
```

---

## 11. gRPC Usage Rules

gRPC is used for internal synchronous operations such as:

```text
HoldSeats
ReleaseSeats
ConfirmSeats

CreateReservation
ConfirmReservation
CancelReservation

ProcessPayment
CancelPayment
GetPaymentStatus
```

Requirements:

* Every RPC uses a finite deadline.
* gRPC contracts must not expose internal domain models directly.
* Metadata may propagate trusted `user_id`, `request_id`, and `trace_id`.
* Long-lived client connections should be reused.

---

## 12. Concert and Seat Model

Concert:

```text
Concert
- id
- title
- artist
- venue
- starts_at
- ends_at
```

Seat:

```text
Seat
- id
- concert_id
- seat_number
- grade
- price
- status
- version
```

Seat states:

```text
AVAILABLE
HELD
SOLD
```

Constraint:

```text
(concert_id, seat_number) must be unique
```

---

## 13. Reservation Model

Reservation states:

```text
PENDING
PAYMENT_PROCESSING
CONFIRMED
EXPIRED
CANCELED
```

Seat hold duration:

```text
5 minutes
```

A reservation:

* Belongs to one user.
* Belongs to one concert.
* Contains one or more seat snapshots.

Reservations in `PAYMENT_PROCESSING` may use a separate payment grace period so a valid payment is not invalidated by the normal seat hold TTL.

---

## 14. Payment Model

Payment states:

```text
CREATED
PROCESSING
SUCCEEDED
FAILED
CANCELED
```

Payment Service communicates with a Mock Payment Provider.

The provider may return:

```text
SUCCESS
FAILED
PENDING
TIMEOUT
```

A gRPC timeout does not automatically mean payment failure.

If the final payment result is unknown, the booking workflow transitions to a waiting state until the final result is resolved through:

* Payment completion event
* Provider webhook
* Payment status query
* Reconciliation

---

## 15. Distributed Booking Workflow

Booking Saga Orchestrator coordinates booking.

```text
Start Booking
    |
    v
Hold Seats
    | gRPC
    v
Create Reservation
    | gRPC
    v
Process Payment
    | gRPC
    v
Payment Result?
    |
    +---- SUCCESS ----> Confirm Reservation
    |                       |
    |                       v
    |                  Confirm Seats
    |                       |
    |                       v
    |                Booking Completed
    |
    +---- FAILED -----> Compensation
    |
    +---- UNKNOWN ----> WAITING_PAYMENT
                            |
                            v
                     Payment event/result
```

Compensation example:

```text
Hold Seats          SUCCESS
Create Reservation  SUCCESS
Payment             FAILED
        |
        v
Cancel Reservation
        |
        v
Release Seats
```

Saga execution state must be persisted.

---

## 16. Messaging

NATS JetStream provides asynchronous messaging.

The system assumes:

```text
at-least-once delivery
```

Therefore:

* Messages may be delivered multiple times.
* Consumers must be idempotent.
* Messages are acknowledged only after successful processing.
* Failed messages may be redelivered.
* Durable consumers must resume after restart.
* Permanently failing messages must remain observable.

---

## 17. Transactional Outbox

Services that modify business state and publish integration events use Transactional Outbox where required.

Example:

```text
BEGIN

UPDATE payments
SET status = 'SUCCEEDED';

INSERT INTO outbox_events (...);

COMMIT
```

Then:

```text
PostgreSQL
    |
    v
Outbox Publisher
    |
    v
NATS JetStream
```

---

## 18. Integration Events

Typical integration events include:

```text
ReservationCreated
ReservationConfirmed
ReservationExpired
ReservationCanceled

PaymentProcessing
PaymentSucceeded
PaymentFailed
PaymentCanceled

BookingCompleted
BookingFailed
```

Integration events are service contracts and should be versionable.

Example:

```text
payment.succeeded.v1
```

---

## 19. Identity Propagation

API Gateway validates external identity.

Trusted identity may then be propagated internally using gRPC metadata.

Example:

```text
user_id
request_id
trace_id
```

Internal services must not trust arbitrary identity headers directly supplied by external clients.

---

## 20. Core Consistency Rules

* A seat belongs to exactly one concert.
* `(concert_id, seat_number)` must be unique.
* A seat must never belong to multiple active reservations simultaneously.
* Multi-seat holds must be atomic.
* A successful payment must never be charged twice.
* Payment timeout must not be treated as guaranteed payment failure.
* Expired reservations must not be confirmed unless protected by the defined payment-processing rule.
* A refresh token must become invalid after successful rotation.
* Refresh token reuse must be detectable.
* Saga and compensation steps must be retry-safe.
* Cross-service consistency is eventual.
* Distributed failures must result in recoverable or observable workflow state.

---

## 21. Observability

Context should propagate across HTTP, gRPC, and NATS.

Recommended identifiers:

```text
request_id
trace_id
user_id
session_id
concert_id
reservation_id
payment_id
saga_id
event_id
```

The following must never be logged:

```text
password
password hash
access token
refresh token
refresh token hash
```

---

## 22. Deployment

Initial deployment uses Docker Compose.

Runtime components:

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

Internal DNS examples:

```text
auth:8080
concert:50051
reservation:50051
payment:50051
booking-orchestrator:8080
nats:4222
```

---

## 23. Out of Scope

* Multiple performances under one concert
* OAuth / social login
* MFA
* Real payment gateway
* Real SMS / email
* Waiting room / traffic queue
* Ticket resale or transfer
* QR admission
* Kubernetes
* Service Mesh
* Multi-region deployment
* Event Sourcing
* Event Store
