{
  description = "bi-directional tangle daemon for literate programming";

  inputs.gitignore.url = "github:hercules-ci/gitignore.nix";
  inputs.gitignore.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, flake-utils, gitignore }:
    let packageName = "entangled";
    in {
      overlays.default = final: prev: {
        ${packageName} = final.haskell.lib.overrideCabal
          (final.haskell.lib.doJailbreak
            (final.haskellPackages.callPackage ./${packageName}.nix { }))
          (oldAttrs: { src = gitignore.lib.gitignoreSource oldAttrs.src; });

        "${packageName}-docker-image" = let
          minimal = final.runCommand "minimal" { } ''
            mkdir -p $out/bin
            cp -p ${
              final.pkgsCross.gnu64.pkgsStatic.${packageName}
            }/bin/${packageName} $out/bin/${packageName}

            # remove "false" run-time dependencies from binary
            # to minimize closure size
            ${final.removeReferencesTo}/bin/remove-references-to -t ${
              final.pkgsCross.gnu64.pkgsStatic.${packageName}
            } $out/bin/*
            ${final.removeReferencesTo}/bin/remove-references-to -t ${
              final.pkgsCross.gnu64.pkgsStatic.${packageName}.data
            } $out/bin/*

            mkdir -p $out/lib/${packageName}/data
            shopt -s globstar
            cp -rp ${
              final.pkgsCross.gnu64.pkgsStatic.${packageName}.data
            }/**/data/* $out/lib/${packageName}/data
          '';
        in final.dockerTools.buildLayeredImage {
          name = "${packageName}";
          tag = "latest";
          contents = [ minimal ];
          config = {
            Env = [ "entangled_datadir=/lib/entangled" ];
            WorkingDir = "/data";
            EntryPoint = [ "/bin/${packageName}" ];
          };
          created = "now";
          fakeRootCommands = ''
            mkdir -p .cache
            chmod a+rwx .cache
          '';
        };

        # https://github.com/NixOS/nixpkgs/issues/49748
        # see nixpkgs/pkgs/development/haskell-modules/lib/compose.nix (generateOptparseApplicativeCompletion)
        haskellPackages = let emptyOverlay = final: prev: { };
        in if prev.stdenv.hostPlatform != prev.stdenv.buildPlatform then
          prev.haskellPackages.override (old: {
            overrides =
              nixpkgs.lib.composeExtensions (old.overrides or emptyOverlay)
              (final: prev: {
                dhall = prev.dhall.overrideAttrs (old: { postInstall = ""; });
              });
          })
        else
          prev.haskellPackages;
      };

    } // flake-utils.lib.eachDefaultSystem (localSystem: rec {
      #
      # e.g., to cross-compile
      # nix build .#pkgsCross.gnu64.entangled
      # nix build .#pkgsCross.gnu64.pkgsStatic.entangled
      # nix build .#pkgsCross.aarch64-darwin.pkgsStatic.entangled
      #

      legacyPackages = import nixpkgs {
        inherit localSystem;
        overlays = [ self.overlays.default ];
        config.allowUnsupportedSystem = true;
      };

      packages.default = packages.${packageName};
      packages.${packageName} = legacyPackages.${packageName};
      packages."${packageName}-docker-image" = legacyPackages."${packageName}-docker-image";

      apps.default = apps.${packageName};
      apps.${packageName} =
        flake-utils.lib.mkApp { drv = packages.${packageName}; };

      devShells.default = legacyPackages.mkShell {
        packages = with legacyPackages; [
          cabal2nix
          cabal-install
          ghcid
          haskellPackages.haskell-language-server
        ];
        inputsFrom = builtins.attrValues packages;
      };

      checks.default = legacyPackages.runCommand "check-cabal2nix-sync" {
        nativeBuildInputs = [ legacyPackages.cabal2nix ];
      } ''
        if [[ -f ${self}/${packageName}.cabal && -f ${self}/${packageName}.nix ]]; then
          cp ${self}/${packageName}.cabal .
          if ! (cabal2nix . | diff ${self}/${packageName}.nix -); then
            echo "error: ${packageName}.nix is out of sync!  To sync, execute ===> cabal2nix . > ${packageName}.nix"
            exit 1
          fi
        fi
        touch $out
      '';

      formatter = legacyPackages.nixfmt;
    });
}
