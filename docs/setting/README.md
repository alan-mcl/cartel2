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
| [planets.md](planets.md) | Six starter systems, stats, cities, Unspace route table |
| [corporations.md](corporations.md) | Sixteen megacorporations |
| [ships.md](ships.md) | Ship families and configurations |
| [equipment.md](equipment.md) | Chassis, engines, armour, weapons, shields, LSS, hyperdrives |

## Current implementation

| Setting area | Current implementation |
|--------------|-----------|
| Sectors playable | Proxima, Bela (near orbit only) |
| Habitats | Proxima Habitat, Bela Orbital Habitat |
| Jump routes listed | Proxima ↔ Bela via flyable **4-space** (n=4 only) |
| Unspace hazards | Shear fields + debris in 4-space; hull stress (non-lethal) |
| GST clock | HUD + habitat; 1:1 in orbit/docked; mapping lumps + irregular unspace flow |
| Ship instances | Flare-ON SS (aboard), Pegasus P101 (parked) |
| Surface cities | Not implemented |

When redesigning, edit these markdown files first; then update JSON catalogs to match.
