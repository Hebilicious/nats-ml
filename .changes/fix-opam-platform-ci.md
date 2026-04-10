patch

- Skip published `nats-client-async` builds on Alpine and riscv64, where upstream `core_unix` fails under opam-ci.
- Run published package tests only on opam and architectures that match the opam-ci matrix we support.
- Split fast validation from slower opam reproduction, cache the slow opam roots between reruns, and mirror the remaining opam-ci platform failures and pending cross-arch checks in the slower workflow.
