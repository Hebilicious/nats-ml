#!/usr/bin/env bash

# Creates the pinned opam switch used by the integration test workflow.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
OPAM_ROOT=${NATS_ML_INTEGRATION_OPAMROOT:-$REPO_ROOT/.opam-integration-root}
SWITCH_NAME=${NATS_ML_INTEGRATION_SWITCH:-nats-ml-integration}

if ! command -v opam >/dev/null 2>&1; then
  echo "opam is required to set up the integration test switch." >&2
  exit 1
fi

if [[ ! -d "$OPAM_ROOT" ]]; then
  opam init --root="$OPAM_ROOT" --bare --disable-sandboxing --no-setup --yes default https://opam.ocaml.org
fi

if ! opam switch list --root="$OPAM_ROOT" --short | grep -Fxq "$SWITCH_NAME"; then
  opam switch create --root="$OPAM_ROOT" --yes "$SWITCH_NAME" ocaml-base-compiler.4.14.0 dune.3.19.0
fi

(
  cd "$REPO_ROOT"
  opam install --root="$OPAM_ROOT" --switch="$SWITCH_NAME" --yes \
    core.v0.14.1 \
    async.v0.14.0 \
    async_unix.v0.14.0 \
    uri.4.2.0 \
    yojson.1.7.0 \
    ppx_jane.v0.14.0
  opam install --root="$OPAM_ROOT" --switch="$SWITCH_NAME" --yes . --deps-only --with-test
)
