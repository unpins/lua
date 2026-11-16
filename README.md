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

- **`luac` in the same file.** A bare `lua` runs the interpreter;
  `lua --unpin-program=luac …` runs the bytecode compiler, and installing
  creates a `luac` command.
- **REPL line editing.** Linux and macOS link readline into the binary
  (upstream's Linux build loads `libreadline.so` at run time instead). A set of
  common terminals is built in as a fallback; the system's terminfo, when
  present, takes precedence. Windows has no line editing (upstream doesn't
  support it there).
- **Module search paths.** Lua modules are looked up under `/usr/local`
  (`share/lua/5.5`, `lib/lua/5.5`) and in the current directory; on Windows,
  in the executable's folder (and its `lua` subfolder) and the current
  directory.
- **Static liblua.** Upstream builds liblua as a DLL on Windows (mingw) and a
  dylib on macOS; here `liblua.a` is linked in on every target.
- **Not included:** loading compiled C modules (`require` of a `.so` or
  `.dll`; they link against a shared liblua this binary doesn't have).
- **Tests:** the Lua test suite is not run: it is a separate download, not
  part of the source release, and `make test` only runs `lua -v`.
