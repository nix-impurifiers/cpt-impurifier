# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
{
  unit = impurifier.unit;
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
