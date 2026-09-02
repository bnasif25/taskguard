#!/bin/sh
set -eu

IMAGE="${IMAGE:-taskguard:1.0.0}"
CONTAINER_ID=""
cleanup() {
	if [ -n "$CONTAINER_ID" ]; then
		docker rm -f "$CONTAINER_ID" >/dev/null 2>&1 || true
	fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

CONTAINER_ID="$(docker run -d --read-only --cap-drop=ALL \
	--security-opt=no-new-privileges \
	--tmpfs /tmp:rw,noexec,nosuid,size=16m \
	-p 127.0.0.1::8080 "$IMAGE")"
test "$(docker inspect --format '{{.Config.User}}' "$CONTAINER_ID")" = 1000:1000
PORT="$(docker port "$CONTAINER_ID" 8080/tcp | sed 's/.*://')"
ATTEMPT=0
until curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; do
	ATTEMPT=$((ATTEMPT + 1))
	if [ "$ATTEMPT" -ge 20 ]; then
		docker logs "$CONTAINER_ID"
		echo "ERROR: hardened container did not become healthy"
		exit 1
	fi
	sleep 1
done
echo "PASS: image runs as UID/GID 1000 with a read-only root filesystem and responds to health checks"

docker stop --time 5 "$CONTAINER_ID" >/dev/null
test "$(docker inspect --format '{{.State.ExitCode}}' "$CONTAINER_ID")" = 0
docker logs "$CONTAINER_ID" 2>&1
echo "PASS: SIGTERM caused a clean exit with code 0"
