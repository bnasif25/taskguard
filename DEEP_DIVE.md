# Deep Dive: Understanding Every Line of main.go

This document exists so you can **explain and modify** every part of the application during the live assessment. Read it carefully. If a judge asks "why did you do X?" the answer is in this file.

---

## Table of Contents

1. [Package and Imports](#1-package-and-imports)
2. [Data Model](#2-data-model)
3. [In-Memory Store](#3-in-memory-store)
4. [Prometheus Metrics](#4-prometheus-metrics)
5. [Readiness / Liveness State](#5-readiness--liveness-state)
6. [HTTP Handlers](#6-http-handlers)
7. [Main Function](#7-main-function)
8. [Graceful Shutdown](#8-graceful-shutdown)

---

## 1. Package and Imports

```go
package main
```

**Why `package main`?** In Go, `main` is a special package name. It tells the compiler to build an executable binary, not a library. Every Go program that runs as a standalone process uses `package main`.

```go
import (
    "context"
    "encoding/json"
    "fmt"
    "log/slog"
    "net/http"
    "os"
    "os/signal"
    "sync"
    "syscall"
    "time"

    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)
```

**Standard library packages:**

| Package | Purpose |
|---------|---------|
| `context` | Request-scoped deadlines and cancellation signals. Used in `server.Shutdown(ctx)` to set a timeout. |
| `encoding/json` | Convert Go structs to JSON and back. Used in every HTTP handler. |
| `fmt` | String formatting. Used to build task IDs like `task-1`. |
| `log/slog` | Structured logging (JSON output). Replaces the older `log` package. Added in Go 1.21. |
| `net/http` | HTTP server and client. The entire app is built on this. |
| `os` | Environment variables (`os.Getenv`), process signals (`os.Signal`). |
| `os/signal` | Register handlers for OS signals like SIGTERM and SIGINT. |
| `sync` | Synchronization primitives: `sync.RWMutex` for thread-safe map access. |
| `syscall` | Low-level system calls. We use it for `syscall.SIGTERM` and `syscall.SIGINT`. |
| `time` | Timestamps, timeouts, sleep durations. |

**Third-party package:**

| Package | Purpose |
|---------|---------|
| `prometheus/client_golang` | Prometheus metrics library. Creates counters, gauges, and histograms. |
| `prometheus/promhttp` | HTTP handler that exposes metrics on `/metrics` in Prometheus text format. |

**Why only one external dependency?** Fewer dependencies = smaller attack surface, faster builds, easier to explain. The judges don't score dependency count, but they will ask "why did you choose this library?" The answer: it's the official Prometheus client, maintained by the Prometheus team, widely used in production.

---

## 2. Data Model

```go
type Task struct {
    ID        string    `json:"id"`
    Title     string    `json:"title"`
    Done      bool      `json:"done"`
    CreatedAt time.Time `json:"created_at"`
}
```

**Why a struct?** In Go, structs are the primary way to group related data. This struct has four fields that describe a task.

**What are the backtick tags?** The `` `json:"id"` `` tags tell Go's `encoding/json` package how to name the field in JSON output. Without them, the JSON key would be `ID` (capitalized), which doesn't match REST API conventions.

**Why `string` for ID instead of `int`?** If we later switch to UUIDs (e.g. `550e8400-e29b-41d4-a716-446655440000`), we don't need to change the type. Strings are more flexible for identifiers.

**Why `time.Time` instead of a string?** `time.Time` carries timezone information and can be formatted consistently. If we stored timestamps as strings, we'd have to parse them manually.

---

## 3. In-Memory Store

```go
type Store struct {
    mu     sync.RWMutex
    tasks  map[string]Task
    nextID int
}
```

**Why a `Store` struct?** We encapsulate the data and the synchronization in one type. This is the "repository pattern" — a single place where all data access happens.

**What is `sync.RWMutex`?** A "read-write mutual exclusion lock." It allows either:
- Many goroutines reading at the same time (RLock), OR
- One goroutine writing (Lock)

**Why not `sync.Mutex`?** `Mutex` allows only one goroutine at a time, even for reads. `RWMutex` is more efficient when reads are frequent (which they are in a web API).

**Why `map[string]Task`?** Go maps are hash tables with O(1) lookup. We use the task ID as the key so we can find a task instantly.

**Why `nextID`?** A simple auto-increment counter. Not thread-safe on its own, but the mutex protects it.

### Constructor

```go
func NewStore() *Store {
    return &Store{
        tasks:  make(map[string]Task),
        nextID: 1,
    }
}
```

**Why a constructor function?** In Go, there's no `new` keyword for structs with initialization logic. A constructor function (`NewXxx`) is the convention.

**Why `make(map[string]Task)`?** Maps in Go must be initialized with `make` before use. A nil map panics when you try to write to it.

### List Method

```go
func (s *Store) List() []Task {
    s.mu.RLock()
    defer s.mu.RUnlock()
    out := make([]Task, 0, len(s.tasks))
    for _, t := range s.tasks {
        out = append(out, t)
    }
    return out
}
```

**What does `RLock()` do?** It acquires the read lock. If another goroutine holds the write lock, this blocks until the writer releases it. If other goroutines hold read locks, this proceeds immediately.

**What is `defer`?** It schedules the function call (`s.mu.RUnlock()`) to run when the current function returns — no matter how it returns (normal return, panic, early return). This prevents forgetting to unlock, which would deadlock the store.

**Why `make([]Task, 0, len(s.tasks))`?** The third argument (`cap`) pre-allocates the slice to the exact size needed. Without it, `append` would repeatedly reallocate memory as the slice grows.

**Why iterate over a map?** Maps in Go are unordered. `List()` returns tasks in random order. For a production app, you'd sort by `CreatedAt`.

### Get Method

```go
func (s *Store) Get(id string) (Task, bool) {
    s.mu.RLock()
    defer s.mu.RUnlock()
    t, ok := s.tasks[id]
    return t, ok
}
```

**What is the `ok` boolean?** In Go, map lookups return `(value, bool)`. The bool is `true` if the key exists, `false` otherwise. This is called the "comma ok idiom."

### Create Method

```go
func (s *Store) Create(title string) Task {
    s.mu.Lock()
    defer s.mu.Unlock()
    t := Task{
        ID:        fmt.Sprintf("task-%d", s.nextID),
        Title:     title,
        Done:      false,
        CreatedAt: time.Now().UTC(),
    }
    s.tasks[t.ID] = t
    s.nextID++
    tasksCreatedTotal.Inc()
    return t
}
```

**Why `Lock()` instead of `RLock()`?** We're writing to the map (adding a task). Writers must use `Lock()`, which blocks all readers and other writers.

**Why `time.Now().UTC()`?** UTC eliminates timezone ambiguity. If you stored local time, a pod in a different timezone would show different timestamps.

**What is `tasksCreatedTotal.Inc()`?** A Prometheus counter increment. Every time a task is created, this counter goes up by 1. Prometheus scrapes this value every 15 seconds.

### Toggle Method

```go
func (s *Store) Toggle(id string) (Task, bool) {
    s.mu.Lock()
    defer s.mu.Unlock()
    t, ok := s.tasks[id]
    if !ok {
        return Task{}, false
    }
    t.Done = !t.Done
    s.tasks[id] = t
    return t, true
}
```

**Why write the struct back to the map?** In Go, map values are copied. If you modify `t` without writing it back, the map still holds the old value.

### Delete Method

```go
func (s *Store) Delete(id string) bool {
    s.mu.Lock()
    defer s.mu.Unlock()
    _, ok := s.tasks[id]
    if !ok {
        return false
    }
    delete(s.tasks, id)
    tasksDeletedTotal.Inc()
    return true
}
```

**Why check `ok` before deleting?** `delete` on a non-existent key is a no-op in Go, but we want to return `false` so the HTTP handler can return 404.

---

## 4. Prometheus Metrics

```go
var (
    tasksCreatedTotal = prometheus.NewCounter(...)
    tasksDeletedTotal = prometheus.NewCounter(...)
    tasksActive       = prometheus.NewGauge(...)
    httpRequestsTotal = prometheus.NewCounterVec(...)
    httpRequestDuration = prometheus.NewHistogramVec(...)
)
```

**What is a `Counter`?** A monotonically increasing value. It can only go up (or reset to 0 on restart). Used for "how many times did X happen?"

**What is a `Gauge`?** A value that can go up or down. Used for "how many items exist right now?"

**What is a `CounterVec`?** A Counter with labels. Each unique combination of labels is a separate time series. We use it to track requests by method, path, and status code.

**What is a `HistogramVec`?** A Histogram with labels. It counts observations into buckets and tracks the sum and count. We use it to track request latency distribution.

**Why `prometheus.DefBuckets`?** Default buckets: 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10 seconds. These cover most web API latencies.

```go
func init() {
    prometheus.MustRegister(tasksCreatedTotal)
    ...
}
```

**What is `init()`?** A special function that runs automatically when the package is imported. We use it to register metrics before `main()` starts.

**Why `MustRegister`?** It panics if registration fails (e.g., duplicate metric name). For a simple app, a panic on startup is acceptable — it means you have a bug to fix.

---

## 5. Readiness / Liveness State

```go
var ready = true
var readyMu sync.RWMutex
```

**Why a package-level variable?** These control the global readiness state of the application. Any HTTP handler can read or modify them.

**Why `sync.RWMutex` instead of `atomic.Bool`?** `atomic.Bool` (Go 1.19+) would work here and be faster. We used `RWMutex` for clarity — it's easier to explain in an interview. You can change it to `atomic.Bool` if you want to show off.

```go
func readyzHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    if isReady() {
        json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
    } else {
        w.WriteHeader(http.StatusServiceUnavailable)
        json.NewEncoder(w).Encode(map[string]string{"status": "not ready"})
    }
}
```

**Why `StatusServiceUnavailable` (503)?** This is the standard HTTP status for "the server is temporarily unable to handle the request." Kubernetes specifically looks for non-2xx responses from readiness probes.

**What happens when this returns 503?** Kubernetes removes the pod's IP from the Service's endpoint list. Existing connections are allowed to finish, but no NEW connections are routed to this pod.

---

## 6. HTTP Handlers

### Instrument Wrapper

```go
func instrument(next http.HandlerFunc) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        start := time.Now()
        rr := &responseRecorder{ResponseWriter: w, statusCode: http.StatusOK}
        next(rr, r)
        duration := time.Since(start).Seconds()
        httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", rr.statusCode)).Inc()
        httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
    }
}
```

**What is a middleware?** A function that wraps another function. The wrapper runs code before and after the inner function. This is the decorator pattern.

**Why `responseRecorder`?** Go's `http.ResponseWriter` doesn't expose the status code after it's written. We embed it in a struct and override `WriteHeader` to capture the code.

**Why `time.Since(start).Seconds()`?** `time.Since` returns a `time.Duration`. Converting to seconds gives us a `float64`, which is what Prometheus histograms expect.

### responseRecorder

```go
type responseRecorder struct {
    http.ResponseWriter
    statusCode int
}

func (rr *responseRecorder) WriteHeader(code int) {
    rr.statusCode = code
    rr.ResponseWriter.WriteHeader(code)
}
```

**What is embedding?** `http.ResponseWriter` is an embedded field. This means `responseRecorder` inherits all methods of `http.ResponseWriter`. We only override `WriteHeader`; all other methods pass through automatically.

**Why default `statusCode` to 200?** If the handler never calls `WriteHeader` (e.g., it only calls `Write`), Go automatically sends 200 OK. We need to capture that default.

---

## 7. Main Function

### Structured Logging

```go
logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
    Level: slog.LevelInfo,
}))
slog.SetDefault(logger)
```

**Why JSON logs?** Kubernetes log aggregation (Fluent Bit, Loki, CloudWatch) parses JSON automatically. Text logs require regex rules that break when the format changes.

**Why `slog` instead of `logrus` or `zap`?** `slog` is in the standard library (Go 1.21+). No external dependency needed. For this demo, it's sufficient.

### Port from Environment

```go
port := os.Getenv("PORT")
if port == "" {
    port = "8080"
}
```

**Why from environment?** The 12-Factor App methodology says: "Store config in the environment." Hardcoded ports make containers non-portable. Cloud platforms assign random ports.

### Server with Timeouts

```go
server := &http.Server{
    Addr:         ":" + port,
    Handler:      mux,
    ReadTimeout:  5 * time.Second,
    WriteTimeout: 10 * time.Second,
    IdleTimeout:  120 * time.Second,
}
```

**What is `ReadTimeout`?** Maximum time to read the entire request (including body). Protects against slowloris attacks that send headers byte-by-byte.

**What is `WriteTimeout`?** Maximum time to write the response. Protects against slow clients that read the response byte-by-byte.

**What is `IdleTimeout`?** Maximum time to keep an idle connection open (HTTP keep-alive). After this, the connection is closed. Prevents file descriptor exhaustion.

**Why does the default `http.ListenAndServe` have NO timeouts?** It's a design flaw in the standard library. Production code MUST set timeouts.

### Goroutine for Server

```go
shutdownChan := make(chan struct{})
go func() {
    slog.Info("server starting", "addr", server.Addr)
    if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        slog.Error("server failed to start", "error", err)
        close(shutdownChan)
    }
}()
```

**What is a goroutine?** A lightweight thread managed by the Go runtime. `go func()` starts the function running concurrently with the rest of the program.

**Why run the server in a goroutine?** We need the main thread to wait for the OS signal. If `ListenAndServe` ran in the main thread, we'd never reach the signal handler.

**Why check `err != http.ErrServerClosed`?** `Shutdown()` causes `ListenAndServe` to return `http.ErrServerClosed`. This is expected, not an error.

---

## 8. Graceful Shutdown

```go
sigChan := make(chan os.Signal, 1)
signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)

<-sigChan // Block until signal received
```

**What is `signal.Notify`?** It tells the OS to send `SIGTERM` and `SIGINT` to our `sigChan` instead of terminating the process immediately.

**Why buffer size 1?** If two signals arrive simultaneously, the second one would be lost with an unbuffered channel. Buffer size 1 ensures we catch at least one.

**What is `<-sigChan`?** Receive from the channel. This blocks the main thread until a signal arrives.

### Shutdown with Timeout

```go
ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
defer cancel()

if err := server.Shutdown(ctx); err != nil {
    slog.Error("graceful shutdown failed", "error", err)
} else {
    slog.Info("server shut down gracefully")
}
```

**What does `server.Shutdown(ctx)` do?**
1. Closes the listening socket (no new connections accepted)
2. Waits for all active requests to finish
3. If the context expires first, force-closes remaining connections

**Why 15 seconds?** Kubernetes sends SIGTERM, then waits `terminationGracePeriodSeconds` (30s in our Deployment) before sending SIGKILL. We use 15s to leave a safety margin.

**What is `context.WithTimeout`?** Creates a context that automatically cancels after the specified duration. If shutdown takes longer than 15s, the context fires and `Shutdown` returns an error.

**Why `defer cancel()`?** Even if `Shutdown` succeeds, we must call `cancel()` to release the context's resources. `defer` ensures this happens.

---

## Quick Reference: Questions You Might Get

**Q: Why Go and not Node.js?**
A: Single static binary, no runtime, fast startup, built-in concurrency. Smaller image = faster pod startup = better HPA response.

**Q: Why in-memory and not Redis?**
A: The demo focuses on Kubernetes behavior. A database adds complexity without scoring points. I can add Redis later by changing the Store interface.

**Q: What's the difference between liveness and readiness?**
A: Liveness failure = kubelet restarts the container. Readiness failure = pod removed from Service endpoints but keeps running.

**Q: Why separate `/healthz` and `/readyz`?**
A: If liveness checked the database, a temporary DB blip would cause unnecessary pod restarts. Liveness should only catch deadlocks/panics.

**Q: Why `sync.RWMutex` and not `sync.Mutex`?**
A: RWMutex allows many concurrent readers. In a read-heavy API, this is more efficient.

**Q: Why JSON logs?**
A: Log aggregators parse JSON automatically. Text logs require fragile regex rules.

**Q: What happens during a rolling update?**
A: Kubernetes creates a new pod, waits for it to pass readiness, then removes an old pod. `maxUnavailable: 0` ensures we never drop below 2 replicas.

**Q: What happens when you drain a node?**
A: kubelet sends SIGTERM, waits 30s, then SIGKILL. Our app catches SIGTERM and shuts down gracefully within 15s.

**Q: How does HPA know when to scale?**
A: The HPA controller queries the Metrics Server for pod CPU/memory. When average CPU > 70%, it increases replicas. When CPU < 70% for 5 minutes, it decreases.

**Q: What does the NetworkPolicy block?**
A: It blocks all ingress except from the ingress controller, monitoring namespace, and same namespace. Pods in other namespaces cannot reach TaskGuard.

**Q: Why `runAsNonRoot: true`?**
A: If an attacker escapes the container, they gain uid 1000 on the host, not root. Defense in depth.

---

Read this file until you can answer every question without looking.
