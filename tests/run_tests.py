#!/usr/bin/env python3
"""Run the ChaosWastesAtHome test suite.

Two tiers, because the failures come in two kinds.

  offline   Pure logic under LuaJIT with no game running: buff pools, run
            carry-over, the difficulty ladder, vote tiebreaks. Seconds to run,
            so it is worth running on every edit. The engine's real data tables
            are loaded out of the decompiled source tree, so "every buff we
            offer is a real buff" actually means something.

  ingame    Driven through dt-cli against a running game, for what only the
            game can answer: the mission hop, activation gating, custom-buff
            network registration.

Usage:
    python3 run_tests.py              # offline, then in-game if the game is up
    python3 run_tests.py --offline    # offline only
    python3 run_tests.py --ingame     # in-game only
    python3 run_tests.py -k difficulty vote     # filter offline files

The in-game tier reports SKIPPED rather than failed when the game is not
running, so a closed game never turns the suite red.

NOTE: the in-game tests DRIVE the game. hop.sh starts a run and forces wins.
Do not fire it at a session you care about.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

TESTS = Path(__file__).resolve().parent
WORKSPACE = TESTS.parent.parent

# hop.sh must come first: the read-only scripts below it assert against a live
# run, and hop.sh is what produces one.
#
# vox_map_vote.sh goes last because it is the only one that ends somewhere it
# did not start -- it hands the next mission to chat, so what comes up is
# whatever the viewers (or, on a silent stream, chance) picked. Anything
# asserting against a known mission has to run before it.
INGAME = ["hop.sh", "buff_pool.sh", "custom_buffs.sh", "activation.sh",
          "vox_map_vote.sh", "vox_map_vote_fallback.sh"]

SKIP_EXIT = 111


def _env():
    env = dict(os.environ)
    env["CWAH_TEST_ROOT"] = str(WORKSPACE)
    env["CWAH_TEST_DIR"] = str(TESTS)
    return env


def run_offline(filters):
    luajit = shutil.which("luajit")

    if not luajit:
        print("offline: SKIPPED - no luajit on PATH")
        print("         run inside the flake: nix develop ./nix --command python3 ...")
        return None

    cmd = [luajit, str(TESTS / "offline" / "run.lua")] + list(filters)
    result = subprocess.run(cmd, cwd=str(TESTS), env=_env())

    return result.returncode == 0


def run_ingame():
    cli = WORKSPACE / ".claude/skills/darktide-dt-cli/scripts/dt-cli.sh"

    if not cli.exists():
        print("ingame: SKIPPED - dt-cli not found at %s" % cli)
        return None

    results = {}

    for name in INGAME:
        script = TESTS / "ingame" / name

        if not script.exists():
            print("ingame: %s is missing" % name)
            results[name] = False
            continue

        result = subprocess.run(["bash", str(script)], cwd=str(TESTS), env=_env())

        if result.returncode == SKIP_EXIT:
            results[name] = None
        else:
            results[name] = result.returncode == 0

    ran = [v for v in results.values() if v is not None]

    if not ran:
        print("\ningame: SKIPPED - the game is not reachable")
        return None

    return all(ran)


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--offline", action="store_true", help="offline tier only")
    parser.add_argument("--ingame", action="store_true", help="in-game tier only")
    parser.add_argument(
        "-k", nargs="*", default=[], metavar="NAME",
        help="substring filters for offline test files",
    )
    args = parser.parse_args()

    want_offline = args.offline or not args.ingame
    want_ingame = args.ingame or not args.offline

    offline = run_offline(args.k) if want_offline else None
    ingame = run_ingame() if want_ingame else None

    print()
    print("=" * 60)

    def label(value):
        if value is None:
            return "SKIPPED"
        return "PASSED" if value else "FAILED"

    if want_offline:
        print("  offline  %s" % label(offline))
    if want_ingame:
        print("  ingame   %s" % label(ingame))

    print("=" * 60)

    # A skipped tier is not a failure: the offline tier has to stay useful with
    # the game closed, which is most of the time.
    failed = [v for v in (offline, ingame) if v is False]

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
