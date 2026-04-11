#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)

cd "$REPO_ROOT"

grep -F 'opam-2.0' .github/workflows/opam-repro.yml >/dev/null
grep -F 'NATS_ML_OPAM_CI_OPAM_VERSION: 2.0.10' .github/workflows/opam-repro.yml >/dev/null
grep -F 'opam_ci_opam "$cmd" --root="$OPAM_ROOT" "$@"' tests/check-opam-ci.sh >/dev/null
grep -F 'depext "$@" --with-test "$package_version"' tests/opam-ci-lib.sh >/dev/null

if grep -F 'opam list --readonly --with-test --external' tests/opam-ci-lib.sh >/dev/null; then
  echo "opam 2.0 repro must use opam depext, matching opam-repo-ci" >&2
  exit 1
fi
