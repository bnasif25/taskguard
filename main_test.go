package main

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	dto "github.com/prometheus/client_model/go"
)

func request(t *testing.T, handler http.Handler, method, path, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	recorder := httptest.NewRecorder()
	handler.ServeHTTP(recorder, req)
	return recorder
}

func TestStoreLifecycle(t *testing.T) {
	store := NewStore()
	created := store.Create("Write tests")

	if created.ID != "task-1" || created.Title != "Write tests" || created.Done {
		t.Fatalf("unexpected created task: %+v", created)
	}
	if created.CreatedAt.IsZero() {
		t.Fatal("created_at should be populated")
	}
	if got := len(store.List()); got != 1 {
		t.Fatalf("task count = %d, want 1", got)
	}
	if got, ok := store.Get(created.ID); !ok || got.ID != created.ID {
		t.Fatal("expected Get to return the created task")
	}
	if _, ok := store.Get("missing"); ok {
		t.Fatal("missing task should not be found")
	}

	toggled, ok := store.Toggle(created.ID)
	if !ok || !toggled.Done {
		t.Fatalf("expected task to be toggled done: %+v, found=%v", toggled, ok)
	}
	if !store.Delete(created.ID) {
		t.Fatal("expected existing task to be deleted")
	}
	if store.Delete(created.ID) {
		t.Fatal("deleting a missing task should return false")
	}
}

func TestActiveTaskMetricChangesWithoutListing(t *testing.T) {
	tasksActive.Set(0)
	t.Cleanup(func() { tasksActive.Set(0) })
	store := NewStore()
	task := store.Create("Observe metric without GET /tasks")
	metric := &dto.Metric{}
	if err := tasksActive.Write(metric); err != nil {
		t.Fatal(err)
	}
	if got := metric.GetGauge().GetValue(); got != 1 {
		t.Fatalf("active gauge after create = %v, want 1", got)
	}
	store.Delete(task.ID)
	if err := tasksActive.Write(metric); err != nil {
		t.Fatal(err)
	}
	if got := metric.GetGauge().GetValue(); got != 0 {
		t.Fatalf("active gauge after delete = %v, want 0", got)
	}
}

func TestHealthAndReadiness(t *testing.T) {
	setReady(true)
	t.Cleanup(func() { setReady(true) })
	router := newRouter(NewStore())

	if got := request(t, router, http.MethodGet, "/healthz", "").Code; got != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", got)
	}
	if got := request(t, router, http.MethodGet, "/readyz", "").Code; got != http.StatusOK {
		t.Fatalf("readyz status = %d, want 200", got)
	}

	request(t, router, http.MethodPost, "/readyz/disable", "")
	if got := request(t, router, http.MethodGet, "/readyz", "").Code; got != http.StatusServiceUnavailable {
		t.Fatalf("disabled readyz status = %d, want 503", got)
	}
	if got := request(t, router, http.MethodGet, "/healthz", "").Code; got != http.StatusOK {
		t.Fatalf("health should remain 200 when readiness is disabled, got %d", got)
	}

	request(t, router, http.MethodPost, "/readyz/enable", "")
	if got := request(t, router, http.MethodGet, "/readyz", "").Code; got != http.StatusOK {
		t.Fatalf("re-enabled readyz status = %d, want 200", got)
	}
}

func TestTaskAPI(t *testing.T) {
	router := newRouter(NewStore())

	createdResponse := request(t, router, http.MethodPost, "/tasks", `{"title":"Learn Kubernetes"}`)
	if createdResponse.Code != http.StatusCreated {
		t.Fatalf("create status = %d, want 201; body=%s", createdResponse.Code, createdResponse.Body)
	}
	var created Task
	if err := json.NewDecoder(createdResponse.Body).Decode(&created); err != nil {
		t.Fatalf("decode create response: %v", err)
	}

	listResponse := request(t, router, http.MethodGet, "/tasks", "")
	var tasks []Task
	if err := json.NewDecoder(listResponse.Body).Decode(&tasks); err != nil {
		t.Fatalf("decode list response: %v", err)
	}
	if listResponse.Code != http.StatusOK || len(tasks) != 1 {
		t.Fatalf("list status=%d tasks=%d, want 200 and one task", listResponse.Code, len(tasks))
	}

	toggleResponse := request(t, router, http.MethodPut, "/tasks/"+created.ID+"/toggle", "")
	if toggleResponse.Code != http.StatusOK {
		t.Fatalf("toggle status = %d, want 200", toggleResponse.Code)
	}
	var toggled Task
	if err := json.NewDecoder(toggleResponse.Body).Decode(&toggled); err != nil {
		t.Fatalf("decode toggle response: %v", err)
	}
	if !toggled.Done {
		t.Fatal("toggle should mark the task done")
	}

	if got := request(t, router, http.MethodDelete, "/tasks/"+created.ID, "").Code; got != http.StatusNoContent {
		t.Fatalf("delete status = %d, want 204", got)
	}
	if got := request(t, router, http.MethodDelete, "/tasks/"+created.ID, "").Code; got != http.StatusNotFound {
		t.Fatalf("second delete status = %d, want 404", got)
	}
}

func TestTaskAPIRejectsInvalidInput(t *testing.T) {
	router := newRouter(NewStore())
	tests := []struct {
		name string
		body string
	}{
		{name: "invalid JSON", body: `{`},
		{name: "missing title", body: `{}`},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := request(t, router, http.MethodPost, "/tasks", test.body).Code; got != http.StatusBadRequest {
				t.Fatalf("status = %d, want 400", got)
			}
		})
	}
}

func TestMetricsEndpoint(t *testing.T) {
	response := request(t, newRouter(NewStore()), http.MethodGet, "/metrics", "")
	if response.Code != http.StatusOK {
		t.Fatalf("metrics status = %d, want 200", response.Code)
	}
	if !strings.Contains(response.Body.String(), "taskguard_tasks_created_total") {
		t.Fatal("metrics output is missing taskguard_tasks_created_total")
	}
}

func TestConfiguredLogLevel(t *testing.T) {
	tests := map[string]slog.Level{
		"debug":   slog.LevelDebug,
		"info":    slog.LevelInfo,
		"warning": slog.LevelWarn,
		"error":   slog.LevelError,
		"unknown": slog.LevelInfo,
	}
	for input, want := range tests {
		if got := configuredLogLevel(input); got != want {
			t.Errorf("configuredLogLevel(%q) = %v, want %v", input, got, want)
		}
	}
}
