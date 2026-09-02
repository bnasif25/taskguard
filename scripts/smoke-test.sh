#!/bin/sh
set -eu

NAMESPACE="${NAMESPACE:-taskguard}"
KUBE_CONTEXT="${KUBE_CONTEXT:-minikube}"
LOCAL_PORT="${LOCAL_PORT:-18080}"
BASE_URL="http://127.0.0.1:${LOCAL_PORT}"
PORT_FORWARD_LOG="$(mktemp -t taskguard-port-forward.XXXXXX)"

kubectl() {
	command kubectl --context="$KUBE_CONTEXT" "$@"
}

cleanup() {
	kill "${PORT_FORWARD_PID:-}" 2>/dev/null || true
	wait "${PORT_FORWARD_PID:-}" 2>/dev/null || true
	rm -f "$PORT_FORWARD_LOG"
}
trap cleanup EXIT INT TERM

echo "==> Checking Kubernetes workload state"
kubectl wait --for=condition=Available deployment/taskguard -n "$NAMESPACE" --timeout=120s
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=api

ENDPOINT_COUNT="$(kubectl get endpointslice -n "$NAMESPACE" \
	-l kubernetes.io/service-name=taskguard \
	-o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -c true || true)"
if [ "$ENDPOINT_COUNT" -lt 2 ]; then
	echo "ERROR: expected at least two ready Service endpoints, found $ENDPOINT_COUNT"
	exit 1
fi
echo "==> Service has $ENDPOINT_COUNT ready endpoints"

kubectl port-forward -n "$NAMESPACE" service/taskguard "${LOCAL_PORT}:8080" >"$PORT_FORWARD_LOG" 2>&1 &
PORT_FORWARD_PID=$!

ATTEMPT=0
until curl -fsS "$BASE_URL/healthz" >/dev/null 2>&1; do
	ATTEMPT=$((ATTEMPT + 1))
	if [ "$ATTEMPT" -ge 20 ]; then
		echo "ERROR: port-forward did not become ready"
		cat "$PORT_FORWARD_LOG"
		exit 1
	fi
	sleep 1
done
if ! kill -0 "$PORT_FORWARD_PID" 2>/dev/null; then
	echo "ERROR: this test's port-forward exited; the local port may already be in use"
	cat "$PORT_FORWARD_LOG"
	exit 1
fi

echo "==> Checking health and readiness"
curl -fsS "$BASE_URL/healthz" | grep -q '"status":"ok"'
curl -fsS "$BASE_URL/readyz" | grep -q '"status":"ready"'

echo "==> Checking the task API"
curl -fsS "$BASE_URL/tasks" >/dev/null
CREATED="$(curl -fsS -X POST "$BASE_URL/tasks" \
	-H 'Content-Type: application/json' \
	-d '{"title":"submission smoke test"}')"
TASK_ID="$(printf '%s' "$CREATED" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
test -n "$TASK_ID"
curl -fsS -X PUT "$BASE_URL/tasks/$TASK_ID/toggle" | grep -q '"done":true'
DELETE_STATUS="$(curl -sS -o /dev/null -w '%{http_code}' -X DELETE "$BASE_URL/tasks/$TASK_ID")"
test "$DELETE_STATUS" = 204
if curl -fsS "$BASE_URL/tasks" | grep -q '"id":"'"$TASK_ID"'"'; then
	echo "ERROR: deleted task still appears in the list"
	exit 1
fi

echo "==> Checking application metrics"
curl -fsS "$BASE_URL/metrics" | grep -q '^taskguard_http_requests_total'

echo "PASS: TaskGuard deployment, Service endpoints, API, and metrics are healthy"
