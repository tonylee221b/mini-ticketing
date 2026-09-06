# API && gRPC Spec

## 1. Purpose

This document defines the external HTTP API and internal gRPC contracts for MiniTicket.

It focuses on:

* Public HTTP endpoints
* Internal gRPC services
* Request and response contracts
* Authentication requirements
* Idempotency requirements
* Error semantics
* Timeout-related behavior

Detailed domain rules, database schemas, and Saga execution logic are defined in separate documents.

---

# 2. Communication Overview

External communication:

```text
Client
  |
  | HTTP / JSON
  v
API Gateway
```

Internal synchronous communication:

```text
API Gateway / Booking Saga
          |
          | gRPC
          v
     Internal Services
```

Internal asynchronous events are handled through NATS JetStream and are not defined in this document.

---

# 3. General API Rules

## 3.1 Base Path

Public HTTP APIs use:

```text
/api/v1
```

Example:

```text
/api/v1/auth/login
/api/v1/concerts
/api/v1/bookings
```

---

## 3.2 Content Type

Requests and responses use:

```text
application/json
```

unless otherwise specified.

---

## 3.3 Identifier Format

All identifiers are UUID values represented as strings in HTTP and gRPC contracts.

Example:

```text
"550e8400-e29b-41d4-a716-446655440000"
```

---

## 3.4 Timestamp Format

HTTP timestamps use RFC 3339.

Example:

```text
2026-08-29T10:30:00Z
```

gRPC contracts should use:

```text
google.protobuf.Timestamp
```

---

# 4. Authentication

Protected endpoints require:

```text
Authorization: Bearer <access_token>
```

The API Gateway validates the PASETO access token.

After successful validation, trusted identity is propagated to internal services.

Internal services should not trust user identity directly from public HTTP headers.

---

# 5. Error Response

Public HTTP APIs use a common error shape.

```json
{
  "code": "SEAT_NOT_AVAILABLE",
  "message": "One or more requested seats are not available."
}
```

Optional contextual fields may be added later if required.

The `code` field is the stable machine-readable contract.

The `message` field is human-readable.

---

# 6. HTTP Status Guidelines

Common mappings:

```text
200 OK
    Successful read or synchronous operation

201 Created
    Resource successfully created

202 Accepted
    Request accepted but final result is still pending

204 No Content
    Successful operation with no response body

400 Bad Request
    Invalid request format or validation failure

401 Unauthorized
    Missing or invalid authentication

403 Forbidden
    Authenticated but not allowed

404 Not Found
    Resource does not exist

409 Conflict
    Business state conflict

422 Unprocessable Entity
    Request is structurally valid but cannot be processed

500 Internal Server Error
    Unexpected internal failure

503 Service Unavailable
    Required internal service unavailable
```

---

# 7. Auth HTTP API

Public routes:

```text
POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
```

---

# 8. Register

```text
POST /api/v1/auth/register
```

Authentication:

```text
Not required
```

Request:

```json
{
  "username": "tony",
  "password": "strong-password"
}
```

Response:

```text
201 Created
```

```json
{
  "user_id": "uuid",
  "username": "tony"
}
```

Possible errors:

```text
INVALID_USERNAME
INVALID_PASSWORD
USERNAME_ALREADY_EXISTS
```

Typical status:

```text
400
409
```

---

# 9. Login

```text
POST /api/v1/auth/login
```

Authentication:

```text
Not required
```

Request:

```json
{
  "username": "tony",
  "password": "strong-password"
}
```

Response:

```text
200 OK
```

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 900
}
```

`expires_in` represents the access-token lifetime in seconds.

Possible errors:

```text
INVALID_CREDENTIALS
```

Typical status:

```text
401
```

Authentication failures should not expose whether the username or password was incorrect.

---

# 10. Refresh Token

```text
POST /api/v1/auth/refresh
```

Authentication:

```text
Refresh token required
```

Request:

```json
{
  "refresh_token": "..."
}
```

Response:

```text
200 OK
```

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 900
}
```

The refresh token is rotated.

The previous refresh token becomes invalid after successful rotation.

Possible errors:

```text
INVALID_REFRESH_TOKEN
REFRESH_TOKEN_EXPIRED
REFRESH_TOKEN_REUSED
SESSION_REVOKED
```

Typical status:

```text
401
```

Reuse detection may revoke the affected session or token family.

---

# 11. Logout

```text
POST /api/v1/auth/logout
```

Authentication:

```text
Required
```

Request:

```json
{
  "refresh_token": "..."
}
```

Response:

```text
204 No Content
```

Logout revokes the relevant refresh-token session.

---

# 12. Concert HTTP API

Public routes:

```text
GET /api/v1/concerts
GET /api/v1/concerts/{concert_id}
GET /api/v1/concerts/{concert_id}/seats
```

Concert browsing may be public.

Authentication is not required for the initial implementation.

---

# 13. List Concerts

```text
GET /api/v1/concerts
```

Response:

```text
200 OK
```

```json
{
  "concerts": [
    {
      "concert_id": "uuid",
      "title": "Example Concert",
      "artist": "Example Artist",
      "venue": "Example Hall",
      "starts_at": "2026-09-01T10:00:00Z",
      "ends_at": "2026-09-01T12:00:00Z"
    }
  ]
}
```

Pagination may be introduced later if required.

---

# 14. Get Concert

```text
GET /api/v1/concerts/{concert_id}
```

Response:

```text
200 OK
```

```json
{
  "concert_id": "uuid",
  "title": "Example Concert",
  "artist": "Example Artist",
  "venue": "Example Hall",
  "starts_at": "2026-09-01T10:00:00Z",
  "ends_at": "2026-09-01T12:00:00Z"
}
```

Possible errors:

```text
CONCERT_NOT_FOUND
```

Typical status:

```text
404
```

---

# 15. List Seats

```text
GET /api/v1/concerts/{concert_id}/seats
```

Response:

```text
200 OK
```

```json
{
  "concert_id": "uuid",
  "seats": [
    {
      "seat_id": "uuid",
      "seat_number": "A1",
      "status": "AVAILABLE"
    },
    {
      "seat_id": "uuid",
      "seat_number": "A2",
      "status": "HELD"
    }
  ]
}
```

Public seat status values:

```text
AVAILABLE
HELD
SOLD
```

Internal hold owner information must not be exposed.

---

# 16. Booking HTTP API

Public routes:

```text
POST /api/v1/bookings
GET  /api/v1/bookings/{booking_id}
```

Authentication:

```text
Required
```

`booking_id` represents the public identifier of the booking workflow.

For the initial implementation, this may map directly to the Booking Saga identifier.

---

# 17. Create Booking

```text
POST /api/v1/bookings
```

Authentication:

```text
Required
```

Request:

```json
{
  "concert_id": "uuid",
  "seat_ids": [
    "uuid",
    "uuid"
  ],
  "payment_method": "MOCK"
}
```

The authenticated `user_id` must not be accepted from the request body.

It is derived from trusted authentication context.

---

## 17.1 Immediate Success

If the full booking workflow completes within the HTTP request window:

```text
201 Created
```

```json
{
  "booking_id": "uuid",
  "reservation_id": "uuid",
  "status": "CONFIRMED"
}
```

---

## 17.2 Payment Still Processing

If the payment outcome is still unresolved:

```text
202 Accepted
```

```json
{
  "booking_id": "uuid",
  "reservation_id": "uuid",
  "status": "PAYMENT_PROCESSING"
}
```

This is not an error.

The client should query:

```text
GET /api/v1/bookings/{booking_id}
```

for the final result.

---

## 17.3 Booking Failure

Example:

```text
409 Conflict
```

```json
{
  "code": "SEAT_NOT_AVAILABLE",
  "message": "One or more requested seats are not available."
}
```

Possible business errors:

```text
CONCERT_NOT_FOUND
SEAT_NOT_FOUND
SEAT_NOT_AVAILABLE
INVALID_SEAT_SELECTION
PAYMENT_FAILED
BOOKING_CANCELED
```

---

## 17.4 Booking Idempotency

Booking creation should support a client-supplied idempotency key.

Recommended header:

```text
Idempotency-Key: <client-generated-value>
```

The same user sending the same idempotency key must not create multiple independent booking attempts.

The exact persistence mechanism may be implemented in the Booking Saga service.

---

# 18. Get Booking

```text
GET /api/v1/bookings/{booking_id}
```

Authentication:

```text
Required
```

The authenticated user must own the booking.

Response:

```text
200 OK
```

Example confirmed booking:

```json
{
  "booking_id": "uuid",
  "reservation_id": "uuid",
  "status": "CONFIRMED"
}
```

Example unresolved booking:

```json
{
  "booking_id": "uuid",
  "reservation_id": "uuid",
  "status": "PAYMENT_PROCESSING"
}
```

Example failed booking:

```json
{
  "booking_id": "uuid",
  "status": "FAILED",
  "failure_reason": "PAYMENT_FAILED"
}
```

Possible public statuses:

```text
PENDING
PAYMENT_PROCESSING
CONFIRMED
FAILED
CANCELED
```

The public API does not need to expose every internal Saga state.

---

# 19. Internal gRPC Rules

Internal synchronous service communication uses gRPC.

All calls must use finite deadlines.

The caller must distinguish:

```text
Business failure
```

from:

```text
Transport / timeout failure
```

A gRPC timeout must never automatically be interpreted as a business failure.

---

# 20. Trusted Identity Metadata

When required, authenticated identity may be propagated through gRPC metadata.

Conceptually:

```text
x-user-id: <uuid>
```

Only trusted internal callers may set this metadata.

Internal services must not accept equivalent public-client headers directly.

For Saga operations, explicit request fields may be preferable when the user identifier is part of the workflow state.

---

# 21. ConcertService gRPC

Service:

```text
ConcertService
```

RPCs:

```text
GetConcert
ListSeats
HoldSeats
ReleaseSeats
ConfirmSeats
```

---

# 22. GetConcert

```text
rpc GetConcert(GetConcertRequest)
    returns (GetConcertResponse)
```

Request:

```text
concert_id
```

Response:

```text
concert_id
title
artist
venue
starts_at
ends_at
```

Errors:

```text
NOT_FOUND
```

---

# 23. ListSeats

```text
rpc ListSeats(ListSeatsRequest)
    returns (ListSeatsResponse)
```

Request:

```text
concert_id
```

Response:

```text
seats[]
    seat_id
    seat_number
    status
```

Errors:

```text
NOT_FOUND
```

---

# 24. HoldSeats

```text
rpc HoldSeats(HoldSeatsRequest)
    returns (HoldSeatsResponse)
```

Used by:

```text
Booking Saga
```

Request:

```text
concert_id
reservation_id
seat_ids[]
hold_until
```

`reservation_id` acts as the logical owner of the seat hold.

Response:

```text
held_seats[]
    seat_id
    seat_number
```

The operation is atomic.

Either all requested seats are held or none are held.

Possible business errors:

```text
CONCERT_NOT_FOUND
SEAT_NOT_FOUND
SEAT_NOT_AVAILABLE
INVALID_SEAT_SELECTION
```

Recommended gRPC mappings:

```text
CONCERT_NOT_FOUND
SEAT_NOT_FOUND
    -> NOT_FOUND

SEAT_NOT_AVAILABLE
    -> FAILED_PRECONDITION

INVALID_SEAT_SELECTION
    -> INVALID_ARGUMENT
```

---

## 24.1 HoldSeats Idempotency

Calling the operation again with the same logical reservation and seats should not produce conflicting state.

Example:

```text
reservation_id = R1
seats = [A1, A2]
```

A retry caused by network uncertainty should safely return the existing compatible hold if it already succeeded.

---

# 25. ReleaseSeats

```text
rpc ReleaseSeats(ReleaseSeatsRequest)
    returns (ReleaseSeatsResponse)
```

Request:

```text
reservation_id
seat_ids[]
```

Response:

```text
released_count
```

The operation must be idempotent.

Retrying release after seats have already been released should succeed safely.

Seats held by another reservation must not be released.

---

# 26. ConfirmSeats

```text
rpc ConfirmSeats(ConfirmSeatsRequest)
    returns (ConfirmSeatsResponse)
```

Request:

```text
reservation_id
seat_ids[]
```

Response:

```text
confirmed_count
```

The operation transitions the matching held seats to:

```text
SOLD
```

The operation must be idempotent.

Retrying confirmation for seats already sold by the same reservation should be treated as success.

Seats owned by another booking must not be confirmed.

---

# 27. ReservationService gRPC

Service:

```text
ReservationService
```

RPCs:

```text
CreateReservation
StartPayment
ConfirmReservation
CancelReservation
GetReservation
```

---

# 28. CreateReservation

```text
rpc CreateReservation(CreateReservationRequest)
    returns (CreateReservationResponse)
```

Request:

```text
reservation_id
user_id
concert_id
expires_at

seats[]
    seat_id
    seat_number
    price_amount
    currency
```

The Saga may pre-generate `reservation_id` to simplify idempotent retry behavior.

Response:

```text
reservation_id
status
expires_at
```

Initial status:

```text
PENDING
```

The request stores seat snapshots.

---

## 28.1 CreateReservation Idempotency

The same:

```text
reservation_id
```

must not create multiple Reservations.

A repeated request with equivalent data should return the existing Reservation.

A repeated request with conflicting data should be rejected.

---

# 29. StartPayment

```text
rpc StartPayment(StartPaymentRequest)
    returns (StartPaymentResponse)
```

Request:

```text
reservation_id
```

Response:

```text
reservation_id
status
```

Expected transition:

```text
PENDING
    ->
PAYMENT_PROCESSING
```

The operation must be idempotent.

Calling it again while already in `PAYMENT_PROCESSING` should be safe.

---

# 30. ConfirmReservation

```text
rpc ConfirmReservation(ConfirmReservationRequest)
    returns (ConfirmReservationResponse)
```

Request:

```text
reservation_id
payment_id
```

Response:

```text
reservation_id
status = CONFIRMED
```

Expected transition:

```text
PAYMENT_PROCESSING
    ->
CONFIRMED
```

The operation must be idempotent.

Already confirmed Reservation should return success.

Invalid final states must not be overwritten.

---

# 31. CancelReservation

```text
rpc CancelReservation(CancelReservationRequest)
    returns (CancelReservationResponse)
```

Request:

```text
reservation_id
reason
```

Response:

```text
reservation_id
status = CANCELED
```

The operation must be idempotent.

A confirmed Reservation should not normally be canceled through this operation unless an explicit compensation policy permits it.

---

# 32. GetReservation

```text
rpc GetReservation(GetReservationRequest)
    returns (GetReservationResponse)
```

Request:

```text
reservation_id
```

Response:

```text
reservation_id
user_id
concert_id
status
expires_at

seats[]
    seat_id
    seat_number
    price_amount
    currency
```

Errors:

```text
NOT_FOUND
```

---

# 33. PaymentService gRPC

Service:

```text
PaymentService
```

RPCs:

```text
ProcessPayment
GetPayment
CancelPayment
```

---

# 34. ProcessPayment

```text
rpc ProcessPayment(ProcessPaymentRequest)
    returns (ProcessPaymentResponse)
```

Request:

```text
payment_id
reservation_id
amount
currency
idempotency_key
payment_method
```

The Saga may pre-generate `payment_id`.

Response when resolved synchronously:

```text
payment_id
status
```

Possible statuses:

```text
SUCCEEDED
FAILED
PROCESSING
```

---

## 34.1 Payment Processing Semantics

If the provider confirms success:

```text
status = SUCCEEDED
```

If the provider confirms failure:

```text
status = FAILED
```

If the payment result remains unresolved but the Payment Service can return normally:

```text
status = PROCESSING
```

---

## 34.2 RPC Timeout Semantics

If the caller receives:

```text
DEADLINE_EXCEEDED
```

the payment outcome is:

```text
UNKNOWN TO THE CALLER
```

The Saga must not convert this directly into:

```text
PAYMENT_FAILED
```

The Payment Service may still complete the operation asynchronously.

The final result may later be delivered through integration events or discovered through `GetPayment`.

---

## 34.3 ProcessPayment Idempotency

Payment processing must use:

```text
idempotency_key
```

The same logical payment request must never create multiple independent provider charges.

Retries after network failure must resolve to the existing payment operation.

---

# 35. GetPayment

```text
rpc GetPayment(GetPaymentRequest)
    returns (GetPaymentResponse)
```

Request:

```text
payment_id
```

Response:

```text
payment_id
reservation_id
amount
currency
status
provider_reference
```

Possible statuses:

```text
CREATED
PROCESSING
SUCCEEDED
FAILED
CANCELED
```

This RPC may be used during reconciliation of an uncertain payment result.

---

# 36. CancelPayment

```text
rpc CancelPayment(CancelPaymentRequest)
    returns (CancelPaymentResponse)
```

Request:

```text
payment_id
reason
```

Response:

```text
payment_id
status
```

The operation must be idempotent.

If payment has not succeeded, cancellation may move it to:

```text
CANCELED
```

If payment already succeeded, the implementation may later perform provider cancellation/refund behavior.

The exact provider-specific refund contract is outside the initial API specification.

---

# 37. gRPC Error Mapping

gRPC transport status and business errors should remain distinguishable.

Recommended mappings:

```text
INVALID_ARGUMENT
    malformed or invalid input

NOT_FOUND
    requested entity does not exist

ALREADY_EXISTS
    duplicate unique resource

FAILED_PRECONDITION
    current domain state does not allow operation

UNAUTHENTICATED
    authentication missing or invalid

PERMISSION_DENIED
    authenticated but unauthorized

DEADLINE_EXCEEDED
    RPC did not complete before deadline

UNAVAILABLE
    target service temporarily unavailable

INTERNAL
    unexpected internal failure
```

Do not use:

```text
INTERNAL
```

for expected domain conflicts.

---

# 38. Retry Rules

Retries are allowed only for idempotent operations.

Safe-to-retry operations include:

```text
HoldSeats
ReleaseSeats
ConfirmSeats

CreateReservation
StartPayment
ConfirmReservation
CancelReservation

ProcessPayment
CancelPayment
```

only because these operations are required to implement idempotency.

Retries must use the same logical identifiers.

Example:

```text
same reservation_id
same payment_id
same idempotency_key
```

A retry must not generate new identifiers for the same logical operation.

---

# 39. Deadline Rules

Every internal gRPC call must have a finite deadline.

Example conceptual policy:

```text
simple DB-backed RPC
    short deadline

payment provider RPC
    longer but still finite deadline
```

Exact timeout durations belong to runtime configuration rather than this contract.

The important semantic rule is:

```text
RPC deadline
!=
business deadline
```

and:

```text
RPC timeout
!=
business failure
```

---

# 40. Public API Summary

```text
Auth

POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/refresh
POST /api/v1/auth/logout
```

```text
Concert

GET /api/v1/concerts
GET /api/v1/concerts/{concert_id}
GET /api/v1/concerts/{concert_id}/seats
```

```text
Booking

POST /api/v1/bookings
GET  /api/v1/bookings/{booking_id}
```

---

# 41. Internal gRPC Summary

```text
ConcertService

GetConcert
ListSeats
HoldSeats
ReleaseSeats
ConfirmSeats
```

```text
ReservationService

CreateReservation
StartPayment
ConfirmReservation
CancelReservation
GetReservation
```

```text
PaymentService

ProcessPayment
GetPayment
CancelPayment
```

---

# 42. Initial Scope

The initial API deliberately excludes:

```text
admin APIs
concert creation APIs
seat management APIs
user profile APIs
payment history APIs
refund management APIs
WebSocket
SSE
GraphQL
public service-to-service APIs
```

These should only be introduced when a concrete requirement appears.

The initial contract should remain focused on demonstrating the complete ticket-booking workflow and its distributed consistency behavior.
