#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT=$(git -C "$(dirname -- "$0")/.." rev-parse --show-toplevel)
SWITCH_NAME=${NATS_ML_INTEGRATION_SWITCH:-nats-ml-integration}

if ! command -v opam >/dev/null 2>&1; then
  echo "opam is required to set up the integration test switch." >&2
  exit 1
fi

if ! opam switch list --short | grep -Fxq "$SWITCH_NAME"; then
  opam switch create --yes "$SWITCH_NAME" ocaml-base-compiler.4.14.0 dune.3.19.0
fi

(
  cd "$REPO_ROOT"
  opam install --switch="$SWITCH_NAME" --yes \
    core.v0.14.1 \
    async.v0.14.0 \
    async_unix.v0.14.0 \
    uri.4.2.0 \
    yojson.1.7.0 \
    ppx_jane.v0.14.0
  opam install --switch="$SWITCH_NAME" --yes . --deps-only --with-test
)
