# Design backlog

Deferred **design and content** features. For what is **not implemented in code today**, see also [architecture.md](architecture.md#not-yet-implemented). For maintainability and extensibility work — refactors, test and CI gaps, content tooling — see [refactor_backlog.md](refactor_backlog.md).

## Propulsion fuel types

**Status:** Implemented. Reaction engines store typed fuel in `OwnedShip.fuels`; each propulsion SKU carries a small built-in bunker (`fuel_capacity` on the engine module) plus untyped `category: fuel` tank addons. Daily habitat prices live in `data/catalog/fuels.json` and roll per sector/GST day (`FuelEconomy`). Gravitic and integrated sail consume no propulsion fuel. Reactor fuel for power plants remains deferred.

**Follow-on (not done):** Exchange-traded fuel commodities, per-chemistry tank SKUs, reactor fuel for fission/fusion plants.

## Gravitic propulsion line

**Status:** Catalogued (five SKUs including `hw_sundancer_loft` on Flare-ON SK). **Local field coupling** is implemented: gravitic thrust scales with ambient gravity; unspace gives only weak fluctuating gravitic acceleration. **Deferred:** independent hyper-travel range mechanics and any gravitic-specific fuel rules.

## Integrated sail

**Status:** Implemented. `engine_type` `integrated_sail` — thrust scales with radiant / particle / magnetic fields; zero propulsion fuel; power draw while thrusting. Six workshop SKUs; no ship template defaults to a sail yet.
