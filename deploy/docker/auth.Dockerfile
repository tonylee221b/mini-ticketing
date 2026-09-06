FROM golang:1.26-alpine AS builder

WORKDIR /src

COPY services/auth/go.mod services/auth/go.sum ./services/auth/

WORKDIR /src/services/auth

RUN go mod download

WORKDIR /src

COPY services/auth ./services/auth
COPY contracts ./contracts

WORKDIR /src/services/auth

RUN CGO_ENABLED=0 GOOS=linux go build \
    -trimpath \
    -ldflags="-s -w" \
    -o /out/auth \
    ./cmd/api


FROM alpine:3.22

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY --from=builder /out/auth /app/auth

USER app

EXPOSE 50051

ENTRYPOINT ["/app/auth"]
