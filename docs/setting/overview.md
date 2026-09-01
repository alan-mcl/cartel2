# Setting overview

**Status:** Full setting intent from original design notes. The Godot prototype implements near-orbit flight in **Proxima** and **Bela** only; corporations, lore topics, and six-sector geography are documented here for future catch-up.

## Fantasy

**Cartel** is a corporate-space-trader game set centuries after Earth became uninhabitable. Humanity spreads across **E-type planets** linked by **Unspace** jump routes. Power rests with **sixteen megacorporations** holding sector monopolies — legal industrial giants, financial houses, media empires, and at least one outright criminal syndicate (Hamatomo Triad).

The player is an **independent operator**: trader, mercenary, outlaw, or entrepreneur carving a living between monopolies — moving goods, buying ships, and navigating a galaxy where law, media, and commerce rarely align.

## Era and tone

- Intended in-game calendar: **~2646 AD**.
- Hard-SF leaning: Unspace physics, cryogenic sleepers, recovered Earth time capsules, **Media Reality**, **Atomic Problems**.
- Asciidians: intelligent natives of Unspace (from design notes; not present in prototype gameplay).

## Currency

- **d** — galactic dollars.
- **Cash** — carried on the person; spent first.
- **Credit (eCash)** — bank balance; used when cash is insufficient.

The prototype tracks a single **credits** integer (no cash/credit split yet).

## Starter playground

Six connected sectors form the original POC world:

| Sector | Role |
|--------|------|
| Proxima | Galactic capital |
| Tycho | Harsh rim world |
| Bela | Water-world resort |
| Irasia | Commerce / industry |
| Tokirev | Factory world |
| New Fennet | Underdeveloped rim |

Details: [planets.md](planets.md). Prototype JSON: Proxima and Bela only.

## Megacorporations

Sixteen named corps appear in world data as **economic factions**, not military alliances. Summaries in [corporations.md](corporations.md); full prose for each.

Ten corps have lore but had **empty product lists** in the original POC catalog.

## Unspace

The scientific term for the higher-order dimensions through which matter can be moved is **n-space**. The public universally says **unspace**. **3-space** is ordinary realspace (planetary orbits). Higher N-spaces are abstract transit layers — routes go *deeper* into N-space.

Each known route stores a **solution** (integer code) and an **N-space depth**. Deeper N is **faster but more dangerous** (more shear, hazards, and hostile phenomena). This prototype implements only **4-space** — the shallowest Unspace layer above realspace.

### Translation flow (prototype)

1. At a **jump gate** in 3-space, pick destination and confirm **4-space**.
2. Ship enters a flyable 4-space layout; navigate shear fields and debris to an **exit portal**.
3. `[E]` at the exit portal to emerge in the destination sector's near orbit.

**Jump gates** inject travellers at a fixed entry point. **Hyperdrive-equipped ships** (future) will translate from other 4-space regions without needing the gate portal — see [equipment.md](equipment.md).

Solution **typing** at the gate is not implemented; known solutions are shown as flavour only.

## Media Reality

Truth and mass media were never close allies. Corporate sponsors, politics, and competition pushed reporting further from reality until laws required fiction labelled **MR** (Media Reality). MR reports appear beside genuine news but bear no relation to events. Teams of writers collaborate on MR content full-time.

## Saint Apex

Of all time capsules recovered from Earth, the most influential was launched by **Samson Thornton** — hacker alias **Apex**, later **Saint Apex** to followers.

Born near Sweetwater, Texas, late twenty-first century; isolated until thirteen, then given a computer. By fifteen he had hacked a major share-trading system and become one of America's most wanted cyber criminals — and probably the wealthiest, though he gave much away online.

Thornton preached a cynical, defiant Christianity to millions he never met. At eighteen he and armed followers seized a NASA launch at New Orleans, replacing the payload with a **time capsule**: revised bible, journals, personal items. The rocket was aimed into deep space; Thornton was killed in Brownwood, Texas, weeks later.

The capsule drifted centuries until recovery; his writings seeded a new cult.

## Sleepers

Some seek to defer death until medicine can cure them: cryogenic freezing plus **mind upload** into fault-tolerant hardware, sealed with century-strength encryption — while the body is clinically dead. Rumours persist about virtual worlds inside and whether sleepers will ever wake.

## Time capsules

Earth's last centuries produced probes and rockets carrying artefacts outward at sub-light speed. Occasional recovery revives lost culture — musicians, writers, religions centuries late.

## Jerusalem Ridge, Mars

When travellers returned to uninhabitable Earth, one human colony survived on Mars: **Jerusalem Ridge**, which wanted nothing to do with newcomers.

## Crimson Land

Common name for planet **BJE356DF** — red dust and exceptionally ferocious native life.

## Asciidians

Intelligent creatures inhabiting unspace dimensions. Humanity is not alone, but contact remains marginal in playable scope.

## Artificial intelligence and Atomic Problems

True self-aware AI remains unachieved — classified among **Atomic Problems**: problems that cannot be solved by decomposition into smaller problems (named after the abandoned search for fundamental particles).

Geoffrey Tensing proved the KPF n-space matrix must admit a root without infinite descent; he claimed the proof came in a dream of letters of fire. Most atomic problems remain open.

## Personal arms culture

Despite futuristic weapons, weight-conscious pilots favour **22-millimeter solid projectile pistols**: best mass efficiency, penetrates light armour, unlikely to breach ship internals unlike heavier kinetic or energy weapons. See [equipment.md](equipment.md).

## Design authority (for rebuilds)

1. Original Office design notes — intent and balance
2. Starter-world catalogs — topology and identities
3. POC / prototype behaviour — what was actually wired

When notes and instance data disagree, **design intent follows the notes** unless this setting bible is deliberately revised here first.
