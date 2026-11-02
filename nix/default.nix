# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
    namespace = "cpt-impurifier";
  };
  hook = pkgs.writeText "cpt-impurifier-hook" ''
    # SPDX-License-Identifier: MIT
    # CPT sources hook files in its own shell; do not change its shell options.
    case "$TYPE" in
      pre-install|end-install|end-remove)
        case "''${CPT_ROOT:-}" in
          ""|/) ;;
          *) die 'cpt-impurifier: foreign CPT_ROOT cannot activate the host' ;;
        esac
        ;;
    esac
    case "$TYPE" in
      pre-install)
        impurifier_required="$DEST/var/db/cpt/installed/$PKG/impurifier-runtime-version"
        if [ -f "$impurifier_required" ]; then
          /usr/bin/python3 -c '
    from pathlib import Path
    import sys
    version = lambda path: tuple(map(int, Path(path).read_text().strip().split(".")))
    if version("/usr/share/cpt-impurifier/runtime-version") < version(sys.argv[1]):
        sys.exit("cpt-impurifier: upgrade the runtime first")
    ' "$impurifier_required" || die 'cpt-impurifier runtime requirement failed'
        fi
        ;;
      end-install|end-remove)
        /usr/sbin/nix-profile-engine reconcile || die 'cpt-impurifier activation failed; repair and reconcile'
        ;;
    esac
  '';
  buildPackage =
    {
      name,
      version,
      payload,
      release ? "1",
      dependencies ? [ ],
      requiredRuntime ? null,
      postInstall ? "",
    }:
    assert lib.assertMsg (
      builtins.match "[a-z0-9][a-z0-9+_.-]*" name != null
      && lib.all (v: builtins.match "[A-Za-z0-9_.+]+" v != null) [
        version
        release
      ]
    ) "invalid CPT package metadata";
    assert lib.assertMsg (lib.all (
      v: builtins.match "[a-z0-9][a-z0-9+_.-]*" v != null
    ) dependencies) "invalid CPT dependency name";
    pkgs.runCommand "${name}-${version}-${release}-cpt-package"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
          pkgs.python3
          pkgs.b3sum
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru.nativeName = name;
        passthru.filename = "${name}#${version}-${release}.tar.gz";
      }
      ''
        mkdir -p root/var/db/cpt/installed/${name} $out
        cp -r ${payload}/. root/
        chmod -R u+w root
        database=root/var/db/cpt/installed/${name}
        printf '%s %s\n' ${lib.escapeShellArg version} ${lib.escapeShellArg release} > "$database/version"
        printf '%s' ${
          lib.escapeShellArg (lib.concatMapStringsSep "" (v: "${v}\n") dependencies)
        } > "$database/depends"
        ${lib.optionalString (
          requiredRuntime != null
        ) "echo ${lib.escapeShellArg requiredRuntime} > \"$database/impurifier-runtime-version\""}
        ${lib.optionalString (postInstall != "") ''
          cat > "$database/post-install" <<'SCRIPT'
          #!/bin/sh
          set -eu
          ${postInstall}
          SCRIPT
          chmod 755 "$database/post-install"
        ''}
        touch "$database/manifest"
        if [ -d root/etc ]; then touch "$database/etcsums"; fi
        python3 - <<'PYTHON'
        from pathlib import Path
        root = Path('root')
        entries = ['/' + str(p.relative_to(root)) + ('/' if p.is_dir() and not p.is_symlink() else "") for p in root.rglob('*')]
        (root / 'var/db/cpt/installed/${name}/manifest').write_text('\n'.join(sorted(entries, reverse=True)) + '\n')
        PYTHON
        if [ -d root/etc ]; then
          (cd root; find etc -type f -exec sha256sum {} +) > "$database/etcsums"
        fi
        # CPT installs through rsync's size/mtime quick check. A fixed mtime
        # silently loses equal-length descriptor and service updates.
        python3 - <<'PYTHON'
        import hashlib, os
        from pathlib import Path
        root = Path("root")
        for path in [root, *root.rglob("*")]:
            stamp = 1
            if path.is_file() and not path.is_symlink():
                stamp = int.from_bytes(hashlib.sha256(path.read_bytes()).digest()[:4], "big")
            os.utime(path, (stamp, stamp), follow_symlinks=False)
        PYTHON
        tar -C root --format=posix --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime --sort=name --owner=0 --group=0 --numeric-owner -czf $out/${name}#${version}-${release}.tar.gz .
      '';
  makePackage =
    args@{
      pkg,
      release ? "1",
      hostDependencies ? [ ],
      ...
    }:
    let
      payload = core.makePayload (
        builtins.removeAttrs args [
          "release"
          "hostDependencies"
        ]
      );
    in
    buildPackage {
      name = payload.name;
      inherit (payload) version;
      inherit payload;
      release = "${release}_${if payload.offline then "offline" else "net"}";
      dependencies = [ "cpt-impurifier" ] ++ hostDependencies;
      requiredRuntime = core.runtimeVersion;
    };
  makeRuntimePackage =
    {
      nixDependency ? "nix",
      pythonDependency ? "python3",
    }:
    buildPackage {
      name = "cpt-impurifier";
      version = core.runtimeVersion;
      dependencies = [
        nixDependency
        pythonDependency
      ];
      payload = pkgs.runCommand "cpt-impurifier-runtime-payload" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { }}/. $out/
        chmod -R u+w $out
        install -Dm644 ${hook} $out/etc/cpt/hooks/impurifier
        mkdir -p $out/usr/share/cpt-impurifier
        echo ${core.runtimeVersion} > $out/usr/share/cpt-impurifier/runtime-version
      '';
      postInstall = ''
        case "''${CPT_ROOT:-}" in
          ""|/) /usr/sbin/nix-profile-engine reconcile ;;
          *) echo 'cpt-impurifier: foreign CPT_ROOT cannot activate the host' >&2; exit 1 ;;
        esac
      '';
    };
  makeRepository =
    { packages }:
    assert lib.assertMsg (
      lib.length (lib.unique (map (p: p.nativeName) packages)) == lib.length packages
    ) "choose one version/flavor per native repository name";
    pkgs.runCommand "cpt-impurifier-repository"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.gzip
        ];
      }
      ''
        mkdir -p $out
        ${lib.concatMapStringsSep "\n" (package: ''
          mkdir -p $out/${package.nativeName}
          for field in version depends; do
            tar -xOzf ${package}/${lib.escapeShellArg package.filename} ./var/db/cpt/installed/${package.nativeName}/$field > $out/${package.nativeName}/$field
          done
          cat > $out/${package.nativeName}/build <<'SCRIPT'
          #!/bin/sh
          # SPDX-License-Identifier: MIT
          set -eu
          tar -xzf ${package}/${lib.escapeShellArg package.filename} -C "$1"
          SCRIPT
          chmod 755 $out/${package.nativeName}/build
        '') packages}
      '';

in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit
    buildPackage
    makePackage
    makeRuntimePackage
    makeRepository
    ;
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackage (args // { offline = false; });
  makeOfflinePackage = args: makePackage (args // { offline = true; });
}
