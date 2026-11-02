# Architecture

CPT database metadata uses /var/db/cpt/installed and name#version-release archives. Runtime hooks are sourced inside CPT, so they preserve shell options and use native die for failures. end-install/end-remove activation batches native changes. Content-derived mtimes avoid rsync skipping same-size updates. Native dependency names plus a pre-install runtime gate enforce requirements. Source recipes retain references to Nix artifacts and repack through real cpt-build.
