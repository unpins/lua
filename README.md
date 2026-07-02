# lua

[Lua](https://www.lua.org/) — the lightweight embeddable scripting language. A single self-contained binary (`lua` + `luac`), built natively for Linux, macOS, and Windows.

[![CI](https://github.com/unpins/lua/actions/workflows/lua.yml/badge.svg)](https://github.com/unpins/lua/actions)
![Linux](https://img.shields.io/badge/Linux-✓-success?logo=linux&logoColor=white)
![macOS](https://img.shields.io/badge/macOS-✓-success?logo=apple&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-✓-success?logo=windows&logoColor=white)

Part of the [unpins](https://unpins.org) catalog; install it with [`unpin`](https://github.com/unpins/unpin): `unpin install lua`.

## Usage

Run the `lua` program with [unpin](https://github.com/unpins/unpin):

```bash
unpin lua script.lua          # run a script
unpin lua -e 'print(1+1)'     # run a one-liner
unpin lua -v                  # version banner
```

To install it onto your PATH:

```bash
unpin install lua
```

Installing also creates the `luac` command (the bytecode compiler) alongside
`lua`:

```bash
luac -o out.luc script.lua    # compile to bytecode
```

## Man pages

Upstream ships `lua.1` and `luac.1`; both are embedded, so `unpin man lua` and
`unpin man lua luac` work offline.

## Build locally

```bash
nix build github:unpins/lua
./result/bin/lua -v
```

Or run directly:

```bash
nix run github:unpins/lua -- -e 'print("hi")'
```

The first invocation will offer to add the [unpins.cachix.org](https://unpins.cachix.org) substituter so most pulls come pre-built.

## Manual download

The [Releases](https://github.com/unpins/lua/releases) page has standalone binaries for manual download.

## Build notes

- **Single multicall binary.** `lua` (interpreter) and `luac` (bytecode
  compiler) are folded into one binary at `$out/bin/lua`, with `luac` an
  `argv[0]`-dispatch alias. The bare/canonical `lua` runs the interpreter
  (`defaultApplet`); `lua --unpin-program=luac …` reaches the compiler from the
  bare binary. Both share the whole Lua library, so — unlike the Info-ZIP/bzip2
  recipe — we don't prefix-rename every global; `nm` confirms `lua.c`/`luac.c`
  each define only `main`, so we compile the library objects once, rename just
  `main` → `lua_main`/`luac_main`, and link with the shared dispatcher. See
  `multicall.nix`.
- **No VFS / embedded data needed.** Lua's standard library is entirely C —
  there is no tree of `.lua` files to ship — so the interpreter is naturally
  self-contained (contrast `unpins/perl` `@INC` and `unpins/python` stdlib).
  `require` of external *Lua* modules still works; `require` of external *C*
  modules (`package.loadlib`/`dlopen`) does not, as expected for one static
  binary.
- **REPL line editing.** Linux/macOS link readline; a curated terminfo set is
  compiled into the binary (ncurses `--disable-database` + fallback), so the
  REPL edits correctly even on a host with no `/usr/share/terminfo` and the
  binary keeps no `/nix/store` reference. Windows has no readline (upstream
  doesn't support it there).
- **Module search paths neutralized.** nixpkgs bakes the build's store prefix
  into `package.path`/`package.cpath`; we reset `LUA_ROOT` to the upstream
  `/usr/local/` default so the binary carries no store path (the paths are
  inert in a single binary anyway). Windows uses Lua's `!`-relative defaults.
- **Static linking, per target.** Upstream's `mingw` Makefile target builds a
  DLL and its macOS path links a dylib; both are replaced with a static link of
  `liblua.a` so every target is a single self-contained binary
  (`otool -L`/imports show only system libraries).
- **Tests.** Lua's official tarball ships no `make check`; the conformance suite
  is a separate download (`lua-5.4.x-tests.tar.gz`), so there is nothing to run
  at build time. `lua -v` is the smoke floor.
