#!/usr/bin/env python3
"""Add signature{} and sensor stats to modules.json (one-shot catalog patch)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import MODULES_DIR, load_array, load_modules, write_module_category

ROOT = Path(__file__).resolve().parents[2]
TRAFFIC_PATH = ROOT / "data" / "catalog" / "traffic.json"

SIGNATURE_KEYS = ("thermal", "gravitational", "electromagnetic", "computational")


def _clamp(value: float, lo: float = 0.0) -> float:
    return max(lo, round(value, 2))


def compute_signature(module: dict) -> dict[str, float]:
    category = str(module.get("category", ""))
    mass = float(module.get("mass", 0.0))
    volume = float(module.get("volume", 0.0))
    power_gen = float(module.get("power_generation", 0.0))
    power_demand = float(module.get("power_demand", 0.0))
    compute_cap = float(module.get("compute_capacity", 0.0))
    compute_demand = float(module.get("compute_demand", 0.0))

    sig = {key: 0.0 for key in SIGNATURE_KEYS}

    if category == "propulsion":
        engine_type = str(module.get("engine_type", "chemical"))
        thrust = float(module.get("thrust", 1000.0))
        scale = max(0.5, thrust / 1600.0)
        if engine_type == "hydro_thermal":
            sig["thermal"] = 8.0 * scale
            sig["electromagnetic"] = 2.0 * scale
            sig["gravitational"] = 0.4 * mass
        elif engine_type == "gravitic":
            sig["gravitational"] = 18.0 * scale
            sig["thermal"] = 2.5 * scale
            sig["electromagnetic"] = 3.0 * scale
        elif engine_type == "antimatter":
            sig["thermal"] = 6.0 * scale
            sig["electromagnetic"] = 4.0 * scale
            sig["gravitational"] = 0.6 * mass
        elif engine_type == "direct_fusion":
            sig["thermal"] = 5.0 * scale
            sig["electromagnetic"] = 3.0 * scale
            sig["gravitational"] = 0.5 * mass
        elif engine_type == "electric_plasma":
            sig["thermal"] = 4.5 * scale
            sig["electromagnetic"] = 5.0 * scale
            sig["gravitational"] = 0.45 * mass
        else:
            sig["thermal"] = 3.0 * scale
            sig["electromagnetic"] = 1.5 * scale
            sig["gravitational"] = 0.35 * mass

    elif category == "computer":
        core_type = str(module.get("core_type", "silicon"))
        cu = max(1.0, compute_cap)
        if core_type == "quantum":
            sig["computational"] = 0.15 + cu * 0.02
            sig["electromagnetic"] = 1.5 + cu * 0.05
            sig["thermal"] = 1.0 + cu * 0.04
        elif core_type == "photon":
            sig["computational"] = 0.8 + cu * 0.12
            sig["electromagnetic"] = 2.0 + cu * 0.08
            sig["thermal"] = 0.8 + cu * 0.05
        else:
            sig["computational"] = 1.5 + cu * 0.22
            sig["electromagnetic"] = 1.2 + cu * 0.06
            sig["thermal"] = 0.6 + cu * 0.04
        sig["gravitational"] = 0.2 * mass

    elif category == "power":
        plant_type = str(module.get("plant_type", "fission"))
        output = max(1.0, power_gen)
        if plant_type == "radioisotope":
            sig["thermal"] = 1.5 + output * 0.04
            sig["electromagnetic"] = 0.8 + output * 0.03
        elif plant_type == "fusion":
            sig["thermal"] = 3.0 + output * 0.06
            sig["electromagnetic"] = 2.0 + output * 0.05
        else:
            sig["thermal"] = 4.0 + output * 0.08
            sig["electromagnetic"] = 2.5 + output * 0.06
        sig["gravitational"] = 0.25 * mass
        sig["computational"] = 0.3

    elif category == "sensor":
        if not module.get("has_active", False):
            return {key: 0.0 for key in SIGNATURE_KEYS}
        sig["computational"] = 3.0 + compute_demand * 0.5
        sig["electromagnetic"] = 2.0 + power_demand * 0.8
        sig["thermal"] = 0.8 + power_demand * 0.3
        sig["gravitational"] = 0.15 * mass

    elif category == "transponder":
        sig["electromagnetic"] = 8.0
        sig["thermal"] = 0.4
        sig["computational"] = 0.2
        sig["gravitational"] = 0.1 * mass

    elif category == "life_support":
        crew = float(module.get("life_support_capacity", 1.0))
        sig["thermal"] = 1.5 + crew * 0.8
        sig["electromagnetic"] = 0.8 + compute_demand * 0.4
        sig["computational"] = 0.3 + compute_demand * 0.3
        sig["gravitational"] = 0.15 * mass

    elif category == "weapon":
        rof = float(module.get("rate_of_fire", 1.0))
        sig["thermal"] = 1.0 + rof * 0.5
        sig["electromagnetic"] = 1.5 + power_demand * 0.6
        sig["computational"] = 0.4
        sig["gravitational"] = 0.2 * mass

    elif category == "shield":
        sig["thermal"] = 1.5 + power_demand * 0.4
        sig["electromagnetic"] = 3.0 + power_demand * 0.5
        sig["computational"] = 0.5
        sig["gravitational"] = 0.2 * mass

    elif category == "point_defence":
        sig["thermal"] = 0.8
        sig["electromagnetic"] = 2.0 + power_demand * 0.5
        sig["computational"] = 0.6 + compute_demand * 0.3
        sig["gravitational"] = 0.15 * mass

    elif category == "cyber_defence":
        sig["computational"] = 1.5 + compute_demand * 0.6
        sig["electromagnetic"] = 1.5 + power_demand * 0.4
        sig["thermal"] = 0.6
        sig["gravitational"] = 0.12 * mass

    elif category == "armour":
        sig["gravitational"] = 0.5 * mass
        sig["thermal"] = 0.2 * mass
        sig["electromagnetic"] = 0.1

    elif category in ("cargo", "fuel"):
        sig["gravitational"] = 0.4 * mass + volume * 0.02
        sig["thermal"] = 0.3
        sig["electromagnetic"] = 0.2

    elif category == "hyperdrive":
        sig["gravitational"] = 1.5 * mass
        sig["thermal"] = 2.0 + power_demand * 0.3
        sig["electromagnetic"] = 3.0 + power_demand * 0.4
        sig["computational"] = 1.0

    elif category == "ammunition":
        sig["gravitational"] = 0.2 * mass
        sig["thermal"] = 0.1

    else:
        sig["gravitational"] = 0.2 * mass
        sig["thermal"] = 0.3 + power_demand * 0.2
        sig["electromagnetic"] = 0.2 + power_demand * 0.2
        sig["computational"] = compute_demand * 0.2

    return {key: _clamp(sig[key]) for key in SIGNATURE_KEYS}


def patch_modules(modules: list) -> None:
    for module in modules:
        if module.get("category") == "sensor":
            if "signature" not in module:
                module["signature"] = compute_signature(module)
        elif "signature" not in module:
            module["signature"] = compute_signature(module)


def patch_traffic(traffic: dict) -> None:
    traffic["visual_contact_radius"] = 250.0


def main() -> int:
    for path in sorted(MODULES_DIR.glob("*.json")):
        modules = load_array(path)
        patch_modules(modules)
        write_module_category(path.stem, modules)

    all_modules = load_modules()
    traffic = json.loads(TRAFFIC_PATH.read_text(encoding="utf-8"))
    patch_traffic(traffic)
    TRAFFIC_PATH.write_text(json.dumps(traffic, indent=2) + "\n", encoding="utf-8")

    sensor_count = sum(1 for m in all_modules if m.get("category") == "sensor")
    sig_count = sum(1 for m in all_modules if "signature" in m)
    print(f"Patched {len(all_modules)} modules ({sig_count} with signature, {sensor_count} sensors).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
