{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  gnutar,
  autoPatchelfHook,
  ...
}:
let
  version = "2.3.0-ocv.4.15";
  asset =
    {
      "aarch64-darwin" = {
        name = "ocv-darwin-arm64.zip";
        hash = "sha256-bO6UZLyYX9DB8YkInDk1jXeAoqgxukhjPRrus8A5X0Q=";
      };
      "x86_64-linux" = {
        name = "ocv-linux-x64.tar.gz";
        hash = "sha256-Z8L39OifvrzVfniDfT5Rl118Z4FH5OS43IBuG3mVm9s=";
      };
      "aarch64-linux" = {
        name = "ocv-linux-arm64.tar.gz";
        hash = "sha256-L8vGAbphHdAFpiUHzANt+EOtQ1SwbPjOicAyd/l5ffk=";
      };
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "opencode-release: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "opencode";
  inherit version;

  src = fetchurl {
    url = "https://github.com/leohenon/opencode-vim/releases/download/v${version}/${asset.name}";
    sha256 = asset.hash;
  };

  nativeBuildInputs =
    if stdenvNoCC.hostPlatform.isDarwin then
      [ unzip ]
    else
      [
        gnutar
        autoPatchelfHook
      ];

  dontConfigure = true;
  dontBuild = true;
  dontUnpack = true;

  # bun --compile keeps the 8-byte BUN_COMPILED payload pointer in a gap
  # no section header covers (the .bun header is repointed at the embedded
  # payload). GNU strip rewrites the ELF through BFD and drops gap content,
  # zeroing that pointer, so the binary boots as plain bun (bun's help
  # text) instead of opencode. autoPatchelfHook propagates binutils-wrapper,
  # which arms the otherwise-inert stdenvNoCC strip phase - keep strip away.
  # Without the hook nothing strips, which is why the darwin build is fine.
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    if [[ "$src" == *.zip ]]; then
      unzip -o "$src" -d $out/bin
    else
      tar xf "$src" -C $out/bin
    fi
    chmod 755 $out/bin/opencode
    runHook postInstall
  '';

  meta = {
    description = "OpenCode (vim-mode fork) pre-built release";
    homepage = "https://github.com/leohenon/opencode-vim";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-darwin"
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "opencode";
  };
}
