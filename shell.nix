{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  buildInputs = [
    pkgs.zig
    pkgs.clang
    pkgs.zsh
    pkgs.pkg-config
  ];

  shellHook = ''
    export SHELL=${pkgs.zsh}/bin/zsh
    exec ${pkgs.zsh}/bin/zsh
  '';
}