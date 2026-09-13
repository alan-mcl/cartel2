#!/usr/bin/env python3
"""Generate Phase 1 combat modules and patch modules.json + ammunition.json."""

from __future__ import annotations

import json
import sys
from collections import defaultdict
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from catalog_io import load_modules_by_category, write_module_category

ROOT = Path(__file__).resolve().parents[2]
AMMO_PATH = ROOT / "data/catalog/ammunition.json"

WEAPON_MAKERS = {
    "Holt-Winters Corp",
    "Orion Aerospace",
    "Oklahoma Combine",
    "Galactic Outcomes",
    "ParaRamcoVidia",
    "Four Rivers Zaibatsu",
    "Chimera Corporation",
    "Atlas Concern",
    "General Industrial",
    "Seven Bells Inc",
    "SnedeCorp",
    "Pacific Triad",
    "Tukey Enterprises",
    "Andean Consolidated",
    "Terra Nova",
    "Sakuraya Shinise",
    "Cult of Apex",
    "Guangzhou Mercantile",
    "Carthage Mercantile",
    "The Meridian Company",
}

ARMOUR_SHIELD_MAKERS = {
    "Holt-Winters Corp",
    "Oklahoma Combine",
    "Orion Aerospace",
    "ParaRamcoVidia",
    "General Industrial",
    "Chimera Corporation",
    "Atlas Concern",
    "Four Rivers Zaibatsu",
    "Galactic Outcomes",
    "Seven Bells Inc",
    "SnedeCorp",
    "The Meridian Company",
    "Sakuraya Shinise",
    "Pacific Triad",
    "Tukey Enterprises",
    "Terra Nova",
    "Andean Consolidated",
    "Evergreen Group",
    "Cult of Apex",
}

LEGACY_WEAPON_IDS = {
    "light_laser",
    "light_mass_driver",
    "turbo_laser",
    "plasma_cannon",
    "plasma_burst",
    "scatter_cannon",
    "missile_launcher",
}

LEGACY_ARMOUR_IDS = {"chitanium_5mm", "chitanium_10mm"}

COMBAT_MAGAZINE_IDS = {"rocket_magazine_16"}


def _weapon(
    id_: str,
    name: str,
    maker: str,
    brand: str,
    weapon_type: str,
    delivery_type: str,
    mount: str,
    *,
    damage_packets: dict | None = None,
    ammunition_type: str = "",
    ammunition_per_shot: int = 1,
    mass: float = 1.0,
    volume: float = 1.0,
    rate_of_fire: float = 1.0,
    range_: float = 800.0,
    power_demand: float = 4.0,
    projectile_speed: float = 0.0,
    cost: int = 1000,
    description: str = "",
    area_effect: bool = False,
) -> dict:
    mod = {
        "id": id_,
        "name": name,
        "maker": maker,
        "brand": brand,
        "category": "weapon",
        "weapon_type": weapon_type,
        "delivery_type": delivery_type,
        "mount": mount,
        "mass": mass,
        "volume": volume,
        "rate_of_fire": rate_of_fire,
        "range": range_,
        "power_demand": power_demand,
        "cost": cost,
        "description": description,
    }
    if damage_packets:
        mod["damage_packets"] = damage_packets
    if ammunition_type:
        mod["ammunition_type"] = ammunition_type
        mod["ammunition_per_shot"] = ammunition_per_shot
    if projectile_speed > 0:
        mod["projectile_speed"] = projectile_speed
    if area_effect:
        mod["area_effect"] = True
    return mod


def _armour(
    id_: str,
    name: str,
    maker: str,
    brand: str,
    hits: int,
    protection: dict,
    *,
    mass: float = 1.0,
    volume: float = 1.5,
    cost: int = 600,
    description: str = "",
) -> dict:
    return {
        "id": id_,
        "name": name,
        "maker": maker,
        "brand": brand,
        "category": "armour",
        "mount": "other",
        "mass": mass,
        "volume": volume,
        "hits": hits,
        "protection": protection,
        "cost": cost,
        "description": description,
    }


def _shield(
    id_: str,
    name: str,
    maker: str,
    brand: str,
    shield_type: str,
    capacity: float,
    protection: dict,
    *,
    mass: float = 1.0,
    volume: float = 1.5,
    power_demand: float = 6.0,
    regen: float = 3.0,
    cost: int = 2000,
    description: str = "",
) -> dict:
    return {
        "id": id_,
        "name": name,
        "maker": maker,
        "brand": brand,
        "category": "shield",
        "shield_type": shield_type,
        "mount": "other",
        "mass": mass,
        "volume": volume,
        "shield_capacity": capacity,
        "protection": protection,
        "power_demand": power_demand,
        "regen": regen,
        "cost": cost,
        "description": description,
    }


def _pd(
    id_: str,
    name: str,
    maker: str,
    brand: str,
    intercept_chance: float,
    *,
    mass: float = 0.8,
    volume: float = 1.0,
    power_demand: float = 3.0,
    compute_demand: float = 0.0,
    cost: int = 1800,
    description: str = "",
) -> dict:
    mod = {
        "id": id_,
        "name": name,
        "maker": maker,
        "brand": brand,
        "category": "point_defence",
        "mount": "other",
        "mass": mass,
        "volume": volume,
        "intercept_chance": intercept_chance,
        "power_demand": power_demand,
        "cost": cost,
        "description": description,
    }
    if compute_demand > 0:
        mod["compute_demand"] = compute_demand
    return mod


def _cyber_def(
    id_: str,
    name: str,
    maker: str,
    brand: str,
    cyber_reduction: float,
    *,
    mass: float = 0.6,
    volume: float = 0.8,
    power_demand: float = 2.0,
    compute_demand: float = 4.0,
    cost: int = 2200,
    description: str = "",
) -> dict:
    return {
        "id": id_,
        "name": name,
        "maker": maker,
        "brand": brand,
        "category": "cyber_defence",
        "mount": "system",
        "mass": mass,
        "volume": volume,
        "protection": {"cyber": cyber_reduction},
        "power_demand": power_demand,
        "compute_demand": compute_demand,
        "cost": cost,
        "description": description,
    }


def build_legacy_weapons() -> list[dict]:
    return [
        _weapon(
            "light_laser",
            "Light Laser",
            "Holt-Winters Corp",
            "Helios",
            "laser",
            "beam",
            "light_weapon",
            damage_packets={"energy": 12},
            rate_of_fire=2.0,
            range_=800,
            power_demand=4.0,
            mass=0.6,
            volume=0.8,
            cost=1100,
            description="Rotating laser turret for self-defence.",
        ),
        _weapon(
            "light_mass_driver",
            "Light Mass Driver",
            "Oklahoma Combine",
            "OC",
            "mass_driver",
            "ballistic",
            "light_weapon",
            ammunition_type="mass_driver_round",
            rate_of_fire=0.8,
            range_=1200,
            projectile_speed=1000,
            power_demand=2.0,
            mass=0.8,
            volume=1.0,
            cost=950,
            description="Kinetic defence cannon. Common on workhorse freighters.",
        ),
        _weapon(
            "turbo_laser",
            "Turbo Laser",
            "Holt-Winters Corp",
            "Helios",
            "laser",
            "beam",
            "medium_weapon",
            damage_packets={"energy": 22},
            rate_of_fire=1.5,
            range_=900,
            power_demand=8.0,
            mass=1.2,
            volume=1.4,
            cost=2800,
            description="Medium rotating turbo laser turret.",
        ),
        _weapon(
            "plasma_cannon",
            "Plasma Cannon",
            "ParaRamcoVidia",
            "Ionique",
            "plasma",
            "plasma",
            "medium_weapon",
            ammunition_type="plasma_cell",
            rate_of_fire=0.6,
            range_=1000,
            power_demand=6.0,
            mass=1.4,
            volume=1.6,
            cost=3200,
            description="Nose-mounted plasma cannon. Common on enforcement Pegasus variants.",
        ),
        _weapon(
            "plasma_burst",
            "Plasma Burst Cannon",
            "Chimera Corporation",
            "Chimera",
            "plasma",
            "plasma",
            "medium_weapon",
            ammunition_type="plasma_cell",
            ammunition_per_shot=2,
            rate_of_fire=0.4,
            range_=700,
            power_demand=10.0,
            mass=1.6,
            volume=1.8,
            cost=4500,
            description="Short-range plasma burst weapon for interceptors.",
        ),
        _weapon(
            "scatter_cannon",
            "Heavy Scatter Cannon",
            "Galactic Outcomes",
            "GO",
            "scatter",
            "ballistic",
            "heavy_weapon",
            ammunition_type="scatter_shell",
            rate_of_fire=0.3,
            range_=600,
            power_demand=5.0,
            mass=2.2,
            volume=2.5,
            cost=3800,
            area_effect=True,
            description="Area-effect scatter cannon for gunship hardpoints.",
        ),
        _weapon(
            "missile_launcher",
            "Rocket Launcher",
            "Orion Aerospace",
            "Bellatrix",
            "rocket",
            "ballistic",
            "medium_weapon",
            ammunition_type="rocket_he",
            rate_of_fire=0.2,
            range_=1500,
            projectile_speed=650,
            power_demand=3.0,
            mass=1.0,
            volume=1.2,
            cost=2600,
            description="Long-range unguided rocket launcher. Wolff standard armament.",
        ),
    ]


def build_extra_weapons() -> list[dict]:
    weapons = [
        _weapon(
            "heavy_mass_driver",
            "Heavy Mass Driver",
            "Oklahoma Combine",
            "OC",
            "mass_driver",
            "ballistic",
            "medium_weapon",
            damage_packets={"kinetic": 32, "concussive": 8},
            rate_of_fire=0.35,
            range_=1400,
            projectile_speed=900,
            power_demand=5.0,
            mass=1.6,
            volume=1.8,
            cost=3400,
            description="Heavy kinetic cannon with a concussive kick.",
        ),
        _weapon(
            "guided_missile_launcher",
            "Guided Missile Launcher",
            "Orion Aerospace",
            "Bellatrix",
            "missile",
            "guided",
            "medium_weapon",
            ammunition_type="missile_light",
            rate_of_fire=0.15,
            range_=1800,
            projectile_speed=720,
            power_demand=4.0,
            mass=1.2,
            volume=1.4,
            cost=4200,
            description="Long-range guided missile launcher.",
        ),
        _weapon(
            "emp_rocket_launcher",
            "EMP Rocket Launcher",
            "Galactic Outcomes",
            "GO",
            "rocket",
            "ballistic",
            "light_weapon",
            ammunition_type="rocket_emp",
            rate_of_fire=0.18,
            range_=1400,
            projectile_speed=620,
            power_demand=3.5,
            mass=0.9,
            volume=1.1,
            cost=3100,
            description="Unguided EMP rocket pod for compute disruption.",
        ),
        _weapon(
            "cyber_intrusion_suite",
            "Cyber Intrusion Suite",
            "SnedeCorp",
            "SnedOS",
            "cyber",
            "cyber",
            "medium_weapon",
            damage_packets={"cyber": 28},
            rate_of_fire=0.25,
            range_=900,
            power_demand=5.0,
            mass=0.7,
            volume=0.9,
            cost=4800,
            description="Direct attack against target compute capacity.",
        ),
    ]

    # Branded lines across manufacturers
    lines = [
        ("hw", "Holt-Winters Corp", "Helios", "laser", "beam", "light_weapon", {"energy": 14}, 2.2, 850, 1300),
        ("ora", "Orion Aerospace", "Bellatrix", "mass_driver", "ballistic", "light_weapon", None, 0.9, 1100, 1200),
        ("oc", "Oklahoma Combine", "OC", "mass_driver", "ballistic", "medium_weapon", {"kinetic": 24}, 0.5, 1200, 2100),
        ("go", "Galactic Outcomes", "GO", "scatter", "ballistic", "heavy_weapon", None, 0.35, 550, 2900),
        ("prv", "ParaRamcoVidia", "Ionique", "plasma", "plasma", "medium_weapon", None, 0.55, 950, 3000),
        ("frz", "Four Rivers Zaibatsu", "FRZ", "laser", "beam", "medium_weapon", {"energy": 18}, 1.2, 880, 2400),
        ("chi", "Chimera Corporation", "Chimera", "plasma", "plasma", "medium_weapon", None, 0.45, 750, 4100),
        ("atl", "Atlas Concern", "Atlas", "mass_driver", "ballistic", "heavy_weapon", {"kinetic": 36}, 0.28, 1300, 3600),
        ("gi", "General Industrial", "GI", "laser", "beam", "light_weapon", {"energy": 10}, 1.8, 700, 900),
        ("sbi", "Seven Bells Inc", "Seven Bells", "laser", "beam", "medium_weapon", {"energy": 20}, 1.4, 920, 2600),
        ("sne", "SnedeCorp", "SnedOS", "cyber", "cyber", "light_weapon", {"cyber": 22}, 0.3, 850, 4200),
        ("pt", "Pacific Triad", "Triad", "rocket", "ballistic", "medium_weapon", None, 0.22, 1500, 2700),
        ("te", "Tukey Enterprises", "TE", "mass_driver", "ballistic", "light_weapon", {"kinetic": 16}, 0.75, 1000, 1050),
        ("adc", "Andean Consolidated", "Andean", "plasma", "plasma", "light_weapon", None, 0.5, 800, 2200),
        ("tn", "Terra Nova", "Terra Nova", "laser", "beam", "heavy_weapon", {"energy": 28}, 0.9, 1000, 3400),
        ("ss", "Sakuraya Shinise", "Shinise", "laser", "beam", "light_weapon", {"energy": 13}, 2.0, 820, 1400),
        ("apex", "Cult of Apex", "Apex", "cyber", "cyber", "medium_weapon", {"cyber": 34}, 0.2, 950, 5200),
        ("gz", "Guangzhou Mercantile", "GZ", "scatter", "ballistic", "medium_weapon", None, 0.4, 650, 2500),
        ("cm", "Carthage Mercantile", "Carthage", "rocket", "ballistic", "light_weapon", None, 0.25, 1300, 2300),
        ("mdc", "The Meridian Company", "Meridian", "missile", "guided", "medium_weapon", None, 0.16, 1700, 3900),
    ]
    for prefix, maker, brand, wtype, delivery, mount, packets, rof, rng, cost in lines:
        wid = f"{prefix}_{wtype}_mk1"
        kwargs = {
            "rate_of_fire": rof,
            "range_": rng,
            "cost": cost,
            "description": f"{maker} {wtype.replace('_', ' ')} line.",
        }
        if wtype in ("rocket", "missile"):
            kwargs["ammunition_type"] = "rocket_he" if wtype == "rocket" else "missile_light"
            if wtype == "rocket":
                kwargs["projectile_speed"] = 650
            else:
                kwargs["projectile_speed"] = 720
        elif wtype == "mass_driver" and packets is None:
            kwargs["ammunition_type"] = "mass_driver_round"
            kwargs["projectile_speed"] = 1000
        elif wtype == "plasma":
            kwargs["ammunition_type"] = "plasma_cell"
        elif wtype == "scatter":
            kwargs["ammunition_type"] = "scatter_shell"
            kwargs["area_effect"] = True
        weapons.append(
            _weapon(
                wid,
                f"{brand} {wtype.replace('_', ' ').title()}",
                maker,
                brand,
                wtype,
                delivery,
                mount,
                damage_packets=packets,
                **kwargs,
            )
        )
    return weapons


def build_armour() -> list[dict]:
    armour = [
        _armour(
            "chitanium_5mm",
            "5mm Chitanium",
            "Oklahoma Combine",
            "OC",
            12,
            {"kinetic": 0.10, "concussive": 0.08, "energy": 0.05},
            mass=0.8,
            volume=1.2,
            cost=650,
            description="Light chitanium plate. Standard orbital traffic protection.",
        ),
        _armour(
            "chitanium_10mm",
            "10mm Chitanium",
            "Holt-Winters Corp",
            "Helios",
            22,
            {"kinetic": 0.18, "concussive": 0.15, "energy": 0.10},
            mass=1.4,
            volume=2.0,
            cost=1200,
            description="Medium chitanium plate for combat hulls.",
        ),
    ]
    specs = [
        ("hw", "Holt-Winters Corp", "Helios", 16, 0.14, 0.12, 0.08, 1.0, 1.4, 900),
        ("ora", "Orion Aerospace", "Bellatrix", 10, 0.08, 0.06, 0.04, 0.7, 1.0, 550),
        ("oc", "Oklahoma Combine", "OC", 18, 0.12, 0.10, 0.06, 1.1, 1.5, 780),
        ("prv", "ParaRamcoVidia", "PRV", 14, 0.10, 0.08, 0.12, 0.9, 1.3, 820),
        ("gi", "General Industrial", "GI", 20, 0.15, 0.12, 0.07, 1.2, 1.6, 950),
        ("chi", "Chimera Corporation", "Chimera", 15, 0.09, 0.08, 0.14, 1.0, 1.4, 880),
        ("atl", "Atlas Concern", "Atlas", 24, 0.20, 0.16, 0.08, 1.5, 2.1, 1350),
        ("frz", "Four Rivers Zaibatsu", "FRZ", 17, 0.11, 0.10, 0.09, 1.0, 1.5, 840),
        ("go", "Galactic Outcomes", "GO", 19, 0.16, 0.14, 0.06, 1.2, 1.7, 980),
        ("sbi", "Seven Bells Inc", "Seven Bells", 13, 0.09, 0.07, 0.11, 0.85, 1.2, 720),
        ("sne", "SnedeCorp", "SnedOS", 11, 0.06, 0.05, 0.15, 0.75, 1.1, 680),
        ("pt", "Pacific Triad", "Triad", 21, 0.17, 0.13, 0.07, 1.3, 1.8, 1100),
        ("te", "Tukey Enterprises", "TE", 9, 0.07, 0.05, 0.04, 0.65, 0.9, 480),
        ("adc", "Andean Consolidated", "Andean", 16, 0.11, 0.09, 0.10, 1.0, 1.4, 760),
        ("eg", "Evergreen Group", "Evergreen", 12, 0.08, 0.07, 0.06, 0.8, 1.1, 620),
        ("apex", "Cult of Apex", "Apex", 8, 0.05, 0.04, 0.18, 0.6, 0.9, 900),
    ]
    for prefix, maker, brand, hits, kin, con, en, mass, vol, cost in specs:
        if prefix in ("hw", "oc"):
            continue
        armour.append(
            _armour(
                f"{prefix}_chit_{hits}",
                f"{brand} Chit {hits}",
                maker,
                brand,
                hits,
                {"kinetic": kin, "concussive": con, "energy": en},
                mass=mass,
                volume=vol,
                cost=cost,
                description=f"{maker} chitanium plate.",
            )
        )
    return armour


def build_shields() -> list[dict]:
    shields = [
        _shield(
            "hw_deflector_mk1",
            "Helios Deflector Mk I",
            "Holt-Winters Corp",
            "Helios",
            "deflector",
            40,
            {"kinetic": 0.75, "concussive": 0.70, "energy": 0.15, "cyber": 0.0},
            power_demand=8.0,
            regen=4.0,
            cost=3200,
            description="General-purpose kinetic deflector.",
        ),
        _shield(
            "hw_energy_mk1",
            "Helios Energy Screen Mk I",
            "Holt-Winters Corp",
            "Helios",
            "energy",
            35,
            {"kinetic": 0.10, "concussive": 0.25, "energy": 0.80, "cyber": 0.0},
            power_demand=10.0,
            regen=3.5,
            cost=3400,
            description="Directed-energy shield screen.",
        ),
        _shield(
            "oc_deflector_mk1",
            "OC Deflector Plate",
            "Oklahoma Combine",
            "OC",
            "deflector",
            30,
            {"kinetic": 0.65, "concussive": 0.60, "energy": 0.10, "cyber": 0.0},
            power_demand=6.0,
            regen=3.0,
            cost=2400,
        ),
        _shield(
            "ora_deflector_mk1",
            "Bellatrix Deflector",
            "Orion Aerospace",
            "Bellatrix",
            "deflector",
            28,
            {"kinetic": 0.60, "concussive": 0.55, "energy": 0.12, "cyber": 0.0},
            power_demand=5.5,
            cost=2200,
        ),
        _shield(
            "prv_energy_mk1",
            "Ionique Energy Shield",
            "ParaRamcoVidia",
            "Ionique",
            "energy",
            32,
            {"kinetic": 0.08, "concussive": 0.20, "energy": 0.75, "cyber": 0.0},
            power_demand=9.0,
            cost=3100,
        ),
        _shield(
            "gi_deflector_mk1",
            "GI Deflector",
            "General Industrial",
            "GI",
            "deflector",
            22,
            {"kinetic": 0.50, "concussive": 0.45, "energy": 0.08, "cyber": 0.0},
            power_demand=5.0,
            cost=1800,
        ),
        _shield(
            "sne_electronic_mk1",
            "SnedOS Electronic Veil",
            "SnedeCorp",
            "SnedOS",
            "electronic",
            20,
            {"kinetic": 0.0, "concussive": 0.0, "energy": 0.20, "cyber": 0.70},
            power_demand=4.0,
            cost=2600,
        ),
    ]
    shields[-1]["compute_demand"] = 2.0
    extra = [
        ("frz", "Four Rivers Zaibatsu", "FRZ", "deflector", 26, 0.58, 0.52, 0.11),
        ("chi", "Chimera Corporation", "Chimera", "energy", 30, 0.09, 0.22, 0.72),
        ("atl", "Atlas Concern", "Atlas", "deflector", 34, 0.68, 0.62, 0.12),
        ("go", "Galactic Outcomes", "GO", "deflector", 25, 0.55, 0.50, 0.10),
        ("pt", "Pacific Triad", "Triad", "energy", 28, 0.10, 0.18, 0.68),
        ("te", "Tukey Enterprises", "TE", "deflector", 18, 0.45, 0.40, 0.08),
    ]
    for prefix, maker, brand, stype, cap, kin, con, en in extra:
        cyber = 0.70 if stype == "electronic" else 0.0
        if stype == "electronic":
            prot = {"kinetic": 0.0, "concussive": 0.0, "energy": 0.20, "cyber": cyber}
        elif stype == "energy":
            prot = {"kinetic": kin, "concussive": con, "energy": en, "cyber": 0.0}
        else:
            prot = {"kinetic": kin, "concussive": con, "energy": en, "cyber": 0.0}
        shields.append(
            _shield(
                f"{prefix}_{stype}_mk1",
                f"{brand} {stype.title()} Shield",
                maker,
                brand,
                stype,
                cap,
                prot,
                cost=1600 + cap * 40,
            )
        )
    return shields


def build_point_defence() -> list[dict]:
    return [
        _pd("go_pd_mk1", "GO Point Defence Turret", "Galactic Outcomes", "GO", 0.35, cost=1900),
        _pd("oc_pd_mk1", "OC Sentinel PD", "Oklahoma Combine", "OC", 0.28, cost=1700),
        _pd("hw_pd_mk1", "Helios Guard PD", "Holt-Winters Corp", "Helios", 0.32, cost=2100),
        _pd("ora_pd_mk1", "Bellatrix PD Array", "Orion Aerospace", "Bellatrix", 0.25, cost=1600),
        _pd("frz_pd_mk1", "FRZ Intercept Grid", "Four Rivers Zaibatsu", "FRZ", 0.30, cost=1850),
        _pd("gi_pd_mk1", "GI Close-In PD", "General Industrial", "GI", 0.22, cost=1400),
        _pd("atl_pd_mk1", "Atlas Watchdog PD", "Atlas Concern", "Atlas", 0.33, cost=2000),
        _pd("sbi_pd_mk1", "Seven Bells PD Bell", "Seven Bells Inc", "Seven Bells", 0.27, cost=1750),
    ]


def build_cyber_defence() -> list[dict]:
    return [
        _cyber_def("sne_cyberwall_mk1", "SnedOS Cyberwall", "SnedeCorp", "SnedOS", 0.40),
        _cyber_def("chi_cyberwall_mk1", "Chimera Firewall", "Chimera Corporation", "Chimera", 0.35),
        _cyber_def("prv_cyberwall_mk1", "PRV Compute Guard", "ParaRamcoVidia", "PRV", 0.30),
        _cyber_def("hw_cyberwall_mk1", "Helios Signal Guard", "Holt-Winters Corp", "Helios", 0.25),
        _cyber_def("sbi_cyberwall_mk1", "Seven Bells Cipher Ring", "Seven Bells Inc", "Seven Bells", 0.28),
        _cyber_def("frz_cyberwall_mk1", "FRZ Lattice Guard", "Four Rivers Zaibatsu", "FRZ", 0.22),
    ]


def build_ammunition() -> list[dict]:
    return [
        {
            "id": "mass_driver_round",
            "name": "Mass Driver Round",
            "mass": 0.05,
            "cost": 2,
            "damage_packets": {"kinetic": 18},
        },
        {
            "id": "missile_light",
            "name": "Light Missile",
            "mass": 1.2,
            "cost": 85,
            "damage_packets": {"kinetic": 25, "concussive": 35},
        },
        {
            "id": "plasma_cell",
            "name": "Plasma Cell",
            "mass": 0.15,
            "cost": 12,
            "damage_packets": {"energy": 20, "concussive": 8},
        },
        {
            "id": "scatter_shell",
            "name": "Scatter Shell",
            "mass": 0.4,
            "cost": 18,
            "damage_packets": {"kinetic": 18, "concussive": 22},
        },
        {
            "id": "rocket_he",
            "name": "HE Rocket",
            "mass": 1.0,
            "cost": 65,
            "damage_packets": {"kinetic": 20, "concussive": 30},
        },
        {
            "id": "rocket_emp",
            "name": "EMP Rocket",
            "mass": 1.0,
            "cost": 95,
            "damage_packets": {"cyber": 32},
        },
    ]


def build_magazines() -> list[dict]:
    return [
        {
            "id": "rocket_magazine_16",
            "name": "Rocket Rack 16",
            "maker": "Orion Aerospace",
            "category": "ammunition",
            "mounts": ["other", "medium_weapon", "light_weapon"],
            "mass": 0.9,
            "volume": 1.8,
            "ammunition_capacity": {"rocket_he": 16, "rocket_emp": 16},
            "cost": 620,
            "description": "Internal rocket storage rack.",
        },
    ]


def patch_modules() -> None:
    remove_cats = {"weapon", "armour", "shield", "point_defence", "cyber_defence"}

    combat = (
        build_legacy_weapons()
        + build_extra_weapons()
        + build_armour()
        + build_shields()
        + build_point_defence()
        + build_cyber_defence()
        + build_magazines()
    )
    combat_ids = {str(m.get("id", "")) for m in combat}
    combat_by_category: dict[str, list] = defaultdict(list)
    for module in combat:
        combat_by_category[str(module.get("category", ""))].append(module)

    by_category = load_modules_by_category()
    for category, modules in by_category.items():
        if category in remove_cats:
            continue
        if category == "ammunition":
            kept = [m for m in modules if str(m.get("id", "")) not in combat_ids]
            write_module_category(category, kept + combat_by_category.get("ammunition", []))
            continue
        kept = [m for m in modules if str(m.get("id", "")) not in combat_ids]
        if len(kept) != len(modules):
            write_module_category(category, kept)

    for category in remove_cats:
        write_module_category(category, combat_by_category.get(category, []))

    print(f"Patched modules/: {len(combat)} combat modules written across category files")


def patch_ammunition() -> None:
    AMMO_PATH.write_text(json.dumps(build_ammunition(), indent=2) + "\n")
    print("Updated ammunition.json")


if __name__ == "__main__":
    patch_modules()
    patch_ammunition()
