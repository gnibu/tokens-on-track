#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["lizard>=1.17,<2"]
# ///
"""Rank refactoring candidates in Python, JavaScript and TypeScript, or flag what a branch made worse.

  uv run hotspots.py [PATH ...] [--top N] [--since "12 months ago"]   repo scan
  uv run hotspots.py --base origin/master [PATH ...]                 diff mode, exit 1 on findings

Function metrics come from lizard (NLOC, cyclomatic and cognitive complexity, nesting,
parameters); imports from Python's ast and lizard's JS/TS tokenizer; churn from git log.
"""
import argparse
import ast
import os
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import PurePosixPath

import lizard  # type: ignore[import-untyped]
from lizard_languages import get_reader_for  # type: ignore[import-untyped]

PY_EXT = {".py"}
JS_EXT = [".ts", ".tsx", ".js", ".jsx", ".mts", ".cts", ".mjs", ".cjs"]
READ_AS = {".mts": ".ts", ".cts": ".ts"}  # lizard has no reader for these
SKIP_DIRS = {"node_modules", "dist", "build", "vendor", "third_party", "__pycache__", "coverage", ".next",
             "fixtures", "__fixtures__", "testdata"}  # generated, vendored or deliberate test data
LIMITS = {"nloc": 50, "ccn": 10, "cognitive": 15, "nesting": 3, "params": 5}
FILE_LIMIT = 500  # NLOC
ANALYZER = lizard.FileAnalyzer(lizard.get_extensions(["ns", "cognitive"]))  # ns: JS/TS nesting only
NESTS = (ast.If, ast.For, ast.AsyncFor, ast.While, ast.Try, ast.With, ast.AsyncWith, ast.Match,
         *([ast.TryStar] if hasattr(ast, "TryStar") else []))
SCOPES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)


@dataclass
class Function:
    path: str
    name: str
    line: int
    nloc: int
    ccn: int
    cognitive: int
    nesting: int
    params: int

    def over(self) -> list[str]:
        return [k for k, limit in LIMITS.items() if getattr(self, k) > limit]

    def metrics(self) -> str:
        return " ".join(f"{k}={getattr(self, k)}" for k in LIMITS)


def git(*args: str, cwd: str) -> str:
    return subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, check=True).stdout


def is_source(path: str) -> bool:
    p = PurePosixPath(path)
    if p.suffix not in PY_EXT | set(JS_EXT) or path.endswith((".d.ts", ".min.js")):
        return False
    return not SKIP_DIRS.intersection(p.parts)


def reader_path(path: str) -> str:
    suffix = PurePosixPath(path).suffix
    return path[: -len(suffix)] + READ_AS[suffix] if suffix in READ_AS else path


def py_functions(code: str) -> dict[int, tuple[str, int]]:
    """(dotted name, max block depth) per Python def line. lizard miscounts Python nesting and
    names a method without its class, so diff mode would pair `A.run` with `B.run`."""
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return {}

    def depth(node: ast.AST, d: int) -> int:
        best = d
        for child in ast.iter_child_nodes(node):
            if isinstance(child, SCOPES):
                continue  # lizard reports nested functions on their own
            elif_ = isinstance(node, ast.If) and node.orelse == [child]
            best = max(best, depth(child, d + (isinstance(child, NESTS) and not elif_)))
        return best

    found: dict[int, tuple[str, int]] = {}

    def visit(node: ast.AST, prefix: str) -> None:
        for child in ast.iter_child_nodes(node):
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                found[child.lineno] = (prefix + child.name, depth(child, 0))
            visit(child, prefix + child.name + "." if isinstance(child, SCOPES[:3]) else prefix)

    visit(tree, "")
    return found


def analyze(path: str, code: str) -> tuple[int, list[Function]]:
    info = ANALYZER.analyze_source_code(reader_path(path), code)
    py = py_functions(code) if path.endswith(".py") else {}
    functions = []
    for f in info.function_list:
        name, nesting = py.get(f.start_line, (f.name, f.max_nested_structures))
        functions.append(Function(path, name, f.start_line, f.nloc, f.cyclomatic_complexity,
                                  f.cognitive_complexity, nesting, f.parameter_count))
    return info.nloc, functions


def imports(path: str, code: str, files: set[str]) -> set[str]:
    """Repo files that `path` imports. Package imports and JS path aliases resolve to nothing."""
    found = (py_imports if path.endswith(".py") else js_imports)(path, code, files)
    return found - {path}


def load_time_imports(body: list[ast.stmt]) -> list[ast.stmt]:
    """Imports that run when the module loads: not function-local, not under TYPE_CHECKING."""
    found: list[ast.stmt] = []
    for node in body:
        if isinstance(node, (ast.Import, ast.ImportFrom)):
            found.append(node)
        elif isinstance(node, ast.If):
            if ast.unparse(node.test) not in ("TYPE_CHECKING", "typing.TYPE_CHECKING"):
                found += load_time_imports(node.body)
            found += load_time_imports(node.orelse)
        elif isinstance(node, (ast.Try, ast.With)):
            for block in ("body", "orelse", "finalbody"):
                found += load_time_imports(getattr(node, block, []))
            for handler in getattr(node, "handlers", []):
                found += load_time_imports(handler.body)
    return found


def py_imports(path: str, code: str, files: set[str]) -> set[str]:
    here = PurePosixPath(path).parent
    try:
        tree = ast.parse(code)
    except SyntaxError:
        return set()
    roots = [PurePosixPath(""), PurePosixPath("src"), here]
    searches: list[tuple[list[PurePosixPath], list[str]]] = []  # (roots, dotted names), first hit wins
    for node in load_time_imports(tree.body):
        if isinstance(node, ast.Import):
            searches += [(roots, [a.name]) for a in node.names]
        elif isinstance(node, ast.ImportFrom):
            mod = node.module or ""
            base = ([here.parents[node.level - 2] if node.level > 1 else here] if node.level else roots)
            # each name is a submodule, else an attribute of the module it comes from
            searches += [(base, [f"{mod}.{a.name}".strip("."), mod]) for a in node.names]
    return {hit for search_roots, names in searches if (hit := py_module(search_roots, names, files))}


def py_module(roots: list[PurePosixPath], names: list[str], files: set[str]) -> str | None:
    stems = (root.joinpath(*dotted.split(".")) if dotted else root for root in roots for dotted in names)
    return next((c for stem in stems for c in (f"{stem}.py", f"{stem}/__init__.py") if c in files), None)


def js_tokens(path: str, code: str) -> list[tuple[str, int]]:
    """Significant tokens (no whitespace or comments) with their line numbers."""
    found, line = [], 1
    for tok in get_reader_for(reader_path(path)).generate_tokens(code):
        if tok.strip() and not tok.startswith(("//", "/*")):
            found.append((tok, line))
        line += tok.count("\n")
    return found


def js_imports(path: str, code: str, files: set[str]) -> set[str]:
    """Relative specifiers of static imports and of requires outside functions. Dynamic
    import() and a require inside a function are deferred, like a function-local import."""
    tokens = js_tokens(path, code)
    words = [tok for tok, _ in tokens]
    # lizard has no columns: only lines strictly inside a function body count as deferred, so
    # `require('./b').map(x => x)` stays a load-time edge
    deferred = {n for f in ANALYZER.analyze_source_code(reader_path(path), code).function_list
                for n in range(f.start_line + 1, f.end_line)} if "require" in code else set()
    specs = []
    type_only = False  # `import type` / `export type`: erased at compile time
    for i, (tok, line) in enumerate(tokens):
        if tok in ("import", "export"):
            type_only = words[i + 1:i + 2] == ["type"]
        if i == 0 or tok[0] not in "'\"`" or tok[1:2] != ".":
            continue
        if words[i - 1] in ("from", "import") and not type_only:
            specs.append(tok[1:-1])
        elif words[i - 2:i] == ["require", "("] and line not in deferred:
            specs.append(tok[1:-1])
    here = PurePosixPath(path).parent
    return {hit for spec in specs if (hit := js_module(here, spec, files))}


def js_module(here: PurePosixPath, spec: str, files: set[str]) -> str | None:
    target = os.path.normpath(str(here / spec))
    ext = PurePosixPath(target).suffix
    bare = target[: -len(ext)] if ext in JS_EXT else target  # './a.js' may name a.ts
    candidates = [target] + [bare + e for e in JS_EXT] + [f"{target}/index{e}" for e in JS_EXT]
    return next((c for c in candidates if c in files), None)


def cycles(graph: dict[str, set[str]]) -> list[list[str]]:
    """Strongly connected components with more than one file (Tarjan)."""
    index: dict[str, int] = {}
    low: dict[str, int] = {}
    stack: list[str] = []
    on_stack: set[str] = set()
    out: list[list[str]] = []

    def visit(v: str) -> None:
        index[v] = low[v] = len(index)
        stack.append(v)
        on_stack.add(v)
        for w in graph.get(v, ()):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on_stack:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            scc = []
            while True:
                w = stack.pop()
                on_stack.discard(w)
                scc.append(w)
                if w == v:
                    break
            if len(scc) > 1:
                out.append(sorted(scc))

    sys.setrecursionlimit(max(10_000, 4 * len(graph)))
    for v in sorted(graph):
        if v not in index:
            visit(v)
    return out


def read(root: str, path: str) -> str:
    with open(os.path.join(root, path), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def import_graph(root: str, files: set[str]) -> dict[str, set[str]]:
    return {f: imports(f, read(root, f), files) for f in sorted(files)}


def scan(root: str, files: set[str], top: int, since: str) -> None:
    churn = Counter(line for line in git("log", f"--since={since}", "--no-merges", "--format=",
                                         "--name-only", cwd=root).splitlines() if line)
    funcs: list[Function] = []
    sizes: dict[str, int] = {}
    for f in sorted(files):
        sizes[f], fs = analyze(f, read(root, f))
        funcs += fs

    print(f"# Hotspots ({len(files)} files, churn = commits since {since})\n")
    print("## Functions: cognitive complexity x (1 + churn)\n")
    ranked = sorted(funcs, key=lambda fn: fn.cognitive * (1 + churn[fn.path]), reverse=True)
    for fn in [fn for fn in ranked if fn.cognitive][:top]:
        over = f"  over: {', '.join(fn.over())}" if fn.over() else ""
        print(f"- {fn.path}:{fn.line} {fn.name}  {fn.metrics()} churn={churn[fn.path]}{over}")

    print("\n## Files: NLOC x (1 + churn)\n")
    for f in sorted(sizes, key=lambda f: sizes[f] * (1 + churn[f]), reverse=True)[:top]:
        print(f"- {f}  nloc={sizes[f]} churn={churn[f]} functions={sum(fn.path == f for fn in funcs)}")

    graph = import_graph(root, files)
    fan_in = Counter(dep for deps in graph.values() for dep in deps)
    print("\n## Import cycles\n")
    for scc in cycles(graph) or [["none"]]:
        print(f"- {' <-> '.join(scc)}")
    print("\n## Most imported (fan-in)\n")
    for f, n in fan_in.most_common(5):
        print(f"- {f}  fan_in={n}")
    print("\n## Most importing (fan-out)\n")
    for f in sorted(graph, key=lambda f: len(graph[f]), reverse=True)[:5]:
        if graph[f]:
            print(f"- {f}  fan_out={len(graph[f])}")


def worse_functions(path: str, old: str, code: str) -> list[str]:
    """Functions past a limit that are new or grew on a metric past its limit."""
    old_size, old_funcs = analyze(path, old) if old else (0, [])
    size, funcs = analyze(path, code)
    seen: Counter[str] = Counter()
    before_by_key = {}
    for fn in old_funcs:  # match by name and occurrence: same-named methods keep their order
        before_by_key[(fn.name, seen[fn.name])] = fn
        seen[fn.name] += 1
    seen.clear()
    findings = []
    for fn in funcs:
        before = before_by_key.get((fn.name, seen[fn.name]))
        seen[fn.name] += 1
        worse = [k for k in fn.over() if before is None or getattr(fn, k) > getattr(before, k)]
        if worse:
            change = ", ".join(f"{k} {getattr(before, k) if before else 'new'}->{getattr(fn, k)}" for k in worse)
            limits = ", ".join(f"{k}<={LIMITS[k]}" for k in worse)
            findings.append(f"- {path}:{fn.line} {fn.name}  {change} (limits: {limits})")
    if size > FILE_LIMIT and size > old_size:
        findings.append(f"- {path}  file nloc {old_size}->{size} (limit {FILE_LIMIT})")
    return findings


def closed_cycles(root: str, files: set[str], new_edges: set[tuple[str, str]]) -> list[str]:
    """Import cycles that contain an edge this branch added. Builds the graph only if needed."""
    findings = []
    for scc in cycles(import_graph(root, files)) if new_edges else []:
        added = [f"{a} -> {b}" for a, b in sorted(new_edges) if a in scc and b in scc]
        if added:
            findings.append(f"- import cycle {' <-> '.join(scc)}  closed by: {'; '.join(added)}")
    return findings


def diff(root: str, files: set[str], base: str) -> int:
    mb = git("merge-base", base, "HEAD", cwd=root).strip()
    changed: list[tuple[str, str]] = []  # (path at the merge base, path now); a rename keeps its history
    for line in git("diff", "--name-status", "-M", "--diff-filter=AMR", mb, cwd=root).splitlines():
        parts = line.split("\t")
        if parts[-1] in files:
            changed.append((parts[1], parts[-1]))
    findings: list[str] = []
    new_edges: set[tuple[str, str]] = set()
    for was, f in changed:
        code = read(root, f)
        try:
            old = git("show", f"{mb}:{was}", cwd=root)
        except subprocess.CalledProcessError:
            old = ""  # added on this branch
        findings += worse_functions(f, old, code)
        old_deps = imports(f, old, files) if old else set()
        new_edges |= {(f, dep) for dep in imports(f, code, files) - old_deps}

    findings += closed_cycles(root, files, new_edges)

    if not findings:
        print(f"No new hotspots in {len(changed)} changed source files since {base}.")
        return 0
    print(f"# Hotspots this branch made worse (vs {base})\n")
    print("\n".join(findings))
    return 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("paths", nargs="*", help="limit to these paths (default: the whole repo)")
    ap.add_argument("--base", help="diff mode: report what HEAD and the working tree made worse vs this ref")
    ap.add_argument("--top", type=int, default=10)
    ap.add_argument("--since", default="12 months ago", help="churn window for the repo scan")
    args = ap.parse_args()

    root = git("rev-parse", "--show-toplevel", cwd=os.getcwd()).strip()
    listed = git("ls-files", "--full-name", "--", *args.paths, cwd=os.getcwd()).splitlines()
    files = {f for f in listed if is_source(f) and os.path.isfile(os.path.join(root, f))}
    if args.base:
        return diff(root, files, args.base)
    scan(root, files, args.top, args.since)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except subprocess.CalledProcessError as e:
        print(f"hotspots.py: {' '.join(e.cmd)}: {e.stderr.strip()}", file=sys.stderr)
        sys.exit(2)  # not 1: diff mode's 1 means findings
