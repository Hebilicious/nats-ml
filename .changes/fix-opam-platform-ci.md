patch

- Skip published `nats-client-async` builds on Alpine, where the upstream `core_unix` dependency fails under opam-ci.
- Run published package tests only on opam and architectures that match the opam-ci matrix we support.
- Mirror the remaining opam-ci platform failures and pending cross-arch checks in GitHub Actions before release.
