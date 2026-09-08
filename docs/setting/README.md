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
| [overview.md](overview.md) | Fantasy, era, currency, Unspace, Media Reality, Saint Apex, Sleepers, Asciidians, Atomic Problems |
| [date_time.md](date_time.md) | Galactic Standard Calendar and Time |
| [planets.md](planets.md) | Eleven E-type worlds, stats, cities, habitats |
| [corporations.md](corporations.md) | Sixteen megacorporations |
| [ships.md](ships.md) | Ship families and configurations |
| [equipment.md](equipment.md) | Chassis, engines, armour, weapons, shields, LSS, hyperdrives |
| [commodities.md](commodities.md) | Closed eleven-category trade roster |
| [trade_network.md](trade_network.md) | Public Unspace route graph, friction, daily markets |

## Current implementation

| Setting area | Current implementation |
|--------------|-----------|
| Sectors in catalog | Eleven near-orbit worlds from [planets.md](planets.md); New Game starts at Proxima |
| Habitats | One dockable habitat per sector (Proxima Habitat, La Bella Vista Habitat, …) |
| Jump routes listed | Full public graph (28 routes) via **4-space**; synthesized from `routes.json` |
| Unspace hazards | Edge-crossing velocity kicks + random mesh deformation in 4-space; soft radial bound near play rim; false proximity via shifting topography |
| GST clock | HUD + habitat; 1:1 in orbit/docked; friction-scaled mapping lumps + irregular unspace flow |
| Ship instances | Flare-ON SS (aboard), Pegasus P101 (parked) |
| Commodities | Eleven categories; daily quotes at every habitat Exchange |
| Market simulation | Daily GST reset from production/consumption + route friction |
| Surface cities | Not implemented |

When redesigning, edit these markdown files first; then update JSON catalogs to match.
