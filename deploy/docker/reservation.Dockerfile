FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/reservation/go.mod services/reservation/go.sum ./services/reservation/

WORKDIR /src/services/reservation

RUN go mod download

WORKDIR /src

COPY services/reservation ./services/reservation
COPY contracts ./contracts

WORKDIR /src/services/reservation

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/reservation \
    ./cmd/api


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/reservation /app/reservation

USER app

EXPOSE 50051

ENTRYPOINT ["/app/reservation"]
