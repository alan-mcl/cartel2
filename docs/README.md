# Cartel documentation

Specification and setting reference for the Godot prototype. This is the checkpoint after JSON-driven orbit and jump-gate travel; content will grow as systems are added.

## Rule of thumb

**Edit setting first, then catch up JSON.** Files under `docs/setting/` describe the intended game world. Files under `docs/design/` describe what this repository implements today. When they diverge, setting is the target; `data/catalog/` is the current subset.

## Contents

### Design (this prototype)

| Document | Contents |
|----------|----------|
| [architecture.md](design/architecture.md) | Code layering, data flow, main loops, non-goals |
| [data_model.md](design/data_model.md) | JSON catalog schemas, runtime types, how to extend data |

### Setting (working bible)

| Document | Contents |
|----------|----------|
| [setting/README.md](setting/README.md) | Glossary and setting index |
| [setting/overview.md](setting/overview.md) | Fantasy, era, currency, lore topics |
| [setting/planets.md](setting/planets.md) | Six starter systems, cities, Unspace routes |
| [setting/corporations.md](setting/corporations.md) | Sixteen megacorporations |
| [setting/ships.md](setting/ships.md) | Ship families and configurations |
| [setting/equipment.md](setting/equipment.md) | Components, weapons, shields, LSS, hyperdrives |

## Source material

Setting prose is distilled from the original Cartel design notes (Office documents in the sibling Java POC repo). This prototype does not copy binary design files; extracts were used as read-only reference when authoring `docs/setting/`.
