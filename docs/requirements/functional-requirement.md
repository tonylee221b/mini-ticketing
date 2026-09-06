# Functional Requirements

## API Gateway

| ID            | Requirement             | Description                                                                                                |
| ------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------- |
| FR-GATEWAY-01 | Public Entry Point      | All external application traffic enters through API Gateway.                                               |
| FR-GATEWAY-02 | Route Auth APIs         | Requests under `/auth/*` are routed to Auth Service.                                                       |
| FR-GATEWAY-03 | Route Concert APIs      | Public concert browsing requests are routed to Concert Service.                                            |
| FR-GATEWAY-04 | Route Booking APIs      | Booking-related requests are routed to Booking Saga Orchestrator or the appropriate booking read endpoint. |
| FR-GATEWAY-05 | Validate Access Token   | Protected endpoints validate PASETO access tokens.                                                         |
| FR-GATEWAY-06 | Propagate User Identity | Verified `user_id` is propagated to trusted downstream components.                                         |
| FR-GATEWAY-07 | Request Context         | Gateway creates or forwards `request_id` and `trace_id`.                                                   |
| FR-GATEWAY-08 | Public Error Mapping    | Internal errors are mapped to consistent public HTTP error responses.                                      |
| FR-GATEWAY-09 | Public Access Logging   | Incoming public requests are recorded using structured access logs.                                        |

---

## Auth Service

| ID         | Requirement               | Description                                                                            |
| ---------- | ------------------------- | -------------------------------------------------------------------------------------- |
| FR-AUTH-01 | Register User             | Users can create an account using valid credentials.                                   |
| FR-AUTH-02 | Login                     | Users can authenticate using valid credentials.                                        |
| FR-AUTH-03 | Issue PASETO Access Token | Successful authentication issues a short-lived PASETO access token.                    |
| FR-AUTH-04 | Issue Refresh Token       | Successful authentication issues a refresh token associated with a persistent session. |
| FR-AUTH-05 | Store Refresh Token Hash  | Only a secure hash of the current refresh token is stored.                             |
| FR-AUTH-06 | Refresh Access Token      | A valid refresh token can obtain a new access token.                                   |
| FR-AUTH-07 | Rotate Refresh Token      | Every successful refresh invalidates the old refresh token and issues a new one.       |
| FR-AUTH-08 | Detect Token Reuse        | Previously rotated or revoked refresh token reuse can be detected.                     |
| FR-AUTH-09 | Revoke Token Family       | Detected reuse revokes the affected refresh session or token family.                   |
| FR-AUTH-10 | Logout                    | Users can revoke their current refresh session.                                        |
| FR-AUTH-11 | Get Current User          | Authenticated users can retrieve basic identity information.                           |

---

## Concert Service

| ID            | Requirement                | Description                                                                  |
| ------------- | -------------------------- | ---------------------------------------------------------------------------- |
| FR-CONCERT-01 | Browse Concerts            | Users can retrieve available concerts.                                       |
| FR-CONCERT-02 | Get Concert                | Users can retrieve details for a specific concert.                           |
| FR-CONCERT-03 | Browse Seats               | Users can retrieve seats and their current state for a concert.              |
| FR-CONCERT-04 | Hold Seats                 | Available seats can atomically transition to `HELD`.                         |
| FR-CONCERT-05 | Release Seats              | Held seats can transition back to `AVAILABLE`.                               |
| FR-CONCERT-06 | Confirm Seats              | Held seats can transition to `SOLD`.                                         |
| FR-CONCERT-07 | Concurrent Seat Protection | Concurrent requests for the same seat result in exactly one successful hold. |
| FR-CONCERT-08 | Atomic Multi-Seat Hold     | Multi-seat reservation attempts either acquire all requested seats or none.  |
| FR-CONCERT-09 | Validate Seat Ownership    | Requested seats must belong to the specified concert.                        |
| FR-CONCERT-10 | Internal gRPC API          | Seat state operations are available through internal gRPC APIs.              |

---

## Reservation Service

| ID                | Requirement              | Description                                                                                  |
| ----------------- | ------------------------ | -------------------------------------------------------------------------------------------- |
| FR-RESERVATION-01 | Create Reservation       | A reservation can be created for successfully held seats.                                    |
| FR-RESERVATION-02 | Associate User           | Reservation is associated with the authenticated user.                                       |
| FR-RESERVATION-03 | Get Reservation          | Reservation details and status can be retrieved.                                             |
| FR-RESERVATION-04 | Confirm Reservation      | A pending or payment-processing reservation can be confirmed after verified payment success. |
| FR-RESERVATION-05 | Cancel Reservation       | A reservation can be canceled from valid states.                                             |
| FR-RESERVATION-06 | Expire Reservation       | Pending reservations expire after the hold deadline.                                         |
| FR-RESERVATION-07 | Payment Processing State | A reservation can enter `PAYMENT_PROCESSING` while the payment result is unresolved.         |
| FR-RESERVATION-08 | Reservation TTL          | New reservations receive a 5-minute hold deadline.                                           |
| FR-RESERVATION-09 | Seat Snapshot            | Seat ID, seat number, and price are persisted as reservation snapshots.                      |
| FR-RESERVATION-10 | Idempotent Reservation   | Duplicate creation requests must not create multiple reservations.                           |
| FR-RESERVATION-11 | Internal gRPC API        | Reservation commands required by the Saga are exposed through gRPC.                          |
| FR-RESERVATION-12 | Publish Events           | Relevant reservation transitions produce integration events.                                 |

---

## Payment Service

| ID            | Requirement               | Description                                                                                       |
| ------------- | ------------------------- | ------------------------------------------------------------------------------------------------- |
| FR-PAYMENT-01 | Create Payment            | Payment can be created for a valid reservation.                                                   |
| FR-PAYMENT-02 | Process Payment           | Payment Service sends payment requests to the Mock Payment Provider.                              |
| FR-PAYMENT-03 | Handle Immediate Success  | A confirmed successful provider response transitions payment to `SUCCEEDED`.                      |
| FR-PAYMENT-04 | Handle Immediate Failure  | A confirmed provider failure transitions payment to `FAILED`.                                     |
| FR-PAYMENT-05 | Handle Processing Result  | Provider responses that are not final leave payment in `PROCESSING`.                              |
| FR-PAYMENT-06 | Handle Timeout            | Provider or gRPC timeout must not automatically mark payment as failed.                           |
| FR-PAYMENT-07 | Receive Provider Callback | Payment Service may receive asynchronous payment result callbacks from the Mock Payment Provider. |
| FR-PAYMENT-08 | Query Provider Status     | Payment Service can query provider status for unresolved payments.                                |
| FR-PAYMENT-09 | Reconcile Payment         | Unresolved payments can be reconciled against provider state.                                     |
| FR-PAYMENT-10 | Cancel Payment            | Successful payments can be canceled or refunded.                                                  |
| FR-PAYMENT-11 | Idempotent Payment        | Retried payment requests must not produce duplicate charges.                                      |
| FR-PAYMENT-12 | Internal gRPC API         | Payment commands and status queries are available to the Saga through gRPC.                       |
| FR-PAYMENT-13 | Publish Payment Events    | Final payment state changes generate integration events.                                          |
| FR-PAYMENT-14 | Mock Failure Modes        | Mock provider can simulate success, failure, pending, timeout, and delay.                         |

---

## Booking Saga Orchestrator

| ID         | Requirement                     | Description                                                                                 |
| ---------- | ------------------------------- | ------------------------------------------------------------------------------------------- |
| FR-SAGA-01 | Start Booking Saga              | An authenticated user can start a booking for selected seats in one concert.                |
| FR-SAGA-02 | Persist Saga State              | Saga state and current step are persisted.                                                  |
| FR-SAGA-03 | Hold Seats                      | Orchestrator calls Concert Service through gRPC.                                            |
| FR-SAGA-04 | Create Reservation              | Orchestrator creates the reservation through gRPC.                                          |
| FR-SAGA-05 | Process Payment                 | Orchestrator requests payment processing through gRPC.                                      |
| FR-SAGA-06 | Wait for Payment                | If the payment result is unknown, Saga enters `WAITING_PAYMENT`.                            |
| FR-SAGA-07 | Resume from Payment Event       | Payment completion events can resume a waiting Saga.                                        |
| FR-SAGA-08 | Confirm Reservation             | Verified payment success triggers reservation confirmation.                                 |
| FR-SAGA-09 | Confirm Seats                   | Confirmed booking marks held seats as `SOLD`.                                               |
| FR-SAGA-10 | Execute Compensation            | Failed workflows compensate previously completed steps where required.                      |
| FR-SAGA-11 | Release Seats Compensation      | Held seats are released when booking cannot complete.                                       |
| FR-SAGA-12 | Cancel Reservation Compensation | A created reservation may be canceled after later failure.                                  |
| FR-SAGA-13 | Cancel Payment Compensation     | A completed payment may be reversed if subsequent booking confirmation irrecoverably fails. |
| FR-SAGA-14 | Resume Workflow                 | Incomplete Saga execution resumes after restart.                                            |
| FR-SAGA-15 | Retry Step                      | Retryable steps can be attempted again safely.                                              |
| FR-SAGA-16 | Handle gRPC Errors              | Saga distinguishes business failure, infrastructure failure, and unknown-result conditions. |
| FR-SAGA-17 | Finalize Saga                   | Saga eventually reaches `SUCCEEDED`, `COMPENSATED`, or `FAILED`.                            |
| FR-SAGA-18 | Get Booking Status              | Current Saga or booking status can be queried by the public API layer.                      |

---

## Notification Service

| ID                 | Requirement                | Description                                                       |
| ------------------ | -------------------------- | ----------------------------------------------------------------- |
| FR-NOTIFICATION-01 | Consume Integration Events | Relevant integration events are consumed from NATS JetStream.     |
| FR-NOTIFICATION-02 | Confirmation Notification  | Booking confirmation creates a notification.                      |
| FR-NOTIFICATION-03 | Cancellation Notification  | Booking cancellation creates a notification.                      |
| FR-NOTIFICATION-04 | Failure Notification       | Booking failure may generate a notification.                      |
| FR-NOTIFICATION-05 | Logging Implementation     | Structured logs are sufficient for initial notification delivery. |
| FR-NOTIFICATION-06 | Idempotent Processing      | Duplicate events must not cause unsafe duplicate side effects.    |

---

## gRPC

| ID         | Requirement           | Description                                                               |
| ---------- | --------------------- | ------------------------------------------------------------------------- |
| FR-GRPC-01 | Internal Service APIs | Internal synchronous communication uses gRPC.                             |
| FR-GRPC-02 | Protocol Buffers      | Internal API contracts are defined in `.proto` files.                     |
| FR-GRPC-03 | Unary RPC             | Initial implementation primarily uses unary RPC.                          |
| FR-GRPC-04 | Deadline Propagation  | gRPC callers provide finite deadlines.                                    |
| FR-GRPC-05 | Metadata Propagation  | Trusted `user_id`, `request_id`, and `trace_id` can be propagated.        |
| FR-GRPC-06 | Status Codes          | Business and infrastructure failures use appropriate gRPC status codes.   |
| FR-GRPC-07 | Interceptors          | Logging, tracing, metrics, and metadata propagation may use interceptors. |
| FR-GRPC-08 | Health Check          | Internal gRPC services expose health status where appropriate.            |
| FR-GRPC-09 | Connection Reuse      | gRPC client connections are reused.                                       |

---

## NATS JetStream

| ID         | Requirement                | Description                                                  |
| ---------- | -------------------------- | ------------------------------------------------------------ |
| FR-NATS-01 | Publish Integration Events | Services can publish integration events.                     |
| FR-NATS-02 | Durable Streams            | Workflow-critical events are persisted in JetStream streams. |
| FR-NATS-03 | Durable Consumers          | Consumers retain delivery position across restart.           |
| FR-NATS-04 | Explicit Acknowledgment    | Messages are acknowledged after successful processing.       |
| FR-NATS-05 | Redelivery                 | Unacknowledged messages may be redelivered.                  |
| FR-NATS-06 | Retry Processing           | Transient failures can be retried.                           |
| FR-NATS-07 | Dead-Letter Handling       | Repeatedly failing messages can be isolated for inspection.  |
| FR-NATS-08 | Fan-Out                    | Multiple independent consumers can receive the same event.   |

---

## Transactional Outbox

| ID           | Requirement            | Description                                                          |
| ------------ | ---------------------- | -------------------------------------------------------------------- |
| FR-OUTBOX-01 | Store Event Atomically | Business state and outgoing event records can be committed together. |
| FR-OUTBOX-02 | Publish Event          | Outbox Publisher sends unpublished events to NATS JetStream.         |
| FR-OUTBOX-03 | Mark Published         | Successfully published records are marked accordingly.               |
| FR-OUTBOX-04 | Retry Publish          | Failed publication attempts can be retried.                          |
| FR-OUTBOX-05 | Duplicate Safe Publish | Downstream consumers tolerate duplicate publication.                 |
