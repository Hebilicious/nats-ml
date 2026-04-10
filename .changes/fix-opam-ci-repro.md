patch

- Publish only hermetic package tests and keep the TCP-listener async coverage in repo-only integration tests.
- Mirror the failing opam-repository lower-bounds and package install checks in CI before the next release is cut.
- Require `yojson >= 2.0.0` for `nats-client-async`.
