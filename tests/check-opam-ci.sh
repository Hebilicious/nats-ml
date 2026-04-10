#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
source "$SCRIPT_DIR/opam-ci-lib.sh"

MODE=${1:-}
PACKAGE=${2:-}
ARTIFACT_ROOT=

opam_ci_validate_mode "$MODE" || opam_ci_usage "$0" "<build|lower-bounds|with-test> <nats-client|nats-client-async>"
opam_ci_validate_package "$PACKAGE" || opam_ci_usage "$0" "<build|lower-bounds|with-test> <nats-client|nats-client-async>"
opam_ci_require_opam
opam_ci_export_env
opam_ci_set_mode_defaults "$MODE"

OPAM_ROOT=${NATS_ML_OPAM_CI_ROOT:-$REPO_ROOT/.opam-ci-root/$MODE-$PACKAGE}
SWITCH_NAME=${PACKAGE}-${MODE}
LOCAL_REPO_NAME=nats-ml-local

trap opam_ci_cleanup_artifacts EXIT

opam_root() {
  local cmd=$1
  shift
  opam "$cmd" --root="$OPAM_ROOT" "$@"
}

if [[ ! -f "$OPAM_ROOT/config" ]]; then
  rm -rf "$OPAM_ROOT"
  opam_init_args=(--bare --no-setup --yes default https://opam.ocaml.org)
  if ((${#INIT_ARGS[@]} > 0)); then
    opam_init_args+=("${INIT_ARGS[@]}")
  fi
  opam_root init "${opam_init_args[@]}"
fi

if opam_root switch list --short | grep -Fxq "$SWITCH_NAME"; then
  opam_root switch remove --yes "$SWITCH_NAME"
fi

opam_ci_prepare_artifacts "$REPO_ROOT" "$SCRIPT_DIR"

opam_root switch create --yes "$SWITCH_NAME" "$OCAML_COMPILER" "$DUNE_PACKAGE"
opam_root repository remove --yes "$LOCAL_REPO_NAME" >/dev/null 2>&1 || true
opam_root repository remove --switch="$SWITCH_NAME" --yes "$LOCAL_REPO_NAME" >/dev/null 2>&1 || true
opam_root repository add --switch="$SWITCH_NAME" --yes "$LOCAL_REPO_NAME" "file://$ARTIFACT_ROOT/repo"

opam_root install --switch="$SWITCH_NAME" --yes "$PACKAGE.$PACKAGE_VERSION"
opam_ci_run_mode "$MODE" "$PACKAGE.$PACKAGE_VERSION" opam_root reinstall --switch="$SWITCH_NAME" --yes
