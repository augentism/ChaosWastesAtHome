# CwahBuffs

The original nine Chaos Wastes at Home blessings, maintained in the core
repository and distributed as a separate optional mod. Requires
ChaosWastesAtHome. Extract the release into the game's `mods/` directory and
add `CwahBuffs` to `mod_load_order.txt` alongside `ChaosWastesAtHome`.
Restart the game after changing installed or enabled packs.

## Development

Run these commands from the Darktide workspace root. The `--workspace` argument
points the shared tools at the parent of the nested mod folder; the installed
mod name and Lua paths remain `CwahBuffs`.

```sh
nix develop path:./nix --command python3 .agents/skills/darktide-lua-check/scripts/check_lua.py ChaosWastesAtHome/CwahBuffs
nix develop path:./nix --command python3 .agents/skills/darktide-mod/scripts/deploy_mod.py CwahBuffs --workspace ChaosWastesAtHome
nix develop path:./nix --command python3 .agents/skills/darktide-mod/scripts/release_mod.py CwahBuffs --workspace ChaosWastesAtHome
nix develop path:./nix --command python3 ChaosWastesAtHome/tests/run_tests.py --offline
```

Release archives live in `CwahBuffs/releases/` and are ignored by Git. Core
release and deployment commands continue to use the outer workspace.
