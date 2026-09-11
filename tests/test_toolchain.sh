#!/usr/bin/env bash
set -euo pipefail

# End-to-end test of the subtree workflow against local bare repositories.
# No network, no Arduino tools required.   Usage: tests/test_toolchain.sh

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

pass=0
ok()   { echo "  ✓ $*"; pass=$((pass + 1)); }
fail() { echo "  ✗ $*"; exit 1; }
g()    { git -c user.name=test -c user.email=test@test -c init.defaultBranch=main "$@"; }

# ---- upstream: snapshot of the working tree as a bare repo ----
UPSTREAM_SRC="${WORK}/upstream-src"
UPSTREAM="${WORK}/upstream.git"
mkdir -p "${UPSTREAM_SRC}"
(cd "${REPO}" && tar --exclude=.git -cf - .) | (cd "${UPSTREAM_SRC}" && tar -xf -)
g -C "${UPSTREAM_SRC}" init -q
g -C "${UPSTREAM_SRC}" add -A
g -C "${UPSTREAM_SRC}" commit -q -m "toolchain snapshot"
g init -q --bare "${UPSTREAM}"
g -C "${UPSTREAM_SRC}" push -q "${UPSTREAM}" HEAD:main
export XEWE_TOOLCHAIN_URL="file://${UPSTREAM}"

new_project() {
  local dir="$1"
  mkdir -p "${dir}/src"
  echo '#include "Config.h"' > "${dir}/$(basename "${dir}").ino"
  echo '#define BUILD_VERSION "0.0.0"' > "${dir}/Config.h"
  g -C "${dir}" init -q
  g -C "${dir}" add -A
  g -C "${dir}" commit -q -m "initial"
}

echo "add"
P="${WORK}/demo"
new_project "${P}"
( export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
  "${UPSTREAM_SRC}/toolchain.sh" add "${P}" >/dev/null 2>&1 )
[[ -x "${P}/build/toolchain/scripts/mac/build.sh" ]] && ok "subtree vendored at build/toolchain" || fail "subtree missing"
[[ -f "${P}/build/release_matrix.csv" && -f "${P}/build/libraries/required_libraries.txt" ]] && ok "project data templates created" || fail "templates missing"
[[ -z "$(git -C "${P}" status --porcelain)" ]] && ok "everything committed" || fail "uncommitted leftovers"
grep -Fxq "build_config" "${P}/build/.gitignore" && ok "build/.gitignore has generated files" || fail "gitignore"

echo "paths (called from an unrelated directory)"
out="$(cd / && bash -c "source '${P}/build/toolchain/scripts/common/paths.sh'; echo \"\${TOOLCHAIN_ROOT}|\${BUILD_ROOT}|\${PROJECT_ROOT_DEFAULT}\"")"
[[ "${out}" == "${P}/build/toolchain|${P}/build|${P}" ]] && ok "paths resolve: ${out}" || fail "paths: ${out}"

out="$(cd / && XEWE_BUILD_ROOT=/tmp XEWE_PROJECT_ROOT=/opt bash -c "source '${P}/build/toolchain/scripts/common/paths.sh'; echo \"\${BUILD_ROOT}|\${PROJECT_ROOT_DEFAULT}\"")"
[[ "${out}" == "/tmp|/opt" ]] && ok "env overrides work" || fail "overrides: ${out}"

out="$(cd / && "${P}/build/toolchain/scripts/linux/upload.sh" -c c3 -p /dev/null 2>&1 || true)"
if grep -q "Run setup_build_environment.sh first" <<< "${out}"; then
  ok "missing build_config gives a clear error"
else
  fail "missing build_config message"
fi

# fake build_config: python replaced by a recorder, so listen_serial.sh runs without hardware
cat > "${P}/build/build_config" <<EOF
venv_python_bin="${WORK}/fakepy"
get_cfg() { local key="\$1"; echo "\${!key}"; }
EOF
printf '#!/usr/bin/env bash\necho "$@" >> "%s/fakepy.log"\n' "${WORK}" > "${WORK}/fakepy"
chmod +x "${WORK}/fakepy"
# PATH without ~/.local/bin so a locally installed arduino-cli does not take precedence
(cd / && PATH=/usr/bin:/bin "${P}/build/toolchain/scripts/linux/listen_serial.sh" -p /dev/fake -b 9600 >/dev/null 2>&1) || true
grep -q "/dev/fake" "${WORK}/fakepy.log" && ok "scripts run via linux stub from any CWD and read build_config" || fail "listen_serial did not run: $(cat "${WORK}/fakepy.log" 2>/dev/null)"
rm "${P}/build/build_config"

echo "update"
echo "# upstream change" >> "${UPSTREAM_SRC}/README.md"
g -C "${UPSTREAM_SRC}" commit -q -am "upstream change"
g -C "${UPSTREAM_SRC}" push -q "${UPSTREAM}" HEAD:main
( export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
  "${P}/build/toolchain/toolchain.sh" update >/dev/null 2>&1 )
grep -q "# upstream change" "${P}/build/toolchain/README.md" && ok "update pulled upstream change" || fail "update"

status="$("${P}/build/toolchain/toolchain.sh" status)"
echo "${status}" | grep -q "upstream rev:  $(git -C "${UPSTREAM_SRC}" rev-parse HEAD)" && ok "status reports upstream revision" || fail "status: ${status}"

echo "push"
echo "# local fix" >> "${P}/build/toolchain/scripts/mac/format.sh"
g -C "${P}" commit -q -am "fix formatter script"
( export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
  "${P}/build/toolchain/toolchain.sh" push --branch local-fix >/dev/null 2>&1 )
git -C "${UPSTREAM}" show local-fix:scripts/mac/format.sh | grep -q "# local fix" && ok "push sent edits to a branch" || fail "push"
if "${P}/build/toolchain/toolchain.sh" push --branch main >/dev/null 2>&1; then fail "push to main allowed"; else ok "push to main refused"; fi

echo "migrate"
M="${WORK}/legacy"
new_project "${M}"
mkdir -p "${M}/build/scripts/mac" "${M}/build/tools/code_formatter" "${M}/build/libraries"
echo 'old' > "${M}/build/scripts/mac/build.sh"
echo 'old' > "${M}/build/tools/code_formatter/format.py"
printf 'CHIP,LED_PIN,_BUILD_NOTES\nc3,8,custom\n' > "${M}/build/release_matrix.csv"
echo "https://github.com/bblanchon/ArduinoJson" > "${M}/build/libraries/required_libraries.txt"
g -C "${M}" add -A
g -C "${M}" commit -q -m "legacy layout"
( export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test
  "${UPSTREAM_SRC}/toolchain.sh" migrate "${M}" >/dev/null 2>&1 )
[[ ! -e "${M}/build/scripts" && ! -e "${M}/build/tools" ]] && ok "old in-tree toolchain removed" || fail "old dirs remain"
[[ -x "${M}/build/toolchain/scripts/mac/build.sh" ]] && ok "subtree added" || fail "subtree missing after migrate"
grep -q "c3,8,custom" "${M}/build/release_matrix.csv" && ok "project release matrix preserved" || fail "matrix overwritten"
grep -q "ArduinoJson" "${M}/build/libraries/required_libraries.txt" && ok "required libraries preserved" || fail "required libraries overwritten"
[[ -z "$(git -C "${M}" status --porcelain)" ]] && ok "migration fully committed" || fail "migration left changes"

echo
echo "all ${pass} checks passed"
