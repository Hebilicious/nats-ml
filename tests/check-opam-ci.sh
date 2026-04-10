#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
source "$SCRIPT_DIR/opam-ci-lib.sh"

MODE=${1:-}
PACKAGE=${2:-}
ARTIFACT_ROOT=

opam_ci_validate_mode "$MODE" || opam_ci_usage "$0" "<build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_validate_package "$PACKAGE" || opam_ci_usage "$0" "<build|lower-bounds|with-test|with-test-opam20|expect-unavailable> <nats-client|nats-client-async>"
opam_ci_set_mode_defaults "$MODE"
opam_ci_resolve_opam_bin
opam_ci_require_opam
opam_ci_export_env

OPAM_ROOT=${NATS_ML_OPAM_CI_ROOT:-$REPO_ROOT/.opam-ci-root/$MODE-$PACKAGE}
SWITCH_NAME=${PACKAGE}-${MODE}
LOCAL_REPO_NAME=nats-ml-local

trap opam_ci_cleanup_artifacts EXIT

opam_root() {
  local cmd=$1
  shift
  opam_ci_opam "$cmd" --root="$OPAM_ROOT" "$@"
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
if opam_root repository list --all --short | grep -Fxq "$LOCAL_REPO_NAME"; then
  opam_root repository set-url "$LOCAL_REPO_NAME" "file://$ARTIFACT_ROOT/repo"
  opam_root repository add --switch="$SWITCH_NAME" --yes "$LOCAL_REPO_NAME"
else
  opam_root repository add --switch="$SWITCH_NAME" --yes "$LOCAL_REPO_NAME" "file://$ARTIFACT_ROOT/repo"
fi

if [[ "$MODE" == expect-unavailable ]]; then
  unavailable_log=$(mktemp)
  trap 'rm -f "$unavailable_log"; opam_ci_cleanup_artifacts' EXIT

  if opam_root install --switch="$SWITCH_NAME" --yes "$PACKAGE.$PACKAGE_VERSION" >"$unavailable_log" 2>&1; then
    cat "$unavailable_log" >&2
    echo "expected $PACKAGE to be unavailable in this environment" >&2
    exit 1
  fi

  if ! grep -Eq 'No solution|No package matches|no package named|Package .* has no version available' "$unavailable_log"; then
    cat "$unavailable_log" >&2
    echo "install failed, but not because the package was unavailable" >&2
    exit 1
  fi
else
  opam_root install --switch="$SWITCH_NAME" --yes "$PACKAGE.$PACKAGE_VERSION"
  opam_ci_run_mode "$MODE" "$PACKAGE.$PACKAGE_VERSION" opam_root reinstall --switch="$SWITCH_NAME" --yes
fi
