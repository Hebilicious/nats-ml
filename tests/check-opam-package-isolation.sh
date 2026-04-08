#!/usr/bin/env bash

# Verifies each published opam package can be installed and tested in isolation.

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
PACKAGE=${1:-}
OPAM_ROOT=${NATS_ML_PACKAGE_CHECK_OPAMROOT:-$REPO_ROOT/.opam-package-check-root}
SWITCH_NAME=${PACKAGE}-package-check
OCAML_COMPILER=ocaml-base-compiler.4.14.3
DUNE_PACKAGE=dune.3.19.0

case "$PACKAGE" in
  nats-client|nats-client-async)
    ;;
  *)
    echo "usage: $0 <nats-client|nats-client-async>" >&2
    exit 1
    ;;
esac

if ! command -v opam >/dev/null 2>&1; then
  echo "opam is required for package isolation checks." >&2
  exit 1
fi

if [[ ! -f "$OPAM_ROOT/config" ]]; then
  rm -rf "$OPAM_ROOT"
  opam init --root="$OPAM_ROOT" --bare --disable-sandboxing --no-setup --yes default https://opam.ocaml.org
fi

opam update --root="$OPAM_ROOT" --yes default

if opam switch list --root="$OPAM_ROOT" --short | grep -Fxq "$SWITCH_NAME"; then
  opam switch remove --root="$OPAM_ROOT" --yes "$SWITCH_NAME"
fi

opam switch create --root="$OPAM_ROOT" --yes "$SWITCH_NAME" "$OCAML_COMPILER" "$DUNE_PACKAGE"
opam pin add --root="$OPAM_ROOT" --switch="$SWITCH_NAME" --yes --no-action nats-client "$REPO_ROOT"
opam pin add --root="$OPAM_ROOT" --switch="$SWITCH_NAME" --yes --no-action nats-client-async "$REPO_ROOT"
opam install --root="$OPAM_ROOT" --switch="$SWITCH_NAME" --yes "$PACKAGE" --with-test
