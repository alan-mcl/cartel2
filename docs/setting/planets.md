# Planets and sectors

**Status:** Six-sector catalog is **setting intent** (from original POC world data). The Godot prototype implements **Proxima** and **Bela** near-orbit only — habitats, jump gates, beacons, wrecks, debris. Surface cities and four other sectors are documented for redesign and future JSON catch-up.

## Spatial model

```
Sector (star system)
├── Planet (habitable E-type world)
│   └── City | Habitat
│       └── Building
├── Jump Gate (orbital, dockable)
└── Unspace mappings → other sectors
```

Every starter planet has an orbital **habitat** on its roadmap — the usual launch and dock point for ships. Habitats use explicit type flags in a full rebuild; the original POC inferred habitat from naming.

## Sectors summary

| Sector | Numeric id | Planet | Jump gate | Role |
|--------|------------|--------|-----------|------|
| Proxima Sector | 528 | Proxima | Proxima Jump Gate | Galactic capital |
| Tycho Sector | −132 | Tycho | Tycho Jump Gate | Harsh rim world |
| Bela Sector | −10810 | Bela | Bela Jump Gate | Water-world resort |
| Irasia Sector | 7487 | Irasia | Irasia Jump Gate | Commerce / industry |
| Tokirev Sector | 29861 | Tokirev | Tokirev Jump Gate | Factory world |
| New Fennet Sector | 2590 | New Fennet | New Fennet Jump Gate | Underdeveloped rim |

Prototype JSON uses string ids `proxima` and `bela` (numeric ids reserved for Unspace canon).

## Planet statistics

| Planet | Class | System | Pop | Temp | Ocean | Default entry |
|--------|-------|--------|-----|------|-------|---------------|
| Proxima | E1 | Alpha Centauri | 6B | 21°C | 81% | Proxima Habitat |
| Tycho | E3 | Acturus | 3B | 23°C | 62% | Tycho Habitat |
| Bela | E4 | Beta Pisces | 2.5B | 20°C | 92% | Bela Orbital Habitat |
| Irasia | E5 | Epsilon Hydra | 6B | 17°C | 76% | Irasia Habitat |
| Tokirev | E2 | Pyxis | 5.6B | 15°C | 62% | Tokirev Habitat |
| New Fennet | E1 | Tau Eridani | 2B | 20°C | 78% | New Fennet Habitat |

---

## Proxima

**Classification:** E1  
**System:** Alpha Centauri  
**Radius:** 1.05 Earth  
**Population:** 6 billion  
**Ocean coverage:** 81%  
**Average temperature:** 21°C  

Proxima was the first E-type planet discovered and colonised by humans, and is today the **galactic capital**. It is a lush, densely populated world with many large cities.

### Cities

Concord (capital hub), New Atlanta, Loch Grumman, Greenfields CM, Century CM, Safeharbour CM, **Proxima Habitat**.

### Prototype orbit (JSON)

Near-orbit entities: Proxima Habitat, Proxima Jump Gate, three nav beacons, derelict wreck (+d850 salvage), debris field, planet limb, dust ring at play bounds 3500. Player spawn (−400, −150).

Habitat buildings in prototype: Terminal, Davidsons (pilot bar), Skyedge Space Ships (merchant, closed), Habitat Workshop.

---

## Tycho

**Classification:** E3  
**System:** Acturus  
**Radius:** 0.89 Earth  
**Population:** 3 billion  
**Ocean coverage:** 62%  
**Average temperature:** 23°C  

Although on paper Tycho seems a tame world, the reality is quite different. Tycho is an E-type planet where none should be: amongst a family of fifteen G-type gas giants orbiting a fierce blue star. It suffers from frequent eclipses, wildly fluctuating magnetic poles, and severe earth tremors and volcanoes.

### Cities

Ozero, **Tycho Habitat**.

**Prose TBD for redesign** — surface detail beyond the above.

---

## Bela

**Classification:** E4  
**System:** Beta Pisces  
**Radius:** 0.95 Earth  
**Population:** 2.5 billion  
**Ocean coverage:** 92%  
**Average temperature:** 20°C  

Bela is a water world with only one continental land mass. It is the most popular holiday resort in the galaxy. All year round the rich and idle flock to the idyllic atolls of Bela, or visit its mega-casinos and orbital hotels.

### Cities

Oberon, Santa Margarita, **Bela Orbital Habitat**.

Notable landmark: Watershed Stadium (Oberon cricket) — from original world catalog.

### Prototype orbit (JSON)

Bela Orbital Habitat, Bela Jump Gate, two beacons, drift wreck (Santa Margarita flavour, +d420 salvage), debris, water-tinted planet limb, play bounds 3200. Player spawn (200, −100).

Habitat buildings: Bela Orbital Terminal, Habitat Workshop (shared workshop id).

---

## Irasia

**Classification:** E5  
**System:** Epsilon Hydra  
**Population:** 6 billion  
**Ocean coverage:** 76%  
**Average temperature:** 17°C  

### Cities

La Palma, Fairhaven CM, **Irasia Habitat**.

**Prose TBD for redesign** — commerce/industry role from sector summary only.

---

## Tokirev

**Classification:** E2  
**System:** Pyxis  
**Population:** 5.6 billion  
**Ocean coverage:** 62%  
**Average temperature:** 15°C  

### Cities

Kaliningrad, **Tokirev Habitat**.

**Prose TBD for redesign** — factory-world role from sector summary only.

---

## New Fennet

**Classification:** E1  
**System:** Tau Eridani  
**Population:** 2 billion  
**Ocean coverage:** 78%  
**Average temperature:** 20°C  

### Cities

Belfast, **New Fennet Habitat**.

**Prose TBD for redesign** — underdeveloped rim; original POC left short description undefined.

---

## Unspace route table

Directed edges: `(from_sector, solution) → to_sector`. Canonical integers from original sector definitions.

### Proxima Sector (528)

| To | Solution |
|----|----------|
| Bela | **42** |
| Tycho | 900008 |
| Irasia | −7620 |
| Tokirev | 2901 |
| New Fennet | 955249 |

### Tycho Sector (−132)

| To | Solution |
|----|----------|
| Bela | 77335 |
| Proxima | −10 |
| Tokirev | 662 |
| New Fennet | 2 |

### Bela Sector (−10810)

| To | Solution |
|----|----------|
| Proxima | **−34458** |
| Irasia | 99 |
| Tokirev | 79999 |

### Irasia Sector (7487)

| To | Solution |
|----|----------|
| Bela | 36 |
| Tycho | 900008 |
| Proxima | 3 |
| Tokirev | 96636 |

### Tokirev Sector (29861)

| To | Solution |
|----|----------|
| Bela | 23412745 |
| Tycho | 6780032 |
| Irasia | −4395625 |
| Proxima | −55 |
| New Fennet | −88327 |

### New Fennet Sector (2590)

| To | Solution |
|----|----------|
| Tycho | 88105 |
| Tokirev | −44 |
| Proxima | 623 |

**Smoke-test route:** Proxima → Bela with solution **42** (canonical test path).

Prototype JSON: only Proxima ↔ Bela mappings are loaded; other routes await sector expansion.

## Notable buildings (original six-system world)

Thirty buildings total in the POC catalog — sample categories:

**Merchants (distributor-linked):** Skyedge Space Ships, Concord Scouts, Grumman Distributors, Tower Ships, Jasons Hardware, BCD Suppliers, Bobs Guns, Self Defence Emporium.

**Landmarks:** Concord Central Hub, Davidsons (pilot bar), habitat terminals/docks, City Mall interfaces.

Prototype implements a subset at Proxima and Bela habitats only.

## Proxima distances (design reference)

From original spreadsheet: pairwise km between Concord, New Atlanta, Loch Grumman, Greenfields CM, Century CM, Safeharbour CM, Proxima Habitat. All habitat legs **2000 km**; longest surface leg Concord ↔ New Atlanta **10849 km**. Relevant when surface travel and roadmaps are implemented.
