# Balance pass, October 2026

This is a point-in-time review of the catalog in `data/catalog/`, measured against the game's goal: the leaderboard ranks careers by profit. Every number here comes from `scripts/tools/balance_report.gd`, which runs the real game code. The full tables are in [balance_pass_2026-10_tables.md](balance_pass_2026-10_tables.md). The standing targets are in [balance.md](../design/content/balance.md). The top recommendations are backlog items D-3 to D-12 in [backlog.md](../design/architecture/backlog.md).

| Item | Value |
| --- | --- |
| Generated against | Commit `159bda6`, 24 October 2026 |
| Uncommitted catalog edits | `data/catalog/sectors.json` adds Irasia city-mall names. No measured value depends on names. |
| Excluded | The Tester background and its kit. They are test-only content and get no recommendations. |
| Scope | Recommendations only. This pass changes no catalog file and no gameplay script. |

## Summary

Three problems outweigh everything else.

1. **The leaderboard measures cash flow, not profit.** `CareerStats.nett_profit()` books part sales as revenue and every purchase as an expense. Stripping the Outlaw's free Wolff Warrior puts d18,378 on the leaderboard with no play at all. The Entrepreneur sits at -d18,635 as soon as it buys its first hull.
2. **Trade earns 12 to 69 times more per hop than the best charter on the same hull, and one commodity dominates trade.**
   - Compute cores make a median d758 per unit (d2,528 per tonne) on one hop. They need no special hold, and volume is unlimited.
   - A 20 t hold earns d50,061 per hop, against d934 for the best charter on the same hull.
   - Every hull with a hold pays for itself in 2.5 trade hops or fewer.
3. **Mass, ammunition, and fuel do not constrain ships.**
   - The mass limit checks dry mass only. A d12,730 Juno 1045 refits to a 44 t freighter, and a Pegasus P107 to 84 t.
   - Nine templates already launch over their limit. The Wolff Warrior launches at 118 t against 42 t.
   - Ammunition can never be bought again once it is fired.
   - An antimatter refill costs 61% to 208% of the hull's used price.

Paid repairs are recommended at **d30 per hull point, times the local Industrial Components index** (the local quote over the base price). At today's quotes that is:

- d16 per point at Irasia and Tokirev
- d64 at Proxima, the median yard
- d74 at Fennet

A full repair of the median 28-point hull costs d451 to d2,058. Five code changes must land first, and bounty pay has to rise in the same change. See [Repair prices](#repair-prices).

| # | Finding | Severity | Fix | Backlog |
| --- | --- | --- | --- | --- |
| 1 | The leaderboard counts asset sales as profit | Critical | Code | D-3 |
| 2 | Trade dominance and compute cores | Critical | Code and data | D-4 |
| 3 | Payload is not constrained | High | Code, then data | D-5 |
| 4 | Ammunition is overfilled, heavy, and never restocked | High | Code and data | D-6 |
| 5 | Antimatter running cost | High | Data | D-7 |
| 6 | Backgrounds are unequal | High | Data, after 1 and 2 | D-8 |
| 7 | Charter and bounty pay | Medium | Data and code | D-9 |
| 8 | Weapon tiers and dominated weapons | Medium | Data | D-10 |
| 9 | Dominated modules and the placeholder hyperdrive | Medium | Data | D-11 |
| 10 | Chassis and template outliers | Medium | Data and code | D-11 |
| 11 | Inert levers and docs drift | Low | Code and docs | D-1 for reactor fuel |
| - | Paid repairs (planned) | - | Code, then data | D-12 |

## Method

`BalanceMetrics` (`scripts/tools/balance_metrics.gd`) builds every table through the game's own functions:

- `OwnedShip.from_template`, `ShipAssembler`, and `ShipAssembly` for prices, part sales, refits, and undock blockers
- `ShipOperations` for power and fuel
- `CommodityEconomy` and `FuelEconomy` for quotes over 30 days from the game's start day
- The passenger, freight, scan, and bounty generators, sampled over 6 days and 3 seeds at every habitat
- `ShipCombat.resolve_hit` and `tick_shields` for hits and duels
- A headless `GameSession` for backgrounds, kit liquidation, and the current repair behaviour

`tests/test_balance_metrics.gd` checks the tool's structure and the guard rails, and `scripts/tools/balance_report.gd` writes the tables. To regenerate the appendix (about 40 seconds):

```bash
$GODOT --headless --path . --script res://scripts/tools/balance_report.gd -- --out docs/reports/balance_pass_2026-10_tables.md --title "Balance pass 2026-10: tables"
```

Read the numbers with these limits in mind:

- **The yardstick is credits per hop.** A hop is one gate translation to an adjacent sector. Real minutes per hop were not measured; see [balance.md](../design/content/balance.md#yardstick).
- **Trade assumes unlimited credits and volume, because the game allows both.** Quotes are fixed for the day, and listing quantity is display-only. Trade income is the median, over 30 days, of the best 1-hop run with a full hold.
- **Charter columns count the best single offer** a hull qualifies for at reputation 0. Several freight lots can share a hold, so freight income per hop is a floor.
- **Duels show relative lethality, not odds.** Both sides land every shot.
- **Refit holds are a greedy floor.** The refit keeps propulsion, power, life support, computers, sensors, navigation, and the transponder. It then fills free slots with whatever cargo bays the fitting check accepts.

The tool corrected several of the plan's preliminary figures:

- Compute cores make d758 per unit, not d779. Data makes d26, not d33.
- Scan pays d298 to d410 and bounties d1,211 to d1,702 (10th to 90th percentile). A 1-hop passenger charter pays a median d1,000, and freight pays d346.
- The Wolff Warrior accelerates at 32.7 loaded against 141 dry.
- The Chimera Flare is not strictly dominated. Six power plants are dominated, not five.
- Refits reach 10 to 84 t, not 24 to 100 t. The Flare-ON SK cannot take a hold at all.

## Findings

Severity levels:

- **Critical:** breaks the leaderboard, or lets one strategy beat all others by an order of magnitude.
- **High:** cripples a whole class of ships, gear, or starts.
- **Medium:** misprices specific items or bands.
- **Low:** inert data, tidy-ups, and docs.

### 1. The leaderboard counts asset sales as profit (Critical)

**Evidence.** `CareerStats.nett_profit()` in `scripts/gameplay/career_stats.gd` is total revenue minus total expenses. Part sales count as revenue, ship and part purchases count as expenses, and the hall of fame ranks by nett profit by default. The starting kit is free, so selling its parts scores as profit:

| Background | Kit | Leaderboard after stripping the kit |
| --- | --- | ---: |
| Outlaw | Wolff Warrior | 18,378 |
| Old Money | Silhouette Mk8 | 7,992 |
| Hotshot | Flare-ON SS | 6,444 |
| Soldier | Juno 1088 | 5,274 |
| Influencer | Krypton K2 | 4,884 |
| Trader | Pegasus P101 | 4,866 |
| Entrepreneur | none | 0 |

The reverse also holds. Every purchase is a permanent loss on the leaderboard, even though the asset keeps its value. The Entrepreneur is the only background that must buy a hull, and buying a Pegasus P105 leaves it at -d18,635. Buying better gear is the main way to get stronger, and today it lowers your rank.

Buying a ship and stripping it never makes money: for every template, the parts sell for less than the used price. `tests/test_balance_metrics.gd` guards this.

**Recommendation (code).** Rank careers by the change in net worth since the career started:

- Net worth is credits, plus the value of owned assets, minus unpaid fines.
- Value each owned ship with the used-price rule applied to its current fit. Value spare parts at the part sale rate, and cargo at the local sell quote.
- Record the starting net worth when the career is created.

`ShipAssembly.used_ship_price` counts modules at 50% of list price, but `sell_part` pays 60%. Make them one shared resale rate. 0.5 keeps ship prices unchanged.

Under this rule:

- Buying a template, stripping a ship, and installing a spare are all neutral.
- Buying a new part costs only its depreciation.
- The kit cannot be cashed in for rank.

Keep the revenue and expense ledgers for the career screen. If hull sales arrive later, price a hull at the same valuation so that selling one stays neutral.

### 2. Trade dominates, and compute cores dominate trade (Critical)

**Evidence.**

- **Margins.** Every commodity's best 1-hop route returns 292% to 390% on its buy price, except data at 23%. The cause is the price band in `CommodityEconomy`:
  - `MIN_PRICE_RATIO` is 0.55 and `MAX_PRICE_RATIO` is 2.2.
  - `NOISE_SPAN` is ±8%, and the outer tier adds 12%.
  - Most goods sit on both clamps, so the clamps, not the supply and demand data, set the margins.
- **Volume.** Quotes are fixed intraday, a trade never moves a price, and the listing `quantity` is display-only ([architecture.md](../design/architecture/architecture.md#not-yet-implemented) lists market depletion as not built).
- **Compute cores** (base price 400, 0.3 t, no hold flag):
  - Median best 1-hop margin d758 per unit, or d2,528 per tonne.
  - Proxima to Fennet is the best route on 63% of days.
  - All 15 of the top routes carry compute cores, and every one is positive on 100% of days.
  - The next best goods per tonne need special holds: luxury goods d1,094 per tonne (secure cargo) and pharmaceuticals d916 (biohazard).

Trade income per hop, against the best charter for the same hull:

| Hull | Hold | Trade per hop | Best charter per hop | Ratio | Payback |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pegasus P105, Wolff Logistico, Wolff Bastion | 20 t | 50,061 | 730 to 934 | 54 to 69 | 0.37 to 0.53 hops |
| Juno 1030 | 14 t | 34,891 | 730 | 48 | 0.36 hops |
| Pegasus P101, P103, Krypton K2 | 10 t | 25,031 | 730 to 934 | 27 to 34 | 0.64 to 0.81 hops |
| 4 t hulls | 4 t | 9,861 | 571 to 798 | 12 to 17 | 1.24 to 2.46 hops |

The best charter per hop is d254 to d934, and the bounty board pays a median d1,445. The Trader turns d5,220 into d17,496 of profit on its first hop.

**Recommendations.**

- **Code (structural): add market depth.** Make the listing `quantity` the volume available at the quoted price. Buying raises the local buy quote and selling lowers the sell quote, both recovering over a few GST days. Without depth, every other change only rescales an unlimited money pump.
- **Code: narrow the price band.**
  - With today's constants the best possible return is about 426%: (2.2 × 1.12 × 1.08) / (0.55 × 0.97 × 0.92) × 0.97 - 1.
  - A band of about 0.75 to 1.6 brings that to about 150%. Re-measure after depth lands.
- **Data: compute cores.** Require the existing `compute_integrated` hold flag on `compute_cores`:
  - Freight compute lots already use the flag.
  - Three cargo modules carry it (d2,100 to d4,200), so the route needs an investment.
  - If that is not wanted, raise the mass per unit instead.
- **Measure:** use the template earning-power table. The [balance.md](../design/content/balance.md#economy) target is a full-hold trade hop worth 1.5 to 3 times the best charter hop for the same hull.

### 3. Payload is not constrained (High)

**Evidence.** `ShipAssembler.validate_install` compares dry mass with `mass_limit`. `ShipAssembly.undock_blockers` checks propulsion, fuel, life support, power, and the transponder, but not mass. Cargo, fuel, and ammunition only reduce acceleration.

Nine templates launch over their own limit:

| Template | Loaded t | Limit t | Ammunition t | Acceleration loaded | Acceleration dry |
| --- | ---: | ---: | ---: | ---: | ---: |
| Wolff Warrior | 118 | 42 | 84.8 | 32.7 | 141 |
| Wolff Gladius | 88.4 | 42 | 56.0 | 45.9 | 155 |
| Wolff Bastion | 52.8 | 42 | 24.0 | 54.0 | 127 |
| Pegasus P113 | 49.3 | 48 | 24.0 | 30.4 | 72.5 |
| Dragon Gold | 42.9 | 36 | 15.0 | 93.3 | 168 |
| Silhouette Mk8 | 37.9 | 34 | 16.4 | 47.8 | 107 |
| Juno 1090 | 34.7 | 28 | 16.4 | 36.7 | 91.5 |
| Silhouette Mk6 | 34.5 | 34 | 16.4 | 46.4 | 103 |
| Mantis XF5700 | 30.9 | 18 | 15.0 | 131 | 294 |

A cargo refit turns nearly any hull into a bulk freighter:

| Template | Used price | Hold as built | Refit hold | Loaded at full hold | Limit | Trade per hop after refit |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Pegasus P107 | 19,195 | 0 t | 84 t | 107 t | 48 t | 212,380 |
| Pegasus P109 | 19,555 | 0 t | 84 t | 108 t | 48 t | 212,380 |
| Silhouette Mk6 | 18,975 | 0 t | 50 t | 68.9 t | 34 t | 125,911 |
| Juno 1045 | 12,730 | 4 t | 44 t | 59.5 t | 28 t | 110,741 |
| Mantis XF900 | 23,245 | 0 t | 30 t | 41.6 t | 18 t | 75,850 |
| Flare-ON SS | 13,355 | 4 t | 20 t | 31.5 t | 18 t | 50,061 |

Every other template reaches 10 to 50 t, except the Flare-ON SK, which takes no hold. The refits cost d-10,178 to d4,140 net of stripped parts (a negative outlay means the stripped parts sell for more than the new holds cost). Hull roles therefore come from the starting fit alone. The chassis envelope never forces a choice between hold, armour, ammunition, and fuel.

**Recommendations.**

- **Code:** count loaded mass (dry mass plus fuel, ammunition, and cargo) against `mass_limit`:
  - At undock, as a blocker.
  - In fitting, with full fuel, full magazines, and a full hold.
  - A softer alternative is an overload band that cuts acceleration and top speed.
- **Data, after the rule:** refit the nine overweight templates so their loaded mass fits, starting with the ammunition loads (finding 4).
- **Measure:** the template mass table and the refit table. Under the [balance.md](../design/content/balance.md#ships) target, no loaded template exceeds its limit, and no refit beats the purpose-built haulers' hold by more than about 50%.

### 4. Ammunition is overfilled, heavy, and never restocked (High)

**Evidence.**

- **Overfilled.** `ShipAssembler.seed_ammunition` fills every ammunition type a magazine lists, at full capacity, whether or not a fitted weapon fires it. Rounds no fitted weapon fires weigh 6.4 t on the Juno 1090, Pegasus P101, and Silhouette Mk6 and Mk8, and 8.0 t on the Pegasus P113 and Wolff Bastion and Gladius.
- **Heavy.** A rocket weighs 1.0 t and a light missile 1.2 t, about the mass of a 20 t cargo bay. The Wolff Warrior carries 84.8 t of ammunition: 80 scatter shells (32 t), 24 missiles (28.8 t), and 24 rockets (24 t).
- **Never restocked.** Nothing restocks ammunition: no session or shipyard path writes to `OwnedShip.ammunition` after creation. The ammunition `cost` field (d2 to d95 a round) is never charged. A launcher that runs dry is dead weight for the rest of the career.
- **Cost of fire.** Lasers fire free. Ammunition weapons would cost d1.1 to d17.1 per second of fire at catalog prices.

**Recommendations.**

- **Code:** add a rearm service at the shipyard beside refuelling:
  - Price it at the ammunition `cost` times the local repair index (see [Repair prices](#repair-prices)), free in sandbox.
  - Record it as a new expense in `CareerStats`.
- **Code:** seed only the ammunition types fitted weapons fire, or let the pilot choose the load at the yard.
- **Data:** after the loaded-mass rule, trim magazine capacities on the heavy loads (Warrior, Gladius, Bastion, P113) rather than round masses, so per-shot damage stays put.
- **Measure:** the bounty table's rearm column. Ammunition weapons should earn their running cost through range, alpha damage, or point-defence-proof delivery. See finding 8.

### 5. Antimatter running cost (High)

**Evidence.**

- Antimatter is priced at d200 to d800 a unit, against d20 to d50 for fusion fuel.
- Antimatter hulls burn d30 to d45 per thrust-second. Every other fuel costs d0.65 to d4.20.
- A full refill at the mid price costs:

| Template | Refill at mid price | Share of used price |
| --- | ---: | ---: |
| Krypton K3 | 41,500 | 208% |
| Wolff Gladius | 61,500 | 194% |
| Wolff Warrior | 61,500 | 185% |
| Pegasus P103a | 41,500 | 171% |
| Dragon Gold | 41,500 | 116% |
| Mantis XF5700 | 21,500 | 61% |

The payoff is modest. The Krypton K3 tops out at 780 against the K2's 420. Against fusion, though, the Dragon Gold has slightly less dry acceleration than the Dragon Bronze (168 against 174) and gains 100 top speed. The Outlaw's Warrior comes with a full tank, but the Outlaw has d250 to refill it with.

**Recommendations.**

- **Data:** cut the antimatter band in `data/catalog/fuels.json` to about d40 to d120 a unit. At the d80 midpoint that is about 1.5 times fusion's cost per thrust-second, and a refill costs 10% to 33% of the used price.
- **Data (alternative):** keep the price and give the antimatter drives a performance edge that justifies ten times the running cost.
- **Measure:** the fuel running-cost table. The [balance.md](../design/content/balance.md#running-costs) target is a mid-price refill under 20% of the used price for every hull, except declared luxury fuels, which stay under 40%.

### 6. Backgrounds are unequal (High)

**Evidence.**

| Background | Start | Liquid credits | Kit used value | Start value | Hold | Seats | Reputation unlocks | First run, 1 hop |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| Entrepreneur | Proxima | 32,000 | 0 | 32,000 | 20 t (buys a P105) | 3 | none | d45,198 |
| Outlaw | Tycho | 250 (after a d500 fine) | 33,315 | 33,565 | 0 t | 1 | none (5) | none |
| Trader | Proxima | 5,220 | 19,055 | 24,275 | 10 t | 3 | none | d17,496 |
| Old Money | Proxima | 1,500 | 20,660 | 22,160 | 0 t | 0 | none (8) | none |
| Influencer | Fortuna | 4,000 | 16,070 | 20,070 | 10 t | 1 | performers, influencers, luxury and prototype freight (25) | d13,262 |
| Soldier | Proxima | 2,000 | 14,395 | 16,395 | 4 t | 1 | none | d6,561 |
| Hotshot | Bela | 3,000 | 13,355 | 16,355 | 4 t | 0 | none | d1,585 (d9,321 over 2 hops) |

- Start value ranges from d16,355 to d33,565, a factor of 2.05.
- Liquid credits range from d250 to d32,000.
- The lowest reputation gate is 15, so reputation 5 and 8 unlock nothing.
- Old Money and the Outlaw cannot trade or carry freight on day one. The Silhouette Mk8 has no seats, so Old Money can only hunt bounties.
- Under today's trade economy, cash beats any kit. The Entrepreneur's first hop earns d45,198, more than 2.5 times the Trader's d17,496.

**Recommendations.**

- **Fix findings 1 and 2 first.** Today the background spread mostly reflects the leaderboard rule and trade income. The tool re-measures it in one run.
- **Data:** bring every start value into one band, about d20,000 to d26,000 for liquid credits plus the kit at used value:
  - Raise the Hotshot and the Soldier.
  - Lower the Entrepreneur's cash.
  - Take the Outlaw's value out of the Warrior. A cheaper kit hull also removes the antimatter trap (finding 5).
- **Data:** give each background one real edge and one real constraint that show up in the tables:
  - Old Money's reputation should reach the first gate (15), or its money should be liquid.
  - The Outlaw's reputation 5 is flavour only; make it unlock something or drop it.
- **Measure:** the backgrounds table. The [balance.md](../design/content/balance.md#backgrounds) target is a spread of no more than 1.3 times in start value, and every background able to earn on day one.

### 7. Charter and bounty pay (Medium)

**Evidence.**

| Board | Median | Median 1-hop | Per passenger or tonne | Per GST hour | Gated at reputation 0 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Passengers (terminal) | 1,280 | 1,000 | 353 | 240 | 5.8% |
| Passengers (bar) | 904 | 904 | 264 | 212 | 8.3% |
| Freight | 461 | 346 | 330 | 72.9 | 11.8% |
| Scan | 351 | - | - | - | 0% |
| Bounty | 1,445 | - | - | - | 0% |

- **Freight against passengers.** Freight pays about the same per tonne as passengers pay per seat. Lots are small, though, so freight earns 3.3 times less per GST hour.
- **Bounty pay is flat across targets.** The median is d1,341 to d1,542 for targets with used prices of d12,730 to d35,660 and scaled hulls of 16 to 52 points. Reward is `base_pay` times the source, objective, and threat multipliers (`BountyCharters`). The target template plays no part, and three hostile ships (`multiple_contacts`) pay 1.4 times.
- **Free completion.** Every armed hull completes every sampled bounty in 1.7 to 3.6 seconds of fire. With free repairs and no rearming, bounty pay is pure profit today.
- **No loot.** Destroying traffic in settled space pays nothing. It costs a d500 fine for firing and d2,500 for the kill, so piracy is not an income source.

**Recommendations.**

- **Data:** raise freight lot sizes or pay in `data/catalog/freight_missions.json` until freight earns at least half of passenger pay per GST hour.
- **Code:** scale bounty pay by the target's strength (scaled hull and best weapon) and by escort count.
- **Data:** with the repair change, retune `base_pay`:
  - The median should land near d2,200, about 1.5 times today's.
  - At that level every armed hull keeps 60% after rearming and a 25% hull repair at the median yard. Today the worst case is the Wolff Gladius at d868 of costs.
- **Measure:** the charter table and the bounty-after-costs table.

### 8. Weapon tiers and dominated weapons (Medium)

**Evidence.**

- **Mount tiers do not scale.**
  - Median hull damage per second is 10.1 for light mounts, 9.24 for medium, and 10.8 for heavy.
  - The best heavy weapon, the Sunspike laser at d5,200, does 16.3. The best medium, the Turbo Laser at d2,800, does 19.8.
  - The light mass driver (d950) and light laser (d1,100) both do 14.4, more than 11 of the 14 medium weapons that damage hulls.
- **Strictly dominated:**
  - The Ionique Lance (d2,900) and the Chimera Plasma Burst (d4,500) are both dominated by the Seven Bells laser (d2,600).
  - The Burst fires two plasma cells per shot for one cell's damage.
- **Guided missiles cost d460 to d881 per hull damage per second, against d76 to d155 for light and medium lasers.** They get 1,700 to 2,000 range against 800 to 1,050. Their ammunition is unpriced and finite (finding 4).
- **Alpha damage.** A Bellatrix rocket lands 44 hull points, more than every unarmoured template's whole hull (30 at most). In the one-hit table, a single rocket costs at least a full hull repair on 19 templates.
- **Cyber weapons** cost d3,800 to d7,200 for 5.8 to 7 compute damage per second and no hull damage.

**Recommendations.**

- **Data:** set tier targets for hull damage per second (light 10 to 14, medium 15 to 20, heavy 22 to 30, against the reference armour). Then lift the three heavies into their band, or reprice them below the mediums.
- **Data:** reprice the Lance to d2,400 or less, or give it a distinct edge. Halve the Burst's ammunition per shot, or double its damage packet.
- **Data:** lower per-round damage on rockets, or raise their price and rely on point defence. A d2,600 launcher should not delete a d35,185 hull in one hit.
- **Measure:** the weapons, mount-tier, and price-curve tables. The weapon curve exponent should be positive within each mount; today it is -2.84 for light mounts and -0.46 for medium.

### 9. Dominated modules and the placeholder hyperdrive (Medium)

**Evidence.** 46 of 296 modules (16%) are strictly dominated even with signature counted: another module for the same mounts is at least as good on every metric, has every capability, and is strictly better somewhere.

| Category | Dominated |
| --- | ---: |
| Life support | 24 of 42 |
| Computers | 9 of 41 |
| Power plants | 6 of 48 |
| Cargo | 4 of 24 |
| Weapons | 2 of 25 |
| Point defence | 1 of 6 |

- **Underpriced dominators** do most of the damage. Counting only the cheapest dominator of each module:
  - `te_lot_6_special` (d700, six habitat seats, 0.37 of its curve) dominates five life-support units costing d1,600 to d2,800.
  - `te_handy_air` (0.24 of its curve) dominates three.
  - `gi_ls_4` (0.48) dominates four.
  - `frz_mizuki_cabin` dominates five luxury cabins.
- **Branded holds that match a generic bay and cost more.** `atl_heavy_dry_20` is `cargo_bay_20` at d80 more.
- **The worst-placed computer:** `chi_hydra_node` (d1,300) is dominated by `tmc_transit_nav` (d900).
- **Luxury cabins** sit 2.4 to 5 times above the life-support curve. `hw_helios_lounge` costs d5,200 for one seat. Comfort and luxury gate passenger fares, so some premium is earned, but the tool cannot price it yet.
- **The placeholder hyperdrive.** `hyperdrive_alpha` costs d12,000 and does nothing ([D-2](../design/architecture/backlog.md#d-2-gravitic-range-and-hyperdrive-translation)). It adds d6,000 to the used prices of the Dragon Post and Dragon Gold.

**Recommendations.**

- **Data:** raise the dominators that sit far under their curve (`te_lot_6_special`, `te_handy_air`, `gi_ls_4`), then re-run the tool and fix what remains. For each remaining pair, either lower the dominated module's price under its rival's, or give it a stat the rival lacks, such as mass, volume, or signature.
- **Data:** remove `hyperdrive_alpha` from both Dragon templates until hyperdrive translation exists, or price it at a token d500.
- **Measure:** the dominance tables. The [balance.md](../design/content/balance.md#gear-pricing) target is no strictly dominated SKU without a recorded reason.

### 10. Chassis and template outliers (Medium)

**Evidence.**

- **Mantis chassis.** The Mantis costs d19,000 for 16 hits, an 18 t limit, and 28 m³. The Silhouette costs d14,000 for 22 hits, 34 t, and 42 m³, with the same weapon mounts. The Flare-ON costs d8,000 for 18 hits, 18 t, and 24 m³. The Mantis costs d1,188 per hull point against a median of d573. Against the Silhouette, its only edge is low mass.
- **Pegasus P111 power.** The P111 runs a power deficit of 7.4 with the engine on, and 11.4 while firing. Its shields and weapons are starved, so its d6,600 of defences cannot all run at once.
- **Manoeuvre.** `ShipStats.linear_damp` is derived from the manoeuvre tier but never applied. Manoeuvre only changes rotation speed, so the low-manoeuvre Pegasus pays almost nothing for the largest envelope.

**Recommendations.**

- **Data:** price the Mantis chassis at about d11,000 to d12,000, or raise its hits and volume.
- **Data:** fit the P111 with a plant that covers shields and weapons while the engine runs.
- **Code:** apply `linear_damp` in flight, or drop it and price manoeuvre through rotation alone.
- **Measure:** the template mass and power table should show no negative power margin with the engine on.

### 11. Inert levers and docs drift (Low)

- **Power-plant `fuel_consumption`** is set on all 48 plants and burns nothing. Reactor fuel is already [D-1](../design/architecture/backlog.md#d-1-reactor-fuel-traded-fuel-and-per-chemistry-tanks). Until then, treat the field as documentation only.
- **Salvage revenue** is wired into `GameSession.salvage` and `CareerStats`, but no catalog interactable sets `salvage_reward`.
- **Docs drift.** [equipment.md](../design/content/equipment.md) says the luxury flags are install-only hooks with no gameplay. `PassengerCharters` already gates comfort and luxury fares on `ls_comfort` and `ls_luxury`. Update the doc.

## Repair prices

Docking repairs hull, power, and compute damage for free today. This section recommends the paid model and the code it needs first.

### Model

**Hull repair costs d30 per point at index 1.0, times the local Industrial Components index.** The index is the sector's buy quote over the base price of 110. It uses the commodity whose description already covers repair parts, so repair prices follow the economy without a second pricing model.

- **One rate per point for every hull.** A stronger hull already pays for its toughness in its purchase price. Armour and shields pay back through smaller bills.
- **Why not scale by hull value.** Charging by hull value would bill expensive hulls twice and make the overpriced Mantis worse.
- **Why d30 is cheap per point.** The median chassis value is d573 per hull point, so d30 is about 5% of the hull's value per point repaired.
- **Power and compute damage** use the same 5% share of module value: d3.53 per unit of lost generation and d3.93 per lost compute unit, each times the local index.

### Prices by shipyard

| Shipyard | Index | Per hull point | Full repair, median 28-point hull |
| --- | ---: | ---: | ---: |
| Irasia, Tokirev | 0.54 | 16 | 451 |
| Concordia (Pelagos) | 0.55 | 16 | 458 |
| Tycho | 0.62 | 19 | 519 |
| New Carthage, Proxima | 2.15 | 64 | 1,802 |
| Fortuna | 2.17 | 65 | 1,821 |
| Horizon | 2.21 | 66 | 1,856 |
| Bela | 2.22 | 67 | 1,863 |
| Titania | 2.43 | 73 | 2,039 |
| Fennet | 2.45 | 74 | 2,058 |

Industrial Components are cheap at four yards and dear at the other seven, so repair prices split the same way. Repairing at the producer worlds is a planning reward, not an exploit. If playtests show players crossing the map just to repair, clamp the index to about 0.75 to 1.5.

### What bills look like

| Template | Hull | 25% damage, median yard | Full repair: cheapest, median, dearest | Breach as typical runs |
| --- | ---: | ---: | --- | ---: |
| Flare-ON SS | 18 | 290 | 290, 1,159, 1,323 | 0.80 |
| Juno 1088 | 20 | 322 | 322, 1,287, 1,470 | 0.89 |
| Pegasus P105 | 28 | 451 | 451, 1,802, 2,058 | 1.25 |
| Silhouette Mk8 | 34 | 547 | 547, 2,188, 2,499 | 1.51 |
| Wolff Warrior | 42 | 676 | 676, 2,703, 3,087 | 1.87 |
| Wolff Gladius | 52 | 837 | 837, 3,347, 3,822 | 2.32 |

A breach is the full repair at the median yard, measured in that hull's typical run.

- **Against the target band.** The [balance.md](../design/content/balance.md#running-costs) target is one to two runs (d48 to d96 per point for the median hull), and the median yard's d64 sits inside it.
- **Light combat hulls** fall under the band (0.71 to 0.98 runs). That fits hulls that die easily.
- **Charter-only hulls** sit above it (2.1 to 4.0 runs) because charters pay less than bounties.
- **One hit at the median yard** on a hull without shields costs:
  - d418 to d492 from a light laser.
  - d762 to d1,172 from a light mass driver.
  - At least a full hull repair from a rocket on every unarmoured hull.
- **Defence payback.** The d800 reference armour plate pays for itself in about 11 laser hits, the Pegasus P111's d6,600 of shields in 17, and the Gladius's d5,000 in 30.

### Coupling to bounty pay

At the median yard, a hunter that wins a duel pays d640 to d1,808 in repairs against the median bounty of d1,445. Every armed hull keeps 40% to 82% of a bounty after rearming and a 25% hull repair.

The tool's ceiling for keeping 60% is d82.6 per point, so d64 at the median yard passes for the median armed hull. The heavy hunters fail:

- The Wolff Bastion, Gladius, and Warrior keep 40% to 51%.
- The Pegasus P101, P109, and P113 keep 55%.
- The Dragons keep 59.9%.

Ship paid repairs together with the bounty change in finding 7, never before it.

### Code preconditions

The tool's code checks run the real session flow:

| Check | Today |
| --- | --- |
| Docking repairs the hull | Free and full: hull 1 to 18 of 18, credits unchanged |
| Arriving from unspace | Restores the hull: 1 to 18 of 18 after Bela to Fortuna |
| Launching a second ship | Carries the previous ship's hull figures: a 36-hull Dragon Bronze launches at 18 of 18 |

Before paid repairs ship:

1. **Make repair a shipyard action.** Replace the automatic repair in `GameSession.dock` (`repair_combat_at_dock`) with an action modelled on `ShipAssembly.refuel_quote` and `refuel_ship`. Keep it free in sandbox, and record it under a new `repairs` expense in `CareerStats`.
2. **Remove the free heal on unspace arrival** in `GameSession.arrive_from_unspace`. Otherwise every translation is a free repair.
3. **Store damage on each `OwnedShip`.** `CombatPersistence` holds one hull state per session and keeps it across a ship change. Per-ship damage, saved with the ship, also fixes the carry-over bug.
4. **Define a breach outcome.** Today a breach stops thrust and weapons, and there is no recovery. One option is a tow to the nearest shipyard plus the full bill.
5. **Use the same price for unspace hull stress.** `GameSession.apply_hull_stress` has no caller. When it gets one, the damage it does should be billed at the same rate.

Retune the d30 rate with the tool after any change to the price band (finding 2), because the index moves with it.

## Recommendations by kind

**Code:**

- Net-worth leaderboard with one shared module resale rate (1)
- Market depth and a narrower price band (2)
- Loaded-mass launch rule (3)
- Rearm service and selective ammunition seeding (4)
- Bounty pay scaled by target (7)
- `linear_damp` (10)
- Paid repairs and their five preconditions

**Data:**

- `compute_integrated` on compute cores (2)
- Overweight templates and magazines (3, 4)
- Antimatter band (5)
- Background start values and reputation (6)
- Freight pay and bounty `base_pay` (7)
- Weapon tiers, the Lance, the Burst, and rockets (8)
- Dominated modules and the placeholder hyperdrive (9)
- Mantis chassis and the Pegasus P111 plant (10)

**Order:** fix the leaderboard first, then trade, then payload and ammunition, then paid repairs together with bounty pay. Re-run the tool after each step. Rebalance backgrounds last, because they inherit everything above.

## Appendix

The tool's full output, 24 tables, is in [balance_pass_2026-10_tables.md](balance_pass_2026-10_tables.md):

- Ship templates, mass and power, earning power, and cargo refits
- Trade margins and routes
- Charter pay
- Module dominance and price curves
- Weapons and mount tiers
- Fuel bands and running costs
- Repair rates, shipyards, bills, and hit costs
- Bounty pay by target and after costs
- Backgrounds and code checks

Regenerate it with the command in [Method](#method). It reflects commit `159bda6` with the uncommitted `sectors.json` names noted above.
