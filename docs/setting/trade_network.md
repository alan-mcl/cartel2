# Public Unspace trade network

**Status:** The public route graph and daily commodity quotes are implemented in `data/catalog/routes.json` and `CommodityEconomy`. Economic events (blockades, friction spikes) and unknown/private routes are not yet implemented.

## Overview

The known interplanetary economy is a graph of **publicly known Unspace routes** connecting inhabited worlds. Routes represent reliable commercial translations, not physical proximity. The graph is deliberately incomplete — undiscovered mappings may exist outside the public network.

Three conceptual layers:

| Layer | Worlds |
|-------|--------|
| **Core** | Proxima, Irasia, Tokirev, New Carthage |
| **Mid** | Fortuna, Horizon, La Bella Vista, Pelagos |
| **Outer** | Tycho, Fennet, Titania IX |

## Route graph

28 undirected public connections are defined in [routes.json](../data/catalog/routes.json). Jump gates list **translations** available from the player's current sector (nav computer plus player library); the daily economy still uses the public 4-space edge graph and friction only. Extra translations on the same sector pair do not add economy edges.

### Core network

| Route | Friction |
|-------|---------:|
| Proxima ↔ Irasia | 15 |
| Proxima ↔ Tokirev | 20 |
| Proxima ↔ New Carthage | 15 |
| Irasia ↔ Tokirev | 20 |
| Irasia ↔ New Carthage | 25 |
| Tokirev ↔ New Carthage | 30 |

### Mid connections

See the full tables in design notes. Notable links include Fortuna to the core, Horizon as a regional hub, La Bella Vista through New Carthage, and Pelagos to the industrial core.

### Outer network

Tycho, Fennet, and Titania IX have sparse, high-friction connections. Fennet–Titania forms a small peripheral corridor.

## Friction

Each route has a friction value (0–100) representing combined translation duration, navigation difficulty, danger, and operational cost. Physical distance is irrelevant.

| Friction | Band |
|---------:|------|
| 0–20 | Excellent |
| 21–40 | Good |
| 41–60 | Moderate |
| 61–80 | Difficult |
| 81–100 | Hazardous |

In play, friction drives:

- **Jump overlay** — qualitative transit band (Excellent … Hazardous)
- **GST lumps** — `entry_seconds` and `exit_seconds` = `friction × 240` GST seconds
- **Commodity prices** — shortest-path friction between worlds reduces how effectively surpluses reach deficits

## Daily commodity markets

Each GST day (midnight reset), habitat Exchanges post buy and sell quotes for all thirteen commodity categories. Quotes are fixed until the next GST midnight; player trades do not move the board. Flows and specialisation come from per-sector profiles in [economies.json](../data/catalog/economies.json); par anchors from [commodities.json](../data/catalog/commodities.json). Settled worlds maintain a small baseline output of every category; belts and stations specialise without that floor (see [planets.md](planets.md) and [commodities.md](commodities.md)).

**Implementation specification** (equations, constants, sign rule, descoped behaviour): [commodity_economy.md](../design/commodity_economy.md).

Each habitat has an Exchange building. Sell quotes sit slightly below buy quotes so graph arbitrage remains viable in fiction and in play.

## Public vs unknown routes

The public graph is what jump gates and the daily economy share. Unknown routes discovered later can function as private commercial advantages without automatically joining the public economy.

## Economic events (future)

Events may block routes or raise effective friction via `session.route_friction_delta`. The next daily reset recalculates trade flows using the modified graph — no separate commodity logic required.
