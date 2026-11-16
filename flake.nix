{
  description = "Lua 5.5 (lua + luac) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # lua + luac folded into one multicall binary at $out/bin/lua, with `luac`
  # as an argv[0]-dispatch UNPIN_META alias.
  #
  # Lua's stdlib is entirely C — there is no tree of `.lua` files to embed — so
  # this needs none of the VFS machinery perl (@INC) and python (stdlib zip)
  # require; pkgsStatic already yields a self-contained interpreter. The
  # LUA_ROOT store-path leak is fixed below; terminfo comes from nix-lib.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "lua";
      # `lua --version` isn't a flag; `lua -v` prints the banner then drops into
      # the REPL — a trailing `-e` makes it print and exit 0.
      smoke = [ "-v" "-e" "os.exit(0)" ];
      smokePattern = "Lua 5\\.5";

      # The engine compiles lua + luac to bitcode and folds them into one `lua`
      # binary on every target. `lua` is itself a program, so a bare invocation
      # runs the interpreter (pkgsAttr=lua5_5, name ≠ attr).
      pkgsAttr = "lua5_5";
      engine = "unpin-llvm";
      multicall = {
        windows = true;
        programs = [ { name = "lua"; } { name = "luac"; } ];
      };
      build = pkgs:
        let
          p = pkgs.pkgsStatic;
          # The REPL links readline -> ncurses(libtinfo). The curated
          # fallback-terminfo + FHS default-dir pin (so the REPL line-edits
          # without a host /usr/share/terminfo and keeps no /nix/store ref, DB-on
          # → one shared ncurses .a in the mega) is baked centrally into every
          # engine ncurses by native-overlay/ncurses.nix, so p.ncurses already
          # carries it.
          base = p.lua5_5;
        in
        # Linux and darwin.
        base.overrideAttrs (old: {
          # Keep luaconf.h's LUA_ROOT "/usr/local/". In a static build nixpkgs'
          # postPatch is only the sed that points it at $out, a /nix/store path
          # baked into the module search defaults.
          postPatch = "";
          # Off, and measured: lua's `make test` is one line — `./lua -v` —
          # and the real suite (lua-tests) is a separate tarball upstream does
          # not ship with the source. Our smoke already runs `lua -v`, so
          # turning this on would duplicate the floor and read as a suite.
          doCheck = false;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          # Lua 5.5's linux recipe dlopen()s libreadline.so at run time, which a
          # static binary cannot do. LUA_USE_READLINE links it in instead (what
          # 5.4's linux-readline did); CFLAGS from nixpkgs drops MYCFLAGS.
          env = (old.env or { }) // { NIX_CFLAGS_COMPILE = "-DLUA_USE_READLINE"; };
          postConfigure = (if old.postConfigure == null then "" else old.postConfigure) + ''
            makeFlagsArray+=("MYLIBS=-lreadline -lncurses")
          '';
        } // pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          # darwin liblua-as-static (self-fold needs a captured `.a`):
          # nixpkgs' 5.5.darwin.patch rebuilds liblua as a `.dylib` and links the
          # interpreter against it (`-L. -llua.<ver>`), so no `liblua.a` is ever
          # produced. The engine self-fold only captures static `.a` archives to
          # fold into the bitcode module, so a dylib liblua leaves every `lua_*`
          # symbol undefined at the mega link. Drop that darwin patch so lua builds
          # the stock static `liblua.a` (exactly as on Linux) and the interpreter
          # links it positionally — the capture shim then folds it in.
          patches = builtins.filter
            (p: !(pkgs.lib.hasInfix "darwin.patch" (toString p)))
            (old.patches or [ ]);
          # configurePhase still hard-codes installFlagsArray TO_LIB to the dylib
          # name on darwin; rewrite it to the static archive we now build so
          # `make install` copies liblua.a rather than a nonexistent dylib.
          postConfigure = (if old.postConfigure == null then "" else old.postConfigure) + ''
            for i in "''${!installFlagsArray[@]}"; do
              case "''${installFlagsArray[$i]}" in
                TO_LIB=*) installFlagsArray[$i]="TO_LIB=liblua.a" ;;
              esac
            done
          '';
        });
      windowsBuild = pkgs:
        (ulib.mingwStaticCross pkgs).lua5_5.overrideAttrs (old: {
          # No readline on Windows (luaconf skips the REPL line editing there),
          # and nothing provides the `-lncurses` nixpkgs pins in MYLIBS.
          buildInputs = [ ];
          # PLAT=mingw is Lua's DLL recipe: it relinks liblua as lua55.dll
          # (`AR=$(CC) -shared -o`, `RANLIB=strip --strip-unneeded`) and links
          # lua.exe/luac.exe AGAINST that DLL. The link capture only records
          # objects and archives, so a DLL-linked program would yield a module
          # with every lua_* undefined. `generic` (empty SYSCFLAGS/SYSLIBS)
          # builds the same static liblua.a every other target folds — luaconf.h
          # auto-detects _WIN32 for LoadLibrary, so no Windows define is needed.
          makeFlags = (builtins.filter
            (f: !(pkgs.lib.hasPrefix "PLAT=" f) && !(pkgs.lib.hasPrefix "MYLIBS=" f))
            (old.makeFlags or [ ])) ++ [ "PLAT=generic" "MYLIBS=" ];
          # A mingw driver writes `lua.exe` for `-o lua`; nixpkgs' TO_BIN lists
          # the bare names, so give `make install` something to find either way.
          postBuild = ''
            for p in lua luac; do
              [ -e "src/$p" ] || cp "src/$p.exe" "src/$p"
            done
          '';
        });
    };
}
