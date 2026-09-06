FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/payment/go.mod services/payment/go.sum ./services/payment/

WORKDIR /src/services/payment

RUN go mod download

WORKDIR /src

COPY services/payment ./services/payment
COPY contracts ./contracts

WORKDIR /src/services/payment

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/payment \
    ./cmd/api


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/payment /app/payment

USER app

EXPOSE 50051

ENTRYPOINT ["/app/payment"]
