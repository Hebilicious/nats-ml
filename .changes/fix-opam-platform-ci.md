patch

- Skip published `nats-client-async` builds on Alpine, and on `riscv64` with OCaml 5.4+, where upstream `core_unix` fails under opam-ci.
- Run published package tests only on opam and architectures that match the opam-ci matrix we support.
- Mirror the remaining opam-ci platform failures and pending cross-arch checks in GitHub Actions before release.
