# Galactic Standard Calendar and Time

**Status:** Calendar rules are setting canon. The Godot prototype implements GST tracking, a HUD/habitat clock, mapping-based translation lumps, and irregular unspace time flow.

The Galactic Standard Calendar (GSC) and Galactic Standard Time (GST) form the common civil timekeeping standard used across human space.

The system is derived from the historical Gregorian calendar but was redesigned for a civilization no longer dependent on Earth's orbital cycle. It retains familiar month names and the seven-day week while eliminating astronomical corrections and irregular month lengths.

## Calendar

A Standard Year consists of exactly **364 days**, divided into **52 weeks** and **12 months**.

The months follow a 4-4-5 pattern within each quarter:

| Month | Quarter | Length |
|---|---|---:|
| January | Q1 | 28 days |
| February | Q1 | 28 days |
| March | Q1 | 35 days |
| April | Q2 | 28 days |
| May | Q2 | 28 days |
| June | Q2 | 35 days |
| July | Q3 | 28 days |
| August | Q3 | 28 days |
| September | Q3 | 35 days |
| October | Q4 | 28 days |
| November | Q4 | 28 days |
| December | Q4 | 35 days |

Each quarter contains exactly **91 days**, or **13 weeks**.

There are no leap years and no leap days. The calendar is not synchronized with Earth's orbit, the seasons, or any other astronomical cycle.

The month names are retained from the historical Gregorian calendar for continuity and familiarity. Their original association with Earth's seasons and orbital position has no significance within the Standard Calendar.

## Standard Date

A Standard Date is written:

**[day] [month] [quarter] [year]**

For example:

**35 March Q1 2653**

The quarter designator is an explicit part of the date rather than being inferred from the month.

Examples:

- 12 February Q1 2653
- 35 March Q1 2653
- 1 April Q2 2653
- 28 May Q2 2653
- 35 June Q2 2653
- 14 September Q3 2653
- 35 December Q4 2653

Because every year contains exactly 52 weeks, a given Standard Date always falls on the same day of the week.

## Galactic Standard Time

**Galactic Standard Time (GST)** is the universal civil time standard used throughout human space.

A Standard Day consists of:

- 24 hours
- 60 minutes per hour
- 60 seconds per minute

GST contains no leap seconds or other astronomical corrections. It advances continuously according to the defined standard second.

The calendar and time system therefore have a completely fixed structure:

**1 year = 364 days = 52 weeks**  
**1 quarter = 91 days = 13 weeks**  
**1 day = 24 hours**  
**1 hour = 60 minutes**  
**1 minute = 60 seconds**

GST is used as the common reference for interstellar navigation, communications, contracts, commerce, shipping schedules, and other activities requiring a time standard shared between star systems.

Individual planets, stations, and habitats may maintain local time systems based on their own rotational cycles. Local time is used for everyday life, while GST provides the common reference for interstellar activities.

A typical timestamp might therefore be:

**35 March Q1 2653, 18:42:17 GST**

with the same event potentially expressed in a different local time by observers elsewhere.

## Prototype time flow

The near-orbit prototype advances GST as follows:

- **Realspace flight** and **habitat/building menus** — one GST second per real second (visible on HUD and habitat header with seconds resolution).
- **Entering unspace** at a jump gate — discrete GST lump from the route mapping (`entry_seconds`, with small random jitter).
- **Flying in unspace** — irregular pulses: time stalls, then jumps forward; higher N-space depth is more erratic.
- **Exiting unspace** at the portal — discrete GST lump from the same mapping (`exit_seconds`, with jitter).
- **Frozen** during main menu, pause overlay, save/load overlay, and jump-route picker.

New games start at **1 January Q1 2646, 08:00:00 GST** (configurable in `player.json`). Saves store `session.gst_seconds`.