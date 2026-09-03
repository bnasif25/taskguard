# TaskGuard Operational Runbook

## System summary

- Namespace: `taskguard`
- Deployment/Service/HPA/PDB: `taskguard`
- Application port: `8080`
- Health: `/healthz`
- Readiness: `/readyz`
- Metrics: `/metrics`
- Monitoring namespace/release: `monitoring` / `prometheus`

## First five commands

Use these in order whenever TaskGuard appears unhealthy:

Confirm `kubectl config current-context` is `minikube` first. The Make targets
select their context explicitly; the manual examples below use the current context.

```bash
kubectl get deployment,pods,service,endpointslice -n taskguard -o wide
kubectl describe deployment taskguard -n taskguard
kubectl describe pod -n taskguard -l app.kubernetes.io/component=api
kubectl logs -n taskguard deployment/taskguard --tail=100
kubectl get events -n taskguard --sort-by=.lastTimestamp
```

The mental model is: **desired replicas -> Pods -> Ready condition -> Service endpoints -> application response**. Find the first broken link.

## Verify the service

```bash
make verify
```

For manual access:

```bash
kubectl port-forward -n taskguard service/taskguard 8080:8080
curl -i http://localhost:8080/healthz
curl -i http://localhost:8080/readyz
```

## Common conditions

### Pod is Running but not Ready

Meaning: the process exists, but Kubernetes has removed it from Service traffic.

```bash
kubectl get pods,endpointslice -n taskguard -w
kubectl describe pod <pod-name> -n taskguard
kubectl logs <pod-name> -n taskguard --tail=100
```

For the deliberate readiness exercise, tunnel directly to the affected Pod and
re-enable it from another terminal. The scratch image contains no shell or wget:

```bash
kubectl port-forward -n taskguard pod/<pod-name> 18081:8080
# In another terminal:
curl -X POST http://127.0.0.1:18081/readyz/enable
```

### `ImagePullBackOff` or `ErrImagePull`

Meaning: the node cannot obtain the image named by the Deployment.

```bash
kubectl describe pod <pod-name> -n taskguard
kubectl get deployment taskguard -n taskguard -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
minikube image ls -p minikube | grep taskguard
```

For this repository, rebuild the pinned local image and reapply:

```bash
make deploy
```

### `CrashLoopBackOff`

Meaning: the container starts, exits and is repeatedly restarted.

```bash
kubectl logs <pod-name> -n taskguard --previous
kubectl describe pod <pod-name> -n taskguard
kubectl get pod <pod-name> -n taskguard -o jsonpath='{.status.containerStatuses[0].lastState}'
```

Do not repeatedly delete the Pod; first capture the previous logs and exit reason.

### High error-rate or latency alert

```bash
kubectl logs -n taskguard deployment/taskguard --since=10m
kubectl top pods -n taskguard
kubectl get hpa taskguard -n taskguard
```

In Prometheus, correlate request rate, status codes and latency:

```promql
sum by (status) (rate(taskguard_http_requests_total[5m]))
histogram_quantile(0.95, sum by (le) (rate(taskguard_http_request_duration_seconds_bucket[5m])))
```

### OOMKilled or CPU throttling

```bash
kubectl describe pod <pod-name> -n taskguard
kubectl top pods -n taskguard
kubectl get hpa taskguard -n taskguard -o yaml
```

An OOM kill means actual memory crossed the 256 MiB limit. CPU above 200m is throttled rather than killed. Change requests/limits only after collecting usage evidence.

## Rollout and rollback

Inspect history and current progress:

```bash
kubectl rollout history deployment/taskguard -n taskguard
kubectl rollout status deployment/taskguard -n taskguard --timeout=180s
```

Rollback to the preceding Deployment revision:

```bash
kubectl rollout undo deployment/taskguard -n taskguard
kubectl rollout status deployment/taskguard -n taskguard --timeout=180s
make verify
```

`maxUnavailable: 0` keeps old ready replicas until replacements are ready. `maxSurge: 1` requires capacity for one temporary extra Pod.

## Configuration changes

ConfigMap values enter the process as environment variables. Existing processes do not automatically reload them. `make deploy` performs a rolling restart after applying manifests so all Pods receive the current values.

## Autoscaling and capacity

The HPA reads CPU and memory from metrics-server, not from Prometheus. Each Pod
requests 100m CPU and 128 MiB memory. Targets of 70% CPU and 80% memory therefore
mean approximately 70m CPU and 102.4 MiB memory per Pod, averaged across replicas.
The limits (200m and 256 MiB) are different: they cap consumption rather than
define the HPA percentage denominator.

As a simplified example, two Pods averaging 140% CPU utilization against their
requests with a 70% target suggest `ceil(2 * 140 / 70) = 4` replicas. Kubernetes
also applies tolerances, readiness/missing-metric handling and configured scaling
policies. It chooses the largest desired replica count from the two metrics.

This configuration permits 2–10 replicas, has no scale-up stabilization delay,
and retains scale-down recommendations for 300 seconds. Scale-down is limited to
50% per minute. Scale-up permits the larger of 100% or four Pods per 15 seconds.

The single node still needs enough free CPU/memory to schedule extra Pods.
Increasing replicas does not create node capacity or make per-Pod tasks shared.
Memory used by an in-memory store may not fall simply because replicas increase.
The current report verifies HPA metrics and configuration, not a controlled
load-driven scale-out test or multi-node resilience.

## Data recovery

There is no task-data recovery. Each Pod has its own in-memory store, and restarts erase it. This is acceptable only for this demonstration. Production requires a shared persistent database, migrations, backups and tested restore procedures.

## Monitoring checks

```bash
kubectl get servicemonitor,prometheusrule -n taskguard
kubectl get pods -n monitoring
kubectl port-forward -n monitoring service/prometheus-kube-prometheus-prometheus 9090:9090
```

Open `http://localhost:9090/targets`. Both TaskGuard targets should be `UP`.

## Safe teardown

```bash
make clean     # remove only TaskGuard
make destroy   # delete the entire dedicated Minikube profile
```
