# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  client = import ./cpt.nix { inherit pkgs; };
  app =
    version:
    impurifier.makeNativePackage {
      name = "native-proof";
      inherit version;
      payload = pkgs.runCommand "native-proof-tree-${version}" { } ''
        mkdir -p $out/usr/bin $out/usr/share $out/etc
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/bin/busybox
        echo ${version} > $out/usr/share/native-proof-version
        echo ${version} > $out/etc/native-proof-config
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "cpt-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      client
      pkgs.pax
      pkgs.rsync
      pkgs.b3sum
    ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native/var/db/cpt/installed /tmp/cpt-cache")
    machine.succeed("env LOGNAME=root CPT_PROMPT=0 CPT_ROOT=/srv/native CPT_CACHE_DIR=/tmp/cpt-cache cpt-install ${app "1"}/*.tar.gz")
    machine.succeed("chroot /srv/native /usr/bin/busybox echo native-execution | grep native-execution")
    machine.succeed("test ! -e /srv/native/nix; grep '^1$' /srv/native/usr/share/native-proof-version")
    machine.succeed("env LOGNAME=root CPT_PROMPT=0 CPT_ROOT=/srv/native CPT_CACHE_DIR=/tmp/cpt-cache cpt-install ${app "2"}/*.tar.gz")
    machine.succeed("grep '^2$' /srv/native/usr/share/native-proof-version")
    machine.succeed("env LOGNAME=root CPT_PROMPT=0 CPT_ROOT=/srv/native CPT_CACHE_DIR=/tmp/cpt-cache cpt-remove native-proof")
    machine.succeed("test ! -e /srv/native/usr/bin/busybox; test ! -e /srv/native/usr/share/native-proof-version; test ! -e /srv/native/nix && test -f /srv/native/etc/native-proof-config")
  '';
}
