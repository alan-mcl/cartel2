# Missions

**Status:** Passenger charters are the first catalog-backed mission type. Other work (cargo, combat, plot) remains design target.

## Passenger charters

Routine habitat-to-habitat passages sold at orbital **terminals** (posted departures, corporate and bulk civilian traffic) and, separately, informal **bar** fares at pilot bars such as Davidsons on Proxima. Terminal and bar boards use different role profiles and blurbs in catalog data; bar fares are smaller parties and lower pay, with no corporate passengers. A charter names a destination habitat, a party profile (role, headcount, comfort tier), and a fee. Terminal corporate parties may be tied to a megacorporation drawn from local presence; sensitive corporate roles expect the pilot to hold affiliation with that corporation (standing not implemented yet).

Role titles, comfort requirements, blurbs, and pay tuning live in `data/catalog/passenger_missions.json`. Destinations are one Unspace hop away on the public route graph. Each new game draws a **run seed** stored with the save; daily boards mix that seed with the GST day and habitat so day-one charters differ between playthroughs while staying stable for a given save until the calendar advances.

## Freight charters

**Freight charters** are virtual consignments posted at orbital **terminals** on a dedicated **Freight Charters** tab beside passenger departures. They do not put Exchange stock into the ship’s cargo manifest; accepting a lot **reserves tonnes** (and any special seat, compute, or power draw) against the selected docked hull the same way passenger headcount reserves life support. Pay lands when the pilot **docks at the destination habitat** on the contracted ship.

Catalog data lives in `data/catalog/freight_missions.json`. Commodity-linked lots inherit mass and hold requirements from the SKU; **special** lots (livestock, cognition crates, culture lockers) use bespoke blurbs and may reserve life support seats, compute units, or reactor headroom. The player reads the formatted description (“2 stud horses…”), not an abstract cargo type name. Destinations and daily boards use the same one-hop route graph and run-seed mixing as passenger charters.
