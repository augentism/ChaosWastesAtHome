"""Test runner cleanup without launching or terminating real game processes."""
import contextlib
import importlib.util
import io
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "cwah_test_runner", Path(__file__).with_name("run_tests.py")
)
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class RunnerCleanupTests(unittest.TestCase):
    def invoke(self, args, *, result=True, error=None, start=True, closed=True):
        with contextlib.ExitStack() as stack:
            stack.enter_context(patch("sys.argv", ["run_tests.py", *args]))
            stack.enter_context(contextlib.redirect_stdout(io.StringIO()))
            offline = stack.enter_context(patch.object(runner, "run_offline", return_value=True))
            ingame = stack.enter_context(patch.object(
                runner, "run_ingame", return_value=result, side_effect=error
            ))
            stack.enter_context(patch.object(runner, "game_is_reachable", return_value=False))
            stack.enter_context(patch.object(runner, "start_game", return_value=start))
            stop = stack.enter_context(patch.object(runner, "stop_game", return_value=closed))
            if error is not None:
                with self.assertRaises(type(error)):
                    runner.main()
                code = None
            else:
                code = runner.main()
            return code, stop.call_count, ingame.call_count, offline.call_count

    def test_existing_game_closes_after_success(self):
        self.assertEqual(self.invoke(["--ingame"]), (0, 1, 1, 0))

    def test_default_combined_run_closes(self):
        self.assertEqual(self.invoke([]), (0, 1, 1, 1))

    def test_failure_still_closes(self):
        self.assertEqual(self.invoke(["--ingame"], result=False), (1, 1, 1, 0))

    def test_exception_still_closes(self):
        self.assertEqual(self.invoke(["--ingame"], error=RuntimeError("test"))[1], 1)

    def test_ctrl_c_still_closes(self):
        self.assertEqual(self.invoke(["--ingame"], error=KeyboardInterrupt())[1], 1)

    def test_keep_open_on_success_failure_and_interruption(self):
        for result, error in [(True, None), (False, None), (True, KeyboardInterrupt())]:
            with self.subTest(result=result, error=error):
                self.assertEqual(self.invoke(
                    ["--ingame", "--keep-open"], result=result, error=error
                )[1], 0)

    def test_offline_does_not_close_game(self):
        self.assertEqual(self.invoke(["--offline", "--close"]), (0, 0, 0, 1))

    def test_failed_start_cleans_up_and_fails(self):
        self.assertEqual(self.invoke(["--ingame", "--start"], start=False), (1, 1, 0, 0))

    def test_shutdown_failure_is_reported(self):
        self.assertEqual(self.invoke(["--ingame"], closed=False)[0], 1)

    def test_legacy_close_flag(self):
        self.assertEqual(self.invoke(["--ingame", "--close"]), (0, 1, 1, 0))


if __name__ == "__main__":
    unittest.main()
