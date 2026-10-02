#!/usr/bin/env python3
"""Fails when a catalog key lacks a Vietnamese translation, or when a View file
contains a string literal that is neither a catalog key nor explicitly allowed."""
import json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
VIEW_DIRS = [ROOT / "App", ROOT / "Packages/Features/Sources", ROOT / "Packages/DesignSystem/Sources/DesignSystem/Gallery"]
# Only SwiftUI view files are checked; LaunchOptions.swift, AppContainer.swift and other
# non-view files carry CLI flags, paths and defaults keys that are not user-facing strings.
VIEW_MARKER = "import SwiftUI"
KEY_RE = re.compile(r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$")
LITERAL_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
ALLOW_MARKERS = ["verbatim:", "systemImage", "systemName", "accessibilityIdentifier", "identifier", "forKey", "UserDefaults", "#Preview",
                 "code:", "lint:allow-string", "import ", "Bundle", "url", "URL", "path", "Path", "arguments", "CommandLine", "LocalizedStringKey(\""]

def main() -> int:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog["strings"]
    errors = []
    for key, entry in strings.items():
        vi = entry.get("localizations", {}).get("vi", {}).get("stringUnit", {})
        if vi.get("state") != "translated" or not vi.get("value"):
            errors.append(f"{CATALOG.name}: key '{key}' has no Vietnamese translation")
    for directory in VIEW_DIRS:
        for path in directory.rglob("*.swift"):
            if "Tests" in path.parts or path.name.endswith("Tests.swift"):
                continue
            source = path.read_text(encoding="utf-8")
            if VIEW_MARKER not in source:
                continue
            for lineno, line in enumerate(source.splitlines(), 1):
                stripped = line.strip()
                if stripped.startswith("//") or any(marker.lower() in line.lower() for marker in ALLOW_MARKERS):
                    continue
                for literal in LITERAL_RE.findall(line):
                    if literal == "" or literal.startswith("\\(") or literal.startswith("--"):
                        continue
                    if KEY_RE.match(literal):
                        if literal not in strings:
                            errors.append(f"{path.relative_to(ROOT)}:{lineno}: key '{literal}' missing from catalog")
                    else:
                        errors.append(f"{path.relative_to(ROOT)}:{lineno}: hard-coded string \"{literal}\"")
    for e in errors:
        print(e)
    print(f"check_localization: {len(strings)} keys, {len(errors)} error(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
