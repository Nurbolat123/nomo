FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum* ./
COPY . .
RUN go mod tidy && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata && adduser -D -u 10001 nomo
WORKDIR /app
COPY --from=build /out/api /app/api
RUN mkdir -p /app/uploads && chown nomo /app/uploads
USER nomo
ENV UPLOAD_DIR=/app/uploads
EXPOSE 8080
ENTRYPOINT ["/app/api"]
