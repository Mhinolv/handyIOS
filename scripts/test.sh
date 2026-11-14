#!/bin/zsh
# Full test suite. Run from any folder. Keep it fast: use fakes for audio, ASR and system calls.
set -e
cd "${0:A:h}/.."
ran=0
for pkg in Packages/*(N/); do
  [[ -f $pkg/Package.swift ]] || continue
  swift test --package-path "$pkg"
  ran=1
done
(( ran )) || echo "test.sh: no Swift packages yet. Nothing to test."
