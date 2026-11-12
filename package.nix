{
  lib,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  gzip,
  makeWrapper,
  ripgrep,
  versionCheckHook,
  writableTmpDirAsHomeHook,
  cctools,
  darwin,
  rcodesign,
}:

let
  # Upstream also publishes linux-x64, which is optimized for AVX2. Use the
  # baseline build so the x86_64-linux package works on all supported x86_64
  # CPUs instead of depending on the build user's CPU flags.
  platforms = {
    x86_64-linux = "linux-x64-baseline";
    aarch64-linux = "linux-arm64";
    x86_64-darwin = "darwin-x64";
    aarch64-darwin = "darwin-arm64";
  };

in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "amp-cli";
  version = "0.0.1794484845-g2f1e0a";

  src = finalAttrs.passthru.sources.${stdenvNoCC.hostPlatform.system};

  nativeBuildInputs = [
    gzip
    makeWrapper
  ]
  ++ lib.optionals stdenvNoCC.hostPlatform.isLinux [ autoPatchelfHook ];
  strictDeps = true;

  dontUnpack = true;
  dontStrip = true;
  dontFixup = !stdenvNoCC.hostPlatform.isLinux;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/libexec/amp-cli
    gunzip -c $src > $out/libexec/amp-cli/amp
    chmod +x $out/libexec/amp-cli/amp

    makeWrapper $out/libexec/amp-cli/amp $out/bin/amp \
      --set AMP_SKIP_UPDATE_CHECK 1 \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}

    runHook postInstall
  '';

  # The upstream Bun binary links the system ICU by absolute path and carries
  # an ad-hoc signature that breaks once the binary is written by gunzip.
  postInstall = lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
    '${lib.getExe' cctools "${cctools.targetPrefix}install_name_tool"}' $out/libexec/amp-cli/amp \
      -change /usr/lib/libicucore.A.dylib '${lib.getLib darwin.ICU}/lib/libicucore.A.dylib'
    '${lib.getExe rcodesign}' sign --code-signature-flags linker-signed $out/libexec/amp-cli/amp
  '';

  doInstallCheck = stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform;
  nativeInstallCheckInputs = [
    writableTmpDirAsHomeHook
    versionCheckHook
  ];
  versionCheckProgram = "${placeholder "out"}/bin/amp";
  versionCheckProgramArg = "--version";
  versionCheckKeepEnvironment = [ "HOME" ];

  passthru = {
    sources = lib.mapAttrs (
      system': platform:
      fetchurl {
        url = "https://static.ampcode.com/cli/${finalAttrs.version}/amp-${platform}.gz";
        hash =
          {
            x86_64-linux = "sha256-cNnG0LDbqIU7tHZLPcwpngptN9gg6BMRcMOaevzpQEQ=";
            aarch64-linux = "sha256-lOMhnY0ap+d0mYzLHMabzQbL2Kj8x/jChV/8YJP4+8I=";
            x86_64-darwin = "sha256-/grrJlVBmQYU8X5udL9yWhooxkxPMQKVv6tX1zWP9QI=";
            aarch64-darwin = "sha256-ysxV28TG+Rvrzh9+RvcNQPg2x+FcgCo+aZORN5m/1B8=";
          }
          .${system'};
      }
    ) platforms;
    updateScript = ./scripts/update.sh;
  };

  meta = {
    description = "CLI for Amp, an agentic coding agent from Sourcegraph";
    homepage = "https://ampcode.com/";
    downloadPage = "https://ampcode.com/install";
    license = lib.licenses.unfree;
    mainProgram = "amp";
    platforms = builtins.attrNames platforms;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
