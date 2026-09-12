# Catalog schema

Generated field reference for schema-driven catalog records. Narrative and assembly
rules remain in [data_model.md](data_model.md). Regenerate with
`python3 scripts/tools/generate_catalog_records.py`.

## CatalogDamagePackets

Shared nested type (`$defs/damage_packets`).

| Field | Type | Required | Default |
| --- | --- | --- | --- |
| `kinetic` | float | no | `0.0` |
| `energy` | float | no | `0.0` |
| `concussive` | float | no | `0.0` |
| `cyber` | float | no | `0.0` |

## CatalogSignature

Shared nested type (`$defs/signature`).

| Field | Type | Required | Default |
| --- | --- | --- | --- |
| `thermal` | float | no | `0.0` |
| `gravitational` | float | no | `0.0` |
| `electromagnetic` | float | no | `0.0` |
| `computational` | float | no | `0.0` |

## AmmunitionDef

Source: `data/catalog/schema/ammunition.schema.json` → `ammunition.json`

| Field | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | string | yes | `` |  |
| `name` | string | yes | `` |  |
| `mass` | number | yes | `` |  |
| `cost` | number | yes | `` |  |
| `damage_packets` | CatalogDamagePackets | yes | `` |  |

## ChassisDef

Source: `data/catalog/schema/chassis.schema.json` → `chassis.json`

| Field | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | string | yes | `` |  |
| `name` | string | yes | `` |  |
| `maker` | string | yes | `` |  |
| `cost` | number | no | `0.0` |  |
| `mass` | number | yes | `` |  |
| `hits` | number | yes | `` |  |
| `mass_limit` | number | yes | `` |  |
| `volume` | number | yes | `` |  |
| `maneuver` | string | yes | `` | enum: `low`, `medium`, `high` |
| `hull_color` | string | no | `` |  |
| `sprite` | string | no | `` |  |
| `mounts` | #/$defs/mounts | yes | `` |  |

## ModuleDef

Source: `data/catalog/schema/modules.schema.json` → `modules.json`

| Field | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | string | yes | `` |  |
| `name` | string | yes | `` |  |
| `maker` | string | yes | `` |  |
| `brand` | string | no | `` |  |
| `category` | string | yes | `` | enum: `propulsion`, `power`, `computer`, `life_support`, `sensor`, `hyperdrive`, `weapon`, `armour`, `cargo`, `fuel`, `ammunition`, `shield`, `point_defence`, `cyber_defence`, `transponder` |
| `mount` | string | no | `` |  |
| `mounts` | array | no | `[]` |  |
| `mass` | number | yes | `` |  |
| `volume` | number | yes | `` |  |
| `cost` | number | yes | `` |  |
| `description` | string | yes | `` |  |
| `capabilities` | array | no | `[]` |  |
| `signature` | CatalogSignature | yes | `` |  |
| `engine_type` | string | no | `` | enum: ``, `chemical`, `hydro_thermal`, `electric_plasma`, `direct_fusion`, `antimatter`, `gravitic` |
| `thrust` | number | no | `0.0` |  |
| `max_speed` | number | no | `0.0` |  |
| `boost_multiplier` | number | no | `0.0` |  |
| `fuel_consumption` | number | no | `0.0` |  |
| `plant_type` | string | no | `` | enum: ``, `fission`, `fusion`, `radioisotope` |
| `power_generation` | number | no | `0.0` |  |
| `power_demand` | number | no | `0.0` |  |
| `core_type` | string | no | `` | enum: ``, `silicon`, `photon`, `quantum` |
| `compute_capacity` | number | no | `0.0` |  |
| `compute_demand` | number | no | `0.0` |  |
| `life_support_capacity` | number | no | `0.0` |  |
| `hits` | number | no | `0.0` |  |
| `protection` | CatalogDamagePackets | no | `` |  |
| `cargo_capacity` | number | no | `0.0` |  |
| `fuel_capacity` | number | no | `0.0` |  |
| `weapon_type` | string | no | `` |  |
| `delivery_type` | string | no | `` |  |
| `rate_of_fire` | number | no | `0.0` |  |
| `range` | number | no | `0.0` |  |
| `projectile_speed` | number | no | `0.0` |  |
| `ammunition_type` | string | no | `` | ref → `ammunition.json` |
| `ammunition_per_shot` | number | no | `0.0` |  |
| `ammunition_capacity` | object | no | `{}` |  |
| `damage_packets` | CatalogDamagePackets | no | `` |  |
| `shield_type` | string | no | `` |  |
| `shield_capacity` | number | no | `0.0` |  |
| `regen` | number | no | `0.0` |  |
| `has_active` | boolean | no | `False` |  |
| `sensor_range` | number | no | `0.0` |  |
| `sensor_sensitivity` | CatalogSignature | no | `` |  |
| `sensor_sensitivity_passive` | CatalogSignature | no | `` |  |
| `area_effect` | boolean | no | `False` |  |
| `intercept_chance` | number | no | `0.0` |  |

## SectorDef

Source: `data/catalog/schema/sectors.schema.json` → `sectors.json`

| Field | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | string | yes | `` |  |
| `name` | string | yes | `` |  |
| `orbit_name` | string | no | `` |  |
| `planet_name` | string | no | `` |  |
| `star_system` | string | no | `` |  |
| `classification` | string | no | `` |  |
| `gravity` | number | no | `1.0` |  |
| `population_billions` | number | no | `0.0` |  |
| `ocean_coverage` | number | no | `0.0` |  |
| `climate` | string | no | `` |  |
| `city_malls` | array | no | `[]` |  |
| `play_bounds` | number | yes | `` |  |
| `objective` | string | no | `` |  |
| `mappings` | array | no | `[]` |  |

## ShipDef

Source: `data/catalog/schema/ships.schema.json` → `ships.json`

| Field | Type | Required | Default | Notes |
| --- | --- | --- | --- | --- |
| `id` | string | yes | `` |  |
| `name` | string | yes | `` |  |
| `maker` | string | yes | `` |  |
| `chassis` | string | yes | `` | ref → `chassis.json` |
| `modules` | array | yes | `` |  |
