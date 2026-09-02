#!/bin/sh
set -eu

NAMESPACE="${NAMESPACE:-taskguard}"
DEPLOYMENT="${DEPLOYMENT:-taskguard}"
KUBE_CONTEXT="${KUBE_CONTEXT:-minikube}"
BROKEN_IMAGE="${BROKEN_IMAGE:-taskguard:does-not-exist}"
CHANGED=false
RECOVERED=false

kubectl() {
	command kubectl --context="$KUBE_CONTEXT" "$@"
}

ready_endpoints() {
	kubectl get endpointslice -n "$NAMESPACE" \
		-l kubernetes.io/service-name=taskguard \
		-o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' | grep -c true || true
}

recover() {
	if [ "$CHANGED" = true ] && [ "$RECOVERED" = false ]; then
		echo "==> Safety recovery: restoring known-good revision $GOOD_REVISION"
		kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE" \
			--to-revision="$GOOD_REVISION" || return 1
		kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
	fi
}
trap recover EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "==> Baseline ($KUBE_CONTEXT / $NAMESPACE)"
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
GOOD_REVISION="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
	-o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')"
GOOD_IMAGE="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
	-o jsonpath='{.spec.template.spec.containers[0].image}')"
BASELINE_ENDPOINTS="$(ready_endpoints)"
test "$BASELINE_ENDPOINTS" -ge 2
test "$GOOD_IMAGE" != "$BROKEN_IMAGE"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=api -o wide
echo "Known-good revision=$GOOD_REVISION image=$GOOD_IMAGE ready_endpoints=$BASELINE_ENDPOINTS"

echo "==> Introducing a realistic bad-image rollout"
CHANGED=true
kubectl set image deployment/"$DEPLOYMENT" taskguard="$BROKEN_IMAGE" -n "$NAMESPACE"

echo "==> Expect a stalled rollout while old healthy replicas continue serving"
if kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=45s; then
	echo "ERROR: the deliberately broken rollout unexpectedly succeeded"
	exit 1
fi

FAILURE="$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=api \
	-o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{" "}{.status.containerStatuses[0].state.waiting.reason}{"\n"}{end}' \
	| awk -v image="$BROKEN_IMAGE" '$2 == image && ($3 == "ErrImagePull" || $3 == "ImagePullBackOff") {print $1; exit}')"
if [ -z "$FAILURE" ]; then
	echo "ERROR: no matching image-pull failure was observed"
	kubectl get pods -n "$NAMESPACE" -o wide
	exit 1
fi
kubectl describe pod "$FAILURE" -n "$NAMESPACE" | tail -40
kubectl get replicasets,pods -n "$NAMESPACE" -o wide
FAILED_ENDPOINTS="$(ready_endpoints)"
test "$FAILED_ENDPOINTS" -ge "$BASELINE_ENDPOINTS"
echo "Ready endpoints during failed rollout: $FAILED_ENDPOINTS"
# This also checks real HTTP traffic while the bad revision is stalled.
KUBE_CONTEXT="$KUBE_CONTEXT" NAMESPACE="$NAMESPACE" ./scripts/smoke-test.sh

echo "==> Restoring the captured known-good revision $GOOD_REVISION"
kubectl rollout undo deployment/"$DEPLOYMENT" -n "$NAMESPACE" --to-revision="$GOOD_REVISION"
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s
kubectl wait --for=delete pod/"$FAILURE" -n "$NAMESPACE" --timeout=60s
RESTORED_IMAGE="$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
	-o jsonpath='{.spec.template.spec.containers[0].image}')"
test "$RESTORED_IMAGE" = "$GOOD_IMAGE"
KUBE_CONTEXT="$KUBE_CONTEXT" NAMESPACE="$NAMESPACE" ./scripts/smoke-test.sh
RECOVERED=true

echo "==> Recovered state"
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=api -o wide
kubectl get endpointslice -n "$NAMESPACE" -l kubernetes.io/service-name=taskguard -o wide
echo "PASS: image-pull failure observed; HTTP checks passed during failure and after rollback"
