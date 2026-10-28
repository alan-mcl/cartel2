# Backlog

Open work only. Nothing here is approved until it is picked up. Status stays **Discuss** until then. When an item is picked up, set **Status** to `In progress`, then remove it in the same change as the work. Run `./scripts/ci/check.sh` before that.

What the code does today: [architecture.md](architecture.md). What is explicitly not built: [architecture.md](architecture.md#not-yet-implemented).

## Bugs

| ID | Area | Sev | Desc |
|----|------|-----|------|
|B1| modules | low | per-chemistry fuel tank SKUs, and reactor fuel for fission and fusion plants.
|B2| UI | med | Leaderboard: "Tonnes" should say Freight, Career Time should be in in-game GST rather than player-time.
|B4| gameplay | low | ship sprites that appear/disappear from the HUD due to sensor range / stealth should fade in and out instead of winking

## Features

| ID | Area | Sev | Desc |
|----|------|-----|------|
|F1|in flight|high| Unspace remainder after F5–F8: infinite unspace navigation, and randomised player spawn plus exit-portal placement|
|F2|in flight|high| Sectors should support infinite lateral movement, just tiling background into infinity|
|F5|in flight|high| Unspace phase 2. N-space flux: a few seconds of hull stress and a velocity kick, rate from instability. See below.|
|F6|in flight|high| Unspace phase 3. Unspace folds rotate the backdrop and exit by a multiple of 360/N around the player. See below.|
|F7|in flight|high| Unspace phase 4. Unspace shards: moving impacts, speed and rate from instability. See below.|
|F8|in flight|high| Unspace phase 5. Ascidians sting on scan, fold nearby geometry, drift in when unstable, and shed shards. See below.|

## Unspace N 4–9

Status: **Discuss**. Do these in order: F5, F6, F7, F8. F1 is what remains after them (infinite navigation, randomised spawn and portal placement).

Public routes already carry 4-space on every edge and a few 5- and 6-space alternates. Transit loads the catalog row matching translation N (`n4_default` … `n9_default`). Hull stress exists and ends the career at zero hull, but nothing calls it. Stability is `translation_stability` (higher is safer). Nav computers can use or display deeper layers up to N 9 at `nav_rating` 95; the public book still only lists N 4–6.

Instability for hazards is `1 - stability/100`, further scaled by depth `(N - 4)`. A calm 4-space crossing stays quiet; a poor solution in 9-space does not.

The public book stays N 4–6. N 7–9 exist only as private solutions: already in the translation library (buy or learn, later), or computed in flight with a fitted hyperdrive. Leave infinite unspace navigation and n>4 trade edges out. Update `docs/design/content/n-space.md` and `translations.md` in each phase that changes behaviour. Do not edit frozen setting files. Remove the matching F-row in the same change as the work.

### F5 — N-space flux

A short storm (a few seconds) while in Unspace. Mean time between storms shrinks as instability and N rise; 4-space at high stability almost never rolls one.

A gameplay `RefCounted` decides start and end. While active it calls `apply_hull_stress` and emits a random velocity kick for the flight controller to apply. Log a line on the HUD tape. A palette flash on the backdrop is enough visually.

### F6 — Unspace folds

Occasionally rotate the backdrop mesh and the exit portal by `k × (360 / N)` degrees, `k` in `1 .. N-1`. The player ship and Ascidians keep their world positions and headings; only the field and the portal swing around the player. Same instability schedule as flux, independent rolls so they can overlap. Radar blips for the portal follow the new position.

### F7 — Unspace shards

Moving hazards in the play disc. Count, speed, and spawn rate rise with instability and N. They are contacts, not pooled projectiles. A hit applies hull stress and a smaller velocity kick than flux, then the shard shatters or glances off. They show on the local radar when the ship has sensors. They do not home.

### F8 — Ascidians

Drive behaviour from instability and from being scanned.

- **Scan sting.** A scan zaps the hull once and shoves the ship. Higher instability, harder sting.
- **Local fold.** Sometimes an Ascidian warps nearby backdrop faces around itself, which can swing the exit if it lies in that patch.
- **Attention.** Low stability makes the nearest Ascidian drift toward the ship. It does not ram.
- **Shed.** On a pulse, one may drop a shard on its heading.

Inhabitant counts on the per-N catalog row make 9-space busier than 4-space.

### Checks

Headless tests for the duration curve (an N 9 lump is about one tenth of N 4 on the same friction), no public route row above N 6, `max_n_for_nav_rating(95) == 9`, a completed hyperdrive calculation appends a library solution and a failed one does not, and a forced flux or shard calls hull stress only while in Unspace. A fold angle is a multiple of `TAU / N` and does not move the player. Backdrop parameters differ by N. Run `./scripts/ci/check.sh` at the end of each phase.


