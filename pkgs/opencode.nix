{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  stdenv,
  glibc,
  gcc-unwrapped,
  zlib,
}:
let
  release = builtins.fromJSON (builtins.readFile ../version.json);
  system = stdenv.hostPlatform.system;
  packages = {
    x86_64-linux = "cli-linux-x64";
    aarch64-linux = "cli-linux-arm64";
    x86_64-darwin = "cli-darwin-x64";
    aarch64-darwin = "cli-darwin-arm64";
  };
  hash = release.hashes.${system} or "";
in
assert lib.assertMsg (hash != "") "opencode-nix: no hash for platform";
assert lib.assertMsg (lib.hasPrefix "2." release.version)
  "opencode-nix: run V2 update workflow to update version.json";
stdenvNoCC.mkDerivation {
  pname = "opencode";
  version = release.version;
  src = fetchurl {
    url = "https://registry.npmjs.org/@opencode/${packages.${system}}/-/${packages.${system}}-${release.version}.tgz";
    inherit hash;
  };
  nativeBuildInputs = [ makeWrapper ] ++ lib.optionals stdenv.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.isLinux [
    glibc
    gcc-unwrapped.lib
    zlib
  ];
  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  # Bun standalone executables contain appended application data that stripping removes.
  dontStrip = true;
  unpackPhase = ''
    runHook preUnpack
    tar -xzf "$src"
    runHook postUnpack
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    binary="$(find package -type f -name opencode | head -n 1)"
    test -n "$binary"
    install -m755 "$binary" "$out/bin/opencode"
    runHook postInstall
  '';
  meta = {
    description = "OpenCode V2 official prebuilt npm binary";
    homepage = "https://opencode.ai";
    license = lib.licenses.mit;
    mainProgram = "opencode";
    platforms = builtins.attrNames packages;
  };
}
