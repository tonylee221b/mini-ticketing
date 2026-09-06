FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/notification/go.mod services/notification/go.sum ./services/notification/

WORKDIR /src/services/notification

RUN go mod download

WORKDIR /src

COPY services/notification ./services/notification
COPY contracts ./contracts

WORKDIR /src/services/notification

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/notification \
    ./cmd/worker


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/notification /app/notification

USER app

ENTRYPOINT ["/app/notification"]
