FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o server ./cmd/server

FROM alpine:3.20
WORKDIR /app
RUN adduser -D -u 1001 aerodrive
COPY --from=builder --chown=aerodrive:aerodrive /app/server .
USER aerodrive
EXPOSE 8080
CMD ["./server"]
