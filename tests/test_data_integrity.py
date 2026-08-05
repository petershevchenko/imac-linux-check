#!/usr/bin/env python3
"""Data-integrity checks for data/.

Runnable two ways:

    python3 tests/test_data_integrity.py     # prints a report, non-zero exit on failure
    pytest tests/test_data_integrity.py       # discovered as test_* functions

Checks (failures):
  * every file in data/models and data/components validates against its schema
  * every component ID referenced by a model (including variant replacements) exists
  * data/index.json matches what gen-index.py would produce now

Checks (warnings only, never fail the build):
  * orphan components not referenced by any model
  * records whose last_verified is more than 24 months old
"""

from __future__ import annotations

import datetime as _dt
import json
import sys
from pathlib import Path

from jsonschema import Draft7Validator

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"
SCHEMA_DIR = REPO_ROOT / "schema"
MODELS_DIR = DATA_DIR / "models"
COMPONENTS_DIR = DATA_DIR / "components"

STALE_AFTER_DAYS = 24 * 30  # ~24 months


def _load(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def _model_files() -> list[Path]:
    return sorted(MODELS_DIR.glob("*.json"))


def _component_files() -> list[Path]:
    return sorted(COMPONENTS_DIR.glob("*.json"))


def _referenced_component_ids() -> set[str]:
    refs: set[str] = set()
    for path in _model_files():
        rec = _load(path)
        refs.update(rec.get("components", []))
        for variant in rec.get("variants", []):
            refs.update(variant.get("components_replace", {}).values())
    return refs


# --- failure checks -------------------------------------------------------


def check_schemas() -> list[str]:
    errors: list[str] = []
    pairs = [
        (_component_files(), _load(SCHEMA_DIR / "component.schema.json")),
        (_model_files(), _load(SCHEMA_DIR / "model.schema.json")),
    ]
    for files, schema in pairs:
        validator = Draft7Validator(schema)
        for path in files:
            rec = _load(path)
            for err in sorted(validator.iter_errors(rec), key=lambda e: e.path):
                loc = "/".join(str(p) for p in err.path) or "(root)"
                errors.append(f"{path.relative_to(REPO_ROOT)}: {loc}: {err.message}")
    return errors


def check_filename_matches_id() -> list[str]:
    errors: list[str] = []
    for path in _component_files():
        rec = _load(path)
        if path.stem != rec["id"]:
            errors.append(
                f"{path.relative_to(REPO_ROOT)}: filename stem '{path.stem}' "
                f"!= id '{rec['id']}'"
            )
    return errors


def check_referential_integrity() -> list[str]:
    existing = {_load(p)["id"] for p in _component_files()}
    errors: list[str] = []
    for path in _model_files():
        rec = _load(path)
        ids = list(rec.get("components", []))
        for variant in rec.get("variants", []):
            ids.extend(variant.get("components_replace", {}).values())
        for cid in ids:
            if cid not in existing:
                errors.append(
                    f"{path.relative_to(REPO_ROOT)}: references missing component '{cid}'"
                )
    return errors


def check_index_fresh() -> list[str]:
    sys.path.insert(0, str(REPO_ROOT / "scripts"))
    import importlib.util

    spec = importlib.util.spec_from_file_location(
        "gen_index", REPO_ROOT / "scripts" / "gen-index.py"
    )
    gen_index = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen_index)

    expected = gen_index.render(gen_index.build_index())
    index_path = DATA_DIR / "index.json"
    current = index_path.read_text(encoding="utf-8") if index_path.exists() else ""
    if current != expected:
        return ["data/index.json is out of date. Run: scripts/gen-index.py"]
    return []


# --- warning checks -------------------------------------------------------


def warn_orphans() -> list[str]:
    referenced = _referenced_component_ids()
    warnings: list[str] = []
    for path in _component_files():
        cid = _load(path)["id"]
        if cid not in referenced:
            warnings.append(f"orphan component not referenced by any model: {cid}")
    return warnings


def warn_stale() -> list[str]:
    today = _dt.date.today()
    warnings: list[str] = []
    for path in _component_files() + _model_files():
        rec = _load(path)
        prov = rec.get("provenance") or rec.get("linux", {}).get("provenance")
        if not prov:
            continue
        try:
            when = _dt.date.fromisoformat(prov["last_verified"])
        except (KeyError, ValueError):
            continue
        age = (today - when).days
        if age > STALE_AFTER_DAYS:
            months = age // 30
            warnings.append(
                f"{path.relative_to(REPO_ROOT)}: last_verified is ~{months} months old "
                f"({prov['last_verified']})"
            )
    return warnings


# --- pytest entry points --------------------------------------------------


def test_schemas():
    assert not check_schemas()


def test_filename_matches_id():
    assert not check_filename_matches_id()


def test_referential_integrity():
    assert not check_referential_integrity()


def test_index_fresh():
    assert not check_index_fresh()


# --- standalone runner ----------------------------------------------------


def main() -> int:
    failure_checks = [
        ("schema validation", check_schemas),
        ("filename == id", check_filename_matches_id),
        ("referential integrity", check_referential_integrity),
        ("index freshness", check_index_fresh),
    ]
    warning_checks = [
        ("orphan components", warn_orphans),
        ("staleness (>24 months)", warn_stale),
    ]

    failed = False
    for label, fn in failure_checks:
        problems = fn()
        if problems:
            failed = True
            print(f"FAIL  {label}")
            for p in problems:
                print(f"        {p}")
        else:
            print(f"ok    {label}")

    for label, fn in warning_checks:
        for w in fn():
            print(f"WARN  {label}: {w}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
