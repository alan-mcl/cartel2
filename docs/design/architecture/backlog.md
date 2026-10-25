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

## D-9 Hull breach recovery

**Status:** Discuss. **Severity:** Low.

A hull breach still stops thrust and weapons. There is no tow, no distress contract, and no way to get a breached ship home except reloading. Paid repair at the yard assumes the ship is already docked.

**Do not:** add recovery in the same pass as weapon retuning unless the player can reach a yard without flying a breached hull.

## D-11 Dominated modules and chassis outliers

**Status:** Discuss. **Severity:** Medium.

46 of 296 modules are strictly dominated, even with signature counted. Most are in life support (24 of 42), driven by underpriced dominators such as `te_lot_6_special` and `te_handy_air`.

- `hyperdrive_alpha` costs d12,000, does nothing yet (D-2), and adds d6,000 to the used prices of the Dragon Post and Dragon Gold.
- The Mantis chassis costs d1,188 per hull point against a median of d573.
- The Pegasus P111 runs a power deficit of 7.4 with the engine on.
- `ShipStats.linear_damp` is derived but never applied.

Evidence: findings 9 and 10 of the [balance pass](../../reports/balance_pass_2026-10.md#9-dominated-modules-and-the-placeholder-hyperdrive-medium).

**Proposal:**

- Raise the underpriced dominators, re-run the tool, then reprice or differentiate the dominated SKUs that remain.
- Take `hyperdrive_alpha` off the Dragon templates, or price it at a token amount.
- Reprice the Mantis chassis.
- Fit the P111 with a larger plant.
- Apply `linear_damp`, or drop it.

**Do not:** delete dominated SKUs to clear the list. Saves store module ids verbatim, so reprice or differentiate them instead.
