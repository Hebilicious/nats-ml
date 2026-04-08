patch

- Add the missing `yojson` dependency to the `nats-client-async` opam metadata.
- Scope test stanzas by package so `nats-client` can build and test without `nats-client-async` installed.
- Add CI checks that install each published opam package in isolation.
