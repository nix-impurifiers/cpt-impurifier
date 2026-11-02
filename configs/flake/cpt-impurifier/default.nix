# SPDX-License-Identifier: MIT
{ ... }:
{ lib, inputs, ... }:
{
  flake.lib = lib.mkForce {
    cpt-impurifier =
      { pkgs }:
      import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
      };
  };
  perSystem =
    { pkgs, ... }:
    let
      impurifier = import ../../../nix {
        inherit pkgs;
        coreSrc = inputs.impurifier;
      };
    in
    {
      packages = {
        default = impurifier.engine;
        engine = impurifier.engine;
        runtime-package = impurifier.runtimePackage;
        hello-net = impurifier.makeNetPackage { pkg = pkgs.hello; };
        hello-offline = impurifier.makeOfflinePackage { pkg = pkgs.hello; };
      };
      formatter = pkgs.nixfmt-tree;
      checks = import ../../../tests {
        inherit pkgs impurifier;
        coreSrc = inputs.impurifier;
      };
    };
}
