# Commodity economy

**Status:** Implemented in [`CommodityEconomy`](../../scripts/gameplay/commodity_economy.gd). Quotes are derived state: recomputed on GST day rollover and on load, not authored as save data. Setting context (route graph, friction bands, trade fiction): [trade_network.md](../setting/trade_network.md). Roster and categories: [commodities.md](../setting/commodities.md).

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

- `id` — snake_case key used in economies and quotes
- `base_price` — integer par value in credits before ratio, noise, and tier
- `mass` — used for cargo, not for pricing

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

**Settled-world produce floor.** Eleven settled worlds (sector ids in `CommodityEconomy.SETTLED_WORLD_SECTOR_IDS`, aligned with [planets.md](../setting/planets.md)) apply:

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
| 2 | `vulcan_research`, `centauri_a_beltworks`, `acb1`, `acb2`, `acb3`, `terminus`, `regulus_belt`, `denarius_ii`, `typhon_xvi` |

Population from `sectors.json` is **not** read by `CommodityEconomy`.

## Graph reach and effective supply/demand

Constants (code):

| Symbol | Code name | Value |
|--------|-----------|------:|
| Distance scale | `DISTANCE_SCALE` | 40 |
| Ratio stabiliser | `EPSILON` | 0.5 |
| Min / max ratio | `MIN_PRICE_RATIO` / `MAX_PRICE_RATIO` | 0.55 / 2.2 |
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
\text{ratio}(D, S) = \mathrm{clamp}\left( \frac{D + 0.5}{S + 0.5},\; 0.55,\; 2.2 \right)
\]

For sector \(s\):

- **Graph ratio:** \(\text{ratio}^{\text{graph}}_s = \text{ratio}(\text{demand}^{\text{eff}}_s, \text{supply}^{\text{eff}}_s)\)
- **Local ratio:** \(\text{ratio}^{\text{local}}_s = \text{ratio}(\text{deficit}_{s,c}, \text{surplus}_{s,c})\)

**Sign rule** (prevents a neighbour’s imbalance from inverting local role):

| Local net | Chosen ratio |
|-----------|--------------|
| \(\text{net}_{s,c} > 0\) (surplus) | \(\min(\text{ratio}^{\text{graph}}_s, \text{ratio}^{\text{local}}_s)\) — exporter stays at or below par |
| \(\text{net}_{s,c} < 0\) (deficit) | \(\max(\text{ratio}^{\text{graph}}_s, \text{ratio}^{\text{local}}_s)\) — importer stays at or above par |
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

**Listing quantity** (display-only, not enforced on trade volume):

\[
q_{s,c} = \max(1,\; \mathrm{round}(|\text{net}_{s,c}| \times 10))
\]

## Sell quote

\[
\text{sell}_{s,c} = \max(1,\; \mathrm{round}(0.97 \times \text{buy}_{s,c}))
\]

Implemented as `CommodityEconomy.sell_price(buy)` and `GameSession.commodity_sell_price`. Fixed until the next GST day boundary; player trades do not move buy or sell quotes intraday.

## Lifecycle and determinism

1. **GST day:** \(day = \lfloor gst\_seconds / \text{SECONDS\_PER\_DAY} \rfloor\) (`GalacticCalendar`).
2. **`ensure_quotes`:** If `session.market_quotes_day == day` and quotes non-empty, skip commodity recompute (still may refresh fuel). Otherwise `market_quotes = compute_quotes(catalog, day, route_friction_delta)`.
3. **New game / load:** Quotes rebuilt for the current day when first needed or on rollover.

Same `catalog`, `day`, and `route_friction_delta` ⇒ identical `compute_quotes` output (see `tests/test_economy.gd` determinism test).

## Assumptions

- The tradable universe is exactly the commodity list in `commodities.json` (currently thirteen categories).
- One unified quote board per sector; habitat Exchange UI reads that sector’s map.
- Route graph is symmetric and undirected; multi-route redundancy is collapsed to shortest path.
- Friction is the only edge cost; cargo mass, refrigeration, or commodity type do not change reach.
- `base_price` is a global par anchor, not sector-specific.
- Economic coupling is linear in surplus/deficit magnitudes with no diminishing returns or stock depletion.
- Tier affects posted price only, not flows.

## Explicitly out of scope (current implementation)

| Topic | Notes |
|-------|--------|
| Player or NPC trades moving quotes | Intraday quotes are fixed; volume is unlimited at listed buy/sell prices |
| `wealth` in flow or price formulas | Field remains in JSON for future or presentation |
| Population scaling | Baked into economy weights at authoring time |
| Unknown / private routes | Only `routes.json` public edges; see setting [trade_network.md](../setting/trade_network.md) |
| Per-commodity shipping cost in pricing | Friction is route-level, not cargo-level |
| Corporate presence (`corporate_presence.json`) | Does not adjust quotes |
| Refrigeration / cargo tags | Affect cargo rules, not `CommodityEconomy` |
| Order book, bid/ask depth, contract enforcement | `quantity` on listings is flavour |
| Commodity-specific tax, tariff, or Exchange fees | Beyond the 97% sell spread |
| Dynamic events without `route_friction_delta` | Blockades must mutate friction (or graph) before the next daily recompute |
| n>4 Unspace routing | Project scope: 4-space public graph only |
| Saving quotes as authoritative | Saves carry GST time; quotes re-derived on load for consistency |

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
- **Local ratio saturation** — clamp thresholds via `price_ratio_for_test`
- **Graph influence** — synthetic three-sector fixture via `quote_analysis`
- **Network friction** — reach and supply_eff change under `route_friction_delta`; alternate-path reach
- **Route disconnection** — pending (edge removal not implemented)
- **Market usability** — multi-day route margin report (printed), positive spreads on representative routes (validates fixed flows + sign rule)

## Related future work

- Economic events that block edges (infinite friction) rather than only adding `route_friction_delta`
- Optional inclusion of discovered private routes as session-local graph overlays
- Typed `CommodityTraded` events and subsystem reactions (see [refactor_backlog.md](refactor_backlog.md))
