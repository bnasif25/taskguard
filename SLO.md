# TaskGuard SLIs and SLOs

These objectives demonstrate how TaskGuard would be operated. They are intentionally modest for a local learning environment and are not claims of historical production performance.

## Availability

- **SLI:** proportion of instrumented API requests that do not return HTTP 5xx.
- **SLO:** at least 99% successful requests over a rolling 30-day window.
- **Short-window diagnostic:**

```promql
1 - (
  (sum(rate(taskguard_http_requests_total{status=~"5.."}[5m])) or vector(0))
  /
  clamp_min(sum(rate(taskguard_http_requests_total[5m])), 0.001)
)
```

Scrape health is a supporting monitoring indicator, not readiness or the user-facing availability SLI:

```promql
sum(up{job="taskguard"})
```

## Latency

- **SLI:** 95th-percentile duration of instrumented API requests.
- **SLO:** p95 below 200 ms for at least 99% of five-minute windows over 30 days.

```promql
histogram_quantile(
  0.95,
  sum by (le) (rate(taskguard_http_request_duration_seconds_bucket[5m]))
)
```

## Alert relationship

- `TaskGuardHighErrorRate` warns when the five-minute 5xx ratio is above 5% for two minutes.
- `TaskGuardHighLatency` warns when p95 is above 200 ms for five minutes.
- `TaskGuardCrashLooping` warns when a Pod restarts more than three times in ten minutes.

The alert thresholds are deliberately faster and more sensitive than the 30-day SLOs so an operator can respond before the error budget is exhausted.

## Measurement limitations

- Probe requests are intentionally excluded from application request metrics.
- Metrics exist per Pod and are aggregated by Prometheus.
- A local cluster does not provide a meaningful 30-day availability history.
- Requests that never reach the process are not represented in application counters; production would combine ingress and black-box metrics.
- With no traffic, the guarded diagnostic may display 1; that is not evidence of successful requests. Inspect request volume alongside it.
