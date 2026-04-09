#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
MODE=${1:-}
PACKAGE=${2:-}

usage() {
  echo "usage: $0 <build|lower-bounds|with-test> <nats-client|nats-client-async>" >&2
  exit 1
}

case "$MODE" in
  build|lower-bounds|with-test)
    ;;
  *)
    usage
    ;;
esac

case "$PACKAGE" in
  nats-client|nats-client-async)
    ;;
  *)
    usage
    ;;
esac

if ! command -v opam >/dev/null 2>&1; then
  echo "opam is required for opam CI compatibility checks." >&2
  exit 1
fi

export CI=true
export OPAM_REPO_CI=true
export OPAMDOWNLOADJOBS=1
export OPAMERRLOGLEN=0
export OPAMPRECISETRACKING=1
export OPAMEXTERNALSOLVER=builtin-0install

case "$MODE" in
  build)
    OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.5.4.0}
    DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.22.1}
    INIT_ARGS=(--disable-sandboxing)
    ;;
  lower-bounds)
    OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.4.14.3}
    DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.19.0}
    INIT_ARGS=(--disable-sandboxing)
    ;;
  with-test)
    OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.5.4.0}
    DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.22.1}
    INIT_ARGS=()
    ;;
esac

OPAM_ROOT=${NATS_ML_OPAM_CI_ROOT:-$REPO_ROOT/.opam-ci-root/$MODE-$PACKAGE}
SWITCH_NAME=${PACKAGE}-${MODE}

opam_root() {
  local cmd=$1
  shift
  opam "$cmd" --root="$OPAM_ROOT" "$@"
}

if [[ ! -f "$OPAM_ROOT/config" ]]; then
  rm -rf "$OPAM_ROOT"
  opam_root init --bare "${INIT_ARGS[@]}" --no-setup --yes default https://opam.ocaml.org
fi

if opam_root switch list --short | grep -Fxq "$SWITCH_NAME"; then
  opam_root switch remove --yes "$SWITCH_NAME"
fi

opam_root switch create --yes "$SWITCH_NAME" "$OCAML_COMPILER" "$DUNE_PACKAGE"
opam_root pin add --switch="$SWITCH_NAME" --yes --no-action -k path nats-client "$REPO_ROOT"
opam_root pin add --switch="$SWITCH_NAME" --yes --no-action -k path nats-client-async "$REPO_ROOT"

opam_root install --switch="$SWITCH_NAME" --yes "$PACKAGE"

case "$MODE" in
  build)
    ;;
  lower-bounds)
    OPAMCRITERIA="+removed,+count[version-lag,solution]" \
    OPAMFIXUPCRITERIA="+removed,+count[version-lag,solution]" \
    OPAMUPGRADECRITERIA="+removed,+count[version-lag,solution]" \
      opam_root reinstall --switch="$SWITCH_NAME" --yes "$PACKAGE"
    ;;
  with-test)
    opam_root reinstall --switch="$SWITCH_NAME" --yes --with-test "$PACKAGE"
    ;;
esac
