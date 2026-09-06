FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/api-gateway/go.mod services/api-gateway/go.sum ./services/api-gateway/

WORKDIR /src/services/api-gateway

RUN go mod download

WORKDIR /src

COPY services/api-gateway ./services/api-gateway
COPY contracts ./contracts

WORKDIR /src/services/api-gateway

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/api-gateway \
    ./cmd/api


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/api-gateway /app/api-gateway

USER app

EXPOSE 8080

ENTRYPOINT ["/app/api-gateway"]
