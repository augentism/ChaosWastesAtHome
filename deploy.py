import shutil
from pathlib import Path

SRC = Path(__file__).parent
DST = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE\mods\ChaosWastesAtHome")

if not SRC.exists():
    raise FileNotFoundError(f"Source not found: {SRC}")

# Overlay source onto destination, overwriting changed files and adding new
# ones. We deliberately do NOT wipe the destination so an existing .git repo
# (or other local files) there is left intact.
shutil.copytree(
    SRC,
    DST,
    dirs_exist_ok=True,
    ignore=shutil.ignore_patterns(".git", "deploy.py", "README.md", "console-*.log"),
)
print(f"Deployed to {DST}")
print("Reminder: 'ChaosWastesAtHome' must be listed in mods/mod_load_order.txt.")
print("That file is Vortex-managed here, so add it through Vortex to make it stick.")
