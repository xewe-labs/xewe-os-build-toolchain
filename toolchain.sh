#!/usr/bin/env bash
set -euo pipefail

# toolchain.sh — vendor this toolchain into ESP32 Arduino projects with git subtree.
#
#   From a clone of this repo:
#     ./toolchain.sh add <project-dir>       add build/toolchain to a project (creates build/ data templates)
#     ./toolchain.sh migrate <project-dir>   replace an old in-tree build/scripts + build/tools with the subtree
#
#   From inside a project (build/toolchain/toolchain.sh):
#     ./toolchain.sh update [--ref <branch|tag>]   pull the latest toolchain into the project
#     ./toolchain.sh push --branch <name>          send local toolchain edits back upstream as a branch
#     ./toolchain.sh status                        show the vendored revision and pending local edits
#
# Options: --url <git-url> (default $XEWE_TOOLCHAIN_URL or DEFAULT_URL), --prefix <path> (default build/toolchain)

DEFAULT_URL="https://github.com/xewe-labs/xewe-os-build-toolchain.git"
DEFAULT_PREFIX="build/toolchain"

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL="${XEWE_TOOLCHAIN_URL:-${DEFAULT_URL}}"
PREFIX="${DEFAULT_PREFIX}"
REF="main"
BRANCH=""

die()  { echo "❌ $*" >&2; exit 1; }
info() { echo "➜ $*" >&2; }

usage() { sed -n '4,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

require_clean() {
  local root="$1"
  [[ -z "$(git -C "${root}" status --porcelain)" ]] || die "${root} has uncommitted changes; commit or stash first (git subtree requires a clean tree)"
}

git_root_of() {
  git -C "$1" rev-parse --show-toplevel 2>/dev/null || die "$1 is not inside a git repository"
}

# ---- project data templates (never part of the subtree) ----
init_build_data() {
  local project="$1"
  local build="${project}/build"
  mkdir -p "${build}/libraries"

  if [[ ! -f "${build}/release_matrix.csv" ]]; then
    cp "${SELF_DIR}/templates/release_matrix.csv" "${build}/release_matrix.csv"
    info "created build/release_matrix.csv"
  fi
  if [[ ! -f "${build}/libraries/required_libraries.txt" ]]; then
    cp "${SELF_DIR}/templates/required_libraries.txt" "${build}/libraries/required_libraries.txt"
    info "created build/libraries/required_libraries.txt"
  fi

  touch "${build}/.gitignore"
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    grep -Fxq -- "${line}" "${build}/.gitignore" || echo "${line}" >> "${build}/.gitignore"
  done < "${SELF_DIR}/templates/build.gitignore"
}

cmd_add() {
  local project="${1:-}"
  [[ -n "${project}" ]] || die "usage: toolchain.sh add <project-dir>"
  project="$(cd "${project}" && pwd)"
  local root; root="$(git_root_of "${project}")"
  [[ "${root}" == "${project}" ]] || die "${project} must be the root of its git repository (found ${root})"
  [[ -e "${project}/${PREFIX}" ]] && die "${PREFIX} already exists in ${project}; use update instead"
  git -C "${project}" rev-parse --verify HEAD >/dev/null 2>&1 || die "${project} has no commits yet; make an initial commit first"
  require_clean "${project}"

  info "adding ${URL} (${REF}) at ${PREFIX}"
  git -C "${project}" subtree add --squash --prefix="${PREFIX}" "${URL}" "${REF}"

  init_build_data "${project}"
  if [[ -n "$(git -C "${project}" status --porcelain -- build)" ]]; then
    git -C "${project}" add build
    git -C "${project}" commit -q -m "Add build data for toolchain (release matrix, required libraries, gitignore)"
    info "committed build/ data templates"
  fi
  info "done. Next: cd ${PREFIX}/scripts/<mac|linux|windows> && ./setup_build_environment.sh"
}

cmd_migrate() {
  local project="${1:-}"
  [[ -n "${project}" ]] || die "usage: toolchain.sh migrate <project-dir>"
  project="$(cd "${project}" && pwd)"
  require_clean "${project}"

  local old=()
  for d in build/scripts build/tools; do
    [[ -e "${project}/${d}" ]] && old+=("${d}")
  done
  [[ ${#old[@]} -gt 0 ]] || die "no in-tree build/scripts or build/tools found in ${project}"

  info "removing in-tree toolchain: ${old[*]}"
  git -C "${project}" rm -r -q -- "${old[@]}"
  rm -rf "${old[@]/#/${project}/}"
  git -C "${project}" commit -q -m "Remove in-tree build toolchain (replaced by ${PREFIX} subtree)"

  cmd_add "${project}"
  info "project data kept in build/: release_matrix.csv, libraries/required_libraries.txt"
  info "re-run setup_build_environment so build_config points at the new script location"
}

vendored_context() {
  # we are running from <project>/<prefix>/toolchain.sh
  PROJECT_GIT_ROOT="$(git_root_of "${SELF_DIR}")"
  [[ "${PROJECT_GIT_ROOT}" != "${SELF_DIR}" ]] || die "run this from the copy vendored inside a project (e.g. build/toolchain/toolchain.sh)"
  PREFIX="${SELF_DIR#"${PROJECT_GIT_ROOT}"/}"
}

cmd_update() {
  vendored_context
  require_clean "${PROJECT_GIT_ROOT}"
  info "pulling ${URL} (${REF}) into ${PREFIX}"
  git -C "${PROJECT_GIT_ROOT}" subtree pull --squash --prefix="${PREFIX}" "${URL}" "${REF}" \
    -m "Update build toolchain from ${REF}"
  info "updated. If scripts changed paths or config keys, re-run setup_build_environment."
}

cmd_push() {
  vendored_context
  [[ -n "${BRANCH}" ]] || die "usage: toolchain.sh push --branch <name>   (never pushes to main directly)"
  [[ "${BRANCH}" != "main" ]] || die "refusing to push to main; push a branch and open a pull request"
  require_clean "${PROJECT_GIT_ROOT}"
  info "pushing local ${PREFIX} history to ${URL} branch ${BRANCH}"
  git -C "${PROJECT_GIT_ROOT}" subtree push --prefix="${PREFIX}" "${URL}" "${BRANCH}"
}

cmd_status() {
  vendored_context
  local last
  last="$(git -C "${PROJECT_GIT_ROOT}" log -1 --grep="git-subtree-dir: ${PREFIX}" --format='%H %s' || true)"
  echo "prefix:        ${PREFIX}"
  echo "upstream:      ${URL}"
  if [[ -n "${last}" ]]; then
    local split
    split="$(git -C "${PROJECT_GIT_ROOT}" log -1 --grep="git-subtree-dir: ${PREFIX}" --format='%b' | sed -n 's/^git-subtree-split: //p')"
    echo "last sync:     ${last}"
    echo "upstream rev:  ${split:-unknown}"
    local changed
    changed="$(git -C "${PROJECT_GIT_ROOT}" diff --stat "${last%% *}" HEAD -- "${PREFIX}" | tail -1)"
    echo "local edits:   ${changed:-none since last sync}"
  else
    echo "last sync:     not found (was it added with git subtree --squash?)"
  fi
}

# ---- arguments ----
[[ $# -gt 0 ]] || usage 1
COMMAND="$1"; shift
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)    URL="${2:?missing value}"; shift 2 ;;
    --prefix) PREFIX="${2:?missing value}"; shift 2 ;;
    --ref)    REF="${2:?missing value}"; shift 2 ;;
    --branch) BRANCH="${2:?missing value}"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

case "${COMMAND}" in
  add)     cmd_add "$@" ;;
  migrate) cmd_migrate "$@" ;;
  update)  cmd_update ;;
  push)    cmd_push ;;
  status)  cmd_status ;;
  -h|--help|help) usage 0 ;;
  *) die "unknown command: ${COMMAND}" ;;
esac
