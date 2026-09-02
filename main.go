// TaskGuard — A minimal task tracker API built for Kubernetes demonstration.
// Comments explain the design and its deliberate learning-lab limitations.

package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ---------------------------------------------------------------------------
// DATA MODEL
// ---------------------------------------------------------------------------
// Task is the only domain entity. We keep it flat and JSON-friendly.
// ID is a string (not int) so we can use UUIDs later without changing the API.
type Task struct {
	ID        string    `json:"id"`         // Unique identifier
	Title     string    `json:"title"`      // What needs to be done
	Done      bool      `json:"done"`       // Completion status
	CreatedAt time.Time `json:"created_at"` // Timestamp for observability demos
}

// ---------------------------------------------------------------------------
// IN-MEMORY STORE
// ---------------------------------------------------------------------------
// We use a map protected by a RWMutex instead of a database.
// Why? Because in a K8s demo, the interesting part is how the app BEHAVES
// (crashes, scales, restarts) — not how it persists data.
// When a pod restarts, tasks disappear. That is a FEATURE for this demo:
// it lets us show StatefulSets vs Deployments, emptyDir vs PVCs, etc.
type Store struct {
	mu     sync.RWMutex    // RWMutex allows many readers OR one writer
	tasks  map[string]Task // Key = Task.ID
	nextID int             // Simple auto-increment counter
}

func NewStore() *Store {
	return &Store{
		tasks:  make(map[string]Task),
		nextID: 1,
	}
}

func (s *Store) List() []Task {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Task, 0, len(s.tasks))
	for _, t := range s.tasks {
		out = append(out, t)
	}
	return out
}

func (s *Store) Get(id string) (Task, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	t, ok := s.tasks[id]
	return t, ok
}

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
	tasksActive.Inc()
	return t
}

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

func (s *Store) Delete(id string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.tasks[id]
	if !ok {
		return false
	}
	delete(s.tasks, id)
	tasksDeletedTotal.Inc()
	tasksActive.Dec()
	return true
}

// ---------------------------------------------------------------------------
// PROMETHEUS METRICS
// ---------------------------------------------------------------------------
// These are application-level metrics, NOT infrastructure metrics.
// Infrastructure metrics (CPU, memory, network) come from cAdvisor/kubelet.
// Application metrics prove you understand observability at the code level.
var (
	tasksCreatedTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "taskguard_tasks_created_total",
		Help: "Total number of tasks created",
	})
	tasksDeletedTotal = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "taskguard_tasks_deleted_total",
		Help: "Total number of tasks deleted",
	})
	tasksActive = prometheus.NewGauge(prometheus.GaugeOpts{
		Name: "taskguard_tasks_active",
		Help: "Current number of tasks in the store",
	})
	httpRequestsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "taskguard_http_requests_total",
		Help: "Total HTTP requests by method and path",
	}, []string{"method", "path", "status"})
	httpRequestDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "taskguard_http_request_duration_seconds",
		Help:    "HTTP request latency distribution",
		Buckets: prometheus.DefBuckets, // 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10
	}, []string{"method", "path"})
)

func init() {
	// Register all custom metrics with the global Prometheus registry.
	// If you forget this, /metrics will not expose your custom metrics.
	prometheus.MustRegister(tasksCreatedTotal)
	prometheus.MustRegister(tasksDeletedTotal)
	prometheus.MustRegister(tasksActive)
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

// ---------------------------------------------------------------------------
// READINESS / LIVENESS STATE
// ---------------------------------------------------------------------------
// ready is controlled via POST /readyz/disable and POST /readyz/enable.
// This lets you DEMONSTRATE readiness probes live in the assessment:
// 1. Port-forward a specific Pod, then POST /readyz/disable through the tunnel
// 2. Watch its ready condition become false in the Service's EndpointSlice
// 3. curl -X POST localhost:8080/readyz/enable
// 4. Watch pod rejoin
// This proves you understand the difference between liveness and readiness.
var ready = true
var readyMu sync.RWMutex

func isReady() bool {
	readyMu.RLock()
	defer readyMu.RUnlock()
	return ready
}

func setReady(v bool) {
	readyMu.Lock()
	defer readyMu.Unlock()
	ready = v
}

// ---------------------------------------------------------------------------
// HTTP HANDLERS
// ---------------------------------------------------------------------------
// Every handler is wrapped with instrument() to record Prometheus metrics.
// This is a middleware pattern: the wrapper runs before/after the real handler.

func instrument(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		// We use a ResponseRecorder to capture the status code.
		// The default http.ResponseWriter does not let you read the status after WriteHeader.
		rr := &responseRecorder{ResponseWriter: w, statusCode: http.StatusOK}
		next(rr, r)
		duration := time.Since(start).Seconds()
		httpRequestsTotal.WithLabelValues(r.Method, r.URL.Path, fmt.Sprintf("%d", rr.statusCode)).Inc()
		httpRequestDuration.WithLabelValues(r.Method, r.URL.Path).Observe(duration)
	}
}

// responseRecorder wraps http.ResponseWriter so we can capture the status code.
type responseRecorder struct {
	http.ResponseWriter
	statusCode int
}

func (rr *responseRecorder) WriteHeader(code int) {
	rr.statusCode = code
	rr.ResponseWriter.WriteHeader(code)
}

// --- /healthz (LIVENESS) ---
// Liveness probe: "Is the process alive?"
// If this returns non-200, kubelet kills the container and starts a new one.
// We keep this VERY cheap: no DB calls, no locks, just return 200.
// Why? If liveness is too strict (e.g. checks DB), a temporary DB blip
// causes unnecessary pod restarts. Liveness should catch deadlocks/panics only.
func healthzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// --- /readyz (READINESS) ---
// Readiness probe: "Is the app ready to receive traffic?"
// If this returns non-200, the pod is removed from the Service endpoints.
// The pod keeps running — it just stops receiving new requests.
// We check the 'ready' boolean which can be toggled for demos.
func readyzHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if isReady() {
		json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
	} else {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{"status": "not ready"})
	}
}

func readyzDisableHandler(w http.ResponseWriter, r *http.Request) {
	setReady(false)
	slog.Info("readiness disabled via POST /readyz/disable")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "not ready"})
}

func readyzEnableHandler(w http.ResponseWriter, r *http.Request) {
	setReady(true)
	slog.Info("readiness enabled via POST /readyz/enable")
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ready"})
}

// --- /tasks ---
func listTasksHandler(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		tasks := store.List()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(tasks)
	}
}

func createTaskHandler(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Title string `json:"title"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
			return
		}
		if req.Title == "" {
			http.Error(w, `{"error":"title is required"}`, http.StatusBadRequest)
			return
		}
		task := store.Create(req.Title)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		json.NewEncoder(w).Encode(task)
	}
}

func toggleTaskHandler(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		task, ok := store.Toggle(id)
		if !ok {
			http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(task)
	}
}

func deleteTaskHandler(store *Store) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		id := r.PathValue("id")
		if !store.Delete(id) {
			http.Error(w, `{"error":"task not found"}`, http.StatusNotFound)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// newRouter keeps route construction separate from process startup. This makes
// the complete HTTP API testable without opening a real network port.
func newRouter(store *Store) *http.ServeMux {
	mux := http.NewServeMux()

	// Kubernetes probe polling is intentionally excluded from request metrics.
	mux.HandleFunc("GET /healthz", healthzHandler)
	mux.HandleFunc("GET /readyz", readyzHandler)
	mux.HandleFunc("POST /readyz/disable", readyzDisableHandler)
	mux.HandleFunc("POST /readyz/enable", readyzEnableHandler)

	mux.Handle("GET /metrics", promhttp.Handler())

	mux.HandleFunc("GET /tasks", instrument(listTasksHandler(store)))
	mux.HandleFunc("POST /tasks", instrument(createTaskHandler(store)))
	mux.HandleFunc("PUT /tasks/{id}/toggle", instrument(toggleTaskHandler(store)))
	mux.HandleFunc("DELETE /tasks/{id}", instrument(deleteTaskHandler(store)))

	return mux
}

func configuredLogLevel(value string) slog.Level {
	switch strings.ToLower(value) {
	case "debug":
		return slog.LevelDebug
	case "warn", "warning":
		return slog.LevelWarn
	case "error":
		return slog.LevelError
	default:
		return slog.LevelInfo
	}
}

// ---------------------------------------------------------------------------
// MAIN
// ---------------------------------------------------------------------------
func main() {
	// --- Structured logging ---
	// slog outputs JSON when using NewJSONHandler. This is critical for K8s:
	// log aggregation systems (Fluent Bit, Loki, CloudWatch) parse JSON easily.
	// Text logs require regex parsing which is fragile.
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: configuredLogLevel(os.Getenv("LOG_LEVEL")),
	}))
	slog.SetDefault(logger)

	// --- Port from env var ---
	// 12-factor app principle: config via environment.
	// Hardcoded ports make containers non-portable.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// --- In-memory store ---
	// No database = fewer moving parts = faster to explain.
	// In the live assessment, you can say:
	// "I chose an in-memory store because the demo focuses on K8s behavior.
	// For production I would add Redis (stateful) or PostgreSQL (StatefulSet)."
	store := NewStore()

	// --- Router ---
	// Go 1.22 introduced PathValue routing. No external router is needed.
	mux := newRouter(store)

	// --- Server with timeouts ---
	// Default http.ListenAndServe has NO timeouts. In production this is dangerous:
	// slow clients can exhaust file descriptors. We set explicit timeouts.
	server := &http.Server{
		Addr:         ":" + port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,   // Time to read the full request
		WriteTimeout: 10 * time.Second,  // Time to write the full response
		IdleTimeout:  120 * time.Second, // Time to keep idle connections open (HTTP keep-alive)
	}

	// --- Graceful shutdown ---
	// We run the server in a goroutine so main() can wait for the OS signal.
	// shutdownChan coordinates clean exit.
	shutdownChan := make(chan struct{})
	go func() {
		defer close(shutdownChan)
		slog.Info("server starting", "addr", server.Addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			slog.Error("server failed to start", "error", err)
		}
	}()

	// --- Signal handling ---
	// SIGTERM = Kubernetes sends this when draining a node or deleting a pod.
	// SIGINT = Ctrl-C in local development.
	// We catch both and trigger graceful shutdown.
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGTERM, syscall.SIGINT)

	defer signal.Stop(sigChan)
	select {
	case <-sigChan:
		// Normal shutdown requested by Kubernetes or the local terminal.
	case <-shutdownChan:
		// A bind/listen failure must exit instead of waiting forever for a signal.
		os.Exit(1)
	}
	slog.Info("shutdown signal received, draining connections...")

	// Create a context with timeout for the shutdown.
	// If shutdown takes longer than 15s, we force-close.
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		slog.Error("graceful shutdown failed", "error", err)
		_ = server.Close()
	} else {
		slog.Info("server shut down gracefully")
	}

	<-shutdownChan
}
