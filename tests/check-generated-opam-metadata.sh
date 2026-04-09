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

rg -F '"alcotest" {with-test}' nats-client.opam >/dev/null
rg -F '"alcotest" {with-test}' nats-client-async.opam >/dev/null
rg -F '"@runtest" {with-test}' nats-client.opam >/dev/null
rg -F '"@runtest" {with-test}' nats-client-async.opam >/dev/null
rg -F '"yojson" {>= "2.0.0"}' nats-client-async.opam >/dev/null
