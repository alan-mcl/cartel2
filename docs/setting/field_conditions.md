# Local field conditions

**Status:** Implemented in flight. Four ambient strengths are sampled at the player ship: **gravity** (G), **magnetic**, **radiant** (stellar flux), and **charged particle** (stellar wind, magnetically shaded when a dipole exists). Values are relative indices except gravity, which is expressed in G.

Sector instances carry a **`neighborhood`** block on `sectors.json` (see [planets.md](planets.md) per-world notes). Unspace uses a fixed profile: very low fluctuating gravity (~0.005–0.03 G), low constant radiant, fluctuating magnetic and particle indices.

Ships with a sensor module and the **`local_sensor`** capability show all four strengths on the flight HUD **Fields** panel. This is environmental readout, separate from the ship **signature** panel (detection emissions).

**Gravitic drives** scale forward/reverse thrust by local gravity relative to the habitat ring in-sector (clamped 0–1.5×). Near the planet is strongest; deep orbit is weak. In unspace the ambient G is tiny but fluctuating, so gravitic thrust is a small fraction of catalog rating. Other engine types are unaffected.
