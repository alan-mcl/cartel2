#!/usr/bin/env python3
"""Generate typed catalog record classes, schema validator, and docs from JSON Schema."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_DIR = ROOT / "data" / "catalog" / "schema"
CATALOG_DIR = ROOT / "data" / "catalog"
RECORDS_DIR = ROOT / "scripts" / "gameplay" / "catalog_records"
VALIDATOR_PATH = ROOT / "scripts" / "tools" / "validate_catalog_schema.py"
DOCS_PATH = ROOT / "docs" / "design" / "catalog_schema.md"

GENERATED_HEADER = "## Generated — do not edit. Run scripts/tools/generate_catalog_records.py.\n"

SHARED_DEF_CLASS_NAMES = {
    "signature": "CatalogSignature",
    "damage_packets": "CatalogDamagePackets",
}

REF_CATALOG_FILES = {
    "chassis": "chassis.json",
    "modules": "modules.json",
    "ammunition": "ammunition.json",
}


@dataclass
class FieldSpec:
    name: str
    gd_type: str
    default: Any
    required: bool
    enum_values: list[str] | None = None
    nested_class: str | None = None
    is_array: bool = False
    array_item_type: str | None = None
    is_dict: bool = False


@dataclass
class ClassSpec:
    class_name: str
    catalog_file: str
    fields: list[FieldSpec] = field(default_factory=list)
    schema_path: str = ""


def load_schema(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def resolve_ref(schema: dict, ref: str) -> dict:
    if not ref.startswith("#/"):
        raise ValueError(f"Unsupported ref: {ref}")
    node: Any = schema
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def schema_default(prop: dict) -> Any:
    if "default" in prop:
        return prop["default"]
    schema_type = prop.get("type")
    if schema_type == "string":
        return ""
    if schema_type in {"number", "integer"}:
        return 0
    if schema_type == "boolean":
        return False
    if schema_type == "array":
        return []
    if schema_type == "object":
        return {}
    return None


def is_freeform_object(prop: dict) -> bool:
    if prop.get("type") != "object":
        return False
    if prop.get("properties"):
        return False
    return True


def gd_type(prop: dict) -> str:
    prop_type = prop.get("type")
    if prop_type == "string":
        return "String"
    if prop_type == "integer":
        return "int"
    if prop_type == "number":
        return "float"
    if prop_type == "boolean":
        return "bool"
    if prop_type == "array":
        return "Array"
    if prop_type == "object":
        return "Dictionary"
    return "Variant"


def shared_class_for_ref(ref: str) -> str | None:
    key = ref.split("/")[-1]
    return SHARED_DEF_CLASS_NAMES.get(key)


def build_shared_def_specs(schema_paths: list[Path]) -> dict[str, ClassSpec]:
    shared: dict[str, ClassSpec] = {}
    for schema_path in schema_paths:
        schema = load_schema(schema_path)
        defs = schema.get("$defs", {})
        for def_key, def_node in defs.items():
            class_name = SHARED_DEF_CLASS_NAMES.get(def_key)
            if not class_name or class_name in shared:
                continue
            if def_node.get("type") != "object" or not def_node.get("properties"):
                continue
            fields: list[FieldSpec] = []
            required = set(def_node.get("required", []))
            for key, prop in def_node.get("properties", {}).items():
                fields.append(
                    FieldSpec(
                        name=key,
                        gd_type=gd_type(prop),
                        default=schema_default(prop),
                        required=key in required,
                        enum_values=prop.get("enum"),
                    )
                )
            shared[class_name] = ClassSpec(
                class_name=class_name,
                catalog_file="",
                fields=fields,
                schema_path=f"$defs/{def_key}",
            )
    return shared


def field_from_property(
    key: str,
    prop: dict,
    required: set[str],
    schema: dict,
) -> FieldSpec:
    if "$ref" in prop:
        shared = shared_class_for_ref(prop["$ref"])
        ref_node = resolve_ref(schema, prop["$ref"])
        if shared:
            return FieldSpec(
                name=key,
                gd_type=shared,
                default=schema_default(ref_node),
                required=key in required,
                nested_class=shared,
            )
        if ref_node.get("additionalProperties") is not None and not ref_node.get("properties"):
            return FieldSpec(
                name=key,
                gd_type="Dictionary",
                default=schema_default(ref_node),
                required=key in required,
                is_dict=True,
            )
        raise ValueError(f"Unsupported ref {prop['$ref']}")

    if is_freeform_object(prop):
        return FieldSpec(
            name=key,
            gd_type="Dictionary",
            default=schema_default(prop),
            required=key in required,
            is_dict=True,
        )

    prop_type = prop.get("type")
    default = schema_default(prop)
    if prop_type == "array":
        item = prop.get("items", {})
        item_type = item.get("type", "")
        gd_item = "String" if item_type == "string" else "Variant"
        return FieldSpec(
            name=key,
            gd_type="Array",
            default=default,
            required=key in required,
            is_array=True,
            array_item_type=gd_item,
        )
    if prop_type == "object":
        if prop.get("additionalProperties") is not None and not prop.get("properties"):
            return FieldSpec(
                name=key,
                gd_type="Dictionary",
                default=default,
                required=key in required,
                is_dict=True,
            )
        raise ValueError(f"Unsupported inline object property {key}")

    return FieldSpec(
        name=key,
        gd_type=gd_type(prop),
        default=default,
        required=key in required,
        enum_values=prop.get("enum"),
    )


def build_class_spec(schema_path: Path) -> ClassSpec:
    schema = load_schema(schema_path)
    class_name = schema["x-gdscript-class"]
    catalog_file = schema.get("x-catalog-file", "")
    props = schema.get("properties", {})
    required = set(schema.get("required", []))
    fields = [field_from_property(key, prop, required, schema) for key, prop in props.items()]
    return ClassSpec(
        class_name=class_name,
        catalog_file=catalog_file,
        fields=fields,
        schema_path=str(schema_path.relative_to(ROOT)),
    )


def gd_default_literal(gd_type: str, value: Any) -> str:
    if gd_type == "String":
        return f'"{value}"'
    if gd_type == "bool":
        return "true" if value else "false"
    if gd_type == "Array":
        return "[]"
    if gd_type == "Dictionary":
        return "{}"
    if gd_type in {"float", "int"}:
        if isinstance(value, float):
            return repr(float(value))
        return str(int(value))
    return "null"


def parse_field_from_dict(field: FieldSpec) -> str:
    key = field.name
    if field.nested_class:
        return f'\tdef.{key} = {field.nested_class}.from_dict(data.get("{key}", {{}}))'
    if field.is_array:
        lines = [f'\tdef.{key} = []', f'\tvar raw_{key}: Variant = data.get("{key}", [])']
        lines.append(f'\tif typeof(raw_{key}) == TYPE_ARRAY:')
        if field.array_item_type == "String":
            lines.append(f'\t\tfor item in raw_{key}:')
            lines.append(f'\t\t\tdef.{key}.append(str(item))')
        else:
            lines.append(f'\t\tdef.{key} = raw_{key}.duplicate()')
        return "\n".join(lines)
    if field.is_dict:
        return (
            f'\tvar raw_{key}: Variant = data.get("{key}", {{}})\n'
            f'\tif typeof(raw_{key}) == TYPE_DICTIONARY:\n'
            f'\t\tdef.{key} = raw_{key}.duplicate()'
        )
    if field.gd_type == "String":
        cast_expr = f'str(data.get("{key}", {gd_default_literal(field.gd_type, field.default)}))'
    elif field.gd_type == "bool":
        cast_expr = f'bool(data.get("{key}", {gd_default_literal(field.gd_type, field.default)}))'
    elif field.gd_type == "int":
        cast_expr = f'int(data.get("{key}", {gd_default_literal(field.gd_type, field.default)}))'
    else:
        cast_expr = f'float(data.get("{key}", {gd_default_literal(field.gd_type, field.default)}))'
    return f"\tdef.{key} = {cast_expr}"


def value_differs(field: FieldSpec) -> str:
    default = gd_default_literal(field.gd_type, field.default)
    if field.nested_class:
        nested = field.nested_class
        return f"not {nested}.is_empty({field.name})"
    if field.is_array:
        return f"not {field.name}.is_empty()"
    if field.is_dict:
        return f"not {field.name}.is_empty()"
    return f"{field.name} != {default}"


def emit_to_dict(field: FieldSpec) -> str:
    if field.required:
        if field.nested_class:
            return f'\tout["{field.name}"] = {field.name}.to_dict()'
        if field.is_array or field.is_dict:
            return f'\tout["{field.name}"] = {field.name}.duplicate()'
        return f'\tout["{field.name}"] = {field.name}'
    if field.nested_class:
        return (
            f'\tif {value_differs(field)}:\n'
            f'\t\tout["{field.name}"] = {field.name}.to_dict()'
        )
    if field.is_array or field.is_dict:
        return (
            f'\tif {value_differs(field)}:\n'
            f'\t\tout["{field.name}"] = {field.name}.duplicate()'
        )
    return f'\tif {value_differs(field)}:\n\t\tout["{field.name}"] = {field.name}'


def emit_nested_helper_class(spec: ClassSpec) -> str:
    lines = [
        GENERATED_HEADER,
        f"class_name {spec.class_name}",
        "extends RefCounted",
        "",
    ]
    for fld in spec.fields:
        lines.append(
            f"var {fld.name}: {fld.gd_type} = {gd_default_literal(fld.gd_type, fld.default)}"
        )
    lines.append("")
    lines.append(f"static func from_dict(data: Dictionary) -> {spec.class_name}:")
    lines.append(f"\tvar def := {spec.class_name}.new()")
    for fld in spec.fields:
        lines.append(parse_field_from_dict(fld))
    lines.append("\treturn def")
    lines.append("")
    lines.append(f"static func is_empty(value: {spec.class_name}) -> bool:")
    checks: list[str] = []
    for fld in spec.fields:
        default = gd_default_literal(fld.gd_type, fld.default)
        checks.append(f"value.{fld.name} == {default}")
    lines.append("\treturn " + (" and ".join(checks) if checks else "true"))
    lines.append("")
    lines.append("func to_dict() -> Dictionary:")
    lines.append("\tvar out: Dictionary = {}")
    for fld in spec.fields:
        lines.append(f'\tout["{fld.name}"] = {fld.name}')
    lines.append("\treturn out")
    lines.append("")
    return "\n".join(lines)


def emit_record_to_dict(field: FieldSpec) -> str:
    if field.required:
        if field.nested_class:
            return f'\tout["{field.name}"] = {field.name}.to_dict()'
        if field.is_array or field.is_dict:
            return f'\tout["{field.name}"] = {field.name}.duplicate()'
        return f'\tout["{field.name}"] = {field.name}'
    include = f'_present_keys.has("{field.name}") or {value_differs(field)}'
    if field.nested_class:
        return (
            f"\tif {include}:\n"
            f'\t\tout["{field.name}"] = {field.name}.to_dict()'
        )
    if field.is_array or field.is_dict:
        return (
            f"\tif {include}:\n"
            f'\t\tout["{field.name}"] = {field.name}.duplicate()'
        )
    return f'\tif {include}:\n\t\tout["{field.name}"] = {field.name}'


def emit_record_class(spec: ClassSpec) -> str:
    parts = [
        GENERATED_HEADER,
        f"class_name {spec.class_name}",
        "extends RefCounted",
        "",
        "var _present_keys: Dictionary = {}",
        "",
    ]
    for fld in spec.fields:
        if fld.nested_class:
            init = f"{fld.nested_class}.new()"
        else:
            init = gd_default_literal(fld.gd_type, fld.default)
        parts.append(f"var {fld.name}: {fld.gd_type} = {init}")
    parts.append("")
    parts.append(f"static func from_dict(data: Dictionary) -> {spec.class_name}:")
    parts.append(f"\tvar def := {spec.class_name}.new()")
    parts.append("\tfor key in data.keys():")
    parts.append("\t\tdef._present_keys[str(key)] = true")
    for fld in spec.fields:
        parts.append(parse_field_from_dict(fld))
    parts.append("\treturn def")
    parts.append("")
    parts.append("func to_dict() -> Dictionary:")
    parts.append("\tvar out: Dictionary = {}")
    for fld in spec.fields:
        parts.append(emit_record_to_dict(fld))
    parts.append("\treturn out")
    parts.append("")
    parts.append("static func allowed_keys() -> PackedStringArray:")
    keys = [f.name for f in spec.fields]
    parts.append("\treturn PackedStringArray([" + ", ".join(f'"{k}"' for k in keys) + "])")
    parts.append("")
    required = [f.name for f in spec.fields if f.required]
    parts.append("static func required_keys() -> PackedStringArray:")
    parts.append("\treturn PackedStringArray([" + ", ".join(f'"{k}"' for k in required) + "])")
    parts.append("")
    return "\n".join(parts)


def record_filename(class_name: str) -> str:
    snake = re.sub(r"(?<!^)(?=[A-Z])", "_", class_name).lower()
    return f"{snake}.gd"


def emit_validator_entrypoints(class_specs: list[ClassSpec]) -> str:
    lines = [
        "#!/usr/bin/env python3",
        '"""Validate catalog JSON against schema rules. Generated — do not edit."""',
        "",
        "from __future__ import annotations",
        "",
        "import json",
        "import sys",
        "from pathlib import Path",
        "",
        "ROOT = Path(__file__).resolve().parents[2]",
        "CATALOG = ROOT / \"data\" / \"catalog\"",
        "SCHEMA_DIR = ROOT / \"data\" / \"catalog\" / \"schema\"",
        "",
        "REF_CATALOG_FILES = " + json.dumps(REF_CATALOG_FILES, indent=4) + "",
        "",
        "TYPE_CHECKS = {",
        '    "string": lambda v: isinstance(v, str),',
        '    "number": lambda v: isinstance(v, (int, float)) and not isinstance(v, bool),',
        '    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),',
        '    "boolean": lambda v: isinstance(v, bool),',
        '    "array": lambda v: isinstance(v, list),',
        '    "object": lambda v: isinstance(v, dict),',
        "}",
        "",
        "SCHEMA_TARGETS = [",
    ]
    for spec in class_specs:
        schema_name = Path(spec.schema_path).name
        lines.append(f'    ("{spec.catalog_file}", SCHEMA_DIR / "{schema_name}"),')
    lines.extend(
        [
            "]",
            "",
            "def load_array(filename: str) -> list:",
            "    return json.loads((CATALOG / filename).read_text(encoding='utf-8'))",
            "",
            "def index_by_id(items: list) -> dict:",
            "    return {",
            "        item['id']: item",
            "        for item in items",
            "        if isinstance(item, dict) and item.get('id')",
            "    }",
            "",
            "def resolve_ref(schema: dict, ref: str) -> dict:",
            "    node = schema",
            "    for part in ref[2:].split('/'):",
            "        node = node[part]",
            "    return node",
            "",
            "def check_type(value, expected: str) -> bool:",
            "    if expected == 'any':",
            "        return True",
            "    checker = TYPE_CHECKS.get(expected)",
            "    return checker(value) if checker else True",
            "",
            "def validate_object(",
            "    value: dict,",
            "    schema: dict,",
            "    label: str,",
            "    path: str,",
            ") -> list[str]:",
            "    errors: list[str] = []",
            "    props = schema.get('properties', {})",
            "    required = set(schema.get('required', []))",
            "    for key in required:",
            "        if key not in value:",
            "            errors.append(f'{label}: missing required field {path}{key}')",
            "    if schema.get('additionalProperties') is False:",
            "        allowed = set(props.keys())",
            "        for key in value:",
            "            if key not in allowed:",
            "                errors.append(f'{label}: unknown field {path}{key}')",
            "    for key, prop in props.items():",
            "        if key not in value:",
            "            continue",
            "        sub_path = f'{path}{key}.'",
            "        item = value[key]",
            "        if '$ref' in prop:",
            "            ref_schema = resolve_ref(schema, prop['$ref'])",
            "            if not isinstance(item, dict):",
            "                errors.append(f'{label}: {path}{key} must be an object')",
            "                continue",
            "            errors.extend(validate_object(item, ref_schema, label, sub_path))",
            "            continue",
            "        prop_type = prop.get('type', 'any')",
            "        if not check_type(item, prop_type):",
            "            errors.append(f'{label}: {path}{key} expected {prop_type}')",
            "            continue",
            "        if prop_type == 'array':",
            "            item_schema = prop.get('items', {})",
            "            item_type = item_schema.get('type', 'any')",
            "            for idx, element in enumerate(item):",
            "                if not check_type(element, item_type):",
            "                    errors.append(f'{label}: {path}{key}[{idx}] expected {item_type}')",
            "        if prop_type == 'object':",
            "            if prop.get('properties'):",
            "                if not isinstance(item, dict):",
            "                    errors.append(f'{label}: {path}{key} must be an object')",
            "                else:",
            "                    errors.extend(validate_object(item, prop, label, sub_path))",
            "            elif isinstance(item, dict):",
            "                val_type = (prop.get('additionalProperties') or {}).get('type')",
            "                if val_type:",
            "                    for sub_key, sub_val in item.items():",
            "                        if not check_type(sub_val, val_type):",
            "                            errors.append(",
            "                                f'{label}: {path}{key}.{sub_key} expected {val_type}'",
            "                            )",
            "        if 'enum' in prop and item not in prop['enum']:",
            "            errors.append(f'{label}: {path}{key} invalid value {item!r}')",
            "    return errors",
            "",
            "def validate_refs(",
            "    indexes: dict[str, dict],",
            "    catalog_file: str,",
            "    schema: dict,",
            ") -> list[str]:",
            "    errors: list[str] = []",
            "    for entry in indexes[catalog_file].values():",
            "        entry_id = str(entry.get('id', '?'))",
            "        for key, prop in schema.get('properties', {}).items():",
            "            ref_catalog = prop.get('x-ref-catalog')",
            "            if ref_catalog:",
            "                ref_val = str(entry.get(key, ''))",
            "                target_file = REF_CATALOG_FILES[ref_catalog]",
            "                if ref_val and ref_val not in indexes.get(target_file, {}):",
            "                    errors.append(",
            "                        f\"{catalog_file} {entry_id}: unknown {key} '{ref_val}'\"",
            "                    )",
            "            if prop.get('type') == 'array':",
            "                items = prop.get('items', {})",
            "                ref_catalog = items.get('x-ref-catalog')",
            "                if ref_catalog:",
            "                    target_file = REF_CATALOG_FILES[ref_catalog]",
            "                    for item in entry.get(key, []):",
            "                        ref_val = str(item)",
            "                        if ref_val and ref_val not in indexes.get(target_file, {}):",
            "                            errors.append(",
            "                                f\"{catalog_file} {entry_id}: unknown {key} item '{ref_val}'\"",
            "                            )",
            "    return errors",
            "",
            "def main() -> int:",
            "    errors: list[str] = []",
            "    indexes: dict[str, dict] = {}",
            "    for catalog_file, schema_path in SCHEMA_TARGETS:",
            "        schema = json.loads(schema_path.read_text(encoding='utf-8'))",
            "        items = load_array(catalog_file)",
            "        indexes[catalog_file] = index_by_id(items)",
            "        for entry in items:",
            "            if not isinstance(entry, dict):",
            "                errors.append(f'{catalog_file}: entry must be an object')",
            "                continue",
            "            entry_id = str(entry.get('id', '?'))",
            "            label = f'{catalog_file} {entry_id}'",
            "            errors.extend(validate_object(entry, schema, label, ''))",
            "        errors.extend(validate_refs(indexes, catalog_file, schema))",
            "    if errors:",
            "        for err in errors:",
            "            print(f'ERROR: {err}', file=sys.stderr)",
            "        return 1",
            "    print('OK: catalog schema validated.')",
            "    return 0",
            "",
            "",
            "if __name__ == '__main__':",
            "    raise SystemExit(main())",
            "",
        ]
    )
    return "\n".join(lines)


def emit_docs(class_specs: list[ClassSpec], shared_specs: dict[str, ClassSpec]) -> str:
    lines = [
        "# Catalog schema",
        "",
        "Generated field reference for schema-driven catalog records. Narrative and assembly",
        "rules remain in [data_model.md](data_model.md). Regenerate with",
        "`python3 scripts/tools/generate_catalog_records.py`.",
        "",
    ]
    for class_name in sorted(shared_specs):
        spec = shared_specs[class_name]
        lines.append(f"## {spec.class_name}")
        lines.append("")
        lines.append(f"Shared nested type (`{spec.schema_path}`).")
        lines.append("")
        lines.append("| Field | Type | Required | Default |")
        lines.append("| --- | --- | --- | --- |")
        for fld in spec.fields:
            req = "yes" if fld.required else "no"
            lines.append(
                f"| `{fld.name}` | {fld.gd_type.lower()} | {req} | `{fld.default}` |"
            )
        lines.append("")

    schema_paths = sorted(SCHEMA_DIR.glob("*.schema.json"))
    for schema_path in schema_paths:
        schema = load_schema(schema_path)
        spec = next(s for s in class_specs if s.class_name == schema["x-gdscript-class"])
        lines.append(f"## {spec.class_name}")
        lines.append("")
        lines.append(f"Source: `{spec.schema_path}` → `{spec.catalog_file}`")
        lines.append("")
        lines.append("| Field | Type | Required | Default | Notes |")
        lines.append("| --- | --- | --- | --- | --- |")
        required = set(schema.get("required", []))
        for key, prop in schema.get("properties", {}).items():
            prop_type = prop.get("type", "object")
            if "$ref" in prop:
                prop_type = shared_class_for_ref(prop["$ref"]) or prop["$ref"]
            default = prop.get("default", "")
            notes: list[str] = []
            if "enum" in prop:
                notes.append("enum: " + ", ".join(f"`{v}`" for v in prop["enum"]))
            if prop.get("x-ref-catalog"):
                notes.append(f"ref → `{prop['x-ref-catalog']}.json`")
            req = "yes" if key in required else "no"
            lines.append(
                f"| `{key}` | {prop_type} | {req} | `{default}` | {'; '.join(notes)} |"
            )
        lines.append("")
    return "\n".join(lines)


def generate_outputs() -> dict[str, str]:
    schema_paths = sorted(SCHEMA_DIR.glob("*.schema.json"))
    if not schema_paths:
        raise SystemExit(f"No schemas found in {SCHEMA_DIR}")

    shared_specs = build_shared_def_specs(schema_paths)
    class_specs = [build_class_spec(path) for path in schema_paths]

    outputs: dict[str, str] = {}
    for class_name, spec in shared_specs.items():
        outputs[str(RECORDS_DIR / record_filename(class_name))] = emit_nested_helper_class(spec)

    for spec in class_specs:
        outputs[str(RECORDS_DIR / record_filename(spec.class_name))] = emit_record_class(spec)

    outputs[str(VALIDATOR_PATH)] = emit_validator_entrypoints(class_specs)
    outputs[str(DOCS_PATH)] = emit_docs(class_specs, shared_specs)
    return outputs


def check_outputs(outputs: dict[str, str]) -> list[str]:
    errors: list[str] = []
    for path_str, content in sorted(outputs.items()):
        path = Path(path_str)
        if not path.exists():
            errors.append(f"missing generated file: {path.relative_to(ROOT)}")
            continue
        existing = path.read_text(encoding="utf-8")
        if existing != content:
            errors.append(f"stale generated file: {path.relative_to(ROOT)}")
    return errors


def write_outputs(outputs: dict[str, str]) -> None:
    for path_str, content in outputs.items():
        path = Path(path_str)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit non-zero if generated files differ from schema output.",
    )
    args = parser.parse_args()

    outputs = generate_outputs()
    if args.check:
        errors = check_outputs(outputs)
        if errors:
            for err in errors:
                print(f"ERROR: {err}", file=sys.stderr)
            return 1
        print("OK: generated catalog artifacts are up to date.")
        return 0

    write_outputs(outputs)
    print(f"Generated {len(outputs)} files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
