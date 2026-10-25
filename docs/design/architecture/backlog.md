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

## D-7 Antimatter running cost

**Status:** Discuss. **Severity:** High.

Antimatter is priced at d200 to d800 a unit, so antimatter hulls burn d30 to d45 per thrust-second, against d0.65 to d4.20 for every other fuel. A mid-price refill costs 61% to 208% of the hull's used price: d61,500 for the Wolff Gladius and Warrior. The Outlaw starts in the Warrior with d250. Evidence: finding 5 of the [balance pass](../../reports/balance_pass_2026-10.md#5-antimatter-running-cost-high).

**Proposal:** cut the band in `data/catalog/fuels.json` to about d40 to d120, or keep the price and give antimatter drives an edge that justifies it. The target is in [balance.md](../content/balance.md#running-costs).

**Do not:** special-case antimatter in `FuelEconomy` code. Tune the catalog band or the drives.

## D-8 Background edges and day-one earning

**Status:** Discuss. **Severity:** High.

Starting nett worth for every background except the Entrepreneur and the Tester sits in d20,000 to d26,000. The Entrepreneur starts at d32,000, about a fifth above the top of that band, with no ship. Profit remains the hall-of-fame default. Nett worth is a secondary column.

Still open:

- Old Money and the Outlaw have no hold, so they cannot trade or haul on day one.
- Old Money and the Hotshot have no seats.
- The Outlaw's reputation 5 and Old Money's reputation 8 unlock nothing, because the lowest gate is 15. A starting reputation should reach a gate, or not be given.
- Each background should have one real edge and one real constraint that show in the balance tool.

Evidence: finding 6 of the [balance pass](../../reports/balance_pass_2026-10.md#6-backgrounds-are-unequal-high). The wealth band in that finding has since been set; the edges and the day-one gaps are what remain. The target is in [balance.md](../content/balance.md#backgrounds).

**Do not:** pull the Entrepreneur down into the band. Their cash is the compensation for buying a hull, and it stays about a fifth above the top. Test-only kits such as Tester stay outside the band. Retune that premium after market depth if the cash then dominates a career.

## D-9 Charter and bounty pay

**Status:** Discuss. **Severity:** Medium.

Freight pays about the same per tonne as passengers per seat, but its lots are small, so it earns 3.3 times less per GST hour (d72.9 against d240). Bounty reward ignores the target. Median pay is d1,341 to d1,542 for targets worth d12,730 to d35,660, and three hostile ships pay only 1.4 times. Evidence: finding 7 of the [balance pass](../../reports/balance_pass_2026-10.md#7-charter-and-bounty-pay-medium).

**Proposal:**

- Raise freight lot sizes or pay until freight earns at least half of passenger pay per GST hour.
- Scale bounty pay in `BountyCharters` by the target's scaled hull, best weapon, and escorts.
- With D-12, retune `base_pay` so the median lands near d2,200.

**Do not:** ship bounty pay changes and paid repairs (D-12) separately. Tune them together with the balance tool.

## D-10 Weapon mount tiers

**Status:** Discuss. **Severity:** Medium.

Median hull damage per second is 10.1 for light mounts, 9.24 for medium, and 10.8 for heavy. The best heavy (Sunspike, d5,200, 16.3) loses to the best medium (Turbo Laser, d2,800, 19.8). The Ionique Lance and the Chimera Plasma Burst are strictly dominated by the Seven Bells laser, and the Burst spends two plasma cells per shot for one cell's damage. A d2,600 Bellatrix rocket lands 44 hull points, more than any unarmoured hull has. Evidence: finding 8 of the [balance pass](../../reports/balance_pass_2026-10.md#8-weapon-tiers-and-dominated-weapons-medium).

**Proposal:**

- Bring weapons into the mount bands in [balance.md](../content/balance.md#gear-pricing): light 10 to 14, medium 15 to 20, heavy 22 to 30.
- Reprice or rework the two dominated weapons.
- Cap per-round damage on rockets.

**Do not:** retune weapon damage without re-running the weapon, repair, and bounty tables. Repair bills and bounty costs depend on it.

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

## D-12 Paid repairs

**Status:** Discuss. **Severity:** Medium.

Docking repairs hull, power, and compute damage for free (`GameSession.dock` calls `repair_combat_at_dock`). Arriving from unspace restores the hull. Damage lives once per session in `CombatPersistence`, so launching a second ship keeps the previous ship's hull figures: a 36-hull Dragon Bronze launched after an 18-hull Flare-ON SS flies at 18 of 18. That carry-over is a bug in its own right.

A breach stops thrust and weapons, and there is no recovery flow. `GameSession.apply_hull_stress` has no caller.

**Proposal:** charge d30 per hull point times the local Industrial Components index (the local buy quote over the base price of 110).

- At today's quotes that is d16 per point at Irasia and Tokirev, d64 at Proxima (the median yard), and d74 at Fennet.
- Power and compute damage cost the same share of module value: d3.53 and d3.93 per unit at index 1.0.

Before charging:

1. Turn the automatic dock repair into a shipyard action modelled on `ShipAssembly.refuel_quote` and `refuel_ship`, priced through `ShipAssembly.repair_price_index`, free in sandbox, with a `repairs` expense key in `CareerStats`.
2. Remove the free heal in `arrive_from_unspace`.
3. Store and save damage on each `OwnedShip`.
4. Define a breach outcome, such as a tow to the nearest shipyard plus the full bill.
5. Bill unspace hull stress at the same rate once it has a caller.

Prices, bills, and targets are in the [Repair prices](../../reports/balance_pass_2026-10.md#repair-prices) section of the report and in [balance.md](../content/balance.md#running-costs).

**Do not:** charge for repairs while docking or unspace arrival still heal for free, or while damage is shared across ships. Do not add a separate repair price list beside the local market index.
