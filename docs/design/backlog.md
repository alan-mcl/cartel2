# Design backlog

Deferred **design and content** features. For what is **not implemented in code today**, see also [architecture.md](architecture.md#not-yet-implemented). For maintainability and extensibility work — refactors, test and CI gaps, content tooling — see [refactor_backlog.md](refactor_backlog.md).

## Propulsion fuel types

**Status:** Not started. All main engines consume the same `fuel_current` pool on owned ships.

**Goal:** Split propulsion fuels by `engine_type` so operating cost reflects chemistry, not only engine list price:

| `engine_type` | Intended fuel |
|---------------|---------------|
| `chemical` | Chemical propellant |
| `hydro_thermal` | Hydrogen |
| `electric_plasma` | Reaction mass (power-limited; plant MW caps thrust) |
| `direct_fusion` | Fusion fuel (dedicated reactor in the engine) |
| `antimatter` | Antimatter — **expensive to buy and scarce to carry** |

**Follow-on work:** `commodities.json` entries, fuel tank modules or capacity by type, refuel pricing at habitats, `ShipOperations` consumption rules, shipyard UI, save migration. Until then, antimatter engines are gated by SKU cost and low `fuel_consumption` on the shared pool only.

## Gravitic propulsion line

**Status:** Single catalog placeholder (`hw_sundancer_loft` on Flare-ON SK). **Local field coupling** is implemented: gravitic thrust scales with ambient gravity; unspace gives only weak fluctuating gravitic acceleration. No expanded gravitic SKU line or independent hyper-travel range mechanics yet.

## Integrated sail

**Status:** Not catalogued. Different mechanics from chemical / thermal / plasma / fusion / antimatter families; add when sail physics are specified.
