# Local field conditions

**Status:** Implemented in flight. **Translation stability** (percent for the current jump) appears on the top-right **Fields** panel while in Unspace (`Stability: N%`); it is not one of the ambient field samples below. Four ambient strengths are sampled at the player ship: **gravity** (G), **magnetic**, **radiant** (stellar flux), and **charged particle** (stellar wind, magnetically shaded when a dipole exists). Values are relative indices except gravity, which is expressed in G.

Sector instances carry a **`neighborhood`** block on `sectors.json` (see [planets.md](planets.md) per-world notes). Unspace uses a fixed profile: very low fluctuating gravity (~0.005–0.03 G), low constant radiant, fluctuating magnetic and particle indices.

Ships with a sensor module and the **`local_sensor`** capability show all four strengths on the flight HUD **Fields** panel. This is environmental readout, separate from the ship **signature** panel (detection emissions).

**Gravitic drives** scale forward/reverse thrust by local gravity relative to the habitat ring in-sector (clamped 0–1.5×). Near the planet is strongest; deep orbit is weak. In unspace the ambient G is tiny but fluctuating, so gravitic thrust is a small fraction of catalog rating.

**Integrated sail drives** scale thrust by a weighted mix of **radiant**, **charged particle**, and **magnetic** indices (50% / 30% / 20%), normalized so a typical habitat ring reads about 1.0× catalog thrust (cap 1.6×). They consume **no propulsion fuel** — only ship power while thrusting. Bright, windy sectors reward sails; unspace gives weak but non-zero drive. Worlds without a magnetic dipole still sail on stellar flux and particle wind.

All other engine types use full catalog thrust regardless of local fields (subject to power and fuel as usual).
