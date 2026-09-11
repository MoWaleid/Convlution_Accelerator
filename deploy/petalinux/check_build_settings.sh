#!/bin/bash
# User-run settings check ONLY; do not reapply packages or regenerate configuration.
set -e -o pipefail
test "$#" -eq 1
M2P_CHECK_OUTPUT=$(realpath -e -- "$1")
readonly M2P_CHECK_OUTPUT
# Sourced scripts inherit this shell's positional arguments unless explicitly replaced.
set --
M2P_CHECK_STAGE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly M2P_CHECK_STAGE
readonly M2P_CHECK_PROJECT=/home/walid/projects/zedboard_linux
readonly M2P_CHECK_BUILD=/home/walid/projects/zedboard_linux/build
readonly M2P_CHECK_TOOLS=/home/walid/petalinux/2025.2
readonly M2P_CHECK_POKY="$M2P_CHECK_PROJECT/components/yocto/layers/poky"
readonly M2P_CHECK_RECIPES=(python3 python3-pillow conv-lab conv-lab-starter conv-lab-validation petalinux-image-minimal)

test -d "$M2P_CHECK_OUTPUT"
test -w "$M2P_CHECK_OUTPUT"
case "$M2P_CHECK_OUTPUT/" in
    "$M2P_CHECK_PROJECT/"*|"$M2P_CHECK_STAGE/"*)
        echo "Output must be outside project/stage" >&2; exit 2;;
esac
M2P_CHECK_EXISTING=$(find "$M2P_CHECK_OUTPUT" -mindepth 1 -maxdepth 1 -print -quit)
test -z "$M2P_CHECK_EXISTING"
for m2p_recipe in "${M2P_CHECK_RECIPES[@]}"; do
    test ! -e "$M2P_CHECK_OUTPUT/$m2p_recipe.env"
    test ! -L "$M2P_CHECK_OUTPUT/$m2p_recipe.env"
done
(cd "$M2P_CHECK_STAGE" && sha256sum -c SHA256SUMS.txt)

# Require the existing project before any setup operation. Never create a build/conf.
test "$(realpath -e -- "$M2P_CHECK_PROJECT")" = "$M2P_CHECK_PROJECT"
test "$(realpath -e -- "$M2P_CHECK_BUILD")" = "$M2P_CHECK_BUILD"
for m2p_config in local.conf bblayers.conf; do
    test -f "$M2P_CHECK_BUILD/conf/$m2p_config"
    test -r "$M2P_CHECK_BUILD/conf/$m2p_config"
    test -s "$M2P_CHECK_BUILD/conf/$m2p_config"
done
# Default Poky bblayers.conf is not an acceptable substitute for this project's file.
grep -Fq "$M2P_CHECK_PROJECT/project-spec/meta-user" "$M2P_CHECK_BUILD/conf/bblayers.conf"
M2P_CHECK_CONFIG_BEFORE=$(sha256sum "$M2P_CHECK_BUILD/conf/local.conf" "$M2P_CHECK_BUILD/conf/bblayers.conf")
readonly M2P_CHECK_CONFIG_BEFORE

set --
source "$M2P_CHECK_TOOLS/settings.sh"
M2P_CHECK_SETUP_STATUS=$?
set -e -o pipefail
test "$M2P_CHECK_SETUP_STATUS" -eq 0
test -n "${PETALINUX:-}"
test "$(realpath -e -- "$PETALINUX")" = "$M2P_CHECK_TOOLS"
unset LD_LIBRARY_PATH
shopt -s nullglob
m2p_sdk=( "$M2P_CHECK_PROJECT"/components/yocto/environment-setup-* )
test "${#m2p_sdk[@]}" -eq 1
test -f "${m2p_sdk[0]}"
readonly M2P_CHECK_SDK="${m2p_sdk[0]}"
set --
source "$M2P_CHECK_SDK"
M2P_CHECK_SETUP_STATUS=$?
set -e -o pipefail
test "$M2P_CHECK_SETUP_STATUS" -eq 0
set --
test -n "${PETALINUX:-}"
test "$(realpath -e -- "$PETALINUX")" = "$M2P_CHECK_TOOLS"

# Retain SDK host tools/PATH/sysroots. Remove routing variables that can override
# oe-init's explicit argument, including BDIR (which takes precedence over $1).
# Do not bypass OECORE_SDK_VERSION/OE_SKIP_SDK_CHECK compatibility checks.
unset LD_LIBRARY_PATH BDIR BUILDDIR OEROOT BITBAKEDIR BBPATH
export PETALINUX="$M2P_CHECK_TOOLS"
export PROOT="$M2P_CHECK_PROJECT"
cd "$M2P_CHECK_PROJECT"
# Recheck after SDK setup immediately before initialization.
test "$(realpath -e -- "$M2P_CHECK_BUILD")" = "$M2P_CHECK_BUILD"
for m2p_config in local.conf bblayers.conf; do
    test -f "$M2P_CHECK_BUILD/conf/$m2p_config"
    test -r "$M2P_CHECK_BUILD/conf/$m2p_config"
    test -s "$M2P_CHECK_BUILD/conf/$m2p_config"
done
test "$(sha256sum "$M2P_CHECK_BUILD/conf/local.conf" "$M2P_CHECK_BUILD/conf/bblayers.conf")" = "$M2P_CHECK_CONFIG_BEFORE"
set --
source "$M2P_CHECK_POKY/oe-init-build-env" "$M2P_CHECK_BUILD"
M2P_CHECK_SETUP_STATUS=$?
set -e -o pipefail
test "$M2P_CHECK_SETUP_STATUS" -eq 0
set --
# No BitBake invocation is allowed until these independent postconditions hold.
test "$(pwd -P)" = "$M2P_CHECK_BUILD"
test -n "${BUILDDIR:-}"
test "$(realpath -e -- "$BUILDDIR")" = "$M2P_CHECK_BUILD"
test "${BBPATH:-}" = "$M2P_CHECK_BUILD"
test "${PETALINUX:-}" = "$M2P_CHECK_TOOLS"
test "$(realpath -e -- "$PETALINUX")" = "$M2P_CHECK_TOOLS"
test "${PROOT:-}" = "$M2P_CHECK_PROJECT"
test "$(realpath -e -- "$PROOT")" = "$M2P_CHECK_PROJECT"
test "$(sha256sum "$M2P_CHECK_BUILD/conf/local.conf" "$M2P_CHECK_BUILD/conf/bblayers.conf")" = "$M2P_CHECK_CONFIG_BEFORE"
unset LD_LIBRARY_PATH
export BB_ENV_PASSTHROUGH_ADDITIONS="${BB_ENV_PASSTHROUGH_ADDITIONS:-} PETALINUX PROOT"
printf 'Settings context: PETALINUX=%s PROOT=%s BUILDDIR=%s\n' "$PETALINUX" "$PROOT" "$BUILDDIR"
printf '%s\n' "$M2P_CHECK_CONFIG_BEFORE"
set -o noclobber
for m2p_recipe in "${M2P_CHECK_RECIPES[@]}"; do
    bitbake -e "$m2p_recipe" > "$M2P_CHECK_OUTPUT/$m2p_recipe.env"
done
python3 -I -B "$M2P_CHECK_STAGE/check_settings.py" --directory "$M2P_CHECK_OUTPUT"
