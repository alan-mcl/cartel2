"""Shared catalog file I/O for Python validators and generators."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"
MODULES_DIR = CATALOG / "modules"


def load_array(path: Path) -> list:
    return json.loads(path.read_text(encoding="utf-8"))


def load_object(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def index_by_id(items: list) -> dict:
    return {
        item["id"]: item
        for item in items
        if isinstance(item, dict) and item.get("id")
    }


def load_modules() -> list:
    """Load all module records from data/catalog/modules/*.json in sorted order."""
    if not MODULES_DIR.is_dir():
        raise FileNotFoundError(f"Modules directory not found: {MODULES_DIR}")
    merged: list = []
    for path in sorted(MODULES_DIR.glob("*.json")):
        data = load_array(path)
        if not isinstance(data, list):
            raise ValueError(f"{path.name} must contain a JSON array")
        merged.extend(data)
    return merged


def write_module_category(category: str, modules: list) -> None:
    """Write one category file under data/catalog/modules/."""
    MODULES_DIR.mkdir(parents=True, exist_ok=True)
    path = MODULES_DIR / f"{category}.json"
    path.write_text(json.dumps(modules, indent=2) + "\n", encoding="utf-8")


def load_modules_by_category() -> dict[str, list]:
    """Return {category: [modules]} from split files."""
    by_category: dict[str, list] = {}
    for path in sorted(MODULES_DIR.glob("*.json")):
        category = path.stem
        by_category[category] = load_array(path)
    return by_category
