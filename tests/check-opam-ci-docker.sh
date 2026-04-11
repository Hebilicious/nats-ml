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
CACHED_OPAM_ROOT_HOST=

[[ -n "$IMAGE" ]] || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_validate_mode "$MODE" || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_validate_package "$PACKAGE" || opam_ci_usage "$0" "<docker-image> <build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
if [[ -n "$DOCKER_PLATFORM" ]]; then
  NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER=1
fi
opam_ci_set_mode_defaults "$MODE"

trap opam_ci_cleanup_artifacts EXIT

ARTIFACT_ROOT=$(mktemp -d "$REPO_ROOT/.opam-ci-artifacts.XXXXXX")
ARTIFACT_BASENAME=$(basename "$ARTIFACT_ROOT")
NATS_ML_OPAM_CI_ARCHIVE_DIR_URL="file:///workspace/$ARTIFACT_BASENAME/dist" opam_ci_prepare_artifacts "$REPO_ROOT" "$SCRIPT_DIR"

docker_args=(run --rm)
if [[ -n "$DOCKER_PLATFORM" ]]; then
  docker_args+=(--platform "$DOCKER_PLATFORM")
fi
if [[ -n "${NATS_ML_OPAM_CI_ROOT:-}" ]]; then
  CACHED_OPAM_ROOT_HOST="$REPO_ROOT/$NATS_ML_OPAM_CI_ROOT"
  mkdir -p "$CACHED_OPAM_ROOT_HOST"
  chmod -R 0777 "$CACHED_OPAM_ROOT_HOST"
  docker_args+=(-v "$CACHED_OPAM_ROOT_HOST:/nats-ml-opam-root")
fi

docker "${docker_args[@]}" \
  -v "$REPO_ROOT:/workspace" \
  -w /workspace \
  -e NATS_ML_OPAM_CI_OPAM_VERSION="${NATS_ML_OPAM_CI_OPAM_VERSION:-}" \
  -e NATS_ML_OPAM_CI_COMPILER="${NATS_ML_OPAM_CI_COMPILER:-}" \
  -e NATS_ML_OPAM_CI_DUNE="${NATS_ML_OPAM_CI_DUNE:-}" \
  -e NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER="${NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER:-}" \
  -e NATS_ML_OPAM_CI_CONTAINER_ROOT="${NATS_ML_OPAM_CI_ROOT:+/nats-ml-opam-root}" \
  "$IMAGE" \
  bash -lc "
    set -euo pipefail
    source /workspace/tests/opam-ci-lib.sh
    opam_ci_set_mode_defaults $MODE
    if [[ '$MODE' == 'with-test-opam20' ]]; then
      opam_ci_ensure_external_depext_plugin
    fi
    opam_ci_resolve_opam_bin
    opam_ci_require_opam
    opam_ci_export_env
    LOCAL_REPO_NAME=nats-ml-local
    if [[ -n \"\${NATS_ML_OPAM_CI_CONTAINER_ROOT:-}\" ]]; then
      export OPAMROOT=\$NATS_ML_OPAM_CI_CONTAINER_ROOT
    else
      export OPAMROOT=/tmp/nats-ml-opam-root
    fi
    mkdir -p \"\$OPAMROOT\"
    opam_root() {
      local cmd=\$1
      shift
      opam_ci_opam \"\$cmd\" --root=\"\$OPAMROOT\" \"\$@\"
    }
    if [[ ! -f \"\$OPAMROOT/config\" ]]; then
      opam_ci_init_root
    fi
    opam_ci_configure_solver
    if opam_root switch list --short | grep -Fxq nats-opam-ci; then
      opam_root switch remove -y nats-opam-ci
    fi
    opam_root switch create -y nats-opam-ci \$OCAML_COMPILER
    opam_root install --switch=nats-opam-ci -y \$DUNE_PACKAGE
    if opam_root repository list --all --short | grep -Fxq \"\$LOCAL_REPO_NAME\"; then
      opam_root repository set-url \"\$LOCAL_REPO_NAME\" file:///workspace/$ARTIFACT_BASENAME/repo
      opam_root repository add --switch=nats-opam-ci -y \"\$LOCAL_REPO_NAME\"
    else
      opam_root repository add --switch=nats-opam-ci -y \"\$LOCAL_REPO_NAME\" file:///workspace/$ARTIFACT_BASENAME/repo
    fi
    if [[ '$MODE' == 'expect-unavailable' ]]; then
      if opam_root install --switch=nats-opam-ci -y $PACKAGE.$PACKAGE_VERSION; then
        echo 'expected $PACKAGE to be unavailable in this environment' >&2
        exit 1
      fi
    else
      opam_root install --switch=nats-opam-ci -y $PACKAGE.$PACKAGE_VERSION
      export OPAMSWITCH=nats-opam-ci
      opam_ci_run_mode $MODE $PACKAGE.$PACKAGE_VERSION opam_root --switch=nats-opam-ci -y
    fi
  "
