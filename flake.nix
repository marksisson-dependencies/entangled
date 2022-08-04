# to display copmlete list of available compilers
# nix search nixpkgs#haskell.compiler ghc -e 'integer|native|HEAD|Binary|js'
{
  description = "bi-directional tangle daemon for literate programming";

  inputs.gitignore.url = "github:hercules-ci/gitignore.nix";
  inputs.gitignore.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, flake-utils, gitignore }:
    let
      packageName = "entangled";

      packageWithRequisitePackages = packages:
        packages.haskell.lib.justStaticExecutables
        (packages.haskell.lib.compose.overrideCabal
          (drv: { src = gitignore.lib.gitignoreSource (drv.src + "/.."); })
          (packages.haskellPackages.callPackage ./nix/${packageName}.nix { }));

      containerImageWithRequisitePackages = packages:
        let
          package = if packages.stdenv.buildPlatform.isLinux then
            packages.pkgsStatic.haskellPackages.${packageName}
          else
            packages.pkgsCross.gnu64.pkgsStatic.haskellPackages.${packageName};

          data = packages.runCommand "data" { } ''
            mkdir -p $out/lib/${packageName}/data
            shopt -s globstar
            cp -rp ${package.data}/**/data/* $out/lib/${packageName}/data
          '';
        in packages.dockerTools.buildLayeredImage {
          name = "${packageName}";
          tag = "latest";
          contents = [ package data ];
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
    in let
      overlay = final: prev: {
        haskellPackages = let
          # https://github.com/NixOS/nixpkgs/issues/49748
          # see nixpkgs/pkgs/development/haskell-modules/lib/compose.nix (generateOptparseApplicativeCompletion)
          dhall = if prev.stdenv.hostPlatform != prev.stdenv.buildPlatform then
            prev.haskellPackages.dhall.overrideAttrs
            (previousAttrs: { postInstall = ""; })
          else
            prev.haskellPackages.dhall;
        in prev.haskellPackages.override (old: {
          overrides = let emptyOverlay = final: prev: { };
          in nixpkgs.lib.composeExtensions (old.overrides or emptyOverlay)
          (finalHaskellPackages: prevHaskellPackages: {
            inherit dhall;
            ${packageName} = packageWithRequisitePackages final;
          });
        });

        "${packageName}-container-image" =
          containerImageWithRequisitePackages final;
      };
    in {
      overlays.default = overlay;
      overlays.${packageName} = overlay;
    } // flake-utils.lib.eachDefaultSystem (localSystem:
      let
        pkgs = nixpkgs.legacyPackages.${localSystem};
        package = packageWithRequisitePackages pkgs;
        app = flake-utils.lib.mkApp { drv = package; };
      in {
        #
        # e.g., to cross-compile
        # nix build .#pkgsCross.gnu64.haskellPackages.entangled
        # nix build .#pkgsCross.aarch64-darwin.haskellPackages.entangled
        #
        legacyPackages = import nixpkgs {
          config = { };
          inherit localSystem;
          overlays = [ self.overlays.default ];
        };

        packages.default = package;
        packages.${packageName} = package;
        packages."${packageName}-container-image" =
          containerImageWithRequisitePackages
          self.legacyPackages.${localSystem};

        apps.default = app;
        apps.${packageName} = app;

        devShells.default = pkgs.mkShell {
          packages = with pkgs.haskellPackages;
            [
              cabal2nix
              cabal-install
              dhall
              ghcid
              haskell-language-server
              hlint
              hoogle
            ] ++ [
              pkgs.dive # for inspecting container image
              pkgs.zlib
            ];
          inputsFrom = [ package ];
        };

        checks.default = pkgs.runCommand "check-cabal2nix-sync" {
          nativeBuildInputs = [ pkgs.cabal2nix ];
        } ''
          if [[ -f ${self}/${packageName}.cabal && -f ${self}/nix/${packageName}.nix ]]; then
            cp ${self}/${packageName}.cabal .
            if ! (cabal2nix . | diff ${self}/nix/${packageName}.nix -); then
              echo "error: ${packageName}.nix is out of sync!"
              echo "  To sync, execute ===> cabal2nix . > ./nix/${packageName}.nix"
              exit 1
            fi
          fi
          touch $out
        '';

        formatter = pkgs.nixfmt;
      });
}
