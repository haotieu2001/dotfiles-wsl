# 03 - `modules/herdr.nix`

herdr lets you run several terminals in one window, and it knows about AI coding
tools. It is not in nixpkgs, so this file wraps the ready-made program that the
authors publish.

Their normal install command is
`curl -fsSL https://herdr.dev/install.sh | sh`. That grabs whatever the newest
version is today, which is the opposite of what this repo wants. So we pick one
version and check the download against a fingerprint instead.

## Line by line

```nix
{ lib, stdenvNoCC, fetchurl }:
```

A package is a function. `pkgs.callPackage` in `home.nix` reads these argument
names and fills each one in from the package set.

`stdenvNoCC` is the normal build setup **without a C compiler**. We are
installing a ready-made program, not building one, so pulling in a compiler
would only make things slower.

```nix
let
  version = "0.7.5";
```

The version we install. Changing this number alone is not enough. The
fingerprints below must change too, and Nix refuses to build if they do not
match.

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

One entry per kind of processor, because the authors publish a separate file for
each.

The `hash` is a fingerprint of the download. It is what keeps you safe: if the
download is damaged, or if someone replaces the published file with a different
one, the build stops with an error instead of quietly installing something else.

```nix
  system = stdenvNoCC.hostPlatform.system;
  source = sources.${system}
    or (throw "herdr: no prebuilt binary for ${system}");
in
```

Picks the right entry for your computer. The `or (throw ...)` part turns an
unsupported processor into a clear message, instead of a confusing
`attribute missing` error.

```nix
stdenvNoCC.mkDerivation {
  pname = "herdr";
  inherit version;

  src = fetchurl { inherit (source) url hash; };
```

`inherit (source) url hash` is short for
`url = source.url; hash = source.hash;`. `fetchurl` downloads the file and checks
the fingerprint before anything else runs.

```nix
  dontUnpack = true;
```

Normally Nix would try to unzip `src`. Here `src` is the program itself, not an
archive, so we skip that.

```nix
  installPhase = ''
    runHook preInstall
    install -Dm755 "$src" "$out/bin/herdr"
    runHook postInstall
  '';
```

This is the whole build. `install -D` creates the `$out/bin/` folder if needed,
and `m755` makes the file runnable. `$out` is where this package lives in the
Nix store.

The two `runHook` lines are a convention. They let someone add extra steps
before or after, without rewriting this part.

**We do not use `autoPatchelfHook`.** Usually a downloaded Linux program expects
a loader at `/lib64/ld-linux-x86-64.so.2`, which does not exist on a
Nix-managed system, so it has to be patched. herdr is built in a way that needs
no loader at all, so it runs as-is. You can check for yourself:

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

Information about the package. `platforms` is worked out from `sources`, so the
two lists can never disagree.

`sourceProvenance = binaryNativeCode` is an honest note that this is a
ready-made program, not something built from source code we can read. Tools use
that to point out packages nobody has checked.

## Updating herdr

```bash
# 1. see the newest version
curl -s https://herdr.dev/latest.json | jq -r .version

# 2. change `version` in this file, then get each fingerprint
nix store prefetch-file --json \
  https://github.com/ogulcancelik/herdr/releases/download/v<NEW>/herdr-linux-x86_64 \
  | jq -r .hash

# 3. paste the fingerprints in, then
./rebuild.sh
```

If you skip step 2, the build stops with
`hash mismatch in fixed-output derivation` and shows both the expected and the
real fingerprint. Copying the "got" value in is fine, as long as you trust where
the file came from.

## Why not just use their install script

Both `herdr update` and their installer write into `~/.local/bin`, which Nix
does not manage. You would then have two copies of herdr, with no record of
which one you are running.

Keeping it in Nix means `flake.lock` and this file describe your herdr
completely, and a new computer gets exactly the same one.
