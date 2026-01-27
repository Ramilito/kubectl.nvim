{
  description = "kubectl.nvim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Go static library (mirrors: make build_go)
        kubectl-go = pkgs.buildGoModule {
          pname = "kubectl-go";
          version = "0.1.0";
          src = ./.;
          modRoot = "go";
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

        # Rust library (mirrors: make build)
        kubectl-client = pkgs.rustPlatform.buildRustPackage {
          pname = "kubectl-client";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;

          nativeBuildInputs = with pkgs; [ pkg-config ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
            pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
          ];

          preBuild = ''
            mkdir -p go
            ln -sf ${kubectl-go}/libkubectl_go.a go/
            ln -sf ${kubectl-go}/libkubectl_go.h go/
          '';

          RUSTFLAGS = pkgs.lib.optionalString pkgs.stdenv.isDarwin
            "-C link-arg=-undefined -C link-arg=dynamic_lookup";
        };
      in
      {
        packages = {
          inherit kubectl-go kubectl-client;

          default = pkgs.vimUtils.buildVimPlugin {
            pname = "kubectl.nvim";
            version = "main";
            src = pkgs.lib.cleanSource ./.;
            postPatch = ''
              mkdir -p target/release
              cp ${kubectl-client}/lib/libkubectl_client.* target/release/
            '';
            doCheck = false;
          };
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ go cargo rustc luacheck stylua ];
        };
      }
    );
}
