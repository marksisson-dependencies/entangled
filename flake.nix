{
  description = "bi-directional tangle daemon for literate programming";

  inputs.gitignore.url = "github:hercules-ci/gitignore.nix";
  inputs.gitignore.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, flake-utils, gitignore }:
    let
      packageName = "entangled";
      packageWithRequisitePackages = packages:
        packages.callPackage ./${packageName}.nix { };
    in let
      overlay = final: prev: {
        ${packageName} = final.haskell.lib.doJailbreak
          ((final.haskell.lib.overrideCabal
            (packageWithRequisitePackages final.haskellPackages)
            (oldAttrs: { src = gitignore.lib.gitignoreSource oldAttrs.src; })));

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

    in {
      overlays.default = overlay;
      overlays.${packageName} = overlay;
    } // flake-utils.lib.eachDefaultSystem (localSystem:
      let
        package = packageWithRequisitePackages
          nixpkgs.legacyPackages.${localSystem}.haskellPackages;
        app = flake-utils.lib.mkApp { drv = package; };
      in {
        #
        # e.g., to cross-compile
        # nix build .#pkgsCross.gnu64.entangled
        # nix build .#pkgsCross.gnu64.pkgsStatic.entangled
        # nix build .#pkgsCross.aarch64-darwin.pkgsStatic.entangled
        #
        legacyPackages = import nixpkgs {
          config = { };
          inherit localSystem;
          overlays = [ self.overlays.default ];
        };

        packages.default = package;
        packages.${packageName} = package;
        packages."${packageName}-docker-image" =
          overlay."${packageName}-docker-image";

        apps.default = app;
        apps.${packageName} = app;

        devShells.default = nixpkgs.legacyPackages.${localSystem}.mkShell {
          packages = with nixpkgs.legacyPackages.${localSystem}; [
            cabal2nix
            cabal-install
            ghcid
            haskellPackages.haskell-language-server
          ];
          inputsFrom = [ package ];
        };

        checks.default = nixpkgs.legacyPackages.${localSystem}.runCommand
          "check-cabal2nix-sync" {
            nativeBuildInputs =
              [ nixpkgs.legacyPackages.${localSystem}.cabal2nix ];
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

        formatter = nixpkgs.legacyPackages.${localSystem}.nixfmt;
      });
}
