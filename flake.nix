{
  description = "Simple Layout Library in Zig";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
  let 
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs;[
        clang-tools
        zig
        zls
        fish
        sdl3
        sdl3-ttf
      ];

      shellHook = "exec fish";
    };
  };
}
