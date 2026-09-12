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
    python3 run_tests.py --start      # launch the game, test, close it again

--start makes an unattended run self-contained: it launches the game, waits for
LuaExec and runs the tier. In-game runs close Darktide afterwards by default,
including an already-running game and runs that fail or are interrupted with
Ctrl+C. Use --keep-open to leave it running for inspection. Offline-only runs
never close the game. --close remains accepted as an explicit default.

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
import time
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
# hop.sh first (it produces the live run the read-only scripts assert against),
# then the VoxPopuli ones, which SKIP cleanly when VoxPopuli is not installed.
#
# hop.sh switches the VoxPopuli integration OFF for its own run so it still
# exercises CWaH's party/solo path; the vox_* scripts switch it back on. Both
# behaviours are covered on a machine that has both mods, which is the machine
# where the integration is developed and therefore the one where losing that
# coverage would go unnoticed.
INGAME = ["hop.sh", "buff_pool.sh", "custom_buffs.sh", "activation.sh",
          "vox_map_vote.sh", "vox_map_vote_fallback.sh", "vox_map_vote_chat.sh"]

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


CLI = WORKSPACE / ".agents/skills/darktide-dt-cli/scripts/dt-cli.sh"
RESTART = WORKSPACE / ".agents/skills/darktide-dt-cli/scripts/restart-game.sh"


def game_is_reachable():
    """True when dt-cli can talk to a running game."""
    if not CLI.exists():
        return False

    try:
        result = subprocess.run(
            [str(CLI), "exec", 'return "up"'],
            capture_output=True, text=True, timeout=40, env=_env())
    except subprocess.TimeoutExpired:
        return False

    return '"ok":true' in result.stdout


def start_game():
    """Launch the game and wait for LuaExec. Returns True if it came up."""
    if not RESTART.exists():
        print("could not start the game: %s is missing" % RESTART)
        return False

    print("starting Darktide for the in-game tier...", flush=True)
    result = subprocess.run(["bash", str(RESTART)], env=_env())

    return result.returncode == 0


def stop_game():
    """Close the game and wait for wine to let go of it.

    Stops the systemd unit first, because that is how restart-game.sh launches
    it -- pkill alone leaves the unit behind in a failed state, and the next
    launch has to reset-failed before it can reuse the name. pkill is the
    fallback for a game somebody started from Steam.
    """
    print("\nclosing Darktide...", flush=True)

    subprocess.run(["systemctl", "--user", "stop", "darktide-test"],
                   capture_output=True)

    for pattern in (r"Darktide\.exe", r"Launcher\.exe"):
        subprocess.run(["pkill", "-f", pattern], capture_output=True)

    # Wine needs a moment to actually release the prefix. Returning before it
    # has is how the next launch ends up with two wineservers and a pipe nobody
    # owns -- the same wait restart-game.sh does for the same reason.
    for _ in range(30):
        still_running = subprocess.run(
            ["pgrep", "-f", r"Darktide\.exe"], capture_output=True)

        if still_running.returncode != 0:
            return True

        time.sleep(1)

    print("  warning: Darktide is still running after 30s")

    return False


def run_ingame():
    cli = CLI

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
    parser.add_argument(
        "--start", action="store_true",
        help="launch the game first if it is not already up",
    )
    shutdown = parser.add_mutually_exclusive_group()
    shutdown.add_argument(
        "--close", action="store_true",
        help="close the game after the in-game tier (the default)",
    )
    shutdown.add_argument(
        "--keep-open", action="store_true",
        help="leave the game running after in-game tests, including on failure",
    )
    args = parser.parse_args()

    want_offline = args.offline or not args.ingame
    want_ingame = args.ingame or not args.offline

    offline = run_offline(args.k) if want_offline else None

    ingame = None
    closed = None
    if want_ingame:
        try:
            ready = True
            if args.start:
                if game_is_reachable():
                    print("the game is already running", flush=True)
                else:
                    ready = start_game()
                    if not ready:
                        print("could not start the game; in-game tests failed", flush=True)
            ingame = run_ingame() if ready else False
        finally:
            # A failed launch may still leave a process behind. Clean it up
            # along with failures/exceptions from the tests themselves.
            if not args.keep_open:
                closed = stop_game()

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
        if closed is not None:
            print("  shutdown %s" % label(closed))

    print("=" * 60)

    # A skipped tier is not a failure: the offline tier has to stay useful with
    # the game closed, which is most of the time.
    failed = [v for v in (offline, ingame, closed) if v is False]

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
