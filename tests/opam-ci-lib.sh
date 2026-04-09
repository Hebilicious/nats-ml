#!/usr/bin/env bash

opam_ci_usage() {
  local script_name=$1
  local args=$2

  echo "usage: $script_name $args" >&2
  exit 1
}

opam_ci_validate_mode() {
  case "$1" in
    build|lower-bounds|with-test) ;;
    *) return 1 ;;
  esac
}

opam_ci_validate_package() {
  case "$1" in
    nats-client|nats-client-async) ;;
    *) return 1 ;;
  esac
}

opam_ci_require_opam() {
  if ! command -v opam >/dev/null 2>&1; then
    echo "opam is required for opam CI compatibility checks." >&2
    exit 1
  fi
}

opam_ci_export_env() {
  export CI=true
  export OPAM_REPO_CI=true
  export OPAMDOWNLOADJOBS=1
  export OPAMERRLOGLEN=0
  export OPAMPRECISETRACKING=1
  export OPAMEXTERNALSOLVER=builtin-0install
}

opam_ci_set_mode_defaults() {
  case "$1" in
    build)
      OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.5.4.0}
      DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.22.1}
      INIT_ARGS=(--disable-sandboxing)
      ;;
    lower-bounds)
      OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.4.14.3}
      DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.19.0}
      INIT_ARGS=(--disable-sandboxing)
      ;;
    with-test)
      OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.5.4.0}
      DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.22.1}
      INIT_ARGS=()
      ;;
  esac
}

opam_ci_prepare_artifacts() {
  local repo_root=$1
  local script_dir=$2

  ARTIFACT_ROOT=$(mktemp -d "$repo_root/.opam-ci-artifacts.XXXXXX")
  "$script_dir/prepare-opam-ci-artifacts.sh" "$ARTIFACT_ROOT"
  PACKAGE_VERSION=$(<"$ARTIFACT_ROOT/version")
}

opam_ci_cleanup_artifacts() {
  if [[ -n "${ARTIFACT_ROOT:-}" && -d "$ARTIFACT_ROOT" ]]; then
    rm -rf "$ARTIFACT_ROOT"
  fi
}

opam_ci_run_mode() {
  local mode=$1
  local package_version=$2
  shift 2

  case "$mode" in
    build)
      ;;
    lower-bounds)
      OPAMCRITERIA="+removed,+count[version-lag,solution]" \
      OPAMFIXUPCRITERIA="+removed,+count[version-lag,solution]" \
      OPAMUPGRADECRITERIA="+removed,+count[version-lag,solution]" \
        "$@" "$package_version"
      ;;
    with-test)
      "$@" --with-test "$package_version"
      ;;
  esac
}
