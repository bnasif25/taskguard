# Multi-stage build: compile in a full image, ship a minimal image.
# This reduces attack surface and image size.

# ---------- STAGE 1: Builder ----------
FROM golang:1.27.1-alpine3.24@sha256:cf6fca6641884b8433441b2b0652976f975e1d0fdd26d177eaaf8596087f3125 AS builder

# Install git + ca-certificates so 'go mod download' can fetch from GitHub.
RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Copy go.mod first (before main.go) to leverage Docker layer caching.
# If go.mod doesn't change, Docker reuses the cached 'go mod download' layer.
COPY go.mod go.sum ./
RUN go mod download

# Copy source and build a static binary.
# CGO_ENABLED=0 = no C dependencies, works in scratch/alpine.
# The builder's platform selects the architecture: arm64 on an M-series Mac,
# or amd64 when building with --platform=linux/amd64.
# -ldflags '-s -w' = strip debug info, smaller binary.
COPY main.go ./
RUN CGO_ENABLED=0 go build \
    -ldflags '-s -w' \
    -o taskguard \
    main.go

# ---------- STAGE 2: Runtime ----------
# The app is a static binary, so it needs no shell or package manager at runtime.
# A scratch image removes unused OS packages and their vulnerability surface.
FROM scratch

WORKDIR /app

# Keep the standard certificate bundle available if HTTPS clients are added later.
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy only the compiled binary from the builder stage.
COPY --from=builder /app/taskguard ./

# The binary listens on this port.
EXPOSE 8080

# Switch to non-root user BEFORE starting the app.
USER 1000:1000

# Run the binary directly (no shell). Using ENTRYPOINT makes the container
# behave like the binary itself — signals are passed correctly.
ENTRYPOINT ["./taskguard"]
