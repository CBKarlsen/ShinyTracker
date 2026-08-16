# syntax=docker/dockerfile:1
# --- build stage ---
FROM golang:1.26-alpine AS build
WORKDIR /src

# Cache deps first
COPY go.mod go.sum ./
RUN go mod download

# Build the API binary (static, no CGO)
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /out/api ./cmd/api

# --- runtime stage ---
FROM alpine:3.20
RUN apk add --no-cache ca-certificates
WORKDIR /app
COPY --from=build /out/api /app/api

# Run as a non-root user: no reason the process needs root inside the container.
RUN addgroup -S app && adduser -S -G app app
USER app

# Railway injects $PORT; main.go falls back to 8080 if unset.
EXPOSE 8080
CMD ["/app/api"]
