# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
}:
let
  cpt = import ./cpt.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "cpt-tool-${version}"
      {
        pname = "cpt-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/cpt-tool
        chmod +x $out/bin/cpt-tool
      '';
  app =
    offline: version:
    impurifier.makePackage {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/cpt-tool.conf" = pkgs.writeText "kiss-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "cpt-service-${version}"
      {
        pname = "cpt-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/cpt-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/cpt-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/cpt-service
      '';
  service =
    version:
    impurifier.makeOfflinePackage {
      pkg = daemon version;
      users.cpt-service = { };
      directories."/var/lib/cpt-service" = {
        owner = "cpt-service:cpt-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('cpt-service')"
          test -x /opt/nix/profile/bin/cpt-service
          echo initialized > /var/lib/cpt-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/cpt-service/migrated";
      };
      systemd.unit = pkgs.writeText "cpt-service.service" ''
        [Service]
        Type=exec
        User=cpt-service
        ExecStart=/opt/nix/profile/bin/cpt-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  hostDriver =
    version:
    impurifier.buildPackage {
      name = "impurifier-host-driver";
      inherit version;
      payload = hardwareFixture.driver version;

    };
  hardware = impurifier.makeOfflinePackage {
    hostDependencies = [ "impurifier-host-driver" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
in
pkgs.testers.runNixOSTest {
  name = "cpt-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      cpt
      pkgs.pax
      pkgs.rsync
      pkgs.b3sum
      pkgs.curl
      pkgs.gnutar
      pkgs.xz
      pkgs.gzip
      pkgs.bzip2
      pkgs.file
      pkgs.util-linux
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.which
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "d /bin 0755 root root -"
      "d /sbin 0755 root root -"
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /bin/du - - - - ${pkgs.coreutils}/bin/du"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${pkgs.nix}/bin/nix-store"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /tmp/packages")
    machine.succeed("cp ${app false "1"}/*.tar.gz ${app true "1"}/*.tar.gz ${app true "2"}/*.tar.gz ${service "1"}/*.tar.gz ${service "2"}/*.tar.gz ${hostDriver "1"}/*.tar.gz ${hostDriver "2"}/*.tar.gz ${hardware}/*.tar.gz /tmp/packages/")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    env = "env LOGNAME=root CPT_PROMPT=0 "
    install = env + "cpt-install "
    remove = env + "cpt-remove "
    machine.succeed(env + "cpt-install ${
      impurifier.buildPackage {
        name = "nix";
        version = "1";
        payload =
          pkgs.runCommand "nix-inventory" { }
            "mkdir -p $out/usr/share/cpt-fixture; touch $out/usr/share/cpt-fixture/nix";
      }
    }/*.tar.gz ${
      impurifier.buildPackage {
        name = "python3";
        version = "1";
        payload =
          pkgs.runCommand "python-inventory" { }
            "mkdir -p $out/usr/share/cpt-fixture; touch $out/usr/share/cpt-fixture/python";
      }
    }/*.tar.gz")
    machine.succeed(env + "cpt-install ${impurifier.runtimePackage}/*.tar.gz")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("native source recipe builds the prebuilt Nix transport"):
        machine.succeed(env + "CPT_PATH=${
          impurifier.makeRepository { packages = [ (app true "1") ]; }
        } CPT_STRIP=0 cpt-build cpt-tool")
        machine.succeed("cp /root/.cache/cpt/bin/cpt-tool#1-1_offline.tar.gz /tmp/packages/")
    with subtest("native script failure preserves the published profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "/tmp/packages/cpt-tool#1-*_net.tar.gz 2>&1")
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline upgrade and native configuration policy"):
        machine.succeed(install + "/tmp/packages/cpt-tool#1-*_offline.tar.gz")
        machine.succeed("test $(/opt/nix/profile/bin/cpt-tool) = 1")
        machine.succeed("echo local > /etc/cpt-tool.conf")
        machine.succeed(install + "/tmp/packages/cpt-tool#1-*_net.tar.gz")
        machine.succeed(install + "/tmp/packages/cpt-tool#2-*_offline.tar.gz")
        machine.succeed("grep local /etc/cpt-tool.conf; test $(/opt/nix/profile/bin/cpt-tool) = 2")
    with subtest("end-of-session reconciliation batches native installs"):
        output = machine.succeed(install + "${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-a";
            version = "1";
          }
        }/*.tar.gz ${
          impurifier.makeOfflinePackage {
            pkg = pkgs.hello;
            name = "batch-b";
            version = "1";
          }
        }/*.tar.gz")
        assert output.count("activated ") == 1, output
        machine.succeed("/opt/nix/profile/bin/hello | grep Hello")
        machine.succeed(remove + "batch-a batch-b")
    with subtest("native upgrades preserve service admin intent"):
        machine.succeed(install + "/tmp/packages/cpt-service#1-*.tar.gz")
        machine.wait_for_unit("cpt-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/cpt-service/version")
        machine.succeed("grep initialized /var/lib/cpt-service/initialized; test $(stat -c %U /var/lib/cpt-service) = cpt-service")
        output = machine.succeed(install + "/tmp/packages/cpt-service#2-*.tar.gz")
        assert output.count("activated ") == 1, output
        machine.wait_until_succeeds("grep '^2$' /var/lib/cpt-service/version")
        machine.succeed("grep '^2$' /var/lib/cpt-service/migrated")
        machine.succeed("systemctl disable --now cpt-service.service")
        machine.succeed(install + "/tmp/packages/cpt-service#1-*.tar.gz")
        machine.fail("systemctl is-active --quiet cpt-service.service")
        machine.fail("systemctl is-enabled --quiet cpt-service.service")
        machine.succeed("systemctl enable --now cpt-service.service")
        machine.succeed(remove + "cpt-service")
        machine.fail("systemctl is-active --quiet cpt-service.service")
    with subtest("end-of-session hook refreshes unrelated native driver changes"):
        code, output = machine.execute(install + "/tmp/packages/hardware-tool#*.tar.gz 2>&1")
        assert code != 0 and "impurifier-host-driver" in output, output
        machine.succeed(install + "/tmp/packages/impurifier-host-driver#1-*.tar.gz")
        machine.succeed(install + "/tmp/packages/hardware-tool#*.tar.gz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        machine.succeed(install + "/tmp/packages/impurifier-host-driver#2-*.tar.gz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed(remove + "hardware-tool impurifier-host-driver")
    with subtest("foreign ROOT scripts cannot activate the host"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(env + "CPT_ROOT=/tmp/foreign-root CPT_FORCE=1 CPT_HOOK=/etc/cpt/hooks/impurifier cpt-install /tmp/packages/cpt-tool#1-*_offline.tar.gz 2>&1")
        assert "foreign CPT_ROOT cannot activate the host" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("native removal and GC preserve edited configuration"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/cpt-tool) = 2")
        machine.succeed(remove + "cpt-tool")
        machine.fail("test -e /opt/nix/profile/bin/cpt-tool")
        machine.succeed("grep local /etc/cpt-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
