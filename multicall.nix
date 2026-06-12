# Lua ships two real programs — `lua` (the interpreter) and `luac` (the bytecode
# compiler) — built from the same source tree. We fold them into one multicall
# binary at $out/bin/lua, with `luac` as an argv[0]-dispatch UNPIN_META alias.
#
# Unlike the bzip2/zip family, the two mains SHARE the whole Lua library
# (lua.c and luac.c both pull in liblua's ~32 objects), so the
# "ld -r + rename every strong global" recipe would break: renaming
# `luaL_newstate` etc. in one program's partial would leave the other's
# references dangling. But that elaborate rename is unnecessary here — `nm`
# confirms lua.o and luac.o each define exactly ONE global (`main`). So we
# compile the library objects ONCE, compile the two mains, rename only
# `main` → `lua_main`/`luac_main`, and link everything (shared library objects
# linked a single time) with the canonical dispatcher.
#
# We recompile from $src (not the nixpkgs build's objects) for two reasons:
# the native build hides them and the Windows build compiles with
# `-DLUA_BUILD_AS_DLL` (dllexport — wrong for a static exe). Compiling here with
# per-OS SYSCFLAGS keeps every target's object set static-clean and uniform.
#
# `luaconf.h` already carries the neutralized LUA_ROOT (the consumer's
# postConfigure sed runs in configurePhase, before this buildPhase) so the
# recompiled objects inherit it — no /nix/store module-search leak.
#
# Shared by the native `build` (pkgsStatic ELF / Mach-O, readline REPL) and
# `windowsBuild` (mingw — no readline/dlopen, LoadLibrary via _WIN32).
{ lib }:
{ pkgs, lua }:
let
  hostPlat = lua.stdenv.hostPlatform;
  isWindows = hostPlat.isWindows or false;
  isDarwin = hostPlat.isDarwin or false;

  # Per-OS feature defines + link libs (catalog "ship every feature"):
  #  - Linux:  LUA_USE_LINUX  → POSIX + dlopen (loadlib) + readline REPL.
  #  - Darwin: LUA_USE_MACOSX → POSIX + readline REPL (dlopen via dyld, no -ldl).
  #  - Windows: none → luaconf auto-detects _WIN32 (LoadLibrary, no readline).
  syscflags =
    if isDarwin then "-DLUA_USE_MACOSX"
    else if isWindows then ""
    else "-DLUA_USE_LINUX";
  syslibs =
    if isWindows then "-lm"
    else if isDarwin then "-lreadline -lncurses -lm"
    else "-lreadline -lncurses -lm -ldl";

  multicall = lua.overrideAttrs (old: {
    pname = "lua-multi";
    outputs = [ "out" ];
    installFlags = [ ];

    # Replace the build entirely — the nixpkgs build would (linux) emit a dylib
    # lua links against, or (mingw) run Lua's DLL-oriented `mingw` target that
    # needs a bare `strip`. We drive our own static multicall link instead.
    buildPhase = ''
      runHook preBuild
      set -e
      mkdir -p multicall/obj

      # liblua object set (CORE_O + LIB_O from Lua 5.4's src/Makefile).
      LIBOBJS="lapi lcode lctype ldebug ldo ldump lfunc lgc llex lmem lobject \
        lopcodes lparser lstate lstring ltable ltm lundump lvm lzio lauxlib \
        lbaselib lcorolib ldblib liolib lmathlib loadlib loslib lstrlib \
        ltablib lutf8lib linit"
      CF="-O2 -Isrc ${syscflags}"

      for s in $LIBOBJS; do
        $CC $CF -c "src/$s.c" -o "multicall/obj/$s.o"
      done
      $CC $CF -c src/lua.c  -o multicall/obj/lua.o
      $CC $CF -c src/luac.c -o multicall/obj/luac.o

      # Mach-O leads C symbols with '_'; detect once from lua.o's `main`.
      if $NM --defined-only multicall/obj/lua.o 2>/dev/null \
           | awk '$3=="_main"{f=1} END{exit !f}'; then up=_; else up=""; fi

      # Only `main` clashes (nm-verified); rename it per interpreter.
      printf '%smain %slua_main\n'  "$up" "$up" > multicall/lua.redef
      printf '%smain %sluac_main\n' "$up" "$up" > multicall/luac.redef
      $OBJCOPY --redefine-syms=multicall/lua.redef  multicall/obj/lua.o
      $OBJCOPY --redefine-syms=multicall/luac.redef multicall/obj/luac.o

      # Dispatcher (shared canonical generator). `lua` is itself an applet and
      # the canonical name, so defaultApplet=lua makes a bare `lua script.lua`
      # run the interpreter; an argv[0] of `luac` runs the compiler.
      printf '%s\n' lua luac > multicall/apps.list
${lib.multicallDispatcherC { name = "lua"; defaultApplet = "lua"; }}
      $CC -O2 -c -o multicall/dispatcher.o multicall/dispatcher.c

      # Final link: cc-wrapper adds -static (pkgsStatic/mingw). Library objects
      # linked once; both *_main present. gc-sections on native only (on windows
      # `pkgs` is the x86_64-linux root, so its lld flags would be wrong here).
      $CC multicall/obj/*.o multicall/dispatcher.o \
        ${lib.optionalString (!isWindows) (lib.gcSectionsFlag pkgs)} \
        ${syslibs} \
        -o multicall/lua
      [ -f multicall/lua ] || mv multicall/lua.exe multicall/lua
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share/man/man1"
      install -m755 multicall/lua "$out/bin/lua"
      ln -s lua "$out/bin/luac"
      install -m644 doc/lua.1  "$out/share/man/man1/lua.1"
      install -m644 doc/luac.1 "$out/share/man/man1/luac.1"
      runHook postInstall
    '';

    # nixpkgs' postInstall/postBuild touch the dylib + lib/lua tree we don't ship.
    postBuild = "";
    postInstall = "";
  });

  aliased = lib.withAliases pkgs
    {
      primary = "lua";
      aliasesFromSymlinksIn = "bin";
    }
    multicall;
in
if isWindows
then aliased.overrideAttrs (o: {
  postFixup = (o.postFixup or "") + ''
    [ -f "$out/bin/lua" ] && mv "$out/bin/lua" "$out/bin/lua.exe"
  '';
})
else aliased
