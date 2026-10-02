#!/usr/bin/env python3
"""Money safety and crash-safety lint for production sources."""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MONEY_DIRS = [ROOT / "Packages/Domain/Sources", ROOT / "Packages/Data/Sources"]
ALL_SOURCE_DIRS = MONEY_DIRS + [ROOT / "Packages/DesignSystem/Sources", ROOT / "Packages/Features/Sources", ROOT / "App"]
FLOAT_RE = re.compile(r"\b(Double|Float|CGFloat)\b")
CRASH_RE = re.compile(r"(try!|as!|fatalError\()")

def swift_files(directory):
    return [p for p in directory.rglob("*.swift") if "Tests" not in p.parts and "UITests" not in p.parts]

def main() -> int:
    errors = []
    for directory in MONEY_DIRS:
        for path in swift_files(directory):
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if FLOAT_RE.search(line) and "lint:allow-double" not in line:
                    errors.append(f"{path.relative_to(ROOT)}:{lineno}: floating point type in money-bearing module")
    for directory in ALL_SOURCE_DIRS:
        for path in swift_files(directory):
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                if line.strip().startswith("//"):
                    continue
                if CRASH_RE.search(line) and "lint:allow-crash" not in line:
                    errors.append(f"{path.relative_to(ROOT)}:{lineno}: try!/as!/fatalError in production code")
    for e in errors:
        print(e)
    print(f"lint_sources: {len(errors)} error(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
