#!/usr/bin/env python3
"""Add signature{} and sensor stats to modules.json (one-shot catalog patch)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES_PATH = ROOT / "data" / "catalog" / "modules.json"
TRAFFIC_PATH = ROOT / "data" / "catalog" / "traffic.json"

SIGNATURE_KEYS = ("thermal", "gravitational", "electromagnetic", "computational")

NEW_SENSORS = [
    {
        "id": "sensor_thermal",
        "name": "Thermal Scanner",
        "maker": "Holt-Winters Corp",
        "category": "sensor",
        "mount": "system",
        "mass": 0.35,
        "volume": 0.45,
        "compute_demand": 2.5,
        "power_demand": 1.2,
        "sensor_type": "thermal",
        "sensor_range": 7500.0,
        "sensor_sensitivity": {
            "thermal": 2.0,
            "gravitational": 0.0,
            "electromagnetic": 0.0,
            "computational": 0.0,
        },
        "capabilities": ["local_sensor"],
        "cost": 720,
        "description": "Specialised thermal detection and tracking.",
        "signature": {
            "thermal": 1.0,
            "gravitational": 0.2,
            "electromagnetic": 3.0,
            "computational": 4.0,
        },
    },
    {
        "id": "sensor_gravimetric",
        "name": "Gravimetric Scanner",
        "maker": "Orion Aerospace",
        "category": "sensor",
        "mount": "system",
        "mass": 0.4,
        "volume": 0.5,
        "compute_demand": 2.8,
        "power_demand": 1.3,
        "sensor_type": "gravitational",
        "sensor_range": 7500.0,
        "sensor_sensitivity": {
            "thermal": 0.0,
            "gravitational": 2.0,
            "electromagnetic": 0.0,
            "computational": 0.0,
        },
        "capabilities": ["local_sensor"],
        "cost": 780,
        "description": "Passive gravitational contact detection.",
        "signature": {
            "thermal": 0.8,
            "gravitational": 0.3,
            "electromagnetic": 2.5,
            "computational": 4.5,
        },
    },
    {
        "id": "sensor_em",
        "name": "EM Spectrum Scanner",
        "maker": "Mercury Communications",
        "category": "sensor",
        "mount": "system",
        "mass": 0.32,
        "volume": 0.42,
        "compute_demand": 2.2,
        "power_demand": 1.1,
        "sensor_type": "electromagnetic",
        "sensor_range": 7500.0,
        "sensor_sensitivity": {
            "thermal": 0.0,
            "gravitational": 0.0,
            "electromagnetic": 2.0,
            "computational": 0.0,
        },
        "capabilities": ["local_sensor"],
        "cost": 700,
        "description": "Electromagnetic emissions detection and tracking.",
        "signature": {
            "thermal": 0.6,
            "gravitational": 0.15,
            "electromagnetic": 3.5,
            "computational": 3.5,
        },
    },
    {
        "id": "sensor_computational",
        "name": "Computational Scanner",
        "maker": "ParaRamcoVidia",
        "category": "sensor",
        "mount": "system",
        "mass": 0.38,
        "volume": 0.48,
        "compute_demand": 3.5,
        "power_demand": 1.4,
        "sensor_type": "computational",
        "sensor_range": 7500.0,
        "sensor_sensitivity": {
            "thermal": 0.0,
            "gravitational": 0.0,
            "electromagnetic": 0.0,
            "computational": 2.0,
        },
        "capabilities": ["local_sensor"],
        "cost": 820,
        "description": "Detects active onboard computational workloads.",
        "signature": {
            "thermal": 0.7,
            "gravitational": 0.15,
            "electromagnetic": 2.0,
            "computational": 5.0,
        },
    },
]

SENSOR_SUITE_STATS = {
    "sensor_basic": {
        "sensor_type": "suite",
        "sensor_range": 6500.0,
        "sensor_sensitivity": {
            "thermal": 1.0,
            "gravitational": 1.0,
            "electromagnetic": 1.0,
            "computational": 1.0,
        },
        "signature": {
            "thermal": 0.8,
            "gravitational": 0.2,
            "electromagnetic": 2.5,
            "computational": 3.5,
        },
    },
    "sensor_advanced": {
        "sensor_type": "suite",
        "sensor_range": 8500.0,
        "sensor_sensitivity": {
            "thermal": 1.35,
            "gravitational": 1.35,
            "electromagnetic": 1.35,
            "computational": 1.35,
        },
        "signature": {
            "thermal": 1.0,
            "gravitational": 0.25,
            "electromagnetic": 3.0,
            "computational": 4.5,
        },
    },
}


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
    existing_ids = {m["id"] for m in modules}

    for module in modules:
        module_id = module["id"]
        if module_id in SENSOR_SUITE_STATS:
            stats = SENSOR_SUITE_STATS[module_id]
            module.update(
                {
                    "sensor_type": stats["sensor_type"],
                    "sensor_range": stats["sensor_range"],
                    "sensor_sensitivity": stats["sensor_sensitivity"],
                    "signature": stats["signature"],
                }
            )
        elif module.get("category") == "sensor":
            if "sensor_type" not in module:
                module["sensor_type"] = "suite"
            if "sensor_range" not in module:
                module["sensor_range"] = 6500.0
            if "sensor_sensitivity" not in module:
                module["sensor_sensitivity"] = {
                    "thermal": 1.0,
                    "gravitational": 1.0,
                    "electromagnetic": 1.0,
                    "computational": 1.0,
                }
            if "signature" not in module:
                module["signature"] = compute_signature(module)
        elif "signature" not in module:
            module["signature"] = compute_signature(module)

    for new_sensor in NEW_SENSORS:
        if new_sensor["id"] not in existing_ids:
            modules.append(new_sensor)


def patch_traffic(traffic: dict) -> None:
    traffic["visual_contact_radius"] = 250.0


def main() -> int:
    modules = json.loads(MODULES_PATH.read_text(encoding="utf-8"))
    patch_modules(modules)
    MODULES_PATH.write_text(json.dumps(modules, indent=2) + "\n", encoding="utf-8")

    traffic = json.loads(TRAFFIC_PATH.read_text(encoding="utf-8"))
    patch_traffic(traffic)
    TRAFFIC_PATH.write_text(json.dumps(traffic, indent=2) + "\n", encoding="utf-8")

    sensor_count = sum(1 for m in modules if m.get("category") == "sensor")
    sig_count = sum(1 for m in modules if "signature" in m)
    print(f"Patched {len(modules)} modules ({sig_count} with signature, {sensor_count} sensors).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
