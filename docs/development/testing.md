# Testing

QEMU runs pinned upstream CPT with pax, rsync and real cpt-build. Preinstalled Nix/Python have native inventory entries. Network is disabled and the application closure is initially absent. Test native solving/rejection, archive ordering, source recipes, offline transport, same-size service updates, configuration, accounts/lifecycle/admin intent, unrelated drivers, foreign roots, removal and rooted GC. Outer boot and PID1 are NixOS.

Native-payload coverage installs, executes, upgrades and removes a static
producer-prepared payload in a target root without `/nix`. The bundled variant
repeats the full original lifecycle suite with actual static Nix and an
incompatible external candidate.
CPT deliberately retains `/etc` configurations after package removal.
