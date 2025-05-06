{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.zig
    pkgs.zls
    pkgs.clang
    pkgs.pkg-config
  ];

  shellHook = ''
    export SHELL=/usr/bin/zsh
  '';
}