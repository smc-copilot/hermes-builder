"""Exercise the shipped launcher with a native executable stand-in, offline."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == "nt", "Windows launcher")
class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="hermes launcher test ")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name).resolve()
        self.hermes_root = self.base / "local appdata" / "hermes"
        self.node_dir = self.hermes_root / "node"
        self.node_dir.mkdir(parents=True)
        self.system32 = Path(os.environ["SystemRoot"]) / "System32"
        self.powershell = self.system32 / "WindowsPowerShell/v1.0/powershell.exe"
        # cmd.exe accepts a command as arguments, letting us inspect the exact
        # environment inherited by the executable launched as hermes.exe.
        exe = self.hermes_root / "hermes-agent/venv/Scripts/hermes.exe"
        exe.parent.mkdir(parents=True)
        shutil.copyfile(self.system32 / "cmd.exe", exe)
        shutil.copyfile(self.system32 / "cmd.exe", self.node_dir / "node.exe")
        self.other_node = self.base / "system node"
        self.other_node.mkdir()
        shutil.copyfile(self.system32 / "cmd.exe", self.other_node / "node.exe")
        for name in ("npm", "npx"):
            (self.node_dir / f"{name}.cmd").write_text(
                f"@echo bundled-{name}\n@exit /b 0\n", encoding="ascii"
            )
            (self.other_node / f"{name}.cmd").write_text(
                f"@echo wrong-{name}\n@exit /b 0\n", encoding="ascii"
            )
        self.env = os.environ.copy()
        self.env["HERMES_HOME"] = str(self.hermes_root)
        self.env["LOCALAPPDATA"] = str(self.hermes_root.parent)
        # A competing Node is initially first; bundled Node is already present
        # later to cover precedence and deduplication in the same test.
        self.env["PATH"] = os.pathsep.join(
            map(str, (self.other_node, self.system32, self.node_dir))
        )

    def launch(self, command):
        return subprocess.run(
            [str(self.powershell), "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", "Bypass", "-File",
             str(ROOT / "enterprise/launchers/hermes.ps1"),
             "/d", "/c", command],
            env=self.env, capture_output=True, text=True, errors="replace",
            timeout=30,
        )

    def test_child_path_commands_and_exit_code(self):
        original_path = os.environ.get("PATH")
        result = self.launch(
            "where.exe node.exe & where.exe npm.cmd & where.exe npx.cmd"
            " & call npm.cmd & call npx.cmd & exit /b 23"
        )
        self.assertEqual(result.returncode, 23, result.stderr)
        lines = result.stdout.splitlines()
        paths = [os.path.normcase(line) for line in lines]
        for name in ("node.exe", "npm.cmd", "npx.cmd"):
            bundled = os.path.normcase(str(self.node_dir / name))
            other = os.path.normcase(str(self.other_node / name))
            self.assertEqual(paths.count(bundled), 1, lines)
            self.assertLess(paths.index(bundled), paths.index(other), lines)
        self.assertIn("bundled-npm", lines)
        self.assertIn("bundled-npx", lines)
        self.assertNotIn("wrong-npm", lines)
        self.assertNotIn("wrong-npx", lines)
        self.assertEqual(os.environ.get("PATH"), original_path)

    def test_default_install_location(self):
        self.env.pop("HERMES_HOME")
        result = self.launch("call npx.cmd")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("bundled-npx", result.stdout)

    def test_incomplete_node_fails_before_launch(self):
        (self.node_dir / "npx.cmd").unlink()
        result = self.launch("echo SHOULD_NOT_RUN")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Packaged Node command missing", result.stderr)
        self.assertNotIn("SHOULD_NOT_RUN", result.stdout)


if __name__ == "__main__":
    unittest.main()
