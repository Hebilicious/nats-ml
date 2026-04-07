#!/usr/bin/env bash

# Sets up the pinned toolchain locally, then runs the shared integration checks.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
OPAM_ROOT=${NATS_ML_INTEGRATION_OPAMROOT:-$REPO_ROOT/.opam-integration-root}
SWITCH_NAME=${NATS_ML_INTEGRATION_SWITCH:-nats-ml-integration}

"$REPO_ROOT/tests/setup-integration-switch.sh"
opam exec --root="$OPAM_ROOT" --switch="$SWITCH_NAME" -- "$REPO_ROOT/tests/run-integration-checks.sh"
