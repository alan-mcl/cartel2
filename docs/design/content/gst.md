# GST in play

The calendar itself is setting canon: [date_time.md](../../setting/date_time.md). This note is how the running game advances that clock.

The game advances GST as follows:

- **Realspace flight** and **habitat/building menus** - one GST second per real second (visible on HUD and habitat header with seconds resolution).
- **Changing buildings within a docked habitat** - fifteen GST minutes per tram hop (logged in the status strip).
- **Entering unspace** at a jump gate - discrete GST lump from the **selected translation** (`entry_seconds`, with small random jitter). Public 4-space lumps match `friction × 240` GST seconds each way; higher-order translations use shorter catalog `duration_scale`.
- **Flying in unspace** - irregular pulses: time stalls, then jumps forward; higher N-space depth is more erratic.
- **Exiting unspace** at the portal - discrete GST lump from the same translation (`exit_seconds`, with jitter).
- **Frozen** during main menu, pause overlay, save/load overlay, and jump-route picker.

New games start at **1 January Q1 2646, 08:00:00 GST** (configurable in `player.json`). Saves store `session.gst_seconds`.
