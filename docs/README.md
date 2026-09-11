# Cartel documentation

Specification and setting reference for the Cartel game. Content grows as systems ship.

## Rule of thumb

**Edit setting first, then catch up JSON.** Files under `docs/setting/` describe the intended game world. Files under `docs/design/` describe what this repository implements today. When they diverge, setting is the target; `data/catalog/` is the current subset.

## Contents

### Design (this game)

| Document | Contents |
|----------|----------|
| [architecture.md](design/architecture.md) | Code layering, data flow, main loops, not-yet-implemented features |
| [sensors_signatures.txt](design/sensors_signatures.txt) | Phase 1 sensor vs signature design spec |
| [backlog.md](design/backlog.md) | Deferred design passes (fuel types, gravitic line, integrated sail) |
| [architecture.md](design/architecture.md) + [data/catalog/](../data/catalog/) | JSON catalogs and runtime types (no separate data_model.md yet) |
| [ui_theme.md](design/ui_theme.md) | Corporate UI theme tokens, variations, showcase |
| [sprite_sizes.md](design/sprite_sizes.md) | Production SVG/PNG dimensions for ships, world art, and UI |

### Setting (working bible)

| Document | Contents |
|----------|----------|
| [setting/README.md](setting/README.md) | Glossary and setting index |
| [setting/overview.md](setting/overview.md) | Fantasy, era, currency, lore topics |
| [setting/planets.md](setting/planets.md) | Eleven E-type worlds, cities, habitats |
| [setting/trade_network.md](setting/trade_network.md) | Public Unspace route graph, friction, daily markets |
| [setting/corporations.md](setting/corporations.md) | Sixteen megacorporations |
| [setting/ships.md](setting/ships.md) | Ship families and configurations |
| [setting/equipment.md](setting/equipment.md) | Components, weapons, shields, LSS, hyperdrives |
| [setting/commodities.md](setting/commodities.md) | Closed eleven-category trade roster |

## Source material

Setting prose is distilled from the original Cartel design notes (Office documents in the sibling Java design repo). This game does not copy binary design files; extracts were used as read-only reference when authoring `docs/setting/`.
