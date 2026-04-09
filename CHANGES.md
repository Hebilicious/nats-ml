# Changelog

## 0.0.2 - 2026-04-09


- Add the missing `yojson` dependency to the `nats-client-async` opam metadata.
- Scope test stanzas by package so `nats-client` can build and test without `nats-client-async` installed.
- Add CI checks that install each published opam package in isolation.


## 0.0.1 - 2026-04-07


Lower the package metadata for broader Async toolchain compatibility and add a
Docker-backed integration test flow with a real NATS server and an external
consumer fixture.

