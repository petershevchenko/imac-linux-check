#!/usr/bin/env python3
"""Generate data/index.json from the model and component files.

The index is a CI-generated manifest: it is never hand-edited. CI regenerates
it and fails if the committed copy differs, so the output MUST be deterministic
(sorted keys, no timestamps).

Usage:
    scripts/gen-index.py            # rewrite data/index.json
    scripts/gen-index.py --check    # exit non-zero if data/index.json is stale
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"
INDEX_PATH = DATA_DIR / "index.json"


def _load(path: Path) -> dict:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def build_index() -> dict:
    models = {}
    for path in sorted((DATA_DIR / "models").glob("*.json")):
        rec = _load(path)
        models[rec["model_identifier"]] = {
            "file": f"models/{path.name}",
            "marketing_name": rec["marketing_name"],
            "components": sorted(rec.get("components", [])),
        }

    components = {}
    for path in sorted((DATA_DIR / "components").glob("*.json")):
        rec = _load(path)
        components[rec["id"]] = {
            "file": f"components/{path.name}",
            "category": rec["category"],
            "status": rec["linux"]["status"],
        }

    return {
        "schema_version": 1,
        "generated_by": "scripts/gen-index.py",
        "models": models,
        "components": components,
    }


def render(index: dict) -> str:
    return json.dumps(index, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit non-zero if data/index.json is out of date instead of rewriting it",
    )
    args = parser.parse_args()

    rendered = render(build_index())

    if args.check:
        current = INDEX_PATH.read_text(encoding="utf-8") if INDEX_PATH.exists() else ""
        if current != rendered:
            sys.stderr.write(
                "data/index.json is out of date. Run: scripts/gen-index.py\n"
            )
            return 1
        return 0

    INDEX_PATH.write_text(rendered, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
