"""Run: python3 -m unittest (needs uv; hotspots.py declares its lizard dependency inline)."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "hotspots.py"
FIXTURES = SCRIPT.parent / "fixtures"
# Hand-checked against the fixture code; a lizard upgrade that changes one fails here.
CORPUS = {
    "pkg/a.py:4 chain": "nloc=8 ccn=4 cognitive=3 nesting=1",  # elif chain stays flat
    "pkg/a.py:14 blocks": "nloc=10 ccn=4 cognitive=4 nesting=4",  # with > try > for > if
    "pkg/a.py:23 blocks.inner": "nloc=2 ccn=2 cognitive=1 nesting=0",  # own function
    "pkg/a.py:29 dispatch": "nloc=7 ccn=4 cognitive=3 nesting=2",  # match > while
    "pkg/b.py:4 step": "nloc=2 ccn=3 cognitive=2 nesting=0 params=6",
    "app.ts:6 load": "nloc=11 ccn=4 cognitive=5 nesting=3",  # for > try > if
    "legacy.js:3 lazy": "nloc=6 ccn=3 cognitive=2 nesting=1",
    "view.tsx:3 View": "nloc=6 ccn=2 cognitive=1 nesting=1 params=2",  # lizard counts destructured props
}

TANGLED = """def tangled(a, b, c, d, e, f):
    for x in a:
        if x:
            for y in b:
                if y and c:
                    while d:
                        if e or f:
                            d -= 1
    return a
"""
SIMPLE = "def simple(a):\n    return a\n"


@unittest.skipUnless(shutil.which("uv"), "uv not installed")
class HotspotsTest(unittest.TestCase):
    def setUp(self):
        self.repo = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.repo)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "t@example.com")
        self.git("config", "user.name", "t")

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)

    def commit(self, files, msg="c"):
        for name, text in files.items():
            (self.repo / name).parent.mkdir(parents=True, exist_ok=True)
            (self.repo / name).write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", msg)

    def run_script(self, *args):
        return subprocess.run(["uv", "run", "-q", str(SCRIPT), *args], cwd=self.repo,
                              capture_output=True, text=True)

    def test_corpus_metrics_and_imports(self):
        shutil.copytree(FIXTURES, self.repo, dirs_exist_ok=True)
        self.commit({})
        out = self.run_script("--top", "50")
        self.assertEqual(out.returncode, 0, out.stderr)
        for function, metrics in CORPUS.items():
            line = next((l for l in out.stdout.splitlines() if l.startswith(f"- {function} ")), "")
            for metric in metrics.split():
                self.assertIn(f" {metric} ", f"{line} ", function)
        # ESM, './x.js' naming x.ts, re-export and require; relative and absolute Python
        # imports. Imports that don't run at load time make no edge: comments, `import type`,
        # dynamic `import()`, TYPE_CHECKING and function-local imports.
        cycles = out.stdout.split("## Import cycles\n\n")[1].split("\n\n")[0].splitlines()
        self.assertEqual(cycles, ["- app.ts <-> legacy.js <-> util.ts",
                                  "- pkg/a.py <-> pkg/b.py"])
        self.assertIn("- app.ts  fan_out=1", out.stdout)
        self.assertIn("- app.ts  fan_in=2", out.stdout)  # side-effect import + require

    def test_scan_ranks_tangled_churned_code_and_finds_ts_cycle(self):
        self.commit({
            "core.py": TANGLED,
            "calm.py": SIMPLE,
            "src/a.ts": "import { b } from './b';\nexport const a = () => b;\n",
            "src/b.ts": "import { a } from './a.js';\nexport function b() { return a; }\n",
            "src/view.tsx": "export function View({ on }: P) { return on ? <b/> : null; }\n",
            "dist/core.js": "function generated(a) { if (a) { if (a) { if (a) { return 1 } } } }\n",
            "tests/fixtures/sample.py": TANGLED,
        })
        self.commit({"core.py": TANGLED + "\n"})
        out = self.run_script()
        self.assertEqual(out.returncode, 0, out.stderr)
        functions = out.stdout.split("## Functions")[1].split("##")[0]
        self.assertIn("core.py:1 tangled", functions.splitlines()[2])
        self.assertIn("over: cognitive, nesting, params", functions)
        self.assertIn("src/a.ts <-> src/b.ts", out.stdout)
        self.assertIn("src/view.tsx", out.stdout)
        self.assertNotIn("dist/", out.stdout)
        self.assertNotIn("fixtures/", out.stdout)

    def test_diff_flags_function_made_worse(self):
        self.commit({"core.py": "def tangled(a, b, c, d, e, f):\n    return a\n"})
        self.git("checkout", "-q", "-b", "feature")
        (self.repo / "core.py").write_text(TANGLED)  # uncommitted counts too
        out = self.run_script("--base", "main")
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("core.py:1 tangled  cognitive 0->23, nesting 0->6", out.stdout)
        self.assertNotIn("params", out.stdout)  # already over the limit on main, unchanged

    def test_diff_flags_new_import_cycle_only(self):
        self.commit({"a.js": "export const a = 1;\n", "b.js": "import { a } from './a';\n",
                     "old.py": "import older\n", "older.py": "import old\n"})
        self.git("checkout", "-q", "-b", "feature")
        self.commit({"a.js": "import { b } from './b';\nexport const a = 1;\n"})
        out = self.run_script("--base", "main")
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("import cycle a.js <-> b.js  closed by: a.js -> b.js", out.stdout)
        self.assertNotIn("old.py", out.stdout)  # pre-existing cycle, untouched

    def test_diff_ignores_a_moved_file(self):
        self.commit({"core.py": TANGLED})
        self.git("checkout", "-q", "-b", "feature")
        self.git("mv", "core.py", "engine.py")
        self.commit({})
        out = self.run_script("--base", "main")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_diff_flags_file_grown_past_limit(self):
        self.commit({"big.py": SIMPLE})
        self.git("checkout", "-q", "-b", "feature")
        self.commit({"big.py": "".join(f"def f{i}(a):\n    return a\n" for i in range(260))})
        out = self.run_script("--base", "main")
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("- big.py  file nloc 2->520 (limit 500)", out.stdout)

    def test_git_failure_exits_2_with_gits_message(self):
        self.commit({"core.py": SIMPLE})
        out = self.run_script("--base", "no-such-ref")
        self.assertEqual(out.returncode, 2)  # 1 means findings: a typo must not look like one
        self.assertIn("no-such-ref", out.stderr)
        self.assertNotIn("Traceback", out.stderr)

    def test_paths_narrow_the_scan(self):
        self.commit({"a/m.py": TANGLED, "b/n.py": TANGLED})
        out = self.run_script("a")
        self.assertIn("(1 files,", out.stdout)
        self.assertNotIn("b/n.py", out.stdout)

    def test_scan_reads_mts_and_cts(self):
        self.commit({"esm.mts": "export function m(a: number) { if (a) { return 1 } return 0 }\n",
                     "cjs.cts": "export function c(a: number) { return a ? 1 : 0 }\n"})
        out = self.run_script()
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn("- esm.mts:1 m ", out.stdout)
        self.assertIn("- cjs.cts:1 c ", out.stdout)

    def test_import_edges_follow_load_time_rules(self):
        self.commit({
            # each name of a from-import resolves on its own: x -> z closes a cycle
            "p/__init__.py": "", "p/y.py": "", "p/x.py": "from . import y, z\n",
            "p/z.py": "from p import x\n",
            # `import type` ends at its specifier; the require after it is a real edge
            "t.ts": "export type T = 1;\n",
            "a.ts": "import type { T } from './t'; const b = require('./b');\n",
            # a require inside a function is deferred: no b -> c edge, no cycle with c
            "b.js": "const a = require('./a');\nfunction later() {\n  return require('./c');\n}\n",
            "c.js": "const b = require('./b');\n",
            # a callback on the require's own line doesn't defer it: e <-> f is a cycle
            "e.js": "const f = require('./f').map((x) => x);\n",
            "f.js": "const e = require('./e');\n",
        })
        out = self.run_script()
        cycles = out.stdout.split("## Import cycles\n\n")[1].split("\n\n")[0].splitlines()
        self.assertEqual(sorted(cycles), ["- a.ts <-> b.js", "- e.js <-> f.js", "- p/x.py <-> p/z.py"],
                         out.stdout)

    def test_diff_matches_python_methods_by_class(self):
        method = "    def run(self, a, b, c, d, e, f):\n" + "".join("    " + l + "\n" for l in TANGLED.splitlines()[1:])
        self.commit({"jobs.py": "class A:\n" + method + "\n\nclass B:\n    def run(self, x):\n        return x\n"})
        self.git("checkout", "-q", "-b", "feature")
        self.commit({"jobs.py": "class B:\n" + method})  # A gone, B.run now tangled
        out = self.run_script("--base", "main")
        self.assertEqual(out.returncode, 1, out.stdout + out.stderr)
        self.assertIn("jobs.py:2 B.run  cognitive 0->", out.stdout)

    def test_diff_clean_branch_passes(self):
        self.commit({"core.py": TANGLED, "calm.py": SIMPLE})
        self.git("checkout", "-q", "-b", "feature")
        self.commit({"calm.py": SIMPLE + "\n\ndef other(b):\n    return b\n"})
        out = self.run_script("--base", "main")
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("No new hotspots in 1 changed", out.stdout)


if __name__ == "__main__":
    unittest.main()
