# nats-client

Lean OCaml NATS clients built around a small protocol core and an `Async` runtime.

The project was inspired by [romanchechyotkin/nats.ocaml](https://github.com/romanchechyotkin/nats.ocaml), but this is a fresh implementation with an `Async`-first runtime, HPUB support, reconnect handling, and a smaller public surface.

## Packages

- `nats-client`
  - protocol types and codecs
  - `CONNECT`, `PUB`, `HPUB`, `SUB`, `UNSUB`, `PING`, `PONG`
  - server line parsing for `INFO`, `MSG`, `HMSG`, `+OK`, and `-ERR`
- `nats-client-async`
  - TCP client built on `Async`
  - automatic reconnect with backoff
  - keepalive `PING`/`PONG`
  - subscriptions and request/reply
  - fire-and-forget publishing

## Installation

With `opam`:

```sh
opam install nats-client nats-client-async
```

From source:

```sh
dune build @install
dune install
```

If you are developing against this repository locally, `proto` will provision the OCaml toolchain from [`.prototools`](./.prototools).

## Features

- TCP connection over `Async`
- required NATS handshake `CONNECT {"verbose":false,"pedantic":false}\r\n`
- configurable `CONNECT` fields
- HPUB publish with headers
- incoming `HMSG` parsing and header delivery
- JSON payload helpers via `Yojson.Safe.t`
- server `PING` handling and client keepalive `PING`
- automatic reconnect with exponential backoff
- disabled mode when `connect None` is used
- silent drop semantics for publish when disconnected or disabled

## Disabled Mode

Calling `Nats_client_async.connect None` returns a disabled client.

In disabled mode:

- `publish` is a no-op
- `publish_json` is a no-op
- `publish_result` returns `` `Dropped ``
- `subscribe`, `unsubscribe`, and `request` return an error

This is useful when a caller wants to keep its main transaction path identical with or without NATS.

## Core API

```ocaml
val Nats_client.Protocol.encode_connect :
  ?connect:Nats_client.Protocol.connect -> unit -> string

val Nats_client.Protocol.encode_pub :
  subject:string -> ?reply_to:string -> string -> string

val Nats_client.Protocol.encode_hpub :
  subject:string -> ?reply_to:string -> headers:Nats_client.Headers.t -> string -> string

val Nats_client.Protocol.parse_server_line :
  string -> Nats_client.Protocol.parsed_line
```

The protocol layer also exposes:

- `Nats_client.Headers` for ordered, repeatable headers
- `Nats_client.Sid` for subscription ids
- `Nats_client.Protocol.message` for received messages

## Async API

```ocaml
val Nats_client_async.connect :
  ?connect:Nats_client.Protocol.connect ->
  ?ping_interval:Time_ns.Span.t ->
  ?ping_timeout:Time_ns.Span.t ->
  ?reconnect_initial:Time_ns.Span.t ->
  ?reconnect_max:Time_ns.Span.t ->
  Uri.t option ->
  client Deferred.t

val Nats_client_async.publish :
  client -> subject:string -> ?reply_to:string -> ?headers:Nats_client.Headers.t -> string -> unit

val Nats_client_async.publish_json :
  client -> subject:string -> ?reply_to:string -> ?headers:Nats_client.Headers.t -> Yojson.Safe.t -> unit

val Nats_client_async.subscribe :
  client -> subject:string -> ?queue_group:string -> ?sid:Nats_client.Sid.t -> unit -> subscription Or_error.t Deferred.t

val Nats_client_async.request :
  client -> subject:string -> ?headers:Nats_client.Headers.t -> ?timeout:Time_ns.Span.t -> string -> string Or_error.t Deferred.t
```

`publish` and `publish_json` are fire-and-forget. If the client is unavailable, they are silently dropped.

## Examples

Build the example executables with:

```sh
dune build examples/protocol_demo.exe examples/publish_json.exe examples/request_reply.exe
dune build examples/natsbyexample/publish_subscribe.exe
dune build examples/natsbyexample/request_reply.exe
dune build examples/natsbyexample/json_for_message_payloads.exe
```

Run them against a local NATS server by setting `NATS_URL` if needed:

```sh
NATS_URL=nats://127.0.0.1:4222 dune exec ./examples/protocol_demo.exe
NATS_URL=nats://127.0.0.1:4222 dune exec ./examples/publish_json.exe
NATS_URL=nats://127.0.0.1:4222 dune exec ./examples/request_reply.exe
NATS_URL=nats://127.0.0.1:4222 dune exec ./examples/natsbyexample/publish_subscribe.exe
NATS_URL=nats://127.0.0.1:4222 dune exec ./examples/natsbyexample/request_reply.exe
NATS_URL=nats://127.0.0.1:4222 dune exec ./examples/natsbyexample/json_for_message_payloads.exe
```

The examples cover:

- protocol framing and HPUB encoding
- JSON publishing with headers
- request/reply round trips
- a `natsbyexample` directory with publish/subscribe, request/reply, and JSON payload examples

## Release Flow

The intended release path is PR-based:

1. Each user-facing PR adds a fragment under `.changes/` with a `patch`, `minor`, or `major` header.
2. The `release-pr.yml` workflow aggregates those fragments into `CHANGES.md` and opens or updates a `release: vX.Y.Z` PR.
3. Merge the release PR.
4. Tag that merge commit with `vX.Y.Z` and push the tag.
5. The `publish.yml` workflow runs `dune-release` and `opam-publish` to submit the release to `opam-repository`.
6. After the `opam-repository` PR is merged, users can install the packages with `opam install`.

## License

MIT. See [LICENSE](./LICENSE).
