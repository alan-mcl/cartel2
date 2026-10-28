# Missions

**Status:** Passenger, freight, scan, and bounty charters are catalog-backed. Optional background **plotlines** expose derived gig records via `MissionSubsystem.list_plot_gigs` (no desk UI yet); see [plotlines.md](plotlines.md). Named-NPC dialogue is not implemented. Scan charters (other than a planet target) and bounty charters grant a volatile translation; the travel rules are in [architecture.md](../architecture/architecture.md).

## Bounty charters

Board copy lists the wanted callsign, site, and threat label only. At the volatile site the return gate and primary target are placed at random within the site annulus (seeded from the offer id). Each bounty ship has hidden posture, resolve, transponder, patrol style, pilot skill, and (when they flee) an escape route. Oblivious contacts ignore you until you are very close or you fire first; stealthy ones stay dark until you are in range; aggressive ones hunt with active sensors. Fleeing targets may run for deep space (contract lost), the entry beacon, or a hyperdrive translation; beacon and hyperdrive escapes can be chased through Unspace and back to the origin system before they reach dock.

## Pilot standing

Each pilot carries a **reputation** score: how well known they are among brokers, terminals, and charter desks. Higher is better. Most backgrounds begin at **0** (unknown). The **Outlaw** begins at **5** - a name on the rim from smuggling and merc work, not yet someone institutions book. **Old Money** begins at **8** - a family name brokers have heard, without much freight behind it. **Influencer** begins at **25** - recognised from streams and sponsorship tags, not yet trusted for sealed institutional work. Rough bands: around **15** a working name, **25–40** recognised, **50** trusted for sealed institutional freight, **75** the sort of pilot officials put on diplomatic parties.

An on-time passenger or freight delivery raises reputation by **1**. A late delivery, passengers abandoning a late charter at the wrong habitat, or cancelling at the origin lowers it by **1**. The score never falls below **0**. Fifteen clean deliveries is enough to reach the threshold for touring performers and bonded luxury freight.

That score is separate from **sanctions**: recorded infractions with a monetary fine. Any outstanding sanction blocks launch from a habitat until the pilot pays the total at the terminal. Firing on another ship in settled space adds an unlawful-fire sanction; destroying a ship adds a heavier one. Shots in Unspace are not recorded yet. The **Outlaw** begins with one unlawful-fire sanction and enough cash to pay it and keep d250. Charter desks do not yet refuse pilots for sanctions on the record. Charter reputation minimums are a separate gate.

## Passenger charters

Routine habitat-to-habitat passages sold at orbital **terminals** (posted departures, corporate and bulk civilian traffic) and, separately, informal **bar** fares at pilot bars such as Davidsons on Proxima. Terminal and bar boards use different role profiles and blurbs in catalog data; bar fares are smaller parties and lower pay, with no corporate passengers. A charter names a destination habitat, a party profile (role, headcount, comfort tier), and a fee. Terminal corporate parties may be tied to a megacorporation drawn from local presence; sensitive corporate roles expect the pilot to hold affiliation with that corporation (standing not implemented yet).

Role titles, comfort requirements, blurbs, and pay tuning live in `data/catalog/passenger_missions.json`. Terminal boards may post **multi-hop** routes (up to catalog `max_hops` on the public route graph); bar fares stay one hop. Multi-hop passenger contracts require **habitat** life support (`ls_habitat`) so the party can live aboard between jumps. Each offer includes a **deadline** in GST hours: per-hop **entry and exit** jump-gate translation (matching route mappings), catalog **orbit time** per hop while GST runs in-sector, plus extra slack. Pay on delivery at the destination if the pilot arrives on time; a late arrival withholds pay and charges the cancellation fee. Passengers who miss the deadline while docked anywhere other than the destination leave the charter and pay that same fee. Charter penalties may overdraw credits; ordinary purchases cannot.

Some passenger **roles** require a minimum pilot **reputation** (touring performers, influencer parties, security consultants, diplomatic parties). The terminal shows the threshold on the offer tile; the pilot cannot accept until their score meets it. Corporate principals still expect affiliation with the posting corporation (standing not implemented yet).

Some **freight** cargo types use the same gate (bonded luxury, prototypes, race animals, museum objects under seal).

Each new game draws a **run seed** stored with the save; daily boards mix that seed with the GST day and habitat so day-one charters differ between playthroughs while staying stable for a given save until the calendar advances.

## Freight charters

**Freight charters** are virtual consignments posted at orbital **terminals** on a dedicated **Freight Charters** tab beside passenger departures. They do not put Exchange stock into the ship’s cargo manifest; accepting a lot **reserves tonnes** (and any special seat, compute, or power draw) against the selected docked hull the same way passenger headcount reserves life support. Pay lands when the pilot **docks at the destination habitat** on the contracted ship. **Launch** is refused when commodity mass plus reserved freight tonnes exceed that hull’s cargo capacity.

Catalog data lives in `data/catalog/freight_missions.json`. Commodity-linked lots inherit mass and hold requirements from the SKU; **special** lots (livestock, cognition crates, culture lockers) use bespoke blurbs and may reserve life support seats, compute units, or reactor headroom. The player reads the formatted description (“2 stud horses…”), not an abstract cargo type name. Terminal freight may use multi-hop destinations and the same deadline rules as passengers (late delivery at the destination withholds pay and charges the cancellation fee; freight does not walk off at intermediate habitats). Penalties may overdraw credits.
