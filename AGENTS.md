# AGENTS.md

## Repo Conventions

- Use `proto` for local toolchain resolution.
- Run tests locally with `proto exec --tools-from-config -- dune runtest`.
- Keep generated `nats-client.opam` and `nats-client-async.opam` committed and in sync with `dune-project`.
- Do not hand-edit generated opam files unless you are intentionally changing package metadata in `dune-project` and then rebuilding them.

## Release Workflow

This repo uses a PR-based release flow built on `dune-release` and `opam-publish`.

The flow has two phases:

1. `release-pr.yml` is the preflight gate.
   - It runs on pull requests targeting `main`.
   - It also runs manually with `workflow_dispatch`.
   - It installs the OCaml toolchain through `moonrepo/setup-toolchain@v0` with `auto-install: true`, so `proto`, `opam`, and `dune` are available on `PATH`.
   - It installs the release helpers with `opam install dune-release opam-publish`.
   - It runs `scripts/prepare-release.sh check`.
   - That script should verify package metadata, build the project, and run `dune-release lint`.

2. `publish.yml` is the tagged release submission step.
   - It runs on tags matching `v*`.
   - It uses the same toolchain setup.
   - It installs `dune-release` and `opam-publish`.
   - It runs `scripts/prepare-release.sh publish`.
   - That script should verify the tag, run the release checks again, and submit the package with `dune-release opam submit`.
   - `dune-release opam submit` is the standard OCaml release path and uses the `opam-publish` machinery under the hood to open the PR against `opam-repository`.

## Release Discipline

- Keep release logic in `scripts/prepare-release.sh`; the workflows should stay thin.
- If release metadata changes, update `dune-project`, regenerate the opam files, and commit the result.
- Prefer validating release readiness before tagging, not after tagging.
- Never invent a parallel release path in the workflows. Use the script as the single source of truth.
