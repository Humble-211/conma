#!/usr/bin/env python3
"""Fails when a catalog key lacks a Vietnamese translation, or when a View file
contains a string literal that is neither a catalog key nor explicitly allowed."""
import itertools, json, pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CATALOG = ROOT / "App/Resources/Localizable.xcstrings"
DOMAIN = ROOT / "Packages/Domain/Sources/Domain"
VIEW_DIRS = [ROOT / "App", ROOT / "Packages/Features/Sources", ROOT / "Packages/DesignSystem/Sources/DesignSystem/Gallery"]
# Only SwiftUI view files are checked; LaunchOptions.swift, AppContainer.swift and other
# non-view files carry CLI flags, paths and defaults keys that are not user-facing strings.
VIEW_MARKER = "import SwiftUI"
KEY_RE = re.compile(r"^[a-z][A-Za-z0-9]*(\.[A-Za-z0-9]+)+$")
LITERAL_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')
ALLOW_MARKERS = ["verbatim:", "systemImage", "systemName", "accessibilityIdentifier", "identifier", "forKey", "UserDefaults", "#Preview",
                 "code:", "lint:allow-string", "import ", "Bundle", "url", "URL", "path", "Path", "arguments", "CommandLine", "LocalizedStringKey(\""]
# Computed properties that return non-user-facing codes (SF Symbol names, catalog-key fragments):
# every line of their body is skipped.
CODE_BLOCK_RE = re.compile(r"\bvar (systemImage|name)\s*:\s*String\s*\{")
# SwiftUI turns `Text("key \(x)")` into the key "key %@" (String/Text) or "key %lld" (Int).
PLACEHOLDERS = ["%@", "%lld"]
PLACEHOLDER_RE = re.compile(r"%(?:\d+\$)?(?:@|lld|d)")


def replace_interpolations(literal: str, token: str = "\0") -> str:
    """Replaces each `\\(…)` (balanced parentheses) with `token`."""
    out, i = [], 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                depth += {"(": 1, ")": -1}.get(literal[j], 0)
                j += 1
            out.append(token)
            i = j
        else:
            out.append(literal[i]); i += 1
    return "".join(out)


def interpolated_candidates(literal: str) -> list[str]:
    """All catalog keys SwiftUI may generate for an interpolated literal."""
    template = replace_interpolations(literal)
    slots = template.count("\0")
    keys = []
    for combo in itertools.product(PLACEHOLDERS, repeat=slots):
        parts = template.split("\0")
        keys.append("".join(p + (combo[i] if i < slots else "") for i, p in enumerate(parts)))
    return keys


def enum_cases(path: pathlib.Path, name: str) -> list[str]:
    """Case names declared directly in `enum <name>` (switch `case .x:` lines are ignored)."""
    source = path.read_text(encoding="utf-8")
    m = re.search(r"\benum\s+" + re.escape(name) + r"\b[^{]*\{", source)
    if not m:
        raise SystemExit(f"check_localization: enum {name} not found in {path}")
    depth, i = 1, m.end()
    while i < len(source) and depth:
        depth += {"{": 1, "}": -1}.get(source[i], 0)
        i += 1
    body = source[m.end():i - 1]
    names: list[str] = []
    for decl in re.findall(r"(?:^|[{;\n])\s*case\s+(?!\.)([^\n;{}]+)", body):
        depth, current, items = 0, "", []
        for ch in decl:
            if ch == "(": depth += 1
            elif ch == ")": depth -= 1
            if ch == "," and depth == 0: items.append(current); current = ""
            else: current += ch
        items.append(current)
        for item in items:
            ident = re.match(r"\s*([A-Za-z_]\w*)", item)
            if ident: names.append(ident.group(1))
    return names


def has_key_family(key: str, strings: dict) -> bool:
    """`key` itself, or `key` followed only by placeholders (e.g. "health.reason.paymentOverdue %lld")."""
    if key in strings:
        return True
    for k in strings:
        head, _, rest = k.partition(" ")
        if head == key and rest and all(PLACEHOLDER_RE.fullmatch(t) for t in rest.split(" ")):
            return True
    return False


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
            code_block_depth = 0
            for lineno, line in enumerate(source.splitlines(), 1):
                if code_block_depth > 0 or CODE_BLOCK_RE.search(line):
                    code_block_depth += line.count("{") - line.count("}")
                    continue
                stripped = line.strip()
                if stripped.startswith("//") or any(marker.lower() in line.lower() for marker in ALLOW_MARKERS):
                    continue
                for literal in LITERAL_RE.findall(line):
                    if literal == "" or literal.startswith("\\(") or literal.startswith("--"):
                        continue
                    if "\\(" in literal and KEY_RE.match(literal.split(" ", 1)[0]):
                        candidates = interpolated_candidates(literal)
                        if not any(c in strings for c in candidates):
                            errors.append(f"{path.relative_to(ROOT)}:{lineno}: interpolated key '{candidates[0]}' (or a %lld variant) missing from catalog")
                    elif KEY_RE.match(literal):
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
    for name in enum_cases(DOMAIN / "Drafts/OtherCostKind.swift", "OtherCostKind"): generated.add(f"otherCost.{name}")
    for tpl in ["depositFinal", "depositProgressFinal", "fourStage", "custom"]: generated.add(f"schedule.template.{tpl}")
    for row in ["deposit", "progress", "stage2", "stage3", "final", "labourQuick"]: generated.add(f"schedule.row.{row}")
    for phase in ["all", "inWork", "preStart", "workDone", "terminal"]: generated.add(f"projects.filter.{phase}")
    for name in enum_cases(DOMAIN / "Payments/PaymentStatusResolver.swift", "PaymentStatus"): generated.add(f"payment.status.{name}")
    for name in enum_cases(DOMAIN / "Entities/Enums.swift", "CostGroup"): generated.add(f"costGroup.{name}")
    for name in enum_cases(DOMAIN / "Entities/Enums.swift", "ProjectStatus"):
        generated.add(f"status.{name}"); generated.add(f"status.{name}.hint")
    for name in enum_cases(DOMAIN / "Entities/ActivityLog.swift", "ActivityAction"): generated.add(f"activity.{name}")
    for name in enum_cases(DOMAIN / "Health/ProjectHealthEvaluator.swift", "HealthStatus"): generated.add(f"health.status.{name}")
    for name in enum_cases(DOMAIN / "Drafts/TimelineValidator.swift", "TimelineError"): generated.add(f"timeline.error.{name}")
    # Parameterised families: the catalog key carries placeholders ("health.reason.paymentOverdue %lld").
    families: set[str] = set()
    for name in enum_cases(DOMAIN / "Health/ProjectHealthEvaluator.swift", "HealthReason"): families.add(f"health.reason.{name}")
    for key in sorted(generated):
        if key not in strings: errors.append(f"generated key '{key}' missing from catalog")
    for key in sorted(families):
        if not has_key_family(key, strings): errors.append(f"generated key family '{key} ...' missing from catalog")
    for e in errors:
        print(e)
    print(f"check_localization: {len(strings)} keys, {len(generated) + len(families)} generated, {len(errors)} error(s)")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
