FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/saga-orchestrator/go.mod services/saga-orchestrator/go.sum ./services/saga-orchestrator/

WORKDIR /src/services/saga-orchestrator

RUN go mod download

WORKDIR /src

COPY services/saga-orchestrator ./services/saga-orchestrator
COPY contracts ./contracts

WORKDIR /src/services/saga-orchestrator

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/saga-orchestrator \
    ./cmd/api


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/saga-orchestrator /app/saga-orchestrator

USER app

EXPOSE 50051

ENTRYPOINT ["/app/saga-orchestrator"]
