# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

## D-1 Reactor fuel, traded fuel, and per-chemistry tanks

**Status:** Discuss. **Severity:** Medium.

Propulsion fuel is implemented. Reaction engines store typed fuel on `OwnedShip.fuels`. Each propulsion SKU has a built-in bunker (`fuel_capacity`) plus untyped `category: fuel` tank addons. Habitat prices live in `data/catalog/fuels.json` and roll per sector and GST day (`FuelEconomy`). Gravitic drives and integrated sails consume no propulsion fuel.

**Still open:** exchange-traded fuel commodities, per-chemistry tank SKUs, and reactor fuel for fission and fusion plants.

**Do not:** invent a second propulsion-fuel model beside `FuelEconomy`.

## D-2 Gravitic range and hyperdrive translation

**Status:** Discuss. **Severity:** Low.

Five gravitic SKUs are catalogued, including `hw_sundancer_loft` on the Flare-ON SK. Local field coupling is implemented: thrust scales with ambient gravity, and unspace gives only a weak fluctuating acceleration. Six `integrated_sail` workshop SKUs exist. No ship template defaults to a sail. Hyperdrive SKUs exist in `data/catalog/modules/hyperdrive.json` and are not a travel mode.

**Still open:** independent gravitic hyper-travel range, any gravitic-specific fuel rules, and ship hyperdrive translation. The last of those is also listed under [Not yet implemented](architecture.md#not-yet-implemented).

**Do not:** enable deeper unspace layouts or hyperdrive translation as a side effect of touching sails or gravitic thrust.
