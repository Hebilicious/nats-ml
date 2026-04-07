#!/bin/sh
set -eu

mode="${1:-check}"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require git
require dune
require opam
require dune-release

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree must be clean before running release preparation" >&2
  git status --short >&2
  exit 1
fi

dune build nats-client.opam nats-client-async.opam
git diff --exit-code -- nats-client.opam nats-client-async.opam

dune build @runtest
dune-release lint

case "$mode" in
  check)
    echo "release preflight OK"
    ;;
  publish)
    git describe --tags --exact-match >/dev/null 2>&1 || {
      echo "publish mode requires the commit to be tagged" >&2
      exit 1
    }
    dune-release opam submit
    ;;
  *)
    echo "usage: $0 [check|publish]" >&2
    exit 2
    ;;
esac
