# Changelog

## [Unreleased]

## [5.4.7-1] - 2026-09-26

### Added

- First release of Lua 5.4.7 as a single self-contained binary for Linux,
  macOS and Windows, on x86_64 and arm64 (plus i686, armv7l, ppc64le and
  riscv64 on Linux).

  One file holds both programs: `lua`, the interpreter, and `luac`, the
  bytecode compiler. `unpin install lua` puts both commands on your PATH.
  The REPL edits lines and recalls history even on a machine with no
  terminal database installed, and `lua.1` and `luac.1` are inside the
  binary, so `unpin man lua` and `unpin man lua luac` work offline.

  Loading Lua modules written in Lua works as usual; loading compiled C
  modules does not, which is the trade for one file that needs nothing
  installed alongside it.

  The Windows build uses the Universal C Runtime, which is part of Windows 10
  and later. On Windows 7 or 8.1 that runtime has to be installed first — it
  comes through Windows Update.
