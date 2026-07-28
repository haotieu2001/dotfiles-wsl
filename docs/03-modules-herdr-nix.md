# 03 - `modules/herdr.nix`

herdr is the agent-aware terminal multiplexer from the video's 33:22 chapter.
The video installs it with `brews = [ "herdr" ]`. There is no Homebrew here and
herdr is not in nixpkgs, so this file packages the upstream release binary.

The upstream install path is `curl -fsSL https://herdr.dev/install.sh | sh`,
which fetches whatever "latest" happens to be at the time. That is the opposite
of what this repo is for, so we pin a version and verify a hash instead.

## Line by line

```nix
{ lib, stdenvNoCC, fetchurl }:
```

A package function. `pkgs.callPackage` in `home.nix` inspects these parameter
names and supplies each one from the package set.

`stdenvNoCC` is the standard build environment **without a C compiler**. We are
installing a prebuilt binary, not compiling anything, so pulling in a whole
toolchain would only slow the build down.

```nix
let
  version = "0.7.5";
```

The pinned version. Bumping this alone is not enough; the hashes below must
change with it, and Nix will refuse the build if they do not match.

```nix
  sources = {
    "x86_64-linux" = {
      url = "https://github.com/ogulcancelik/herdr/releases/download/v${version}/herdr-linux-x86_64";
      hash = "sha256-PcgyiAc+TC08Z5ow576XvMqRQcb9F9u7khkULpXFklM=";
    };
    "aarch64-linux" = {
      url = ".../herdr-linux-aarch64";
      hash = "sha256-MudjoUmaa2lLHXCOTwYrdDvh2p80/PpNIS1ttv4JqLk=";
    };
  };
```

One entry per architecture, since upstream ships separate binaries. The hash is
SRI format (`sha256-` plus base64) and is the integrity guarantee: if the
download is corrupted, or the release asset is ever replaced with different
bytes, the build fails loudly instead of silently installing something else.

```nix
  system = stdenvNoCC.hostPlatform.system;
  source = sources.${system}
    or (throw "herdr: no prebuilt binary for ${system}");
in
```

Selects the right entry. The `or (throw ...)` turns an unsupported platform into
a readable message rather than a bare `attribute missing` error.

```nix
stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;

  src = fetchurl { inherit (source) url hash; };
```

`inherit (source) url hash` is shorthand for `url = source.url; hash = source.hash;`.
`fetchurl` downloads and verifies against the hash before the build starts.

```nix
  dontUnpack = true;
```

The default build would try to extract `src` as an archive. Here `src` is a bare
executable, so unpacking is skipped.

```nix
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';
```

The entire build. `install -D` creates `$out/bin/` as needed, and `m755` makes
the result executable. `$out` is the package's store path.

The `runHook` calls are convention: they let anyone override the package with
`preInstall` / `postInstall` additions without rewriting this phase.

**No `autoPatchelfHook`.** Normally a downloaded Linux binary expects an ELF
interpreter at `/lib64/ld-linux-x86-64.so.2`, which does not exist on NixOS-style
systems, and needs patching. herdr's releases are `static-pie` linked, with no
interpreter and no `NEEDED` entries at all, so the binary runs unmodified. You
can confirm this yourself:

```bash
file $(which herdr)
# ... ELF 64-bit LSB pie executable, x86-64, ... static-pie linked ...
```

```nix
  meta = {
    description = "Agent-aware terminal multiplexer";
    homepage = "https://herdr.dev";
    platforms = builtins.attrNames sources;
    mainProgram = "herdr";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
```

Metadata. `platforms` is derived from `sources` so the two cannot drift apart.
`sourceProvenance = binaryNativeCode` is an honest declaration that this is a
prebuilt binary rather than something built from source, which tooling uses to
flag packages that were not compiled from auditable inputs.

## Upgrading herdr

```bash
# 1. see what is current
curl -s https://herdr.dev/latest.json | jq -r .version

# 2. bump `version` in this file, then get each hash
nix store prefetch-file --json \
  https://github.com/ogulcancelik/herdr/releases/download/v<NEW>/herdr-linux-x86_64 \
  | jq -r .hash

# 3. paste the hashes in, then
./rebuild.sh
```

If you skip step 2, the build fails with `hash mismatch in fixed-output
derivation`, showing both the expected and actual values. Copying the "got"
value in is a valid way to do this, as long as you trust the download.

## Why not just use the install script

`herdr update` and the upstream installer both write into `~/.local/bin`, which
sits outside Nix's control. You would then have two herdrs on `PATH` and no
record of which one you are running. Keeping it in Nix means `flake.lock` plus
this file fully describe your herdr, and a fresh machine reproduces it exactly.
