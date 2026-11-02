# cpt-impurifier

Native Carbs Packaging Tools archives and recipes backed by atomic Nix profiles.
Original project code is MIT licensed; upstream CPT retains its MIT notices.
This targets CPT's own database and hook contracts, independently of KISS.

```nix
let impurifier = inputs.cpt-impurifier.lib.cpt-impurifier { inherit pkgs; };
in impurifier.makeOfflinePackage { pkg = pkgs.hello; }
```

Install native Nix/Python providers first, then
`cpt-install /path/to/runtime-output/*.tar.gz`, followed by your application
archives. `makeRuntimePackage` accepts `nixDependency` and `pythonDependency`
names. Nix installation itself remains deferred. CPT orders standalone archives
without reading their embedded dependency graph: install providers before
consumers. Native named-package repositories can resolve their declared graph.

`makeNetPackage`, `makeOfflinePackage` and `makePackage` accept shared application
arguments plus `release` and `hostDependencies`. The same native name has flavor
release suffixes. CPT checks dependency names; the pre-install hook also checks
the minimum source-derived runtime version. These are native package metadata,
not SemVer releases. `buildPackage` emits a raw payload archive.

The runtime owns `/etc/cpt/hooks/impurifier`. CPT sources this hook in its shell;
it validates before installation and reconciles at end-install/end-remove.
Existing user hooks remain separate. Native file changes can precede activation
failure; repair the transaction and run `/usr/sbin/nix-profile-engine reconcile`.
The old profile remains published on engine failure. This does not roll back
native files. Foreign CPT_ROOT hooks reject host activation; native foreign
roots without this hook stage files without activating the host.

Configuration follows CPT's native checksums and preservation rules. Shared
accounts, directories, lifecycle, explicit hardware bindings and chosen systemd,
OpenRC or runit protocols are supported. Consumers provide native dependency
names and choose an existing supervisor. The end-of-session hook also refreshes
host-library bindings after unrelated driver package changes.

CPT uses rsync's size/mtime quick check when installing files. This emitter uses
content-derived file timestamps so equal-length changed descriptors/services
are installed. The VM explicitly covers that regression.

`makeRepository { packages = [ artifact ]; }` emits native build recipes that
repack already-built Nix artifacts. Keep the repository in the Nix store and
root it while building; the recipe retains its artifact references. Set
`CPT_PATH` to that output and use `cpt-build name`. Select one flavor/version per
name. Application compilation remains in Nix; the native builder owns package
construction. Recipes are not portable copies independent of their Nix store.

`nix flake check -L` runs actual pinned upstream CPT in QEMU with native pax,
rsync and source-recipe builds. Tests cover dependency rejection, net failure
and offline recovery, configuration, batch activation, service/account lifecycle
and admin intent, driver changes, foreign roots, native removal and GC. The outer
OS/init is NixOS with preinstalled Nix; a full Carbs Linux boot is separate work.
