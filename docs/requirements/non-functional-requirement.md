# Non-Functional Requirements

## API Gateway

| ID             | Requirement                 | Description                                                                                             |
| -------------- | --------------------------- | ------------------------------------------------------------------------------------------------------- |
| NFR-GATEWAY-01 | Single Public Entry Point   | Public clients must not directly depend on internal service addresses.                                  |
| NFR-GATEWAY-02 | No Business Logic           | Gateway must not implement seat, reservation, payment, or Saga business logic.                          |
| NFR-GATEWAY-03 | Authentication Boundary     | Protected traffic must be authenticated before trusted identity is propagated internally.               |
| NFR-GATEWAY-04 | Statelessness               | Gateway should remain stateless for normal routing and access-token verification.                       |
| NFR-GATEWAY-05 | Bounded Timeout             | Forwarded requests must use bounded timeouts.                                                           |
| NFR-GATEWAY-06 | Failure Isolation           | Failure of one backend route should not unnecessarily break unrelated routes.                           |
| NFR-GATEWAY-07 | Observability               | Gateway participates in structured logging, metrics, and distributed tracing.                           |
| NFR-GATEWAY-08 | Sensitive Header Protection | Authentication and internal identity headers must not be logged as raw secrets.                         |
| NFR-GATEWAY-09 | Trusted Context             | Client-supplied internal identity headers must not be forwarded as trusted identity without validation. |

---

## Auth Service

| ID          | Requirement                   | Description                                                                               |
| ----------- | ----------------------------- | ----------------------------------------------------------------------------------------- |
| NFR-AUTH-01 | Password Security             | Passwords must never be stored in plaintext.                                              |
| NFR-AUTH-02 | PASETO Access Tokens          | Protected operations use cryptographically validated PASETO access tokens.                |
| NFR-AUTH-03 | Short-Lived Access Token      | Access tokens have a limited lifetime.                                                    |
| NFR-AUTH-04 | Refresh Token Confidentiality | Raw refresh tokens are never stored or logged.                                            |
| NFR-AUTH-05 | Refresh Token Hashing         | Only a secure refresh token hash is persisted.                                            |
| NFR-AUTH-06 | Refresh Token Rotation        | A successfully used refresh token becomes invalid immediately.                            |
| NFR-AUTH-07 | Reuse Detection               | Reuse of rotated or revoked refresh tokens must be detectable.                            |
| NFR-AUTH-08 | Family Revocation             | Detected reuse revokes the associated session or token family.                            |
| NFR-AUTH-09 | Atomic Rotation               | Rotation-related validation and persistence are transactionally coordinated.              |
| NFR-AUTH-10 | Concurrent Refresh Safety     | Concurrent use of one refresh token must not create multiple valid token branches.        |
| NFR-AUTH-11 | Session Revocation            | Logout revokes the corresponding refresh session.                                         |
| NFR-AUTH-12 | Local Access Validation       | Access-token verification should not require synchronous Auth Service access per request. |
| NFR-AUTH-13 | Secret Logging                | Passwords and authentication tokens must never appear in logs.                            |
| NFR-AUTH-14 | Data Ownership                | Only Auth Service directly accesses authentication state.                                 |

---

## Concert Service

| ID             | Requirement            | Description                                                                     |
| -------------- | ---------------------- | ------------------------------------------------------------------------------- |
| NFR-CONCERT-01 | Seat Consistency       | A seat cannot simultaneously belong to multiple active bookings.                |
| NFR-CONCERT-02 | Atomic Multi-Seat Hold | Multi-seat state changes either succeed entirely or fail entirely.              |
| NFR-CONCERT-03 | Concurrency Safety     | Seat state remains correct under concurrent booking requests.                   |
| NFR-CONCERT-04 | Database Integrity     | Database constraints and transactions enforce seat invariants.                  |
| NFR-CONCERT-05 | Query Performance      | Concert and seat queries target p95 below 200 ms under normal development load. |
| NFR-CONCERT-06 | Data Ownership         | Only Concert Service modifies Concert DB.                                       |
| NFR-CONCERT-07 | Seat Uniqueness        | `(concert_id, seat_number)` remains unique.                                     |

---

## Reservation Service

| ID                 | Requirement            | Description                                                                                                             |
| ------------------ | ---------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| NFR-RESERVATION-01 | State Correctness      | Invalid reservation transitions are rejected.                                                                           |
| NFR-RESERVATION-02 | Expiration Reliability | Expired reservations are eventually processed.                                                                          |
| NFR-RESERVATION-03 | Payment Grace Safety   | A reservation undergoing valid payment processing must not be incorrectly released solely due to the original hold TTL. |
| NFR-RESERVATION-04 | Retry Safety           | Retries do not create duplicate reservations or invalid transitions.                                                    |
| NFR-RESERVATION-05 | Outbox Consistency     | Required outgoing events are persisted transactionally with state changes.                                              |
| NFR-RESERVATION-06 | Duplicate Event Safety | Duplicate messages are processed idempotently.                                                                          |
| NFR-RESERVATION-07 | Compensation Safety    | Cancel and expiration operations tolerate retry.                                                                        |
| NFR-RESERVATION-08 | User Ownership         | Protected reservation access respects reservation ownership where applicable.                                           |

---

## Payment Service

| ID             | Requirement                | Description                                                                                |
| -------------- | -------------------------- | ------------------------------------------------------------------------------------------ |
| NFR-PAYMENT-01 | Payment Idempotency        | Retries never create duplicate charges.                                                    |
| NFR-PAYMENT-02 | State Consistency          | Invalid payment transitions are rejected.                                                  |
| NFR-PAYMENT-03 | Timeout Semantics          | Network or RPC timeout is treated as an unknown result unless failure is explicitly known. |
| NFR-PAYMENT-04 | Provider Failure Tolerance | Provider delays and transient failures do not corrupt payment state.                       |
| NFR-PAYMENT-05 | Reconciliation             | Unresolved payment state must be recoverable through provider status reconciliation.       |
| NFR-PAYMENT-06 | Callback Idempotency       | Duplicate provider callbacks must be handled safely.                                       |
| NFR-PAYMENT-07 | Outbox Consistency         | Payment state and outgoing integration events are committed consistently.                  |
| NFR-PAYMENT-08 | Compensation Safety        | Cancellation and refund operations tolerate retry.                                         |
| NFR-PAYMENT-09 | Data Ownership             | Only Payment Service accesses Payment DB directly.                                         |

---

## Booking Saga Orchestrator

| ID          | Requirement             | Description                                                                                   |
| ----------- | ----------------------- | --------------------------------------------------------------------------------------------- |
| NFR-SAGA-01 | Durable Execution       | Saga state survives process and container restart.                                            |
| NFR-SAGA-02 | Idempotent Steps        | Every Saga step tolerates retries.                                                            |
| NFR-SAGA-03 | Idempotent Compensation | Compensation steps tolerate retries and duplicate execution.                                  |
| NFR-SAGA-04 | Failure Recovery        | Incomplete workflows eventually resume, compensate, or reach an observable failed state.      |
| NFR-SAGA-05 | Persistent State        | Workflow correctness does not depend only on in-memory state.                                 |
| NFR-SAGA-06 | RPC Timeout Handling    | Remote RPC timeout does not automatically imply business failure.                             |
| NFR-SAGA-07 | Waiting State           | Unknown payment outcomes can transition the Saga to `WAITING_PAYMENT`.                        |
| NFR-SAGA-08 | Retry Classification    | Retryable infrastructure errors are distinguished from business failures and unknown results. |
| NFR-SAGA-09 | Crash Safety            | Process failure between steps does not lose workflow progression.                             |
| NFR-SAGA-10 | Eventual Completion     | Every Saga eventually reaches a terminal or manually actionable state.                        |
| NFR-SAGA-11 | Observability           | Saga execution is traceable through `saga_id`.                                                |

---

## Notification Service

| ID                  | Requirement       | Description                                             |
| ------------------- | ----------------- | ------------------------------------------------------- |
| NFR-NOTIFICATION-01 | Failure Isolation | Notification failure does not block booking completion. |
| NFR-NOTIFICATION-02 | Eventual Delivery | Notification processing may be asynchronous.            |
| NFR-NOTIFICATION-03 | Duplicate Safety  | Duplicate events are processed safely.                  |
| NFR-NOTIFICATION-04 | Retry Safety      | Notification processing may be retried independently.   |

---

## gRPC

| ID          | Requirement            | Description                                                                              |
| ----------- | ---------------------- | ---------------------------------------------------------------------------------------- |
| NFR-GRPC-01 | Bounded Deadline       | Every RPC uses a finite deadline.                                                        |
| NFR-GRPC-02 | Deadline Propagation   | Downstream calls respect remaining upstream deadlines where appropriate.                 |
| NFR-GRPC-03 | Connection Reuse       | Client connections are reused.                                                           |
| NFR-GRPC-04 | Contract Compatibility | Proto changes preserve compatibility unless intentionally versioned.                     |
| NFR-GRPC-05 | No Domain Leakage      | Proto contracts do not directly expose internal domain models.                           |
| NFR-GRPC-06 | Error Mapping          | Business, infrastructure, and unknown-result conditions use appropriate status handling. |
| NFR-GRPC-07 | Observability          | RPCs participate in logging, metrics, and tracing.                                       |
| NFR-GRPC-08 | Graceful Shutdown      | Services gracefully stop accepting new RPCs where practical.                             |
| NFR-GRPC-09 | Health Checking        | Internal service health is inspectable.                                                  |
| NFR-GRPC-10 | Retry Safety           | Retries are enabled only for retry-safe operations.                                      |

---

## NATS JetStream

| ID          | Requirement             | Description                                                   |
| ----------- | ----------------------- | ------------------------------------------------------------- |
| NFR-NATS-01 | At-Least-Once Delivery  | Messages may be delivered more than once.                     |
| NFR-NATS-02 | Durability              | Workflow-critical events are persisted.                       |
| NFR-NATS-03 | Consumer Recovery       | Durable consumers continue after restart.                     |
| NFR-NATS-04 | Explicit Acknowledgment | Events are acknowledged only after successful processing.     |
| NFR-NATS-05 | Duplicate Tolerance     | Correctness does not depend on exactly-once delivery.         |
| NFR-NATS-06 | Loose Coupling          | Producers do not require asynchronous consumers to be online. |
| NFR-NATS-07 | Failure Visibility      | Repeatedly failing events remain observable.                  |

---

## Transactional Outbox

| ID            | Requirement                  | Description                                                                              |
| ------------- | ---------------------------- | ---------------------------------------------------------------------------------------- |
| NFR-OUTBOX-01 | Atomicity                    | Business state and outbox records commit atomically.                                     |
| NFR-OUTBOX-02 | Eventual Publication         | Committed outbox events are eventually published when NATS becomes available.            |
| NFR-OUTBOX-03 | Publisher Recovery           | Publisher restart does not lose committed events.                                        |
| NFR-OUTBOX-04 | Duplicate Publication Safety | Duplicate publication does not corrupt consumer state.                                   |
| NFR-OUTBOX-05 | Cleanup                      | Successfully published records may be archived or deleted according to retention policy. |

---

## Cross-Service Requirements

| ID            | Requirement                 | Description                                                                                                                                                    |
| ------------- | --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| NFR-SYSTEM-01 | Database per Service        | Each service owns its own database.                                                                                                                            |
| NFR-SYSTEM-02 | No Cross-Service DB Access  | Services do not directly query another service's database.                                                                                                     |
| NFR-SYSTEM-03 | Independent Deployment      | Every service is independently buildable and runnable.                                                                                                         |
| NFR-SYSTEM-04 | No Shared Domain Package    | Business-domain code is not imported across service boundaries.                                                                                                |
| NFR-SYSTEM-05 | External Protocol           | External client communication uses HTTP/JSON through API Gateway.                                                                                              |
| NFR-SYSTEM-06 | Internal Sync Protocol      | Internal synchronous communication uses gRPC where appropriate.                                                                                                |
| NFR-SYSTEM-07 | Async Messaging             | Integration events use NATS JetStream.                                                                                                                         |
| NFR-SYSTEM-08 | Eventual Consistency        | Distributed business operations do not depend on distributed ACID transactions.                                                                                |
| NFR-SYSTEM-09 | Saga Coordination           | Booking transactions are coordinated by Booking Saga Orchestrator.                                                                                             |
| NFR-SYSTEM-10 | Idempotency                 | Retryable commands, events, callbacks, Saga steps, and compensation are idempotent.                                                                            |
| NFR-SYSTEM-11 | Timeout Discipline          | Every synchronous network request uses a finite timeout.                                                                                                       |
| NFR-SYSTEM-12 | Retry Discipline            | Retries are only applied to operations known to be safe to retry.                                                                                              |
| NFR-SYSTEM-13 | Correctness over Throughput | Correctness is prioritized under concurrency and partial failure.                                                                                              |
| NFR-SYSTEM-14 | Failure Isolation           | Failure of one service should not unnecessarily cascade.                                                                                                       |
| NFR-SYSTEM-15 | Structured Logging          | Services use consistent structured logs.                                                                                                                       |
| NFR-SYSTEM-16 | Distributed Tracing         | Trace context propagates across HTTP, gRPC, and NATS.                                                                                                          |
| NFR-SYSTEM-17 | Traceability                | Core operations use `request_id`, `trace_id`, `user_id`, `session_id`, `concert_id`, `reservation_id`, `payment_id`, `saga_id`, and `event_id` where relevant. |
| NFR-SYSTEM-18 | Sensitive Data Logging      | Secrets, passwords, and tokens are never logged.                                                                                                               |
| NFR-SYSTEM-19 | Testability                 | Tests include unit, integration, concurrency, authentication rotation, gRPC, idempotency, callback, and distributed failure scenarios.                         |
| NFR-SYSTEM-20 | Docker Compose Deployment   | Initial deployment uses Docker Compose.                                                                                                                        |
| NFR-SYSTEM-21 | No Service Mesh Initially   | Service Mesh is excluded from the initial Compose phase.                                                                                                       |
| NFR-SYSTEM-22 | No Event Sourcing           | PostgreSQL state-based persistence remains the source of truth.                                                                                                |
