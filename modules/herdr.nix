# herdr - agent-aware terminal multiplexer.
#
# A macOS setup installs this with `brews = [ "herdr" ]`. There is no
# Homebrew here and herdr is not in nixpkgs, so we fetch the upstream release
# binary and pin it by hash. That keeps the install reproducible: the same
# flake.lock + the same hash always yields the same herdr.
#
# To upgrade: bump `version`, then get the new hashes with
#   nix store prefetch-file --json \
#     https://github.com/ogulcancelik/herdr/releases/download/v<VER>/herdr-linux-x86_64
{ lib, stdenvNoCC, fetchurl }:

let
  version = "0.7.5";

  # Upstream publishes static-pie binaries, so there is nothing to patchelf:
  # they carry no ELF interpreter and no NEEDED entries, and run as-is on WSL.
  sources = {
    "x86_64-linux" = {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/herdr-linux-x86_64";
      hash = "sha256-PcgyiAc+TC08Z5ow576XvMqRQcb9F9u7khkULpXFklM=";
    };
    "aarch64-linux" = {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/herdr-linux-aarch64";
      hash = "sha256-MudjoUmaa2lLHXCOTwYrdDvh2p80/PpNIS1ttv4JqLk=";
    };
  };

  system = stdenvNoCC.hostPlatform.system;
  source = sources.${system}
    or (throw "herdr: no prebuilt binary for ${system}");
in

stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;

  src = fetchurl { inherit (source) url hash; };

  # `src` is a bare executable, not an archive.
  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';

  meta = {
    description = "Agent-aware terminal multiplexer";
    homepage = "https://herdr.dev";
    platforms = builtins.attrNames sources;
    mainProgram = "herdr";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
