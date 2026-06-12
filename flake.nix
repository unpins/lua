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
      # the REPL — a trailing `-e` makes it print and exit 0. defaultApplet=lua
      # (in multicall.nix) routes the bare/renamed binary here.
      smoke = [ "-v" "-e" "os.exit(0)" ];
      smokePattern = "Lua 5\\.4";
      build = pkgs:
        let
          p = pkgs.pkgsStatic;
          # The REPL links readline -> ncurses(libtinfo), which bakes the
          # ncurses share/terminfo store path in. embedFallbackTerminfoOnly
          # (same helper nano/htop use) compiles a curated terminfo set into
          # libtinfo.a + --disable-database, so no dangling ref and the REPL
          # still line-edits without /usr/share/terminfo.
          ncursesFB = ulib.embedFallbackTerminfoOnly p.ncurses;
          readlineFB = p.readline.override { ncurses = ncursesFB; };
          base = neutralizeLuaRoot (p.lua5_4.override { readline = readlineFB; });
        in
        import ./multicall.nix { lib = pkgs.lib // ulib; } { inherit pkgs; lua = base; };
      windowsBuild = pkgs:
        let base = neutralizeLuaRoot (ulib.mingwStaticCross pkgs).lua5_4; in
        import ./multicall.nix { lib = pkgs.lib // ulib; } { inherit pkgs; lua = base; };
    };
}
