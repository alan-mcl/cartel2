# Balance

This is how Cartel's content is balanced and measured. Each section has two parts:

- **Today** states what the code and catalog do now.
- **Target** states what a balance change should aim for.

Targets are proposals until a change meets them. The latest measured values are in the most recent report under `docs/reports/`, currently [balance_pass_2026-10.md](../../reports/balance_pass_2026-10.md). Open work is in [backlog.md](../architecture/backlog.md).

Test-only content, such as the Tester background and its kit, is outside every target here.

## Goals

- **Profit is the score.** The leaderboard should reward earning skill: route choice, planning, and managing risk. It should not reward accounting quirks.
- **No dominant money-maker.** Trade, passenger and freight charters, scans, and bounties should each be a good choice for the hull built for them.
- **Price is the main lever for power.** Stronger ships and gear cost more, along a curve a player can learn. Nothing is strictly worse than a cheaper alternative without a stated reason.
- **Running costs make choices matter.** Fuel, repairs, and rearming turn speed, toughness, and firepower into trade-offs rather than free upgrades.
- **Backgrounds differ in kind, not in value.** Each start has its own edge and constraint, and every start is worth about the same.
- **It is a sandbox.** Nothing is level-gated. Progress is bought with money, and reputation opens better-paid work.

## Yardstick

Every income source and cost is compared in the same units, for the same reference hulls.

- **Credits per hop** is the primary unit. A hop is one gate translation to an adjacent sector, plus the in-system flying at each end.
- **Credits per GST hour** is the secondary unit. It uses the charter deadline model: each translation's entry and exit lumps (`friction × 240` GST seconds each way on public 4-space routes), plus `deadline_orbit_hours_per_hop` (2 hours) per hop.
- **Credits per real minute** is the player's experience. Realspace and menus run one GST second per real second, while translations are lumps that take only the unspace flight's real time ([gst.md](gst.md)). So GST hours per hop are mostly translation, and real minutes per hop are mostly in-system flight and docking. Real minutes per hop have not been measured yet. Measure them in playtests and record them here; until then, compare activities per hop.
- **Reference hulls** are the starting kits (Pegasus P101, Krypton K2, Juno 1088, Flare-ON SS, Silhouette Mk8, and Wolff Warrior) plus the Pegasus P105, the 20 t hauler the Entrepreneur buys.
- **Statistics:** use the median over a 30-day market window and several board seeds, and the 10th percentile when the downside matters.

## Money flow

| Flow | Today | Target |
| --- | --- | --- |
| Commodity trade | Listing quantity is the book at the posted price. Trades move that price and recover over GST days. | A book-limited hold earns 1.5 to 3 times the best charter hop for the same hull. |
| Passenger charters | Terminal and bar boards. Pay scales by role, comfort tier, and route. | The benchmark for a 1-hop run. |
| Freight charters | Terminal board. Lots reserve tonnes on the hull. | At least half of passenger pay per GST hour. |
| Scan contracts | Low, narrow pay band for an active scan at a volatile site or planet. | Below charters per hop, unless the site carries combat risk. |
| Bounties | Flat pay regardless of target. Free repairs make it pure profit. | Scales with target strength. Keeps at least 60% of pay after costs. |
| Part sales | 60% of list price. Counted as revenue. | Stay revenue. Nett worth books the module at 50% until it is sold. |
| Salvage | Wired into the session and career stats. No catalog content. | Small extra income from exploration. |
| Ship and part purchases | Expenses. | Stay expenses. Profit counts the full spend. |
| Fuel | Refuelling at local `FuelEconomy` quotes. | See [Running costs](#running-costs). |
| Fines and penalties | d500 for unlawful fire, d2,500 for a destroyed ship, and charter cancellation fees. | Unchanged. Piracy is not an income source. |
| Repairs | Free and automatic on docking. | Priced per hull point (see [Running costs](#running-costs)). |
| Rearming | Not possible. Magazines are filled only when a ship is created. | Priced per round at the shipyard. |

### Leaderboard metric

**Today:** the hall of fame ranks by `CareerStats.nett_profit()`, which is revenue minus expenses. Part sales count as revenue and purchases as expenses, so selling modules from a free kit scores, and buying a hull scores as spending. Buying a hull and stripping it still loses money, because the chassis is not sold and the parts come back for less than the used price.

Nett worth is a second column. It is credits, plus each owned ship at the used-price rule on its current fit (chassis at list, each fitted module at 50%), plus spare parts at that same 50%, plus cargo at the local sell quote, minus unpaid fines. Unplugging a module does not move it. Selling the module lifts it only by the gap between the 60% cash and the 50% book value. The column is absolute wealth, so a richer start can lead it while trailing on profit. Rows saved before the column existed have no figure and sort below measured rows until that career is saved again.

**Target:** keep this split. Profit stays the default rank. Nett worth stays the secondary column, on the definition above.

### Risk premium

An activity that ties up capital, or risks the hull, may pay more per hop than a safe one, but not by more than about two times on the hull built for it. Beyond that, the riskier activity simply dominates.

A typical career should draw income from at least two sources, and no single source should be required to compete on the leaderboard.

## Economy

**Today:**

- Commodity quotes come from `CommodityEconomy` ([commodity_economy.md](../architecture/commodity_economy.md)). Price is the base price times a demand-over-supply ratio, a noise term, and a tier modifier:
  - The ratio is clamped to `MIN_PRICE_RATIO` 0.8 and `MAX_PRICE_RATIO` 1.55.
  - The noise term is ±`NOISE_SPAN` 8%.
  - The tier modifier is 0.97 for core sectors, 1.0 for mid, and 1.12 for outer.
- The sell price is 97% of the buy price.
- The listing quantity is the volume available at the posted price. Buying raises the buy price and selling lowers it, by up to 25% when the book is emptied. Outstanding units halve each GST day. The pressure is saved. The base board is still derived from the day.
- A trade larger than the posted quantity is refused.
- Hold flags (`refrigerated`, `biohazard`, `secure_cargo`, `military_grade`, `compute_integrated`) gate goods to suitable holds. Compute cores require `compute_integrated`.
- On a fresh-day board, with the lot capped by the book, the best unflagged hop against the best charter hop is about 1.6× for the Flare-ON SS and the Juno 1088, 2.1× for the Pegasus P101, and 2.7× for the Krypton K2. The Pegasus P105 is about 4.3× (d4,038 against d934): its charter hop matches the P101, and the book fills the 20 t hold. A narrower band that brought the P105 down to 3× would put the 4 t hulls under 1.5×, so the clamps stay at 0.8 and 1.55. The Silhouette Mk8 and the Wolff Warrior have no cargo hold.

**Target:**

- **Margin bands.** The Pegasus P105's book-limited hold still earns about 4.3× its best charter hop. Bring that hull into the 1.5 to 3× band without pushing the 4 t hulls under 1.5×. Goods that need a special hold may earn up to about 1.5 times the unflagged best per tonne, so the special hold pays back. Compute cores still earn about five times the best unflagged good per tonne.
- **No dominant good.** No single commodity should be the best route on most days for most hulls. Value-dense goods carry a hold flag or enough mass per unit to keep them in their band.
- **Charter benchmarks.** Measure passenger and freight pay per hop and per GST hour for the reference hulls at reputation 0. Freight earns at least half of passenger pay per GST hour. Reputation-gated work (from reputation 15) pays its multipliers on top.
- **Bounty and scan pay.** Bounty pay scales with the target's scaled hull, its best weapon, and its escorts. Scan pay stays below charter pay per hop unless the site carries combat risk.

## Gear pricing

**Today:**

- Every module has a list price in `data/catalog/modules/`.
- No manufacturer-tier modifier exists in code. Brand differences are data.
- The balance tool measures each category against its main metric and flags strictly dominated modules.
- A module is strictly dominated when another module for the same mounts is at least as good on every metric, including cost and signature, has every capability flag it has, and is strictly better on at least one metric.

**Target:**

| Category | Main metric | Curve group |
| --- | --- | --- |
| Propulsion | Thrust | Engine type |
| Power | Generation | Plant type |
| Computer | Compute capacity | Core type |
| Life support | Seats | One group; comfort and luxury flags are premiums |
| Cargo | Capacity | One group; hold flags are premiums |
| Armour | Hits | One group |
| Shield | Capacity | Shield type |
| Point defence | Intercept chance | One group |
| Sensor | Range | One group |
| Navigation | Nav rating | One group |
| Fuel tank | Capacity | One group |
| Weapon | Hull damage per second against the reference armour | Mount |

- **Price curve.** Within a curve group, cost follows a power law in the main metric. An exponent of 1 or more rewards progression; below 0.8 makes the top end a bargain. Every SKU sits within 0.7 to 1.4 of its fitted cost, unless a capability flag explains the gap. Price each flag as a stated premium on the curve.
- **Manufacturer lines.** Budget lines may sit at 0.7 to 0.9 of the curve, and premium lines at 1.1 to 1.4. A budget SKU must pay for its price in another metric, such as mass, volume, signature, or power demand, so that it never dominates.
- **No strictly dominated SKUs**, with signature counted, unless the catalog records why. Fix a dominated pair by moving the dominated SKU's price under its rival's, or by giving it a metric the rival lacks.
- **Mount tiers.** Target hull damage per second against the reference armour:

  | Mount | Target |
  | --- | --- |
  | Light | 10 to 14 |
  | Medium | 15 to 20 |
  | Heavy | 22 to 30 |

  Price rises with tier. Within a mount, cost per hull damage per second rises with damage. Range, guidance, point-defence immunity, and alpha damage are paid for, but no single round should remove a typical unarmoured hull.
- **Modules with no gameplay yet**, such as the alpha hyperdrive, stay off ship templates or carry a token price until their feature exists.

## Running costs

**Today:**

- **Propulsion fuel.** Refuelling is priced by `ShipAssembly.refuel_quote` at the local `FuelEconomy` quote. Bands per unit:

  | Fuel | Band per unit |
  | --- | --- |
  | Chemical | d2 to d6 |
  | Hydrogen | d4 to d10 |
  | Reaction mass | d8 to d18 |
  | Fusion | d20 to d50 |
  | Antimatter | d200 to d800 |

- **Reactor fuel.** Power-plant `fuel_consumption` is not burned ([D-1](../architecture/backlog.md#d-1-reactor-fuel-traded-fuel-and-per-chemistry-tanks)).
- **Repairs** are free and automatic on docking, and arriving from unspace also restores the hull.
- **Ammunition.** The shipyard and the docking-bay terminal rearm a docked ship to the listed capacity of every round a fitted weapon fires. The bill is the ammunition `cost` per missing round times the local Industrial Components index (`ShipAssembly.repair_price_index`), ceiled once. Sandbox rearm is free. A paid rearm is an `ammunition` career expense. Seeding fills only those fired types; a magazine that also lists an unfired round leaves that type empty. Rounds already aboard are left in place.

**Target:**

- **Fuel.** A mid-price refill costs no more than 20% of the hull's used price. A declared luxury fuel may cost up to 40%, and no engine type costs more than about twice fusion per thrust-second without a matching performance edge.
- **Hull repairs.** Each hull point costs a base rate times the local Industrial Components index (the local buy quote over the base price). The proposed base rate is d30 per point at index 1.0.
  - The rate is the same for every hull. A tougher hull already paid for its toughness in its purchase price, and armour and shields pay back through smaller bills.
  - Power and compute damage cost the same share of module value per unit: about d3.53 per unit of generation and d3.93 per compute unit at index 1.0.
- **Breach.** A breach costs one to two typical runs of income for the median hull. That is a band of d48 to d96 per hull point at the median yard.
- **Bounties after costs.** At the median yard, every armed hull keeps at least 60% of the median bounty after rearming and repairing a quarter of its hull. With rearm charged at the median index (1.51, Proxima), the Wolff Bastion keeps 55.4% and the Gladius 55.9%. The Warrior keeps 63.8%. The line stays open for the weapon and bounty passes.
- **Ammunition weapons** must justify their running cost through range, alpha damage, or point-defence-proof delivery. Measure that as cost per kill against a laser of similar price.
- **Retune with the band.** Retune the repair rate with the balance tool whenever the commodity price band changes, because the index moves with it.

## Ships

**Today:**

- **Prices.** A template's build cost is its chassis plus every module at list price. The used price, which the shipyard charges, is the chassis plus 50% of module list prices. Stripped modules sell for 60% of list price.
- **No hull sales.** Hulls cannot be sold.
- **No-strip-profit invariant.** For every template, the parts sell for less than the used price, so buying a ship to strip it never pays. `tests/test_balance_metrics.gd` checks this.
- **Mass.** Fitting compares a full load with `mass_limit`: dry mass, a full tank of the engine's fuel, every magazine at its listed capacity, and a full hold. Undock compares the fuel, ammunition, and cargo actually aboard. A partial hold can leave. A fit that cannot fly full cannot be installed. Fuel, ammunition, and cargo still reduce acceleration.
- **Payload sets the role.** Every template's full load is within its limit, so hold, armour, ammunition, and fuel compete for it. The largest purpose-built hold that fits is the Pegasus P105 at 20 t. The largest cargo refit is 28 t, on the Pegasus P107, about 1.4 times that hold.

**Target:**

- **Chassis price model.** Chassis cost tracks hull points, mass limit, volume, and mounts. A chassis priced well above that, such as the Mantis at about twice the median cost per hull point, needs an edge that justifies the premium.
- **Resale.** The yard's used price counts modules at 50% of list, and part sales pay 60%. Profit books the purchase and the sale in full. Nett worth books a fitted module and a spare at the same 50%, so moving a part between the ship and the pile does not change it, and selling the part lifts nett worth only by the gap over that book value. The no-strip-profit invariant must keep holding.
- **Power.** No template has a negative power margin with the engine on. Firing the best weapon does not starve shields.
- **Payback.** A new hull or a major upgrade pays for itself in about 10 to 30 hops of the activity it serves.

## Backgrounds

**Today:** starting nett worth is credits, plus the kit at the used-price rule on its current fit, plus spare parts at 50%, minus unpaid fines. The Tester kit is outside this.

- Every other background except the Entrepreneur starts between d20,000 and d26,000.
- The Entrepreneur starts at d32,000 with no ship, about a fifth above the top of that band.
- Liquid credits still run from d250, after the Outlaw's fine, to the Entrepreneur's d32,000.
- Reputation gates start at 15. The others are 25, 30, 40, 50, and 75, depending on role and cargo.
- Each on-time delivery adds 1 reputation, and each late or cancelled charter removes 1 ([missions.md](missions.md)).

**Target:**

- **Start value band.** Keep the d20,000 to d26,000 band for every background except the Entrepreneur and the Tester. Keep the Entrepreneur about a fifth above the top of the band (d30,000 to d32,000). That premium is for having to buy a hull, and it is smaller than the hull's price, because choosing the ship is already their edge.
- **Day-one income.** Every background can earn on day one with its kit through at least one activity: trade, a charter, or a bounty.
- **One edge and one constraint each,** both visible in the balance tool's backgrounds table. A starting reputation either reaches a gate or is not given.
- **Earning power.** Compare backgrounds by start value and by first-run income from the start habitat. Revisit the Entrepreneur's premium after market depth, if that cash then dominates a career.

## Process and guard rails

Run the balance tool after any of these:

- A price change
- A new or retired SKU, template, or background
- A change to an economy or fuel constant
- A change to charter or bounty pay rules

```bash
$GODOT --headless --path . --script res://scripts/tools/balance_report.gd -- --out /tmp/balance_tables.md
```

The run takes about 40 seconds. Without `--out` it prints the tables, and `--title` sets the heading. For a full balance pass, write the tables to `docs/reports/balance_pass_<yyyy-mm>_tables.md`, put a dated report beside them, and update the targets here if they change.

| Target | Table in the tool's output |
| --- | --- |
| A full-hold trade hop earns 1.5 to 3 times the best charter hop | Template earning power |
| Freight earns at least half of passenger pay per GST hour | Charter pay |
| No strictly dominated SKU without a recorded reason | Strictly dominated modules |
| Every SKU within 0.7 to 1.4 of its curve, flags aside | Module price curves, price-curve outliers |
| Weapon damage per second within its mount band | Weapons, weapon mount tiers |
| Mid-price refill at most 20% of used price | Fuel running cost by template |
| Loaded mass within the mass limit | Template mass and power |
| Refit hold within about 1.5 times the haulers' | Hold after a cargo refit |
| No negative power margin with the engine on | Template mass and power |
| Breach costs one to two typical runs | Hull repair bills by template |
| Armed hulls keep at least 60% of a bounty after costs | Bounty pay after rearming and repairs |
| Start value within d20,000 to d26,000, Entrepreneur about a fifth above | Backgrounds |

**Guard rails as tests.**

- `tests/test_balance_metrics.gd` asserts the no-strip-profit invariant and the tool's structure.
- `tests/test_career.gd` asserts the starting nett-worth bands, and that profit stays the ranking column.
- `tests/test_assembler.gd` asserts that every template's full load is within its mass limit, that seeding skips rounds no fitted weapon fires, and that rearm bills the ammunition cost times the local index.
- When the catalog meets another target, add it as an invariant test in the same change, so it cannot regress. Candidates:
  - No strictly dominated modules
  - No negative power margin
- Assert floors and invariants, never exact catalog counts.
