FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/concert/go.mod services/concert/go.sum ./services/concert/

WORKDIR /src/services/concert

RUN go mod download

WORKDIR /src

COPY services/concert ./services/concert
COPY contracts ./contracts

WORKDIR /src/services/concert

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/concert \
    ./cmd/api


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/concert /app/concert

USER app

EXPOSE 50051

ENTRYPOINT ["/app/concert"]
