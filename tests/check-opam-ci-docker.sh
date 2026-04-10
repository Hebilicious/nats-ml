#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
source "$SCRIPT_DIR/opam-ci-lib.sh"

IMAGE=${1:-}
MODE=${2:-}
PACKAGE=${3:-}
ARTIFACT_ROOT=
DOCKER_PLATFORM=${NATS_ML_OPAM_CI_DOCKER_PLATFORM:-}

[[ -n "$IMAGE" ]] || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_validate_mode "$MODE" || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_validate_package "$PACKAGE" || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_set_mode_defaults "$MODE"

trap opam_ci_cleanup_artifacts EXIT

ARTIFACT_ROOT=$(mktemp -d "$REPO_ROOT/.opam-ci-artifacts.XXXXXX")
ARTIFACT_BASENAME=$(basename "$ARTIFACT_ROOT")
NATS_ML_OPAM_CI_ARCHIVE_DIR_URL="file:///workspace/$ARTIFACT_BASENAME/dist" opam_ci_prepare_artifacts "$REPO_ROOT" "$SCRIPT_DIR"

docker_args=(run --rm)
if [[ -n "$DOCKER_PLATFORM" ]]; then
  docker_args+=(--platform "$DOCKER_PLATFORM")
fi

docker "${docker_args[@]}" \
  -v "$REPO_ROOT:/workspace" \
  -w /workspace \
  -e NATS_ML_OPAM_CI_OPAM_VERSION="${NATS_ML_OPAM_CI_OPAM_VERSION:-}" \
  -e NATS_ML_OPAM_CI_COMPILER="${NATS_ML_OPAM_CI_COMPILER:-}" \
  -e NATS_ML_OPAM_CI_DUNE="${NATS_ML_OPAM_CI_DUNE:-}" \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    source /workspace/tests/opam-ci-lib.sh
    opam_ci_set_mode_defaults $MODE
    opam_ci_resolve_opam_bin
    opam_ci_require_opam
    opam_ci_export_env
    export OPAMROOT=/tmp/nats-ml-opam-root
    rm -rf \"\$OPAMROOT\"
    opam_ci_init_root
    opam_ci_configure_solver
    opam_ci_opam switch create -y nats-opam-ci $OCAML_COMPILER $DUNE_PACKAGE
    opam_ci_opam repository add --switch=nats-opam-ci -y nats-ml-local file:///workspace/$ARTIFACT_BASENAME/repo
    if [[ '$MODE' == 'expect-unavailable' ]]; then
      if opam_ci_opam install --switch=nats-opam-ci -y $PACKAGE.$PACKAGE_VERSION; then
        echo 'expected $PACKAGE to be unavailable in this environment' >&2
        exit 1
      fi
    else
      opam_ci_opam install --switch=nats-opam-ci -y $PACKAGE.$PACKAGE_VERSION
      opam_ci_run_mode $MODE $PACKAGE.$PACKAGE_VERSION opam_ci_opam reinstall --switch=nats-opam-ci -y
    fi
  "
