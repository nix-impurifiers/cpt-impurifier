# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "carbs-packaging-tools";
  version = "unstable-ad7c8a9";
  src = pkgs.fetchurl {
    url = "https://github.com/carbslinux/cpt/archive/ad7c8a93b558d5cec731acb95183208c120e3539.tar.gz";
    hash = "sha256-B5bN1YBAcKC3ADf3BAUAe/FVhEzPCOiRPxDDtWunCco=";
  };
  nativeBuildInputs = [
    pkgs.pax
    pkgs.rsync
    pkgs.b3sum
    pkgs.curl
  ];
  postInstall = "install -Dm644 LICENSE $out/share/licenses/cpt/LICENSE";
  configureFlags = [
    "--sysconfdir=/etc"
    "--without-docs"
  ];
}
