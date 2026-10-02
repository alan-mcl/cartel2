# Setting index

Working bible for the Cartel setting. Content is **setting intent** — editable prose that may run ahead of `data/catalog/` JSON in the current game.

Each linked document opens with a **Status** note where relevant: what is playable today vs what is design target.

## Glossary

| Term | Meaning |
|------|---------|
| **Sector** | A star system; primary unit for orbital play and Unspace routing |
| **Planet** | Habitable E-type world within a sector; has surface cities and usually an orbital habitat |
| **Habitat** | Orbital city; default launch/dock hub for ships |
| **City Mall (CM)** | Enclosed consumer habitat (MicroDonald-style) |
| **Building** | Visitable location within a city or habitat |
| **Unspace / n-space** | Higher-order dimensions used for inter-sector travel |
| **Solution** | Integer code required to traverse a known Unspace route (stored in data; typing not yet implemented) |
| **d** | Galactic dollar |
| **Cash** | Carried on the person |
| **Credit (eCash)** | Bank balance |
| **E-type** | Earth-like planetary classification E1–E5 |
| **GST / GSC** | Galactic Standard Time / Calendar — interstellar civil time (364-day year) |

## Documents

| File | Contents |
|------|----------|
| [overview.md](overview.md) | Premise, backgrounds, worlds, Unspace, corporations, trade, culture |
| [date_time.md](date_time.md) | Galactic Standard Calendar and Time |
| [planets.md](planets.md) | Eleven E-type worlds, stats, cities, habitats |
| [corporations.md](corporations.md) | Sixteen megacorporations |
| [ships.md](ships.md) | Ship families and configurations |
| [equipment.md](equipment.md) | Chassis, engines, armour, weapons, shields, LSS, hyperdrives |
| [commodities.md](commodities.md) | Closed eleven-category trade roster |
| [trade_network.md](trade_network.md) | Public Unspace route graph, friction, daily markets |
| [missions.md](missions.md) | Passenger charters and mission intent |

## Current implementation

| Setting area | Current implementation |
|--------------|-----------|
| Sectors in catalog | Eleven near-orbit worlds from [planets.md](planets.md); New Game background selects starting habitat |
| Player backgrounds | Six kits in `backgrounds.json` (Tester default); callsign + portrait at New Game |
| Habitats | One dockable habitat per sector (Proxima Habitat, La Bella Vista Habitat, …) |
| Jump routes listed | Full public graph (28 routes) via **4-space**; synthesized from `routes.json` |
| Unspace hazards | Static irregular Delaunay topo in 4-space (no player velocity perturbations for now); fixed exit portal on a host face; 1–3 ambient Ascidians per visit |
| GST clock | HUD + habitat; 1:1 in orbit/docked; friction-scaled mapping lumps + irregular unspace flow |
| Ship instances | Background kits + buy at Proxima **Concord Scouts** (used fitted) or **Skyedge** (unfitted chassis) |
| Commodities | Eleven categories; daily quotes at every habitat Exchange |
| Market simulation | Daily GST reset from production/consumption + route friction |
| Surface cities | Not implemented |

When redesigning, edit these markdown files first; then update JSON catalogs to match.
