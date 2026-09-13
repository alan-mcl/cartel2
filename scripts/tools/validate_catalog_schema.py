#!/usr/bin/env python3
"""Validate catalog JSON against schema rules. Generated — do not edit."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "data" / "catalog"
SCHEMA_DIR = ROOT / "data" / "catalog" / "schema"

REF_CATALOG_FILES = {
    "chassis": "chassis.json",
    "modules": "modules/",
    "ammunition": "ammunition.json",
    "commodities": "commodities.json"
}

TYPE_CHECKS = {
    "string": lambda v: isinstance(v, str),
    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "array": lambda v: isinstance(v, list),
    "object": lambda v: isinstance(v, dict),
}

SCHEMA_TARGETS = [
    ("ammunition.json", SCHEMA_DIR / "ammunition.schema.json"),
    ("chassis.json", SCHEMA_DIR / "chassis.schema.json"),
    ("commodities.json", SCHEMA_DIR / "commodities.schema.json"),
    ("economies.json", SCHEMA_DIR / "economies.schema.json"),
    ("modules/", SCHEMA_DIR / "modules.schema.json"),
    ("sectors.json", SCHEMA_DIR / "sectors.schema.json"),
    ("ships.json", SCHEMA_DIR / "ships.schema.json"),
]

def load_array(filename: str) -> list:
    path = CATALOG / filename
    if filename.endswith('/'):
        merged: list = []
        module_dir = CATALOG / filename.rstrip('/')
        for child in sorted(module_dir.glob('*.json')):
            data = json.loads(child.read_text(encoding='utf-8'))
            if not isinstance(data, list):
                raise ValueError(f'{child.name} must contain a JSON array')
            merged.extend(data)
        return merged
    return json.loads(path.read_text(encoding='utf-8'))

def index_by_id(items: list) -> dict:
    return {
        item['id']: item
        for item in items
        if isinstance(item, dict) and item.get('id')
    }

def resolve_ref(schema: dict, ref: str) -> dict:
    node = schema
    for part in ref[2:].split('/'):
        node = node[part]
    return node

def check_type(value, expected: str) -> bool:
    if expected == 'any':
        return True
    checker = TYPE_CHECKS.get(expected)
    return checker(value) if checker else True

def validate_object(
    value: dict,
    schema: dict,
    label: str,
    path: str,
) -> list[str]:
    errors: list[str] = []
    props = schema.get('properties', {})
    required = set(schema.get('required', []))
    for key in required:
        if key not in value:
            errors.append(f'{label}: missing required field {path}{key}')
    if schema.get('additionalProperties') is False:
        allowed = set(props.keys())
        for key in value:
            if key not in allowed:
                errors.append(f'{label}: unknown field {path}{key}')
    for key, prop in props.items():
        if key not in value:
            continue
        sub_path = f'{path}{key}.'
        item = value[key]
        if '$ref' in prop:
            ref_schema = resolve_ref(schema, prop['$ref'])
            if not isinstance(item, dict):
                errors.append(f'{label}: {path}{key} must be an object')
                continue
            errors.extend(validate_object(item, ref_schema, label, sub_path))
            continue
        prop_type = prop.get('type', 'any')
        if not check_type(item, prop_type):
            errors.append(f'{label}: {path}{key} expected {prop_type}')
            continue
        if prop_type == 'array':
            item_schema = prop.get('items', {})
            item_type = item_schema.get('type', 'any')
            for idx, element in enumerate(item):
                if not check_type(element, item_type):
                    errors.append(f'{label}: {path}{key}[{idx}] expected {item_type}')
        if prop_type == 'object':
            if prop.get('properties'):
                if not isinstance(item, dict):
                    errors.append(f'{label}: {path}{key} must be an object')
                else:
                    errors.extend(validate_object(item, prop, label, sub_path))
            elif isinstance(item, dict):
                val_type = (prop.get('additionalProperties') or {}).get('type')
                if val_type:
                    for sub_key, sub_val in item.items():
                        if not check_type(sub_val, val_type):
                            errors.append(
                                f'{label}: {path}{key}.{sub_key} expected {val_type}'
                            )
        if 'enum' in prop and item not in prop['enum']:
            errors.append(f'{label}: {path}{key} invalid value {item!r}')
    return errors

def validate_refs(
    indexes: dict[str, dict],
    catalog_file: str,
    schema: dict,
) -> list[str]:
    errors: list[str] = []
    for entry in indexes[catalog_file].values():
        entry_id = str(entry.get('id', '?'))
        for key, prop in schema.get('properties', {}).items():
            ref_catalog = prop.get('x-ref-catalog')
            if ref_catalog:
                ref_val = str(entry.get(key, ''))
                target_file = REF_CATALOG_FILES[ref_catalog]
                if ref_val and ref_val not in indexes.get(target_file, {}):
                    errors.append(
                        f"{catalog_file} {entry_id}: unknown {key} '{ref_val}'"
                    )
            if prop.get('type') == 'array':
                items = prop.get('items', {})
                ref_catalog = items.get('x-ref-catalog')
                if ref_catalog:
                    target_file = REF_CATALOG_FILES[ref_catalog]
                    for item in entry.get(key, []):
                        ref_val = str(item)
                        if ref_val and ref_val not in indexes.get(target_file, {}):
                            errors.append(
                                f"{catalog_file} {entry_id}: unknown {key} item '{ref_val}'"
                            )
            if prop.get('type') == 'object':
                property_names = prop.get('propertyNames', {})
                ref_catalog = property_names.get('x-ref-catalog')
                if ref_catalog:
                    target_file = REF_CATALOG_FILES[ref_catalog]
                    obj = entry.get(key, {})
                    if isinstance(obj, dict):
                        for sub_key in obj.keys():
                            ref_val = str(sub_key)
                            if ref_val and ref_val not in indexes.get(target_file, {}):
                                errors.append(
                                    f"{catalog_file} {entry_id}: unknown {key} key '{ref_val}'"
                                )
    return errors

def main() -> int:
    errors: list[str] = []
    indexes: dict[str, dict] = {}
    for catalog_file, schema_path in SCHEMA_TARGETS:
        schema = json.loads(schema_path.read_text(encoding='utf-8'))
        items = load_array(catalog_file)
        indexes[catalog_file] = index_by_id(items)
        for entry in items:
            if not isinstance(entry, dict):
                errors.append(f'{catalog_file}: entry must be an object')
                continue
            entry_id = str(entry.get('id', '?'))
            label = f'{catalog_file} {entry_id}'
            errors.extend(validate_object(entry, schema, label, ''))
        errors.extend(validate_refs(indexes, catalog_file, schema))
    if errors:
        for err in errors:
            print(f'ERROR: {err}', file=sys.stderr)
        return 1
    print('OK: catalog schema validated.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
