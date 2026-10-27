# Tools that are neither in apt nor installable by a vendor script, downloaded from their
# GitHub releases and checked against these SHA-256 digests (GitHub publishes them per asset:
# `gh api repos/OWNER/REPO/releases/tags/TAG --jq '.assets[] | .name + " " + .digest'`).
# To upgrade one: change the version and the digest together, then re-run ./bootstrap.sh.

HERDR_VERSION="0.7.5"
HERDR_URL="https://github.com/ogulcancelik/herdr/releases/download/v${HERDR_VERSION}/herdr-linux-x86_64"
HERDR_SHA256="3dc83288073e4c2d3c679a30e7be97bcca9141c6fd17dbbb9219142e95c59253"

LUALS_VERSION="3.19.2"
LUALS_URL="https://github.com/LuaLS/lua-language-server/releases/download/${LUALS_VERSION}/lua-language-server-${LUALS_VERSION}-linux-x64.tar.gz"
LUALS_SHA256="93ad326b10f6c00911dd8c450fa098332dbd8f9f45d1052f5636a2d54479b947"

NERDFONT_VERSION="3.5.1"
NERDFONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERDFONT_VERSION}/Hack.tar.xz"
NERDFONT_SHA256="cdd389472e10e2261520140ff1b382b4f8a226af5fd0b2735b975d31151d9c3c"

# Global npm packages (installed into ~/.local with `npm install -g`) and uv tools.
NPM_GLOBALS="typescript typescript-language-server bash-language-server"
UV_TOOLS="basedpyright"
