#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)
IMAGE=${1:-}
MODE=${2:-}
PACKAGE=${3:-}

usage() {
  echo "usage: $0 <docker-image> <build|lower-bounds|with-test> <nats-client|nats-client-async>" >&2
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

if [[ -z "$IMAGE" ]]; then
  usage
fi

docker run --rm \
  -v "$REPO_ROOT:/workspace" \
  -w /workspace \
  "$IMAGE" \
  sh -lc "
    set -euo pipefail
    sudo ln -f /usr/bin/opam-dev /usr/bin/opam
    opam init --reinit -ni
    opam option solver=builtin-0install
    export CI=true
    export OPAM_REPO_CI=true
    export OPAMDOWNLOADJOBS=1
    export OPAMERRLOGLEN=0
    export OPAMPRECISETRACKING=1
    opam pin add -yn nats-client /workspace
    opam pin add -yn nats-client-async /workspace
    opam install -y $PACKAGE
    case $MODE in
      build)
        ;;
      lower-bounds)
        OPAMCRITERIA='+removed,+count[version-lag,solution]' \
        OPAMFIXUPCRITERIA='+removed,+count[version-lag,solution]' \
        OPAMUPGRADECRITERIA='+removed,+count[version-lag,solution]' \
          opam reinstall -y $PACKAGE
        ;;
      with-test)
        opam reinstall -y --with-test $PACKAGE
        ;;
    esac
  "
