# SAGA Flow

## 1. Purpose

This document defines the distributed booking workflow coordinated by the Booking Saga Orchestrator.

It focuses on:

* Saga states
* Normal booking flow
* Failure handling
* Compensation
* Payment uncertainty
* Retry behavior
* Idempotency
* Crash recovery
* Final booking outcomes

The Saga coordinates multiple services but does not own their business data.

---

# 2. Participating Services

The booking workflow involves:

```text
Booking Saga Orchestrator

Concert Service
Reservation Service
Payment Service
```

The orchestrator coordinates the workflow using synchronous gRPC calls and asynchronous payment-result events when necessary.

---

# 3. Saga Ownership

`BookingSaga` owns only workflow state.

Conceptual persisted state:

```text
BookingSaga
- id
- user_id
- concert_id
- reservation_id
- payment_id
- status
- current_step
- failure_reason
- created_at
- updated_at
```

The Saga does not own:

```text
Concert
Seat
Reservation
Payment
```

Those remain owned by their respective services.

---

# 4. Saga States

Recommended Saga states:

```text
STARTED

SEATS_HELD

RESERVATION_CREATED

WAITING_PAYMENT

PAYMENT_SUCCEEDED

CONFIRMING

COMPENSATING

COMPLETED

FAILED
```

The state represents the overall workflow position.

`current_step` may additionally describe the operation currently being executed or resumed.

---

# 5. Saga Steps

The normal workflow consists of:

```text
1. Hold Seats
2. Create Reservation
3. Start Reservation Payment State
4. Process Payment
5. Confirm Reservation
6. Confirm Seats
7. Complete Booking
```

Conceptually:

```text
STARTED
   |
   | HoldSeats
   v
SEATS_HELD
   |
   | CreateReservation
   v
RESERVATION_CREATED
   |
   | StartPayment
   v
WAITING_PAYMENT
   |
   | Payment succeeded
   v
PAYMENT_SUCCEEDED
   |
   v
CONFIRMING
   |
   | ConfirmReservation
   | ConfirmSeats
   v
COMPLETED
```

---

# 6. Booking Initialization

The workflow begins when:

```text
POST /api/v1/bookings
```

is received.

The API Gateway forwards the authenticated booking request to the Booking Saga Orchestrator.

The user identifier comes from trusted authentication context.

The Saga creates:

```text
booking_id
reservation_id
payment_id
```

before executing remote operations.

These identifiers must be reused for retries.

---

## 6.1 Initial Saga Persistence

Before performing the first distributed operation, persist:

```text
status = STARTED
current_step = HOLD_SEATS
```

This ensures that the booking attempt can be recovered even if the orchestrator process crashes immediately afterward.

---

# 7. Step 1 — Hold Seats

The orchestrator calls:

```text
ConcertService.HoldSeats
```

Request:

```text
concert_id
reservation_id
seat_ids[]
hold_until
```

The Concert Service must hold all requested seats atomically.

---

## 7.1 Hold Success

If all seats are successfully held:

```text
Saga status:
STARTED
    ->
SEATS_HELD
```

Persist:

```text
status = SEATS_HELD
current_step = CREATE_RESERVATION
```

Then continue.

---

## 7.2 Seat Unavailable

If the Concert Service explicitly returns:

```text
SEAT_NOT_AVAILABLE
```

the booking fails immediately.

No compensation is required because no successful distributed step exists.

```text
STARTED
   |
   | HoldSeats failed
   v
FAILED
```

Persist:

```text
status = FAILED
failure_reason = SEAT_NOT_AVAILABLE
```

Public result:

```text
409 Conflict
```

---

## 7.3 HoldSeats Transport Failure

If the RPC fails due to:

```text
DEADLINE_EXCEEDED
UNAVAILABLE
connection failure
```

the outcome may be uncertain.

The orchestrator must not assume that the seats were not held.

Because `HoldSeats` is idempotent using the same:

```text
reservation_id
seat_ids
```

the operation may be retried safely.

Conceptually:

```text
Call HoldSeats

timeout
   |
   v
retry same HoldSeats request
```

The retry must not create a different hold.

---

# 8. Step 2 — Create Reservation

After seats are held, call:

```text
ReservationService.CreateReservation
```

Request includes:

```text
reservation_id
user_id
concert_id
expires_at
seat snapshots
```

---

## 8.1 Reservation Success

On success:

```text
SEATS_HELD
    ->
RESERVATION_CREATED
```

Persist:

```text
status = RESERVATION_CREATED
current_step = START_PAYMENT
```

---

## 8.2 Reservation Business Failure

If Reservation creation fails irrecoverably:

```text
SEATS_HELD
    |
    v
COMPENSATING
```

Compensation:

```text
ReleaseSeats
```

Then:

```text
FAILED
```

Conceptually:

```text
Hold Seats          SUCCESS
Create Reservation  FAILED

        ↓

Release Seats
```

---

## 8.3 Reservation RPC Failure

If the `CreateReservation` RPC result is uncertain:

```text
DEADLINE_EXCEEDED
UNAVAILABLE
```

retry using the same:

```text
reservation_id
```

`CreateReservation` must be idempotent.

If the first request already succeeded, the retry returns the existing Reservation.

---

# 9. Step 3 — Start Payment State

Before calling the Payment Service, the Reservation should transition:

```text
PENDING
    ->
PAYMENT_PROCESSING
```

Call:

```text
ReservationService.StartPayment
```

---

## 9.1 Success

Saga remains conceptually within the payment phase.

Persist:

```text
status = RESERVATION_CREATED
current_step = PROCESS_PAYMENT
```

The Reservation now explicitly reflects that payment is being attempted.

---

## 9.2 StartPayment Failure

If the transition cannot be performed due to a business-state conflict:

```text
COMPENSATING
```

Compensation:

```text
CancelReservation
ReleaseSeats
```

Then:

```text
FAILED
```

If the RPC outcome is uncertain, retry using the same reservation identifier.

---

# 10. Step 4 — Process Payment

Call:

```text
PaymentService.ProcessPayment
```

Request includes:

```text
payment_id
reservation_id
amount
currency
idempotency_key
payment_method
```

The operation must be idempotent.

---

# 11. Payment Synchronous Success

If Payment Service returns:

```text
SUCCEEDED
```

then:

```text
RESERVATION_CREATED
    ->
PAYMENT_SUCCEEDED
```

Persist:

```text
status = PAYMENT_SUCCEEDED
current_step = CONFIRM_RESERVATION
```

Then begin final confirmation.

---

# 12. Payment Explicit Failure

If Payment Service explicitly returns:

```text
FAILED
```

this is a known business failure.

The Saga must compensate.

```text
RESERVATION_CREATED
    |
    v
COMPENSATING
```

Compensation:

```text
CancelReservation
ReleaseSeats
```

Then:

```text
FAILED
```

Persist:

```text
failure_reason = PAYMENT_FAILED
```

Conceptually:

```text
Hold Seats             SUCCESS
Create Reservation     SUCCESS
Payment                FAILED

          ↓

Cancel Reservation
Release Seats
```

---

# 13. Payment Still Processing

Payment Service may return normally with:

```text
PROCESSING
```

This means the payment is still being resolved.

Saga transitions to:

```text
WAITING_PAYMENT
```

Persist:

```text
status = WAITING_PAYMENT
current_step = WAIT_PAYMENT_RESULT
```

The HTTP request does not need to remain open.

Public response may be:

```text
202 Accepted
```

with:

```text
PAYMENT_PROCESSING
```

The final result is resolved later.

---

# 14. Payment RPC Timeout

This is a critical Saga rule.

Suppose:

```text
Booking Saga
    |
    | ProcessPayment
    v
Payment Service
```

and the caller receives:

```text
DEADLINE_EXCEEDED
```

This means only:

```text
The caller does not know the result.
```

It does not mean:

```text
Payment failed.
```

The provider may already have charged the customer.

Therefore:

```text
DEADLINE_EXCEEDED
```

must not trigger immediate payment compensation.

---

## 14.1 Timeout Transition

The Saga should transition to:

```text
WAITING_PAYMENT
```

rather than:

```text
FAILED
```

Persist:

```text
status = WAITING_PAYMENT
current_step = WAIT_PAYMENT_RESULT
```

Conceptually:

```text
ProcessPayment
     |
     | RPC timeout
     v
Outcome Unknown
     |
     v
WAITING_PAYMENT
```

---

# 15. Resolving WAITING_PAYMENT

The payment result may later be resolved through:

```text
PaymentSucceeded event

PaymentFailed event

PaymentService.GetPayment

Payment Service reconciliation
```

The Saga must handle repeated or delayed resolution safely.

---

# 16. PaymentSucceeded Event

If the Saga receives:

```text
payment.succeeded.v1
```

for its `payment_id`:

```text
WAITING_PAYMENT
    ->
PAYMENT_SUCCEEDED
```

Persist:

```text
status = PAYMENT_SUCCEEDED
current_step = CONFIRM_RESERVATION
```

Then continue the normal confirmation workflow.

Duplicate success events must be harmless.

---

# 17. PaymentFailed Event

If the Saga receives:

```text
payment.failed.v1
```

for its `payment_id`:

```text
WAITING_PAYMENT
    ->
COMPENSATING
```

Execute:

```text
CancelReservation
ReleaseSeats
```

Then:

```text
FAILED
```

Persist:

```text
failure_reason = PAYMENT_FAILED
```

Duplicate failure events must also be harmless.

---

# 18. Payment Reconciliation

If a Saga remains:

```text
WAITING_PAYMENT
```

for too long, the system may query:

```text
PaymentService.GetPayment
```

Possible results:

```text
SUCCEEDED
FAILED
PROCESSING
CANCELED
```

Behavior:

```text
SUCCEEDED
    -> continue confirmation

FAILED
    -> compensate

CANCELED
    -> compensate

PROCESSING
    -> remain WAITING_PAYMENT
```

The Saga must not invent a final payment outcome.

---

# 19. Seat Hold Expiration During Payment

The normal seat hold TTL is:

```text
5 minutes
```

However:

```text
PAYMENT_PROCESSING
```

may legitimately exceed the original hold duration.

Therefore:

```text
hold TTL expiration
```

must not automatically mean the booking failed if payment is still resolving.

A separate payment grace policy may be used.

Conceptually:

```text
Normal Hold Window
        |
        v
Payment still unresolved
        |
        v
Payment Grace Window
```

The exact grace duration is runtime/business policy and does not need to be fixed in this document.

---

# 20. Step 5 — Confirm Reservation

After payment is confirmed successful:

```text
PAYMENT_SUCCEEDED
```

the orchestrator begins final confirmation.

Set:

```text
status = CONFIRMING
current_step = CONFIRM_RESERVATION
```

Call:

```text
ReservationService.ConfirmReservation
```

Expected transition:

```text
PAYMENT_PROCESSING
    ->
CONFIRMED
```

---

## 20.1 ConfirmReservation Success

Persist:

```text
current_step = CONFIRM_SEATS
```

Then continue to seat confirmation.

---

## 20.2 ConfirmReservation Transport Failure

Retry the same request.

The operation must be idempotent.

If the previous call already succeeded:

```text
CONFIRMED
```

should be treated as successful on retry.

---

## 20.3 Irrecoverable Confirmation Failure

If payment succeeded but Reservation confirmation becomes irrecoverably impossible:

```text
Payment     SUCCEEDED
Reservation NOT CONFIRMED
```

the Saga must enter compensation.

```text
CONFIRMING
    ->
COMPENSATING
```

Possible compensation:

```text
Cancel / Refund Payment
Cancel Reservation
Release Seats
```

---

# 21. Step 6 — Confirm Seats

After Reservation is confirmed, call:

```text
ConcertService.ConfirmSeats
```

Request:

```text
reservation_id
seat_ids[]
```

Expected seat transition:

```text
HELD
    ->
SOLD
```

The operation must be idempotent.

---

## 21.1 ConfirmSeats Success

When all seats are confirmed:

```text
CONFIRMING
    ->
COMPLETED
```

Persist:

```text
status = COMPLETED
current_step = NONE
```

The booking is final.

Public status:

```text
CONFIRMED
```

---

## 21.2 ConfirmSeats Transport Failure

Retry the operation using the same:

```text
reservation_id
seat_ids
```

Seats already sold by the same Reservation should be treated as successfully confirmed.

---

# 22. Confirmation Ordering

The initial confirmation order is:

```text
1. Confirm Reservation
2. Confirm Seats
```

Conceptually:

```text
Payment SUCCEEDED

    ↓

Reservation CONFIRMED

    ↓

Seats SOLD
```

This creates a short period where:

```text
Reservation = CONFIRMED
Seats       = HELD
```

which is acceptable within the distributed workflow because the Saga continues until both converge.

If the second step fails temporarily, the Saga retries.

---

# 23. Late Failure After Payment Success

The most expensive failure case is:

```text
Payment SUCCEEDED
```

followed by an irrecoverable downstream failure.

Example:

```text
Payment             SUCCEEDED
ConfirmReservation  FAILED permanently
```

or:

```text
Payment             SUCCEEDED
Reservation         CONFIRMED
ConfirmSeats        FAILED permanently
```

The Saga must compensate the successful payment.

Conceptual flow:

```text
Payment SUCCEEDED
      |
      v
Later Step FAILED
      |
      v
COMPENSATING
      |
      +--> Cancel / Refund Payment
      |
      +--> Cancel Reservation
      |
      +--> Release Seats
      |
      v
FAILED
```

Compensation order may depend on which steps already completed.

---

# 24. Compensation Rules

Compensation is not database rollback.

Once separate service transactions commit, they cannot be globally rolled back.

Instead, the Saga performs new business operations that semantically compensate previous steps.

Example:

```text
HoldSeats
```

is compensated by:

```text
ReleaseSeats
```

`CreateReservation` is compensated by:

```text
CancelReservation
```

Successful payment is compensated by:

```text
CancelPayment / RefundPayment
```

---

# 25. Compensation Matrix

```text
Completed Step            Compensation
------------------------------------------------
Hold Seats                Release Seats

Create Reservation        Cancel Reservation

Start Payment State       Cancel Reservation

Payment Failed            No payment compensation

Payment Succeeded         Cancel / Refund Payment

Confirm Reservation       Cancel Reservation
                          if domain policy permits

Confirm Seats             Release is normally impossible
                          once truly SOLD; compensation
                          requires explicit cancellation policy
```

The exact refund/cancellation behavior for already sold seats may be refined when provider and ticket cancellation rules are implemented.

---

# 26. Compensation Idempotency

Every compensation operation must be safe to retry.

Examples:

```text
ReleaseSeats
CancelReservation
CancelPayment
```

must not fail merely because the requested compensation already happened.

Conceptually:

```text
ReleaseSeats

first call:
HELD -> AVAILABLE

retry:
already AVAILABLE by same booking
-> success
```

The same principle applies to other compensation steps.

---

# 27. Compensation State Persistence

Before executing compensation, persist:

```text
status = COMPENSATING
current_step = <next compensation>
```

Example:

```text
status = COMPENSATING
current_step = CANCEL_RESERVATION
```

After success:

```text
current_step = RELEASE_SEATS
```

Then:

```text
status = FAILED
```

This allows compensation to resume after process restart.

---

# 28. Retry Strategy

Retries should be used only for transient failures.

Examples:

```text
DEADLINE_EXCEEDED
UNAVAILABLE
temporary network failure
```

Expected business failures should not be blindly retried.

Examples:

```text
SEAT_NOT_AVAILABLE
INVALID_STATE
PAYMENT_FAILED
```

---

## 28.1 Retry Requirements

Retries must reuse the same logical identifiers.

```text
same booking_id
same reservation_id
same payment_id
same idempotency_key
```

Never create a new identifier merely because an RPC timed out.

---

# 29. Retry Backoff

Transient retries should use bounded backoff.

Conceptually:

```text
attempt 1

small delay

attempt 2

larger delay

attempt 3
```

Retries must be finite.

When synchronous retry is exhausted, the Saga should persist a recoverable state instead of depending on process memory.

---

# 30. Crash Recovery

Saga correctness must not depend on the orchestrator process remaining alive.

Example:

```text
HoldSeats succeeds

       ↓

Orchestrator crashes

       ↓

process restarts
```

Because the Saga state and identifiers are persisted, the workflow can resume safely.

---

# 31. Recovery Loop

On startup or through a background recovery worker, find incomplete Sagas:

```text
status NOT IN (
    COMPLETED,
    FAILED
)
```

For each Saga:

```text
inspect status
inspect current_step
resume operation
```

Example:

```text
status       = SEATS_HELD
current_step = CREATE_RESERVATION
```

means:

```text
retry CreateReservation
```

using the already persisted `reservation_id`.

---

# 32. Recovery by State

Conceptual recovery behavior:

```text
STARTED
    -> retry HoldSeats

SEATS_HELD
    -> retry CreateReservation

RESERVATION_CREATED
    -> resume payment phase

WAITING_PAYMENT
    -> wait for event or query Payment

PAYMENT_SUCCEEDED
    -> resume confirmation

CONFIRMING
    -> resume current confirmation step

COMPENSATING
    -> resume current compensation step
```

`COMPLETED` and `FAILED` require no further normal Saga execution.

---

# 33. State Update Concurrency

Only one worker should advance the same Saga at a time.

Saga transitions should verify expected state before persisting.

Example:

```text
expected:
WAITING_PAYMENT

transition:
PAYMENT_SUCCEEDED
```

If another worker already changed the state, the duplicate operation should not overwrite it.

PostgreSQL row locking or conditional updates may be used.

---

# 34. Remote Calls and Database Transactions

Do not hold a local PostgreSQL transaction open while making slow remote gRPC calls.

Avoid:

```text
BEGIN

lock Saga row

call Payment Service

wait several seconds

update Saga

COMMIT
```

Prefer:

```text
Read persisted state

        ↓

Call remote service

        ↓

BEGIN

lock / verify current Saga state

persist result

COMMIT
```

Because a crash may happen between the remote call and local persistence, remote operations must be idempotent.

---

# 35. Duplicate Events

NATS JetStream provides at-least-once delivery.

The Saga may therefore receive:

```text
payment.succeeded.v1
```

multiple times.

Handling must be idempotent.

Example:

```text
WAITING_PAYMENT
    -> PAYMENT_SUCCEEDED
```

first event:

```text
transition succeeds
```

duplicate event:

```text
Saga already PAYMENT_SUCCEEDED or later
-> ignore / acknowledge
```

The duplicate must not restart confirmation from an invalid state.

---

# 36. Out-of-Order Events

An asynchronous payment event may arrive after the Saga has already resolved payment through another path.

Example:

```text
GetPayment
    -> SUCCEEDED

Saga continues

later:

payment.succeeded.v1 arrives
```

The event should be recognized as already applied.

Likewise:

```text
payment.failed.v1
```

must not overwrite an already confirmed successful payment outcome without an explicit reconciliation rule.

Persisted Saga and Payment state remain authoritative.

---

# 37. HTTP Request Lifetime

The Saga lifetime is independent from the original HTTP request lifetime.

Possible fast path:

```text
POST /bookings

Hold
Reservation
Payment
Confirmation

all complete quickly

        ↓

201 Created
CONFIRMED
```

Possible slow path:

```text
POST /bookings

Payment unresolved

        ↓

202 Accepted
PAYMENT_PROCESSING
```

The Saga continues independently.

The client polls:

```text
GET /bookings/{booking_id}
```

---

# 38. Public Status Mapping

Internal Saga states do not need to be exposed directly.

Recommended mapping:

```text
Internal Saga State        Public Booking Status
-------------------------------------------------
STARTED                    PENDING
SEATS_HELD                 PENDING
RESERVATION_CREATED        PENDING
WAITING_PAYMENT            PAYMENT_PROCESSING
PAYMENT_SUCCEEDED          PAYMENT_PROCESSING
CONFIRMING                 PAYMENT_PROCESSING
COMPLETED                  CONFIRMED
COMPENSATING               PENDING
FAILED                     FAILED
```

The public API should expose only states meaningful to clients.

---

# 39. Normal Flow Summary

```text
Client
  |
  | POST /bookings
  v
Booking Saga
  |
  | HoldSeats
  v
Concert Service
  |
  | success
  v
Booking Saga
  |
  | CreateReservation
  v
Reservation Service
  |
  | success
  v
Booking Saga
  |
  | StartPayment
  v
Reservation Service
  |
  | success
  v
Booking Saga
  |
  | ProcessPayment
  v
Payment Service
  |
  | SUCCEEDED
  v
Booking Saga
  |
  | ConfirmReservation
  v
Reservation Service
  |
  | success
  v
Booking Saga
  |
  | ConfirmSeats
  v
Concert Service
  |
  | success
  v
COMPLETED
```

---

# 40. Payment Timeout Flow Summary

```text
Booking Saga
  |
  | ProcessPayment
  v
Payment Service
  |
  X RPC deadline exceeded
  |
  v

WAITING_PAYMENT

  |
  +-------------------------+
  |                         |
  | PaymentSucceeded        | PaymentFailed
  v                         v

PAYMENT_SUCCEEDED       COMPENSATING
  |                         |
  v                         v

Confirm Reservation     Cancel Reservation
Confirm Seats           Release Seats
  |                         |
  v                         v

COMPLETED               FAILED
```

---

# 41. Pre-Payment Failure Summary

```text
HoldSeats FAILED

    -> FAILED
```

```text
HoldSeats SUCCESS
CreateReservation FAILED

    -> ReleaseSeats
    -> FAILED
```

```text
Reservation SUCCESS
StartPayment FAILED

    -> CancelReservation
    -> ReleaseSeats
    -> FAILED
```

```text
Payment FAILED

    -> CancelReservation
    -> ReleaseSeats
    -> FAILED
```

---

# 42. Post-Payment Failure Summary

```text
Payment SUCCEEDED
        |
        v
Confirmation irrecoverably fails
        |
        v
COMPENSATING
        |
        +--> Cancel / Refund Payment
        |
        +--> Cancel Reservation
        |
        +--> Release Seats where valid
        |
        v
FAILED
```

A successful charge must never be silently abandoned merely because the Saga lost the synchronous response.

---

# 43. Core Saga Invariants

The booking Saga must preserve the following rules:

```text
One Saga represents one booking attempt.

The same logical step must be safe to retry.

RPC timeout does not imply business failure.

Payment timeout does not trigger immediate compensation.

Payment success must eventually lead to confirmation
or explicit payment compensation.

Seat hold failure must never produce a partial booking.

Compensation steps must be idempotent.

Saga state must be persisted before relying on it.

A process restart must not lose workflow progress.

A completed Saga must never restart.

A failed Saga must not silently resume normal forward execution.

Cross-service transactions must never be implemented
as one shared database transaction.
```

---

# 44. Initial Implementation Scope

The initial Saga implementation should support:

```text
normal success

seat conflict

reservation creation failure

explicit payment failure

payment processing

payment RPC timeout

payment success event

payment failure event

confirmation retry

compensation

process restart recovery
```

The initial implementation does not need:

```text
generic Saga framework

dynamic workflow definitions

complex workflow DSL

distributed lock service

service mesh retries

full payment refund subsystem

manual operator recovery UI
```

The Saga should remain explicit and easy to trace in code.
