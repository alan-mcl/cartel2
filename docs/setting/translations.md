# Translation and navigation stability

**Status:** Playable for jump-gate selection, nav inventory, accuracy, and per-jump stability. Learning, copying, and hyperdrive-initiated translation are not implemented. Higher-order (5-space and 6-space) translations use the same transit field presentation as 4-space until layer-specific environments exist.

## Stored translations

Interstellar travel uses **N-space translations** (Unspace). A translation is a stored navigation solution, not a destination code.

Each record is conceptually:

`(source sector, solution integer) → (N-space layer, destination sector)`

The same source and destination may have several translations through different N-space layers. Solution integers identify the stored solution; the player does not calculate them.

Public commercial translations live in [`routes.json`](../../data/catalog/routes.json). Each route edge has a friction value for trade and charter timing; one or more **translation** entries supply `n`, directional solutions, and optional tuning.

## Navigation computer

The ship’s **navigation computer** (`category: navigation`, separate from sensors and compute cores) stores a finite set of translation records. **`nav_rating`** (0–100) drives solution **accuracy**. **`translation_capacity`** is how many directed translations the computer can hold at once.

Fill policy in play:

- Every **public 4-space** translation from the current sector is always loaded (routine commercial travel).
- Remaining slots take higher-order translations the computer tier supports (`nav_rating` ≥ 55 → 5-space, ≥ 75 → 6-space), preferring lower N and easier routes.
- Player **library** entries can surface translations above the computer tier, still at that computer’s accuracy.

The player also has a **translation library** (saved, empty on a new game). Library entries are unioned into the jump list when the ship is at the matching source. Access does not copy solutions onto the ship; a basic computer still shows a learned 6-space solution but computes low accuracy for it.

Mechanics to acquire, buy, or copy translations are future work.

## Jump gates and translation beacons

**Jump gates** are large, expensive installations at populous central locations (the eleven settled worlds and similar hubs). At a jump gate, only translations whose **source** is the current sector are offered, subject to the navigation computer fill policy above: all public 4-space routes from the sector, eligible higher-order translations, and matching library entries.

**Translation beacons** are smaller devices used at minor sites where a full gate is uneconomic. A beacon is programmed for **one destination sector** only. In play it offers the single **public 4-space** translation to that destination. Higher-order translations and library-only solutions are not available from a beacon, even if the ship could use them at a gate.

## Jump selection

At a jump gate or translation beacon, the player initiates through the same orbit interaction. Each offered line shows:

`solution: destination via N-space, Accuracy X%, expected duration Y`

The player picks one translation. Initiation is through the gate in the current build; hyperdrive initiation is separate future work.

## Accuracy vs stability

**Accuracy** is the nav computer’s confidence in the chosen solution before the jump. It depends on equipment rating, translation ease, and N-space depth—not on current compute load.

**Stability** is rolled when the jump is confirmed. It reflects accuracy, N-space depth, available compute headroom, compute integrity, and a small random spread. Stability is shown in flight on the **Fields** HUD panel (`Stability: N%`) and is cleared on emergence; it is not a permanent ship stat.

Future Unspace hazard and environment systems will consume stability and N-space; they are not wired in this pass.

## Time and friction

**Friction** on a route edge still drives commodity markets and charter deadlines for the **public 4-space** path.

When the player flies a specific translation, GST **entry** and **exit** lumps use that translation’s expected duration (friction-based seconds scaled by `duration_scale` for higher-order solutions). Public 4-space scales remain unchanged from the pre-inventory model.

## Prototype limits

- 5-space and 6-space jumps load the existing 4-space field mesh; session and HUD report the real N.
- Stability does not yet alter ascidians, portal placement rules, or field geometry beyond existing solution/N seeding.
