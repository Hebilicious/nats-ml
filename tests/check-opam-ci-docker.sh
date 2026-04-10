#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
source "$SCRIPT_DIR/opam-ci-lib.sh"

IMAGE=${1:-}
MODE=${2:-}
PACKAGE=${3:-}
ARTIFACT_ROOT=

[[ -n "$IMAGE" ]] || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test> <nats-client|nats-client-async>"
opam_ci_validate_mode "$MODE" || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test> <nats-client|nats-client-async>"
opam_ci_validate_package "$PACKAGE" || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test> <nats-client|nats-client-async>"

trap opam_ci_cleanup_artifacts EXIT

ARTIFACT_ROOT=$(mktemp -d "$REPO_ROOT/.opam-ci-artifacts.XXXXXX")
ARTIFACT_BASENAME=$(basename "$ARTIFACT_ROOT")
NATS_ML_OPAM_CI_ARCHIVE_DIR_URL="file:///workspace/$ARTIFACT_BASENAME/dist" opam_ci_prepare_artifacts "$REPO_ROOT" "$SCRIPT_DIR"

docker run --rm \
  -v "$REPO_ROOT:/workspace" \
  -w /workspace \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    source /workspace/tests/opam-ci-lib.sh
    sudo ln -f /usr/bin/opam-dev /usr/bin/opam
    opam init --reinit -ni
    opam option solver=builtin-0install
    opam_ci_export_env
    opam repository add -y nats-ml-local file:///workspace/$ARTIFACT_BASENAME/repo
    opam install -y $PACKAGE.$PACKAGE_VERSION
    opam_ci_run_mode $MODE $PACKAGE.$PACKAGE_VERSION opam reinstall -y
  "
