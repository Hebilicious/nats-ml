#!/usr/bin/env bash

# Runs the integration checks against an already configured toolchain and NATS server.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
NATS_IMAGE=${NATS_IMAGE:-nats:2.10-alpine}
NATS_PORT=${NATS_PORT:-42229}
CONTAINER_NAME="nats-ml-integration-${NATS_PORT}-$$"
INSTALL_PREFIX=${NATS_ML_INTEGRATION_PREFIX:-$REPO_ROOT/_integration-install}
STARTED_DOCKER=""

cleanup() {
  if [[ -n "$STARTED_DOCKER" ]]; then
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required for the integration test." >&2
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker is unavailable. Start the Docker daemon and rerun the test." >&2
    exit 1
  fi
}

start_nats_if_needed() {
  if [[ -n "${NATS_URL:-}" ]]; then
    return
  fi

  ensure_docker

  docker run --rm -d --name "$CONTAINER_NAME" -p "127.0.0.1:${NATS_PORT}:4222" \
    "$NATS_IMAGE" >/dev/null
  STARTED_DOCKER=1

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
}

trap cleanup EXIT

start_nats_if_needed

dune build @install
dune exec ./tests/real_nats_integration.exe
rm -rf "$INSTALL_PREFIX"
dune install --prefix "$INSTALL_PREFIX"

(
  cd "$REPO_ROOT/tests/consumer_fixture"
  OCAMLPATH="${INSTALL_PREFIX}/lib${OCAMLPATH+:${OCAMLPATH}}" \
    dune exec ./consumer.exe
)
