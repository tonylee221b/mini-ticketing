# Domain Model

## 1. Purpose

This document defines the core domain model of MiniTicket.

It focuses on:

* Aggregate boundaries
* Entities
* Value Objects
* Domain invariants
* State transitions
* Important domain behaviors

Infrastructure concerns such as databases, messaging, gRPC contracts, deployment, and service communication are intentionally excluded unless they directly affect a domain rule.

---

# 2. Modeling Principles

MiniTicket uses lightweight DDD.

The domain model should express business rules explicitly without introducing unnecessary abstractions.

The following principles apply:

1. Each Aggregate protects its own invariants.
2. Aggregate state should only change through explicit domain behavior.
3. Cross-service domain objects are not shared directly.
4. References across Aggregate boundaries should normally use identifiers.
5. External service data should be stored as snapshots when historical consistency is required.
6. Invalid state transitions must be rejected by the domain model.
7. Infrastructure concerns must not leak into domain entities.
8. Aggregate boundaries should remain as small as possible while still protecting required consistency rules.

---

# 3. Auth Domain

The Auth domain owns authentication identity and refresh-token sessions.

Major aggregates:

```text
User
Session
```

`User` and `Session` are modeled as separate Aggregates.

A User may have multiple active Sessions.

### 3.1 User Aggregate

Aggregate Root:

```text
User
```

Conceptual state:

```text
User
- user_id
- username
- password_hash
- created_at
```

Possible Value Objects:

```text
Username
PasswordHash
```

The User Aggregate represents an account that can authenticate with the system.

It owns authentication credentials but does not own refresh-token lifecycle state.

### 3.2 User Invariants

The User Aggregate must maintain the following rules.

```text
username must not be empty
password_hash must represent an already-hashed password
```

Username uniqueness is required at the application persistence boundary.

Raw passwords must never become persistent domain state.

The domain should work with:

```text
PasswordHash
```

rather than storing the original password.

### 3.3 User Behaviors

Important behaviors include:

```text
CreateUser
ChangePassword
VerifyPassword
```

Password hashing itself may depend on an external cryptographic implementation.

The User domain model should not depend directly on a particular hashing library.

---

# 4. Session Aggregate

Aggregate Root:

```text
Session
```

Conceptual state:

```text
Session
- session_id
- user_id
- token_family_id
- refresh_token_hash
- expires_at
- revoked_at
```

Possible Value Objects:

```text
TokenFamilyID
RefreshTokenHash
```

A Session represents one refresh-token authentication lifecycle.

The raw refresh token is never part of persistent Session state.

### 4.1 Session States

A Session does not require a dedicated enum if its state can be derived from its fields.

Conceptually:

```text
ACTIVE
EXPIRED
REVOKED
```

Derived rules:

```text
revoked_at != nil
    -> REVOKED

current_time >= expires_at
    -> EXPIRED

otherwise
    -> ACTIVE
```

### 4.2 Session Invariants

```text
session must belong to exactly one user

refresh_token_hash must never contain the raw token

an expired session cannot be refreshed

a revoked session cannot be refreshed
```

Only the current valid refresh token of a session/token family may be accepted.

Refresh-token rotation must not allow two independent valid descendants from the same token.

### 4.3 Session Behaviors

Important behaviors include:

```text
RotateRefreshToken
Revoke
DetectReuse
IsExpired
IsRevoked
```

Conceptual rotation:

```text
Current Refresh Token
        |
        v
Validate
        |
        v
Replace RefreshTokenHash
        |
        v
Issue New Refresh Token
```

If a previously consumed token is reused, the affected session or token family must be revoked.

---

# 5. Concert Domain

The Concert domain owns:

```text
Concert
Seat
```

The major Aggregate is:

```text
Concert
  └── Seat
```

`Concert` is the Aggregate Root.

Seats are consistency-sensitive parts of the Concert Aggregate because seat acquisition must protect against conflicting reservations.

---

# 6. Concert Aggregate

Aggregate Root:

```text
Concert
```

Conceptual state:

```text
Concert
- concert_id
- title
- artist
- venue
- starts_at
- ends_at
- seats
```

Possible Value Objects:

```text
ConcertTitle
ArtistName
Venue
```

A Concert represents exactly one ticketable performance at one date, time, and venue.

There is no separate Performance entity.

### 6.1 Concert Invariants

```text
starts_at must be before ends_at

seat numbers must be unique within one concert

a seat belongs to exactly one concert
```

The following uniqueness rule must always hold:

```text
(concert_id, seat_number) is unique
```

---

# 7. Seat Entity

Entity:

```text
Seat
```

Conceptual state:

```text
Seat
- seat_id
- seat_number
- status
- held_by
- hold_expires_at
```

Possible Value Objects:

```text
SeatNumber
ReservationID
```

Seat status:

```text
AVAILABLE
HELD
SOLD
```

### 7.1 Seat State Transitions

Normal transitions:

```text
AVAILABLE
   |
   | Hold
   v
HELD
   |
   +-------- Release / Expire --------+
   |                                  |
   v                                  v
SOLD                              AVAILABLE
```

Valid transitions:

```text
AVAILABLE -> HELD
HELD      -> AVAILABLE
HELD      -> SOLD
```

Invalid examples:

```text
SOLD -> AVAILABLE

AVAILABLE -> SOLD

SOLD -> HELD
```

unless a future business requirement explicitly introduces such behavior.

### 7.2 Seat Invariants

```text
AVAILABLE seat must not have an active holder

HELD seat must belong to exactly one active reservation attempt

HELD seat must have a hold expiration time

SOLD seat cannot be held again

SOLD seat cannot be sold twice
```

Multiple seats requested as part of one booking must be acquired atomically.

The system must never produce a partial successful hold such as:

```text
Requested:
A1
A2
A3

Result:
A1 HELD
A2 HELD
A3 FAILED
```

The entire operation must succeed or fail as one logical domain operation.

### 7.3 Seat Behaviors

Important behaviors include:

```text
HoldSeats
ReleaseSeats
ConfirmSeats
ExpireSeatHolds
```

`HoldSeats` must reject the operation if any requested seat cannot be held.

Example:

```text
HoldSeats([A1, A2, A3])

if all seats AVAILABLE
    -> all become HELD

otherwise
    -> no seat state changes
```

---

# 8. Reservation Domain

The Reservation domain owns:

```text
Reservation
ReservationSeat
```

Aggregate:

```text
Reservation
  └── ReservationSeat
```

`Reservation` is the Aggregate Root.

---

# 9. Reservation Aggregate

Conceptual state:

```text
Reservation
- reservation_id
- user_id
- concert_id
- status
- seats
- expires_at
- created_at
```

Possible Value Objects:

```text
Money
```

Reservation states:

```text
PENDING
PAYMENT_PROCESSING
CONFIRMED
EXPIRED
CANCELED
```

### 9.1 ReservationSeat

Entity:

```text
ReservationSeat
```

Conceptual state:

```text
ReservationSeat
- seat_id
- seat_number
- price
```

A ReservationSeat is a snapshot.

It does not act as a live reference to the Concert Service's Seat domain entity.

This ensures that reservation history does not change if Concert data changes later.

Example:

```text
Concert Seat
seat_number = A12
price = 50,000

Reservation created

Later Concert data changes

ReservationSeat still keeps:
seat_number = A12
price = 50,000
```

### 9.2 Reservation Invariants

```text
reservation must belong to exactly one user

reservation must belong to exactly one concert

reservation must contain at least one seat

all ReservationSeat entries must belong to the same concert context

confirmed reservation cannot expire

expired reservation cannot be confirmed

canceled reservation cannot be confirmed
```

Seat snapshots should not change after reservation creation unless the business requirements explicitly allow modification.

### 9.3 Reservation State Transitions

Primary flow:

```text
PENDING
   |
   | BeginPayment
   v
PAYMENT_PROCESSING
   |
   +---------- Payment Failed / Cancel ----------+
   |                                              |
   | Payment Success                              v
   v                                          CANCELED
CONFIRMED
```

Expiration path:

```text
PENDING
   |
   | Hold TTL exceeded
   v
EXPIRED
```

A payment may still be resolving when the normal seat hold TTL is reached.

Therefore:

```text
PAYMENT_PROCESSING
```

must not automatically become:

```text
EXPIRED
```

solely because the original hold TTL passed.

Payment resolution and expiration policy must be considered separately.

### 9.4 Reservation Behaviors

Important behaviors include:

```text
CreateReservation
StartPayment
Confirm
Cancel
Expire
```

Each behavior must validate the current Reservation state before changing it.

Example:

```text
Confirm()

allowed:
PAYMENT_PROCESSING -> CONFIRMED

rejected:
EXPIRED -> CONFIRMED
CANCELED -> CONFIRMED
```

---

# 10. Payment Domain

The Payment domain owns:

```text
Payment
```

`Payment` is the Aggregate Root.

### 10.1 Payment Aggregate

Conceptual state:

```text
Payment
- payment_id
- reservation_id
- amount
- status
- provider_reference
- created_at
- updated_at
```

Possible Value Objects:

```text
Money
ProviderReference
IdempotencyKey
```

Payment states:

```text
CREATED
PROCESSING
SUCCEEDED
FAILED
CANCELED
```

### 10.2 Payment Invariants

```text
payment belongs to exactly one reservation

payment amount must be positive

successful payment cannot succeed twice

failed payment cannot later be treated as successful without an explicit new payment attempt or recovery rule

canceled payment cannot be processed again
```

Processing a payment must be idempotent for the same logical payment request.

Retries must not produce duplicate charges.

### 10.3 Payment State Transitions

Normal flow:

```text
CREATED
   |
   | StartProcessing
   v
PROCESSING
   |
   +-------- Success --------> SUCCEEDED
   |
   +-------- Failure --------> FAILED
   |
   +-------- Cancel ---------> CANCELED
```

Valid examples:

```text
CREATED    -> PROCESSING
PROCESSING -> SUCCEEDED
PROCESSING -> FAILED
PROCESSING -> CANCELED
```

A timeout from another service does not cause a Payment state transition by itself.

For example:

```text
Booking Saga waits for Payment RPC

RPC deadline exceeded
```

does not imply:

```text
PROCESSING -> FAILED
```

The payment may still remain:

```text
PROCESSING
```

until the actual provider result is known.

### 10.4 Payment Behaviors

Important behaviors include:

```text
CreatePayment
StartProcessing
MarkSucceeded
MarkFailed
Cancel
```

Provider interaction itself belongs outside the domain model.

The domain model receives an already interpreted result and applies the corresponding transition.

---

# 11. Booking Saga Domain

The Booking Saga domain owns distributed workflow state.

Aggregate Root:

```text
BookingSaga
```

The Saga does not own:

```text
Concert
Seat
Reservation
Payment
```

It only owns the state required to coordinate them.

### 11.1 BookingSaga Aggregate

Conceptual state:

```text
BookingSaga
- saga_id
- user_id
- concert_id
- reservation_id
- payment_id
- status
- requested_seats
- current_step
- failure_reason
- created_at
- updated_at
```

The Saga may retain identifiers and workflow metadata but must not become a duplicated source of truth for other services' business entities.

---

# 12. Saga State

Conceptual Saga states may include:

```text
STARTED
SEATS_HELD
RESERVATION_CREATED
PAYMENT_PROCESSING
PAYMENT_SUCCEEDED
CONFIRMING
COMPLETED
COMPENSATING
FAILED
```

The exact persistence representation may be refined later.

The important rule is that the Saga state must describe enough information to resume the workflow safely after failure or restart.

### 12.1 Normal Saga Flow

Conceptual transitions:

```text
STARTED
   |
   v
SEATS_HELD
   |
   v
RESERVATION_CREATED
   |
   v
PAYMENT_PROCESSING
   |
   v
PAYMENT_SUCCEEDED
   |
   v
CONFIRMING
   |
   v
COMPLETED
```

### 12.2 Compensation Flow

Example:

```text
SEATS_HELD
   |
   v
RESERVATION_CREATED
   |
   v
PAYMENT FAILED
```

Compensation:

```text
Cancel Reservation
Release Seats
```

Saga state:

```text
COMPENSATING
   |
   v
FAILED
```

If payment has already succeeded:

```text
Payment SUCCEEDED
Reservation confirmation irrecoverably fails
```

compensation may require:

```text
Cancel / Refund Payment
Cancel Reservation
Release Seats
```

### 12.3 Saga Invariants

```text
a saga represents exactly one booking attempt

a completed saga cannot restart

compensation must be safe to retry

workflow steps must be idempotent

a saga must not assume that RPC timeout means business failure

a saga must persist enough state to resume after restart
```

The Saga must distinguish:

```text
Business failure

from

Unknown remote outcome
```

Example:

```text
Payment Service returns explicit FAILED
    -> business failure

Payment RPC times out
    -> outcome unknown
```

An unknown payment result should normally keep the Saga in a waiting state until the result can be resolved.

---

# 13. Aggregate Relationships

Conceptual relationships:

```text
User
  |
  | user_id
  v
Session


User
  |
  | user_id
  v
Reservation


Concert
  |
  └── Seat


Reservation
  |
  └── ReservationSeat


Reservation
  |
  | reservation_id
  v
Payment


BookingSaga
  |
  +--> user_id
  +--> concert_id
  +--> reservation_id
  +--> payment_id
```

These relationships do not imply direct object references across service boundaries.

Cross-service references should use identifiers.

Example:

```text
Payment
    reservation_id
```

instead of:

```text
Payment
    Reservation reservation
```

The service owning an Aggregate remains the source of truth for that Aggregate.

---

# 14. Aggregate Summary

```text
Auth Domain

User
  Aggregate Root

Session
  Aggregate Root
```

```text
Concert Domain

Concert
  Aggregate Root
    └── Seat
        Entity
```

```text
Reservation Domain

Reservation
  Aggregate Root
    └── ReservationSeat
        Entity / Snapshot
```

```text
Payment Domain

Payment
  Aggregate Root
```

```text
Booking Saga Domain

BookingSaga
  Aggregate Root
```

---

# 15. Domain Invariant Summary

The most important cross-cutting domain rules are:

```text
A seat cannot be actively held by multiple bookings.

Multiple requested seats must be held atomically.

A sold seat cannot be reserved again.

A ReservationSeat is a historical snapshot.

A confirmed Reservation cannot expire.

An expired or canceled Reservation cannot be confirmed.

Payment processing must be idempotent.

A remote timeout is not equivalent to payment failure.

Refresh token rotation must not create multiple valid token branches.

Previously consumed refresh tokens must not become valid again.

Saga compensation must be idempotent.

Saga state must be resumable after process failure.
```

These invariants are the primary rules that future implementation and persistence design must preserve.
