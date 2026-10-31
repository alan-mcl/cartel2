# Commodity economy

**Status:** Implemented in [`CommodityEconomy`](../../../scripts/gameplay/commodity_economy.gd). Quotes are derived state: recomputed on GST day rollover and on load, not authored as save data. Route graph and friction bands: [trade_network.md](../content/trade_network.md). Roster and categories: [commodities.md](../content/commodities.md).

## Purpose

Provide deterministic **daily buy quotes** for every catalog commodity at every catalog sector, using fixed sector flows and reach-weighted coupling over the **public** Unspace route graph. Sell quotes are a fixed spread off the buy quote. The model is a stylised arbitrage surface for trading and UI flavour, not a full general-equilibrium simulation.

## Code map

| Piece | Location |
|-------|----------|
| Quote computation | `CommodityEconomy.compute_quotes` |
| Session cache | `GameSession.market_quotes`, `market_quotes_day`; refreshed via `CommodityEconomy.ensure_quotes` |
| Day index | `CommodityEconomy.gst_day(session.gst_seconds)` |
| Graph friction overrides | `GameSession.route_friction_delta` (added to route friction before shortest paths) |
| Catalog inputs | `commodities.json`, `economies.json`, `routes.json`, `sectors.json` |
| UI | `GameSession.get_sector_quote_listings`, `MarketPanel`, habitat Exchange buildings |
| Tests | `tests/test_economy.gd` |

`FuelEconomy` shares the same day rollover hook in `ensure_quotes` but is a separate fuel-pricing model; this document does not specify fuel.

## Catalog inputs

### Commodities (`commodities.json`)

Each commodity has at least:

- `id` - snake_case key used in economies and quotes
- `base_price` - integer par value in credits before ratio, noise, and tier
- `mass` - used for cargo, not for pricing

All commodities listed in the catalog receive a quote at every sector every day.

### Economies (`economies.json`)

One record per sector id (must match `sectors.json`). Fields used by pricing:

| Field | Used in quotes? | Notes |
|-------|-----------------|-------|
| `id` | yes | Sector key |
| `tier` | yes | `core` \| `mid` \| `outer` → price multiplier |
| `produce` | yes | Map commodity id → non-negative flow weight |
| `consume` | yes | Map commodity id → non-negative flow weight |
| `wealth` | **no** | Retained in schema and records for setting/tier notes; **does not** enter `_sector_nets` or `compute_quotes` |

Missing keys in `produce` or `consume` mean **zero** flow for that commodity (not a default of 1).

### Routes (`routes.json`)

Undirected edges `{ a, b, friction, … }`. The economy graph includes only these public edges. Jump-gate **translation** lists on a route do not create extra edges. Effective edge weight for sector *i* → *j*:

\[
w_{ij} = \max(1,\; f_{ij} + \delta_{route(id)})
\]

where \(f_{ij}\) is catalog friction and \(\delta\) comes from `session.route_friction_delta` keyed by route `id`. Disconnected pairs have infinite shortest-path distance and contribute **no** reach.

### Sectors

Every sector id returned by `Catalog.list_sectors()` is priced. Sectors without an economy record will misbehave at load/validation time; CI validates economy coverage.

## Local net (fixed flows)

For sector \(s\) and commodity \(c\), let \(P_{s,c}\) and \(K_{s,c}\) be produce and consume weights from `economies.json` (0 if absent).

**Settled-world produce floor.** Eleven settled worlds (sector ids in `CommodityEconomy.SETTLED_WORLD_SECTOR_IDS`, aligned with [planets.md](../../setting/planets.md)) apply:

\[
\text{output}_{s,c} = \max(P_{s,c},\, 1)
\]

Belts, moons, and stations **do not** use this floor; \(\text{output}_{s,c} = P_{s,c}\) only.

\[
\text{demand}_{s,c} = K_{s,c}
\]

\[
\text{net}_{s,c} = \text{output}_{s,c} - \text{demand}_{s,c}
\]

Decompose for ratio math:

\[
\text{surplus}_{s,c} = \max(\text{net}_{s,c}, 0), \quad
\text{deficit}_{s,c} = \max(-\text{net}_{s,c}, 0)
\]

**Content authoring:** Historical relative weights (≈1–6) were scaled once by sector **magnitude** when baking `economies.json` so flows are absolute in data, not multiplied at runtime by population. Magnitude table (authoring only; not a runtime constant):

| Multiplier | Sector ids |
|-----------:|------------|
| 10 | `proxima`, `irasia`, `tokirev` |
| 6 | `new_carthage`, `fortuna`, `horizon` |
| 4 | `bela`, `pelagos`, `fennet`, `titania`, `tycho` |
| 2 | `vulcan_research`, `centauri_a_beltworks`, `acb1`, `acb2`, `acb3`, `terminus`, `regulus_belt`, `denarius_ii`, `typhon_xvi`, `pelagos_belt`, `aurelia`, `boreas`, `calypso_vi`, `hesper`, `kestrel`, `alecto`, `new_ceres`, `virginis_belt`, `varda_iii`, `varda_belt`, `cressida`, `scoria`, `ursa_belt`, `ursa_belt_shipyard`, `ursa_xvi`, `ursa_xxix`, `long_drift`, `junkers_world`, `swan`, `freediver`, `nostromo`, `eternum`, `janus`, `sapphire_xvi`, `vesuvius_v`, `tc_inner_disc`, `tc_outer_disc`, `terminary`, `byrsa`, `depot_61c`, `tanit_xx`, `nightjar`, `alpha_disc`, `cueball`, `halo_station`, `kb_station_i`, `kb_station_ii`, `kb_station_iii`, `nocturn`, `titania_v`, `titania_ixx`, `tartarus` |

Population from `sectors.json` is **not** read by `CommodityEconomy`.

## Graph reach and effective supply/demand

Constants (code):

| Symbol | Code name | Value |
|--------|-----------|------:|
| Distance scale | `DISTANCE_SCALE` | 40 |
| Ratio stabiliser | `EPSILON` | 0.5 |
| Min / max ratio | `MIN_PRICE_RATIO` / `MAX_PRICE_RATIO` | 0.8 / 1.55 |
| Book price step | `BOOK_PRICE_STEP` | 0.25 |
| Book recovery | `BOOK_RECOVERY` | 0.5 per GST day |
| Noise half-span | `NOISE_SPAN` | 0.08 (±8%) |
| Sell spread | `SELL_SPREAD` | 0.97 |

Let \(d(s, s')\) be shortest-path sum of edge weights \(w\) on the public graph (Dijkstra from each sector to all others). For buyer sector \(s\) evaluating commodity \(c\):

\[
\text{reach}(s, s') = \begin{cases}
\dfrac{1}{1 + d(s,s') / 40} & d(s,s') \text{ finite} \\
0 & \text{otherwise}
\end{cases}
\]

Initial effective supply and demand at \(s\) start as local surplus and deficit. For each other sector \(s' \neq s\):

\[
\text{supply}^{\text{eff}}_s \mathrel{+}= \text{surplus}_{s',c} \cdot \text{reach}(s, s')
\]
\[
\text{demand}^{\text{eff}}_s \mathrel{+}= \text{deficit}_{s',c} \cdot \text{reach}(s, s')
\]

Interpretation: remote surpluses cheaply add to effective supply; remote deficits add to effective demand. Low friction ⇒ high reach ⇒ stronger cross-sector pressure on the ratio.

## Price ratio

Generic ratio from supply and demand buckets:

\[
\text{ratio}(D, S) = \mathrm{clamp}\left( \frac{D + 0.5}{S + 0.5},\; 0.8,\; 1.55 \right)
\]

For sector \(s\):

- **Graph ratio:** \(\text{ratio}^{\text{graph}}_s = \text{ratio}(\text{demand}^{\text{eff}}_s, \text{supply}^{\text{eff}}_s)\)
- **Local ratio:** \(\text{ratio}^{\text{local}}_s = \text{ratio}(\text{deficit}_{s,c}, \text{surplus}_{s,c})\)

**Sign rule** (prevents a neighbour’s imbalance from inverting local role):

| Local net | Chosen ratio |
|-----------|--------------|
| \(\text{net}_{s,c} > 0\) (surplus) | \(\min(\text{ratio}^{\text{graph}}_s, \text{ratio}^{\text{local}}_s)\) - exporter stays at or below par |
| \(\text{net}_{s,c} < 0\) (deficit) | \(\max(\text{ratio}^{\text{graph}}_s, \text{ratio}^{\text{local}}_s)\) - importer stays at or above par |
| \(\text{net}_{s,c} = 0\) | \(\text{ratio}^{\text{graph}}_s\) only |

Example intent: Proxima’s mineral deficit must not bid Centauri A Beltworks (mineral surplus) above par when friction is low.

## Posted buy price

**Tier multiplier** \(\tau_s\) from `economies.json` `tier`:

| tier | \(\tau_s\) |
|------|----------:|
| `core` | 0.97 |
| `mid` | 1.0 |
| `outer` | 1.12 |
| (other / missing) | 1.0 |

**Daily noise** (deterministic, not saved separately):

\[
\text{noise}(day, s, c) = 1 + \eta \cdot 0.08
\]

where \(\eta \in [-1, 1]\) is derived from `hash("%d:%s:%s" % [day, sector_id, commodity_id])` mapped uniformly to that interval (see `_deterministic_noise`).

**Buy quote** (integer credits):

\[
\text{buy}_{s,c} = \max\left(1,\; \mathrm{round}\bigl( \text{base\_price}_c \cdot \text{ratio}_s \cdot \text{noise} \cdot \tau_s \bigr)\right)
\]

**Listing quantity** is the volume available at the posted price. A buy or a sell larger than that quantity is refused.

\[
q_{s,c} = \max(1,\; \mathrm{round}(|\text{net}_{s,c}| \times 10))
\]

That is the base book. Outstanding traded units thin it. See [Market pressure](#market-pressure).

## Sell quote

\[
\text{sell}_{s,c} = \max(1,\; \mathrm{round}(0.97 \times \text{buy}_{s,c}))
\]

Implemented as `CommodityEconomy.sell_price(buy)` and `GameSession.commodity_sell_price`. The sell price is always 97% of the posted buy, so a trade that moves the buy price moves the sell price with it.

## Market pressure

The base board above is deterministic for a catalog, a GST day, and `route_friction_delta`. Player trades do not change that base. They add a saved overlay.

`WorldPresence.market_pressure` stores net units per sector and commodity. A buy adds units. A sell subtracts them. `market_pressure_day` is the GST day those units were last decayed. Both are saved with the session. A save that has no pressure fields starts with an empty book. Quotes themselves are still rebuilt on load.

Units halve once per GST day (`BOOK_RECOVERY` 0.5), so three days leave about an eighth. On the day roll, `ensure_quotes` decays the units, recomputes the base board, then posts:

- Buy price = base price × (1 + fraction × 0.25), where fraction is the outstanding units divided by the base quantity, clamped to −1..1.
- Quantity = base quantity minus the absolute outstanding units, floored at 0.

Buying raises the buy price. Selling lowers it. Either trade thins the book. Units that fit pay the price on the board, then the overlay updates, so the next trade the same day sees the new price and the smaller quantity. A full book moves the buy price by 25% and leaves nothing to trade until the units decay.

## Lifecycle and determinism

1. **GST day:** \(day = \lfloor gst\_seconds / \text{SECONDS\_PER\_DAY} \rfloor\) (`GalacticCalendar`).
2. **`ensure_quotes`:** Decay pressure to the current day. If `session.market_quotes_day == day` and quotes are non-empty, skip the commodity recompute (fuel may still refresh). Otherwise recompute the base board and overlay pressure.
3. **New game / load:** The base board is rebuilt for the current day. Saved pressure is overlaid after decay for any days elapsed since `market_pressure_day`.

Same `catalog`, `day`, and `route_friction_delta` ⇒ identical `compute_quotes` output (see `tests/test_economy.gd` determinism test). The posted board also depends on pressure.

## Assumptions

- The tradable universe is exactly the commodity list in `commodities.json` (currently thirteen categories).
- One unified quote board per sector; habitat Exchange UI reads that sector’s map.
- Route graph is symmetric and undirected; multi-route redundancy is collapsed to shortest path.
- Friction is the only edge cost; cargo mass, refrigeration, or commodity type do not change reach.
- `base_price` is a global par anchor, not sector-specific.
- Economic coupling of the base board is linear in surplus and deficit magnitudes. Player trades thin the posted book and shift its price. They do not change the underlying flows.
- Tier affects posted price only, not flows.

## Explicitly out of scope (current implementation)

| Topic | Notes |
|-------|--------|
| NPC trades moving quotes | Only the player's buys and sells write `market_pressure` |
| `wealth` in flow or price formulas | Field remains in JSON for future or presentation |
| Population scaling | Baked into economy weights at authoring time |
| Unknown / private routes | Only `routes.json` public edges. Volatile grants are not economy edges; see [trade_network.md](../content/trade_network.md) |
| Per-commodity shipping cost in pricing | Friction is route-level, not cargo-level |
| Corporate presence (`corporate_presence.json`) | Does not adjust quotes |
| Refrigeration / cargo tags | Affect cargo rules, not `CommodityEconomy` |
| A second order book beside the posted quantity | Depth is the listing quantity and the pressure overlay |
| Commodity-specific tax, tariff, or Exchange fees | Beyond the 97% sell spread |
| Dynamic events without `route_friction_delta` | Blockades must mutate friction (or graph) before the next daily recompute |
| n>4 Unspace routing | Project scope: 4-space public graph only |
| Saving the posted board as authoritative | Saves carry GST time and `market_pressure`. The base board is re-derived on load |

## Test seams

Headless regression tests call these public helpers on `CommodityEconomy` (not used in production UI):

| Helper | Purpose |
|--------|---------|
| `price_ratio_for_test(demand, supply)` | Ratio clamp without graph or sign rule |
| `chosen_ratio_for_test(local_net, supply_eff, demand_eff)` | Sign rule on precomputed effective flows |
| `quote_analysis(catalog, sector_id, commodity_id, friction_delta)` | Local net, effective flows, reach map, graph/local/chosen ratios (no noise or tier) |

Run economy tests only: `GODOT=… godot --headless --path . --script res://tests/run_economy.gd`

## Regression checks

`tests/test_economy.gd` includes:

- Full sector × commodity listing shape and positive price/quantity
- Determinism and day-boundary rollover via `GameSession`
- Sell spread never above buy
- Route friction delta changes quotes
- **Beltworks export:** on a fixed GST day, `centauri_a_beltworks` **minerals** and **water_ice** buy prices are below `base_price` and below `proxima` for the same commodities
- **Local ratio saturation** - clamp thresholds via `price_ratio_for_test`
- **Graph influence** - synthetic three-sector fixture via `quote_analysis`
- **Network friction** - reach and supply_eff change under `route_friction_delta`; alternate-path reach
- **Route disconnection** - pending (edge removal not implemented)
- **Market usability** - multi-day route margin report (printed), positive spreads on representative routes (validates fixed flows + sign rule)

## Related future work

- Economic events that block edges (infinite friction) rather than only adding `route_friction_delta`
- Optional inclusion of discovered private routes as session-local graph overlays. Volatile mission translations are private navigation solutions; they are not economy edges
