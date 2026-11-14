#!/bin/zsh
# Run all local package tests. Run from any folder.
set -euo pipefail
cd "${0:A:h}/.."
if [[ ! -f Packages/HandyKit/Package.swift ]]; then
  print -u2 "test.sh: missing required package: Packages/HandyKit"
  exit 1
fi
for pkg in Packages/*(N/); do
  if [[ ! -f "$pkg/Package.swift" ]]; then
    print -u2 "test.sh: missing Package.swift: $pkg"
    exit 1
  fi
  swift test --package-path "$pkg"
done
