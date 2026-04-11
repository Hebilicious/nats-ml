#!/usr/bin/env bash

opam_ci_usage() {
  local script_name=$1
  local args=$2

  echo "usage: $script_name $args" >&2
  exit 1
}

opam_ci_validate_mode() {
  case "$1" in
    build|lower-bounds|with-test|with-test-opam20|expect-unavailable) ;;
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
  local opam_cmd=${OPAM_BIN:-${NATS_ML_OPAM_CI_OPAM_BIN:-opam}}

  if ! command -v "$opam_cmd" >/dev/null 2>&1 && [[ ! -x "$opam_cmd" ]]; then
    echo "opam is required for opam CI compatibility checks." >&2
    exit 1
  fi
}

opam_ci_resolve_opam_bin() {
  if [[ -n "${NATS_ML_OPAM_CI_OPAM_VERSION:-}" ]]; then
    local arch
    local opam_dir
    local opam_url

    case "$(uname -m)" in
      x86_64|amd64) arch=x86_64-linux ;;
      aarch64|arm64) arch=arm64-linux ;;
      *)
        echo "unsupported architecture for opam ${NATS_ML_OPAM_CI_OPAM_VERSION}: $(uname -m)" >&2
        exit 1
        ;;
    esac

    opam_dir=${NATS_ML_OPAM_CI_OPAM_DIR:-$(mktemp -d)}
    OPAM_BIN_CLEANUP_DIR=$opam_dir
    OPAM_BIN="$opam_dir/opam"
    opam_url="https://github.com/ocaml/opam/releases/download/${NATS_ML_OPAM_CI_OPAM_VERSION}/opam-${NATS_ML_OPAM_CI_OPAM_VERSION}-${arch}"
    curl -fsSL "$opam_url" -o "$OPAM_BIN"
    chmod +x "$OPAM_BIN"
  elif [[ -n "${NATS_ML_OPAM_CI_OPAM_BIN:-}" ]]; then
    OPAM_BIN=$NATS_ML_OPAM_CI_OPAM_BIN
  elif [[ -x /usr/bin/opam-dev ]]; then
    OPAM_BIN=/usr/bin/opam-dev
  else
    OPAM_BIN=opam
  fi
}

opam_ci_opam() {
  "$OPAM_BIN" "$@"
}

opam_ci_configure_solver() {
  if [[ -n "${NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER:-}" ]]; then
    return 0
  fi
  opam_ci_opam option solver=builtin-0install || true
}

opam_ci_export_env() {
  export CI=true
  export OPAM_REPO_CI=true
  export OPAMDOWNLOADJOBS=1
  export OPAMERRLOGLEN=0
  export OPAMPRECISETRACKING=1
  if [[ -z "${NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER:-}" ]]; then
    export OPAMEXTERNALSOLVER=builtin-0install
  else
    unset OPAMEXTERNALSOLVER || true
  fi
}

opam_ci_init_root() {
  local init_args=(--bare --no-setup -y default https://opam.ocaml.org)

  if ((${#INIT_ARGS[@]} > 0)); then
    init_args+=("${INIT_ARGS[@]}")
  fi

  opam_ci_opam init "${init_args[@]}"
}

opam_ci_create_switch() {
  local switch_name=$1

  opam_ci_opam switch create -y "$switch_name" "$OCAML_COMPILER"
  opam_ci_opam install --switch="$switch_name" -y "$DUNE_PACKAGE"
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
    with-test-opam20)
      OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.5.4.0}
      DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.22.1}
      INIT_ARGS=()
      NATS_ML_OPAM_CI_OPAM_VERSION=${NATS_ML_OPAM_CI_OPAM_VERSION:-2.0.10}
      NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER=1
      ;;
    expect-unavailable)
      OCAML_COMPILER=${NATS_ML_OPAM_CI_COMPILER:-ocaml-base-compiler.5.4.0}
      DUNE_PACKAGE=${NATS_ML_OPAM_CI_DUNE:-dune.3.22.1}
      INIT_ARGS=(--disable-sandboxing)
      if [[ "${NATS_ML_OPAM_CI_OPAM_VERSION:-}" == 2.0* ]]; then
        NATS_ML_OPAM_CI_DISABLE_BUILTIN_SOLVER=1
      fi
      ;;
  esac
}

opam_ci_prepare_artifacts() {
  local repo_root=$1
  local script_dir=$2

  if [[ -z "${ARTIFACT_ROOT:-}" ]]; then
    ARTIFACT_ROOT=$(mktemp -d "$repo_root/.opam-ci-artifacts.XXXXXX")
  fi
  "$script_dir/prepare-opam-ci-artifacts.sh" "$ARTIFACT_ROOT"
  PACKAGE_VERSION=$(<"$ARTIFACT_ROOT/version")
}

opam_ci_cleanup_artifacts() {
  if [[ -n "${ARTIFACT_ROOT:-}" && -d "$ARTIFACT_ROOT" ]]; then
    rm -rf "$ARTIFACT_ROOT"
  fi
  if [[ -n "${OPAM_BIN_CLEANUP_DIR:-}" && -d "$OPAM_BIN_CLEANUP_DIR" ]]; then
    rm -rf "$OPAM_BIN_CLEANUP_DIR"
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
    with-test-opam20)
      "$@" --with-test "$package_version"
      ;;
  esac
}
