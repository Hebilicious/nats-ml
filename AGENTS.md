# AGENTS.md

## Repo Conventions

- Use `proto` for local toolchain resolution.
- Run tests locally with `proto exec --tools-from-config -- dune runtest`.
- Keep generated `nats-client.opam` and `nats-client-async.opam` committed and in sync with `dune-project`.
- Do not hand-edit generated opam files unless you are intentionally changing package metadata in `dune-project` and then rebuilding them.

## Release Workflow

This repo uses a PR-based release flow modeled after changesets/release-plz, but implemented with `dune-release` and `opam-publish`.

The flow has three pieces:

1. Each user-facing PR adds one fragment under `.changes/`.
   - The first non-empty line is `patch`, `minor`, or `major`.
   - The remaining lines are release notes.
   - See `.changes/README.md`.

2. `release-pr.yml` runs on pushes to `main` or manually.
   - It installs the toolchain through `moonrepo/setup-toolchain@v0` with `auto-install: true`, so `opam` and `dune` are directly on `PATH`.
   - It installs `dune-release` and `opam-publish`.
   - It runs `scripts/prepare-release.sh prepare-pr`.
   - That script validates the repo, computes the next version from `.changes/`, prepends a new section to `CHANGES.md`, removes the consumed fragments, and emits the next version as workflow output.
   - The workflow then opens or updates a `release: vX.Y.Z` PR with `peter-evans/create-pull-request`.

3. `publish.yml` runs when a `v*` tag is pushed.
   - It repeats the release preflight.
   - It runs `dune-release distrib`, `dune-release publish`, and `dune-release opam submit`.
   - `dune-release opam submit` is the standard OCaml publication path and uses the `opam-publish` submission flow under the hood to open the PR against `opam-repository`.

## Release Discipline

- Keep release logic in `scripts/prepare-release.sh`; the workflows should stay thin.
- If release metadata changes, update `dune-project`, regenerate the opam files, and commit the result.
- Prefer validating release readiness before tagging, not after tagging.
- Never invent a parallel release path in the workflows. Use the script as the single source of truth.
- Merge the automated release PR before tagging.
- Tags should be named `vX.Y.Z` and point at `main`.
