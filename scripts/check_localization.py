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
            if path.name == "ScopeFieldCatalog.swift":  # data catalog: ids are checked via the generated-key block below
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
    # Keys generated from Swift catalogs must exist too.
    generated: set[str] = set()
    catalog_swift = (ROOT / "Packages/Features/Sources/FeatureSupport/ScopeFieldCatalog.swift").read_text(encoding="utf-8")
    for m in re.finditer(r'key: "([A-Za-z0-9]+)"', catalog_swift): generated.add(f"scope.field.{m.group(1)}")
    for m in re.finditer(r'unitKey: "([a-z]+)"', catalog_swift): generated.add(f"scope.unit.{m.group(1)}")
    for m in re.finditer(r"\.choice\(\[([^\]]+)\]\)", catalog_swift):
        for opt in re.findall(r'"([A-Za-z0-9]+)"', m.group(1)): generated.add(f"scope.option.{opt}")
    enums = (ROOT / "Packages/Domain/Sources/Domain/Drafts/OtherCostKind.swift").read_text(encoding="utf-8")
    body = enums.split("{", 1)[1]
    for case_line in re.findall(r"case ([a-zA-Z0-9, ]+)", body.split("var costGroup")[0]):
        for name in case_line.split(","): generated.add(f"otherCost.{name.strip()}")
    for tpl in ["depositFinal", "depositProgressFinal", "fourStage", "custom"]: generated.add(f"schedule.template.{tpl}")
    for row in ["deposit", "progress", "stage2", "stage3", "final", "labourQuick"]: generated.add(f"schedule.row.{row}")
    for phase in ["all", "inWork", "preStart", "workDone", "terminal"]: generated.add(f"projects.filter.{phase}")
    for st in ["upcoming", "dueSoon", "dueToday", "overdue", "partiallyPaid", "paid"]: generated.add(f"payment.status.{st}")
    for g in ["labour", "material"]: generated.add(f"costGroup.{g}")
    for key in sorted(generated):
        if key not in strings: errors.append(f"generated key '{key}' missing from catalog")
    for e in errors:
        print(e)
    print(f"check_localization: {len(strings)} keys, {len(errors)} error(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
