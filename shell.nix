{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/nixos-24.05.tar.gz") {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.zig
    pkgs.zls
    pkgs.clang
    pkgs.pkg-config
  ];
}