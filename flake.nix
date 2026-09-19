{
  description = "Environment with grub-mkrescue";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux"; 
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.grub2
          pkgs.xorriso
          pkgs.mtools
        ];

        shellHook = ''
          echo "Environment ready with grub-mkrescue"
        '';
      };
    };
}
