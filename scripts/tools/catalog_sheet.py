#!/usr/bin/env python3
"""Export catalog record tables to CSV for spreadsheet editing and import changes back.

JSON under data/catalog/ remains the source of truth. CSV files are scratch sheets;
do not commit them.

Usage:
  python3 scripts/tools/catalog_sheet.py list
  python3 scripts/tools/catalog_sheet.py export passenger.descriptions -o /tmp/descriptions.csv
  python3 scripts/tools/catalog_sheet.py import passenger.descriptions -i /tmp/descriptions.csv

Spreadsheets in locales that default to semicolon separators must still import comma-
delimited CSV (blurbs and descriptions contain commas). Use explicit comma separator
on import in LibreOffice Calc / Excel.

Targets are discovered automatically (modules, commodities, mission roles/descriptions,
corporate presence matrix, etc.). worlds.json, player.json, and traffic.json string
lists are excluded.
"""

from __future__ import annotations

import argparse
import copy
import csv
import json
import re
import sys
from dataclasses import dataclass
from json import JSONDecoder
from pathlib import Path
from typing import Any

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import CATALOG, MODULES_DIR, load_array, load_object

_DECODER = JSONDecoder()

_OBJECT_PREFIX = {
    "passenger_missions.json": "passenger",
    "freight_missions.json": "freight",
    "backgrounds.json": "backgrounds",
}

_SKIP_TOP_LEVEL = frozenset(
    {
        "worlds.json",
        "player.json",
        "traffic.json",
        "corporate_presence.json",
        "passenger_missions.json",
        "freight_missions.json",
        "backgrounds.json",
    }
)


@dataclass(frozen=True)
class Target:
    target_id: str
    path: Path
    kind: str  # records | settings | matrix
    array_key: str | None = None  # key inside object file for records


def is_scalar_map(value: Any) -> bool:
    if not isinstance(value, dict):
        return False
    for v in value.values():
        if isinstance(v, dict):
            return False
        if isinstance(v, list):
            return False
    return True


def is_id_record_array(value: Any) -> bool:
    return (
        isinstance(value, list)
        and len(value) > 0
        and all(isinstance(x, dict) and x.get("id") for x in value)
    )


def discover_targets(catalog: Path = CATALOG) -> list[Target]:
    targets: list[Target] = []

    for fname, prefix in sorted(_OBJECT_PREFIX.items()):
        path = catalog / fname
        if not path.is_file():
            continue
        data = load_object(path)
        for key, value in data.items():
            if is_id_record_array(value):
                targets.append(
                    Target(f"{prefix}.{key}", path, "records", array_key=key)
                )
        targets.append(Target(f"{prefix}.settings", path, "settings"))

    for path in sorted(catalog.glob("*.json")):
        if path.name in _SKIP_TOP_LEVEL:
            continue
        raw = path.read_text(encoding="utf-8")
        data = json.loads(raw)
        if isinstance(data, list) and is_id_record_array(data):
            targets.append(Target(path.stem, path, "records"))

    if MODULES_DIR.is_dir():
        for path in sorted(MODULES_DIR.glob("*.json")):
            data = load_array(path)
            if is_id_record_array(data):
                targets.append(
                    Target(f"modules/{path.stem}", path, "records")
                )

    cp = catalog / "corporate_presence.json"
    if cp.is_file():
        targets.append(Target("corporate_presence", cp, "matrix"))

    return targets


def resolve_target(target_id: str, catalog: Path = CATALOG) -> Target:
    for t in discover_targets(catalog):
        if t.target_id == target_id:
            return t
    raise SystemExit(f"Unknown target {target_id!r}. Run list for available targets.")


def flatten_value(prefix: str, value: Any, out: dict[str, str]) -> None:
    if isinstance(value, dict) and is_scalar_map(value):
        for sub_key, sub_val in value.items():
            flatten_value(f"{prefix}.{sub_key}", sub_val, out)
        return
    if isinstance(value, list) and all(isinstance(x, str) for x in value):
        out[prefix] = ";".join(value) if value else "[]"
        return
    if isinstance(value, list) and len(value) == 0:
        out[prefix] = "[]"
        return
    if isinstance(value, bool):
        out[prefix] = "true" if value else "false"
        return
    if isinstance(value, int) and not isinstance(value, bool):
        out[prefix] = str(value)
        return
    if isinstance(value, float):
        out[prefix] = str(value)
        return
    if isinstance(value, str):
        out[prefix] = value
        return
    out[prefix] = json.dumps(value, ensure_ascii=False)


def flatten_record(record: dict) -> dict[str, str]:
    out: dict[str, str] = {"id": str(record["id"])}
    for key, value in record.items():
        if key == "id":
            continue
        flatten_value(key, value, out)
    return out


def column_order(records: list[dict]) -> list[str]:
    cols: list[str] = ["id"]
    seen: set[str] = {"id"}
    for record in records:
        flat = flatten_record(record)
        for key in flat:
            if key not in seen:
                seen.add(key)
                cols.append(key)
    return cols


def collect_column_hints(records: list[dict]) -> dict[str, Any]:
    hints: dict[str, Any] = {}
    for record in records:
        for key, value in _walk_leaves(record):
            if key not in hints:
                hints[key] = value
    return hints


def _walk_leaves(record: dict, prefix: str = "") -> list[tuple[str, Any]]:
    out: list[tuple[str, Any]] = []
    for key, value in record.items():
        path = f"{prefix}.{key}" if prefix else key
        if key == "id":
            out.append((path, value))
            continue
        if isinstance(value, dict) and is_scalar_map(value):
            out.extend(_walk_leaves(value, path))
        else:
            out.append((path, value))
    return out


def parse_cell(cell: str, hint: Any | None) -> Any:
    if cell == "[]":
        return []
    if hint is not None:
        if isinstance(hint, bool):
            lowered = cell.strip().lower()
            if lowered in ("true", "1", "yes"):
                return True
            if lowered in ("false", "0", "no"):
                return False
            raise ValueError(f"Expected boolean, got {cell!r}")
        if isinstance(hint, int) and not isinstance(hint, bool):
            return int(cell)
        if isinstance(hint, float):
            return float(cell)
        if isinstance(hint, list):
            if all(isinstance(x, str) for x in hint):
                if cell == "":
                    return []
                return [part.strip() for part in cell.split(";") if part.strip()]
            return json.loads(cell)
        if isinstance(hint, dict):
            return json.loads(cell)
        return cell

    cell = cell.strip()
    if cell == "":
        return None
    if cell.startswith(("{", "[")):
        return json.loads(cell)
    lowered = cell.lower()
    if lowered in ("true", "false"):
        return lowered == "true"
    try:
        if re.fullmatch(r"-?\d+", cell):
            return int(cell)
        if re.fullmatch(r"-?\d+\.\d+", cell):
            return float(cell)
    except ValueError:
        pass
    return cell


def set_nested(target: dict, dotted: str, value: Any) -> None:
    parts = dotted.split(".")
    node = target
    for part in parts[:-1]:
        if part not in node or not isinstance(node[part], dict):
            node[part] = {}
        node = node[part]
    node[parts[-1]] = value


def del_nested(target: dict, dotted: str) -> None:
    parts = dotted.split(".")
    node = target
    for part in parts[:-1]:
        if not isinstance(node, dict) or part not in node:
            return
        node = node[part]
    if isinstance(node, dict):
        node.pop(parts[-1], None)
        # prune empty parent objects
        if parts[:-1]:
            _prune_empty_parents(target, parts[:-1])


def _prune_empty_parents(root: dict, parts: list[str]) -> None:
    if not parts:
        return
    node: Any = root
    stack: list[tuple[dict, str]] = []
    for part in parts:
        if not isinstance(node, dict) or part not in node:
            return
        stack.append((node, part))
        node = node[part]
    for parent, key in reversed(stack):
        child = parent.get(key)
        if isinstance(child, dict) and not child:
            del parent[key]
        else:
            break


def unflatten_row(row: dict[str, str], hints: dict[str, Any]) -> dict:
    record: dict[str, Any] = {"id": row["id"]}
    for col, cell in row.items():
        if col == "id":
            continue
        if cell == "":
            continue
        hint = hints.get(col)
        value = parse_cell(cell, hint)
        if "." in col:
            set_nested(record, col, value)
        else:
            record[col] = value
    return record


def record_from_row(
    existing: dict | None,
    row: dict[str, str],
    cols: list[str],
    hints: dict[str, Any],
) -> dict:
    record = copy.deepcopy(existing) if existing else {}
    record["id"] = row["id"]
    for col in cols:
        if col == "id":
            continue
        cell = row.get(col, "")
        if cell == "":
            if existing is not None:
                if "." in col:
                    del_nested(record, col)
                else:
                    record.pop(col, None)
            continue
        value = parse_cell(cell, hints.get(col))
        if "." in col:
            set_nested(record, col, value)
        else:
            record[col] = value
    return record


def values_equal(a: Any, b: Any) -> bool:
    if isinstance(a, float) and isinstance(b, float):
        return abs(a - b) < 1e-12
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(float(a) - float(b)) < 1e-12
    return a == b


def records_equal(a: dict, b: dict) -> bool:
    return json.dumps(a, sort_keys=True, ensure_ascii=False) == json.dumps(
        b, sort_keys=True, ensure_ascii=False
    )


def serialize_record(obj: dict, original_span: str | None) -> str:
    single_line = original_span is None or "\n" not in original_span
    if single_line:
        return json.dumps(obj, ensure_ascii=False, separators=(", ", ": "))
    return json.dumps(obj, indent=2, ensure_ascii=False)


def try_patch_record_span(span: str, old: dict, new: dict) -> str | None:
    """Patch only top-level scalar fields in an existing record span."""
    if old.get("id") != new.get("id"):
        return None
    changed: list[tuple[str, Any]] = []
    for key in set(old.keys()) | set(new.keys()):
        if key == "id":
            continue
        old_val = old.get(key)
        new_val = new.get(key)
        if values_equal(old_val, new_val):
            continue
        if isinstance(old_val, (dict, list)) or isinstance(new_val, (dict, list)):
            return None
        changed.append((key, new_val))
    if not changed:
        return span
    result = span
    for key, new_val in changed:
        pattern = re.compile(
            rf'("{re.escape(key)}"\s*:\s*)'
            rf"(-?\d+(?:\.\d+)?|true|false|null|\"[^\"\\]*(?:\\.[^\"\\]*)*\")"
        )
        match = pattern.search(result)
        if not match:
            return None
        new_token = _format_scalar(new_val, match.group(2))
        result = result[: match.start(2)] + new_token + result[match.end(2) :]
    return result


def record_text(span: str, old_rec: dict, new_rec: dict) -> str:
    if records_equal(old_rec, new_rec):
        return span
    patched = try_patch_record_span(span, old_rec, new_rec)
    if patched is not None:
        return patched
    return serialize_record(new_rec, span)


def parse_top_level_array_spans(text: str) -> tuple[list[Any], list[tuple[int, int]], int, int]:
    text = text.lstrip()
    if not text.startswith("["):
        raise ValueError("Expected top-level JSON array")
    array_start = 0
    idx = 1
    n = len(text)
    values: list[Any] = []
    spans: list[tuple[int, int]] = []
    while idx < n:
        while idx < n and text[idx] in " \t\r\n,":
            idx += 1
        if idx >= n:
            break
        if text[idx] == "]":
            array_end = idx + 1
            break
        start = idx
        value, end = _DECODER.raw_decode(text, idx)
        values.append(value)
        spans.append((start, end))
        idx = end
    else:
        raise ValueError("Unclosed JSON array")
    while idx < n and text[idx] in " \t\r\n,":
        idx += 1
    if idx >= n or text[idx] != "]":
        raise ValueError("Malformed JSON array")
    array_end = idx + 1
    return values, spans, array_start, array_end


def _find_object_key_array(
    text: str, key: str
) -> tuple[list[Any], list[tuple[int, int]], int, int]:
    pattern = re.compile(rf'"{re.escape(key)}"\s*:\s*\[')
    match = pattern.search(text)
    if not match:
        raise ValueError(f'Key "{key}" array not found')
    bracket_start = match.end() - 1
    idx = bracket_start + 1
    n = len(text)
    values: list[Any] = []
    spans: list[tuple[int, int]] = []
    while idx < n:
        while idx < n and text[idx] in " \t\r\n,":
            idx += 1
        if idx >= n:
            break
        if text[idx] == "]":
            array_end = idx + 1
            break
        start = idx
        value, end = _DECODER.raw_decode(text, idx)
        values.append(value)
        spans.append((start, end))
        idx = end
    else:
        raise ValueError(f'Unclosed array for key "{key}"')
    return values, spans, bracket_start, array_end


def rebuild_array_simple(
    text: str,
    array_start: int,
    array_end: int,
    old_values: list[dict],
    old_spans: list[tuple[int, int]],
    new_values: list[dict],
) -> str:
    """Preserve bytes between elements; reserialize only changed/new records."""
    if (
        len(new_values) == len(old_values)
        and [r["id"] for r in new_values] == [r["id"] for r in old_values]
        and all(records_equal(n, o) for n, o in zip(new_values, old_values))
    ):
        return text

    old_by_id = {v["id"]: (v, span) for v, span in zip(old_values, old_spans)}
    old_id_index = {v["id"]: i for i, v in enumerate(old_values)}
    if len(old_spans) >= 2:
        default_sep = text[old_spans[0][1] : old_spans[1][0]]
    elif "\n" in text[array_start:array_end]:
        default_sep = ",\n    "
    else:
        default_sep = ", "
    def unchanged(rec: dict) -> bool:
        rid = rec["id"]
        if rid not in old_by_id:
            return False
        return records_equal(old_by_id[rid][0], rec)

    parts: list[str] = [text[array_start : array_start + 1]]
    if new_values and old_spans:
        parts.append(text[array_start + 1 : old_spans[0][0]])

    for i, record in enumerate(new_values):
        rid = record["id"]
        if i > 0:
            prev = new_values[i - 1]
            prev_id = prev["id"]
            if (
                unchanged(prev)
                and unchanged(record)
                and old_id_index.get(prev_id, -1) + 1 == old_id_index.get(rid, -2)
            ):
                _, (_, pe) = old_by_id[prev_id]
                cs, _ = old_by_id[rid][1]
                parts.append(text[pe:cs])
            else:
                parts.append(default_sep)

        if rid in old_by_id:
            old_rec, (s, e) = old_by_id[rid]
            parts.append(record_text(text[s:e], old_rec, record))
        else:
            parts.append(serialize_record(record, None))

    if new_values:
        same_length_and_order = len(new_values) == len(old_values) and [
            r["id"] for r in new_values
        ] == [r["id"] for r in old_values]
        if same_length_and_order and unchanged(new_values[-1]):
            _, (_, le) = old_by_id[new_values[-1]["id"]]
            parts.append(text[le:array_end])
        else:
            inner = text[array_start:array_end]
            match = re.search(r"\n(\s*)\]", inner)
            if match:
                parts.append("\n" + match.group(1) + "]")
            elif "\n" in inner:
                parts.append("\n]")
            else:
                parts.append("]")
    else:
        parts.append(text[array_start + 1 : array_end])

    return text[:array_start] + "".join(parts) + text[array_end:]


def load_records_for_target(target: Target, catalog: Path = CATALOG) -> list[dict]:
    if target.kind == "records":
        if target.array_key:
            data = load_object(target.path)
            return data[target.array_key]
        return load_array(target.path)
    raise ValueError(f"Target {target.target_id} is not a record table")


def export_records(target: Target, out_path: Path) -> None:
    records = load_records_for_target(target)
    cols = column_order(records)
    with out_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        writer.writeheader()
        for record in records:
            flat = flatten_record(record)
            writer.writerow({c: flat.get(c, "") for c in cols})


def export_settings(target: Target, out_path: Path) -> None:
    data = load_object(target.path)
    rows: list[tuple[str, str]] = []
    for key, value in data.items():
        if isinstance(value, list) or (
            isinstance(value, dict) and not is_scalar_map(value)
        ):
            continue
        if key == "hop_offer_weights" and isinstance(value, dict):
            for sub_key, sub_val in value.items():
                rows.append((f"hop_offer_weights.{sub_key}", str(sub_val)))
            continue
        if isinstance(value, (int, float, str, bool)):
            rows.append((key, str(value).lower() if isinstance(value, bool) else str(value)))
    with out_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["key", "value"])
        writer.writerows(rows)


def export_matrix(target: Target, out_path: Path) -> None:
    data = load_object(target.path)
    corps: list[str] = []
    seen: set[str] = set()
    for sector_weights in data.values():
        if not isinstance(sector_weights, dict):
            continue
        for corp in sector_weights:
            if corp not in seen:
                seen.add(corp)
                corps.append(corp)
    corps.sort()
    cols = ["id", *corps]
    with out_path.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=cols)
        writer.writeheader()
        for sector_id in data:
            row = {"id": sector_id}
            weights = data[sector_id]
            for corp in corps:
                row[corp] = weights.get(corp, "")
            writer.writerow(row)


def export_target(target: Target, out_path: Path) -> None:
    if target.kind == "records":
        export_records(target, out_path)
    elif target.kind == "settings":
        export_settings(target, out_path)
    elif target.kind == "matrix":
        export_matrix(target, out_path)
    else:
        raise ValueError(f"Unknown kind {target.kind}")


def read_csv_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as fh:
        reader = csv.DictReader(fh)
        if reader.fieldnames is None:
            raise ValueError("CSV has no header")
        cols = list(reader.fieldnames)
        rows = [{k: (row.get(k) or "").strip() for k in cols} for row in reader]
    return cols, rows


def import_records(
    target: Target,
    in_path: Path,
    drop_missing: bool,
    catalog: Path = CATALOG,
) -> bool:
    path = target.path
    text = path.read_text(encoding="utf-8")
    cols, rows = read_csv_rows(in_path)

    if "id" not in cols:
        raise SystemExit("CSV must include an id column")

    ids = [r["id"] for r in rows if r.get("id")]
    if len(ids) != len(set(ids)):
        raise SystemExit("Duplicate id values in CSV")

    if target.array_key:
        old_values, old_spans, a0, a1 = _find_object_key_array(text, target.array_key)
    else:
        old_values, old_spans, a0, a1 = parse_top_level_array_spans(text)

    hints = collect_column_hints(old_values)
    unknown = [c for c in cols if c != "id" and c not in hints]
    # allow new columns if they look like dotted paths? Plan says unknown columns are errors
    if unknown:
        raise SystemExit(f"Unknown columns: {', '.join(unknown)}")

    old_by_id = {r["id"]: r for r in old_values}
    sheet_by_id = {r["id"]: r for r in rows if r.get("id")}

    new_order: list[dict] = []
    for old in old_values:
        oid = old["id"]
        if oid in sheet_by_id:
            new_order.append(record_from_row(old, sheet_by_id[oid], cols, hints))
        elif not drop_missing:
            new_order.append(old)

    for rid, row in sheet_by_id.items():
        if rid not in old_by_id:
            new_order.append(record_from_row(None, row, cols, hints))

    new_text = rebuild_array_simple(text, a0, a1, old_values, old_spans, new_order)
    if new_text != text:
        path.write_text(new_text, encoding="utf-8")
        return True
    return False


def _replace_scalar_at(text: str, key: str, new_raw: str) -> tuple[str, bool]:
    pattern = re.compile(
        rf'("{re.escape(key)}"\s*:\s*)(-?\d+(?:\.\d+)?|true|false|null|"[^"\\]*(?:\\.[^"\\]*)*")'
    )
    match = pattern.search(text)
    if not match:
        raise ValueError(f"Scalar key {key!r} not found")
    start, end = match.span(2)
    old = text[start:end]
    if old == new_raw:
        return text, False
    return text[:start] + new_raw + text[end:], True


def _format_scalar(value: Any, old_token: str | None) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int) and not isinstance(value, bool):
        if old_token and re.fullmatch(r"-?\d+", old_token):
            return str(value)
        return str(value)
    if isinstance(value, float):
        if old_token and re.fullmatch(r"-?\d+\.\d+", old_token):
            return str(value)
        if old_token and re.fullmatch(r"-?\d+", old_token) and float(value) == int(value):
            return old_token
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    return json.dumps(value, ensure_ascii=False)


def import_settings(target: Target, in_path: Path) -> bool:
    path = target.path
    text = path.read_text(encoding="utf-8")
    data = load_object(path)
    _, rows = read_csv_rows(in_path)
    changed = False
    hop_updates: dict[str, float | int] = {}
    for row in rows:
        key = row.get("key", "")
        if not key:
            continue
        val_cell = row.get("value", "")
        if key.startswith("hop_offer_weights."):
            sub = key.split(".", 1)[1]
            new_val: float | int = float(val_cell) if "." in val_cell else int(val_cell)
            old_val = data.get("hop_offer_weights", {}).get(sub)
            if not values_equal(old_val, new_val):
                hop_updates[sub] = new_val
            continue

        old_val = data.get(key)
        if isinstance(old_val, bool):
            new_val = val_cell.lower() in ("true", "1", "yes")
        elif isinstance(old_val, int) and not isinstance(old_val, bool):
            new_val = int(val_cell)
        elif isinstance(old_val, float):
            new_val = float(val_cell)
        else:
            new_val = val_cell
        if values_equal(old_val, new_val):
            continue
        pattern = re.compile(
            rf'("{re.escape(key)}"\s*:\s*)(-?\d+(?:\.\d+)?|true|false|null|"[^"\\]*(?:\\.[^"\\]*)*")'
        )
        match = pattern.search(text)
        if not match:
            raise ValueError(f"Key {key!r} not found in JSON")
        old_token = match.group(2)
        new_token = _format_scalar(new_val, old_token)
        if old_token == new_token:
            continue
        s, e = match.span(2)
        text = text[:s] + new_token + text[e:]
        changed = True

    if hop_updates:
        weights = dict(data.get("hop_offer_weights", {}))
        weights.update(hop_updates)
        pattern = re.compile(r'"hop_offer_weights"\s*:\s*\{')
        match = pattern.search(text)
        if not match:
            raise ValueError("hop_offer_weights not found")
        start = match.end() - 1
        _, end = _DECODER.raw_decode(text, start)
        new_obj = json.dumps(weights, ensure_ascii=False, separators=(", ", ": "))
        text = text[:start] + new_obj + text[end:]
        changed = True

    if changed:
        path.write_text(text, encoding="utf-8")
    return changed


def parse_top_level_object_spans(text: str) -> tuple[dict[str, Any], dict[str, tuple[int, int]], int, int]:
    text = text.lstrip()
    if not text.startswith("{"):
        raise ValueError("Expected top-level object")
    obj_start = 0
    idx = 1
    n = len(text)
    keys: dict[str, Any] = {}
    spans: dict[str, tuple[int, int]] = {}
    while idx < n:
        while idx < n and text[idx] in " \t\r\n,":
            idx += 1
        if idx >= n or text[idx] == "}":
            obj_end = idx + 1
            break
        key_start = idx
        if text[idx] != '"':
            raise ValueError("Expected object key string")
        key, idx = _DECODER.raw_decode(text, idx)
        while idx < n and text[idx] in " \t\r\n":
            idx += 1
        if idx >= n or text[idx] != ":":
            raise ValueError("Expected colon after key")
        idx += 1
        while idx < n and text[idx] in " \t\r\n":
            idx += 1
        val_start = idx
        value, idx = _DECODER.raw_decode(text, idx)
        keys[key] = value
        spans[key] = (val_start, idx)
    else:
        raise ValueError("Unclosed JSON object")
    return keys, spans, obj_start, obj_end


def import_matrix(target: Target, in_path: Path) -> bool:
    path = target.path
    text = path.read_text(encoding="utf-8")
    cols, rows = read_csv_rows(in_path)
    if "id" not in cols:
        raise SystemExit("Matrix CSV must include id column (sector id)")
    corps = [c for c in cols if c != "id"]

    data, val_spans, o0, o1 = parse_top_level_object_spans(text)
    changed = False
    new_text = text

    for row in rows:
        sector = row["id"]
        if sector not in data:
            raise SystemExit(f"Unknown sector id {sector!r}")
        sector_obj = copy.deepcopy(data[sector])
        sector_changed = False
        for corp in corps:
            cell = row.get(corp, "")
            if cell == "":
                continue
            new_w = float(cell)
            old_w = sector_obj.get(corp)
            if old_w is not None and values_equal(old_w, new_w):
                continue
            sector_obj[corp] = new_w
            sector_changed = True
        if not sector_changed:
            continue
        # Replace sector value span
        pattern = re.compile(
            rf'("{re.escape(sector)}"\s*:\s*)(\{{(?:[^{{}}]|\{{[^{{}}]*\}})*\}})'
        )
        match = pattern.search(new_text)
        if not match:
            raise ValueError(f"Sector {sector!r} block not found")
        orig_val_span = new_text[match.start(2) : match.end(2)]
        single_line = "\n" not in orig_val_span
        if single_line:
            serialized = json.dumps(sector_obj, ensure_ascii=False, separators=(", ", ": "))
        else:
            serialized = json.dumps(sector_obj, indent=2, ensure_ascii=False)
        new_text = (
            new_text[: match.start(2)] + serialized + new_text[match.end(2) :]
        )
        changed = True

    if changed:
        path.write_text(new_text, encoding="utf-8")
    return changed


def import_target(
    target: Target,
    in_path: Path,
    drop_missing: bool,
    catalog: Path = CATALOG,
) -> bool:
    if target.kind == "records":
        return import_records(target, in_path, drop_missing, catalog)
    if target.kind == "settings":
        return import_settings(target, in_path)
    if target.kind == "matrix":
        return import_matrix(target, in_path)
    raise ValueError(f"Unknown kind {target.kind}")


def cmd_list(_: argparse.Namespace) -> None:
    for t in discover_targets():
        print(t.target_id)


def cmd_export(args: argparse.Namespace) -> None:
    target = resolve_target(args.target)
    out = Path(args.output)
    export_target(target, out)
    print(f"Wrote {out}")


def cmd_import(args: argparse.Namespace) -> None:
    target = resolve_target(args.target)
    inp = Path(args.input)
    if import_target(target, inp, args.drop_missing):
        print(f"Updated {target.path}")
    else:
        print("No changes")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_list = sub.add_parser("list", help="List export/import targets")
    p_list.set_defaults(func=cmd_list)

    p_exp = sub.add_parser("export", help="Export a target to CSV")
    p_exp.add_argument("target")
    p_exp.add_argument("-o", "--output", required=True)
    p_exp.set_defaults(func=cmd_export)

    p_imp = sub.add_parser("import", help="Import CSV changes into catalog JSON")
    p_imp.add_argument("target")
    p_imp.add_argument("-i", "--input", required=True)
    p_imp.add_argument(
        "--drop-missing",
        action="store_true",
        help="Remove catalog records whose ids are absent from the CSV",
    )
    p_imp.set_defaults(func=cmd_import)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
