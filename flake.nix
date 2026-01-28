{
  description = "kubectl.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, crane, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default ];
        };

        rustToolchain = pkgs.rust-bin.stable.latest.default;
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        # Go static library
        kubectl-go = pkgs.buildGoModule {
          pname = "kubectl-go";
          version = "0.1.0";
          src = ./go;
          vendorHash = "sha256-lh5DAqr8o13q++5VnfJnVOcBpfKI6fSm+Qch15B/DRE=";
          buildPhase = ''
            runHook preBuild
            go build -trimpath -ldflags="-s -w" -buildmode=c-archive -o libkubectl_go.a
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            cp libkubectl_go.a libkubectl_go.h $out/
            runHook postInstall
          '';
        };

        # Source with only Rust files + Cargo
        rustSrc = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [
            ./Cargo.toml
            ./Cargo.lock
            ./kubectl-client
            ./kubectl-telemetry
          ];
        };

        # Common args for crane builds
        commonArgs = {
          pname = "kubectl-client";
          version = "0.1.0";
          src = rustSrc;
          strictDeps = true;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = with pkgs; [
            openssl
            luajit
          ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.libiconv
            pkgs.apple-sdk
          ];

          # Link Go library
          preBuild = ''
            mkdir -p go
            ln -sf ${kubectl-go}/libkubectl_go.a go/
            ln -sf ${kubectl-go}/libkubectl_go.h go/
          '';

          env = {
            OPENSSL_NO_VENDOR = "1";
          } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
            RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
          };
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        # Rust library
        kubectl-client = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
        });

        # Library extension for this platform
        libExt = if pkgs.stdenv.isDarwin then "dylib" else "so";

      in {
        packages = {
          inherit kubectl-go kubectl-client;

          kubectl-nvim = pkgs.vimUtils.buildVimPlugin {
            pname = "kubectl.nvim";
            version = "main";
            src = pkgs.lib.cleanSource ./.;
            preInstall = ''
              mkdir -p target/release
              ln -s ${kubectl-client}/lib/libkubectl_client.${libExt} target/release/
            '';
            doCheck = false;
          };

          default = self.packages.${system}.kubectl-nvim;
        };

        apps.build-plugin = flake-utils.lib.mkApp {
          drv = pkgs.writeShellScriptBin "build-plugin" ''
            mkdir -p target/release
            cp -f ${kubectl-client}/lib/libkubectl_client.${libExt} target/release/
            echo "Library copied to target/release/"
          '';
        };

        devShells.default = craneLib.devShell {
          inputsFrom = [ kubectl-client ];
          packages = with pkgs; [ go luaPackages.luacheck stylua ];
        };
      }
    );
}
