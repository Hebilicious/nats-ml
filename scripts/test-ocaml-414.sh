#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SWITCH_NAME=${NATS_ML_OCAML_414_SWITCH:-nats-ml-ocaml-414}
NATS_IMAGE=${NATS_IMAGE:-nats:2.10-alpine}
NATS_PORT=${NATS_PORT:-42229}
CONTAINER_NAME="nats-ml-ocaml-414-${NATS_PORT}-$$"
INSTALL_PREFIX="$ROOT_DIR/_ocaml-414-install"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required for the OCaml 4.14 real NATS compatibility test." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is unavailable. Start the Docker daemon and rerun the test." >&2
  exit 1
fi

trap cleanup EXIT

"$ROOT_DIR/scripts/setup-ocaml-414-switch.sh"

docker run --rm -d --name "$CONTAINER_NAME" -p "127.0.0.1:${NATS_PORT}:4222" \
  "$NATS_IMAGE" >/dev/null

ready=""
for _ in $(seq 1 30); do
  if docker logs "$CONTAINER_NAME" 2>&1 | grep -q "Server is ready"; then
    ready=1
    break
  fi
  sleep 1
done

if [[ -z "$ready" ]]; then
  echo "NATS failed to become ready in Docker. Recent logs:" >&2
  docker logs "$CONTAINER_NAME" >&2 || true
  exit 1
fi

export NATS_URL="nats://127.0.0.1:${NATS_PORT}"

opam exec --switch="$SWITCH_NAME" -- dune build @install @runtest
opam exec --switch="$SWITCH_NAME" -- dune exec ./test/real_nats_integration.exe
rm -rf "$INSTALL_PREFIX"
opam exec --switch="$SWITCH_NAME" -- dune install --prefix "$INSTALL_PREFIX"

(
  cd "$ROOT_DIR/integration/consumer_fixture"
  OCAMLPATH="${INSTALL_PREFIX}/lib${OCAMLPATH+:${OCAMLPATH}}" \
    opam exec --switch="$SWITCH_NAME" -- dune exec ./consumer.exe
)
