# Changelog

## 0.0.8 - 2026-04-20


- Add package documentation landing pages and public API docs for ocaml.org.
- Relax the nats-client-async Yojson dependency lower bound to 1.7.0.


## 0.0.7 - 2026-04-14


- Skip published package tests on opam 2.0 and make the async package smoke test bytecode-only so opam-ci matches supported targets more closely.


## 0.0.6 - 2026-04-14


- Restore lightweight published package tests and keep the mirrored opam target checks minimal so opam releases still exercise the installed packages.


## 0.0.5 - 2026-04-11


- Fix the published opam package metadata and release CI so releases no longer ship repo-only tests and now cover the previously flaky upstream opam targets.


## 0.0.4 - 2026-04-11


- Skip published `nats-client-async` builds on Alpine and riscv64, where upstream `core_unix` fails under opam-ci.
- Run published package tests only on opam and architectures that match the opam-ci matrix we support.
- Split fast validation from slower opam reproduction, cache the slow opam roots between reruns, and mirror the remaining opam-ci platform failures and pending cross-arch checks in the slower workflow.


## 0.0.3 - 2026-04-10


- Publish only hermetic package tests and keep the TCP-listener async coverage in repo-only integration tests.
- Mirror the failing opam-repository lower-bounds and package install checks in CI before the next release is cut.
- Require `yojson >= 2.0.0` for `nats-client-async`.


## 0.0.2 - 2026-04-09


- Add the missing `yojson` dependency to the `nats-client-async` opam metadata.
- Scope test stanzas by package so `nats-client` can build and test without `nats-client-async` installed.
- Add CI checks that install each published opam package in isolation.


## 0.0.1 - 2026-04-07


Lower the package metadata for broader Async toolchain compatibility and add a
Docker-backed integration test flow with a real NATS server and an external
consumer fixture.

