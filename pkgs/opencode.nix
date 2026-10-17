{ lib, stdenvNoCC, fetchurl, autoPatchelfHook, unzip, makeWrapper, stdenv, glibc, gcc-unwrapped, zlib }:
let
  release = builtins.fromJSON (builtins.readFile ../version.json);
  system = stdenv.hostPlatform.system;
  assets = {
    x86_64-linux = "opencode-linux-x64.tar.gz";
    aarch64-linux = "opencode-linux-arm64.tar.gz";
    x86_64-darwin = "opencode-darwin-x64.zip";
    aarch64-darwin = "opencode-darwin-arm64.zip";
  };
  hash = release.hashes.${system} or "";
in
assert lib.assertMsg (hash != "") "opencode-nix: run update workflow to bootstrap version.json first";
stdenvNoCC.mkDerivation {
  pname = "opencode";
  version = release.version;
  src = fetchurl {
    url = "https://github.com/anomalyco/opencode/releases/download/v${release.version}/${assets.${system}}";
    inherit hash;
  };
  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ]
    ++ lib.optionals stdenv.isDarwin [ unzip ];
  buildInputs = lib.optionals stdenv.isLinux [ glibc gcc-unwrapped.lib zlib ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  unpackPhase = ''
    runHook preUnpack
    if [[ "$src" == *.zip ]]; then
      unzip -q "$src"
    else
      tar -xzf "$src"
    fi
    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    binary="$(find . -type f -name opencode | head -n 1)"
    test -n "$binary"
    install -m755 "$binary" "$out/bin/opencode"
    runHook postInstall
  '';
  meta = {
    description = "OpenCode AI coding agent, official upstream binary";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames assets;
  };
}
