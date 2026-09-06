# MiniTicket Intro

## 1. Purpose of this project

- Build a distributed ticket reservation system that the user can reserve a seat for a limited time and pay to confirm the seat.
- This project is started to learn and deepen my backend engineering skills

### Key Points to learn

- MSA design (using Go)
- DB per service
- Concurrent ticket reservation control
- optimistic / pessimistic lock
- idempotency (at-least-once delivery)
- outbox pattern
- event driven architecture
- SAGA pattern

## 2. Service Architecture

- Since this project is for educational purpose, only 4 following services will be implemented:

```
API Gateway
  |-- Concert Service
  |-- Reservation Service
  |-- Payment Service
  |-- Notification Service
```

- Each services will have its own database.
- Services must not directly access another service's database.

## 3. Service Responsibilities

### Concert Service

Manages concerts, performances, and seats.

```txt
Concert
  └── Performance
        └── Seat
```

Responsibilities:

- Browse concerts
- Browse performances
- Browse seats
- Manage seat state

### Reservation Service

Manages seat holds and the reservation lifecycle.

```txt
PENDING
   ↓
CONFIRMED

or

PENDING
   ↓
EXPIRED / CANCELED
```

### Payment Service

Manages the payment lifecycle.

```txt
READY
 ↓
PROCESSING
 ↓
SUCCEEDED / FAILED
```

- Use a Mock Payment Provider instead of a real PG provider.

### Notification Service

Consumes domain events and handles notifications.

Initially, logging instead of real email/SMS is enough.

## Main User Flow

```txt
Browse Concert
      ↓
Select Performance
      ↓
Browse Seats
      ↓
Select Seats
      ↓
Hold Seats
      ↓
Payment
      ↓
Reservation Confirmed
```

Seat hold duration:

- 5 minutes

If payment is not completed before expiration, the seats become available again.
