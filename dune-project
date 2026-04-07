(lang dune 3.19)

(name nats-client)

(generate_opam_files true)

(source
 (github hebilicious/nats-ml))

(authors "Hebilicious")

(maintainers "Hebilicious")

(license MIT)

(package
 (name nats-client)
 (synopsis "Lean OCaml NATS protocol client")
 (description "Runtime-independent OCaml NATS protocol primitives")
 (depends
  (ocaml (>= 4.14.0))
  dune
  yojson
  (alcotest :with-test)))

(package
 (name nats-client-async)
 (synopsis "Lean OCaml Async NATS client")
 (description "Async-based OCaml NATS client")
 (depends
  (ocaml (>= 4.14.0))
  dune
  core
  async
  async_unix
  uri
  nats-client
  (alcotest :with-test)))
