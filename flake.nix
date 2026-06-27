{
  description = "Lua 5.4 (lua + luac) as a single self-contained binary";

  nixConfig = {
    extra-substituters = [ "https://unpins.cachix.org" ];
    extra-trusted-public-keys = [ "unpins.cachix.org-1:DDaShjbZ8VvcqxeTcAU3kV9vxZQBlyb7V/uLBHfTynI=" ];
  };

  inputs.unpins-lib.url = "github:unpins/nix-lib";

  # lua + luac folded into one multicall binary at $out/bin/lua, with `luac`
  # as an argv[0]-dispatch UNPIN_META alias. See ./multicall.nix.
  #
  # Lua's stdlib is entirely C — there is no tree of `.lua` files to embed — so
  # this needs none of the VFS machinery perl (@INC) and python (stdlib zip)
  # require; pkgsStatic already yields a self-contained interpreter. Two
  # store-path leaks are fixed below (LUA_ROOT module-search defaults, and the
  # readline→terminfo path); see ./multicall.nix for the static-link details.
  outputs = { self, unpins-lib }:
    let
      ulib = unpins-lib.lib;
      # Put LUA_ROOT back to the neutral upstream default: nixpkgs' postPatch
      # rewrites luaconf.h's `#define LUA_ROOT "/usr/local/"` to `"$out/"`, which
      # bakes a /nix/store path into the compiled-in module search paths — a
      # portability-gate ref and meaningless in a relocatable single binary.
      # (Windows is immune: luaconf uses `!`-relative defaults there.) lua5_4
      # sets postConfigure=null explicitly, so `or ""` won't catch it.
      neutralizeLuaRoot = drv: drv.overrideAttrs (old: {
        postConfigure = (if old.postConfigure == null then "" else old.postConfigure) + ''
          sed -i "s@$out/@/usr/local/@g" src/luaconf.h
        '';
      });
    in
    ulib.mkStandaloneFlake {
      inherit self;
      name = "lua";
      # `lua --version` isn't a flag; `lua -v` prints the banner then drops into
      # the REPL — a trailing `-e` makes it print and exit 0. defaultProgram=lua
      # routes the bare/renamed binary here.
      smoke = [ "-v" "-e" "os.exit(0)" ];
      smokePattern = "Lua 5\\.4";

      # Build via the unpin-llvm engine + emit a bitcode multicall module. On
      # Linux the engine compiles lua5_4 (lua + luac) to bitcode and the
      # standalone self-folds them into one `lua` binary; darwin (no engine)
      # keeps the objcopy fold in ./multicall.nix; windows via windowsBuild.
      # Pure C — no requires.cxx. The bare smoke (`lua -v …`) runs the
      # interpreter, so defaultProgram pins it (pkgsAttr=lua5_4, name ≠ attr).
      pkgsAttr = "lua5_4";
      engine = "unpin-llvm";
      multicall = {
        defaultProgram = "lua";
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
          readlineFB = p.readline.override { ncurses = p.ncurses; };
          base = neutralizeLuaRoot (p.lua5_4.override { readline = readlineFB; });
        in
        if pkgs.stdenv.hostPlatform.isLinux
        # engine path: apps → bitcode → selfFold. lua5_4 sets postBuild/
        # postInstall to literal `null` (not absent), which the bitcode hook's
        # `(old.postBuild or "")` can't coerce — neutralize to "" so the hook
        # can append its module-emit step.
        then base.overrideAttrs (old: {
          postBuild = if old.postBuild == null then "" else old.postBuild;
          postInstall = if old.postInstall == null then "" else old.postInstall;
        })
        else import ./multicall.nix { lib = pkgs.lib // ulib; } { inherit pkgs; lua = base; };
      windowsBuild = pkgs:
        let base = neutralizeLuaRoot (ulib.mingwStaticCross pkgs).lua5_4; in
        import ./multicall.nix { lib = pkgs.lib // ulib; } { inherit pkgs; lua = base; };
    };
}
