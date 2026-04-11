#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)

cd "$REPO_ROOT"

grep -F 'opam-2.0' .github/workflows/opam-repro.yml >/dev/null
grep -F 'NATS_ML_OPAM_CI_OPAM_VERSION: 2.0.10' .github/workflows/opam-repro.yml >/dev/null
grep -F 'opam_ci_opam "$cmd" --root="$OPAM_ROOT" "$@"' tests/check-opam-ci.sh >/dev/null
grep -F '"@runtest"' tests/check-generated-opam-metadata.sh >/dev/null

if grep -F 'opam list --readonly --with-test --external' tests/opam-ci-lib.sh >/dev/null; then
  echo "repo CI should not reimplement opam-depext solver internals" >&2
  exit 1
fi

if grep -F 'opam-depext' tests/opam-ci-lib.sh tests/check-opam-ci.sh tests/check-opam-ci-docker.sh >/dev/null; then
  echo "repo CI should not install opam-depext into package test switches" >&2
  exit 1
fi

if grep -F 'with-test-opam20' tests/opam-ci-lib.sh tests/check-opam-ci.sh tests/check-opam-ci-docker.sh .github/workflows/opam-repro.yml >/dev/null; then
  echo "opam 2.0 checks should use the normal with-test path" >&2
  exit 1
fi
