#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR/.." rev-parse --show-toplevel)

cd "$REPO_ROOT"

before_nats_client=$(mktemp)
before_nats_client_async=$(mktemp)
trap 'rm -f "$before_nats_client" "$before_nats_client_async"' EXIT

cp nats-client.opam "$before_nats_client"
cp nats-client-async.opam "$before_nats_client_async"

dune build nats-client.opam nats-client-async.opam
cmp -s "$before_nats_client" nats-client.opam
cmp -s "$before_nats_client_async" nats-client-async.opam

assert_contains() {
  local needle=$1
  local file=$2

  grep -F "$needle" "$file" >/dev/null
}

assert_contains '"alcotest" {with-test & opam-version >= "2.1"}' nats-client.opam
assert_contains '"@runtest" {with-test & opam-version >= "2.1"}' nats-client.opam
assert_contains 'available: [ os-distribution != "alpine" ]' nats-client-async.opam
assert_contains '"alcotest" {with-test & opam-version >= "2.1" & (arch = "x86_64" | arch = "arm64")}' nats-client-async.opam
assert_contains '"@runtest" {with-test & opam-version >= "2.1" & (arch = "x86_64" | arch = "arm64")}' nats-client-async.opam
assert_contains '"yojson" {>= "2.0.0"}' nats-client-async.opam
