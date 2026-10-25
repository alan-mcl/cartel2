# Ships

**Status:** Eight ship families below are **setting intent** from original `Ships.doc` plus the Mantis interceptor line. The **Tester** background starts with **Flare-ON SS** (first in fleet) plus one parked instance of every catalog template for shipyard testing at Proxima Habitat. Other backgrounds start with a single hull appropriate to their kit - see `data/catalog/backgrounds.json`.

**Hull sales at Proxima Habitat:** **Concord Scouts** stocks used, manufacturer-fitted scout templates from the catalog. **Skyedge Space Ships** sells unfitted chassis frames; **Centauri Shipyard** fits modules. Used ship price is chassis list cost plus half the fitted module value.

## Composition model

A space ship is assembled from a fixed chassis and installed modules:

```
SpaceShip
├── Chassis (required, fixed)
├── modules[] (slot → module_id)
├── fuel_current, ammunition{}, cargo{}
└── derived stats + operating state (in flight)
```

| Field | Description |
|-------|-------------|
| **name** | Instance call sign |
| **type / subtype / maker** | Catalog metadata |

### Families at a glance

| Family | Maker (typical) | Role | Configurations |
|--------|-----------------|------|----------------|
| Pegasus | GVW Corp (defunct) | Civilian cargo / workhorse | P101, P103, P103a, P105, P107, P109, P111, P113, P115 |
| Flare-ON | Holt-Winters | Sporty light craft | SS, SK, CX |
| Krypton | Orion Aerospace | Mid-range saucer | K2, K3, K4 |
| Wolff | Bayes Inc (defunct) | Armed freighter / gunship | Warrior, Gladius, Bastion, Logistico |
| Dragon | Seven Bells Inc | Interceptor w/ hyperdrive | Bronze, Gold, Post |
| Juno | General Industrial | Light scout / freighter | 1030, 1045, 1060, 1088, 1090 |
| Silhouette | Oklahoma Combine | Tactical fighter | Mk8, Mk6, Warden |
| Mantis | The Praetorium | Dedicated interceptor | XF900, XF4400, XF5700 |

---

## Pegasus

Originally designed and manufactured fifty years ago by the now defunct **GVW Corporation**, the Pegasus is arguably the most numerous space ship in the galaxy. It is a simple yet elegant design that has stood the test of time. Today there are multitudes still in service and maintenance is easily available, and indeed spare parts and chassis are still manufactured on many worlds. Many different configurations are available; the catalog lists the most common trims by model number.

### P101

The original model and still the most common civilian configuration. The P101 heralded a revolution in space travel when it was marketed as the first affordable private space ship. It is mounted with a basic GI-HT-18 hydro-thermal engine and in modern times a mass driver cannon for defence. The original had a basic life support system, making it an uncomfortable vessel by modern standards.

### P103

The P103 was billed as the luxury model Pegasus when it was released. It features a similar configuration with the addition of a luxurious A3 life support system and still hauls freight.

### P103a

Just before the liquidation of GVW, they released the P103a Pegasus. This craft featured a then cutting edge antimatter engine and a powerful nose mounted plasma cannon. It had limited success in the civilian market, but with the addition of an advanced targeting system it has become a common law enforcement vehicle throughout the galaxy.

### P105

Long-haul trim: spartan habitat bunks, a large hold, generous fuel, and hydro-thermal drive. Built for crews who sleep aboard between ports rather than day hops.

### P107

Survey and picket trim: long-range listen array, modest fuel, minimal cargo, and a light laser for show. Trades hold space for sensor reach.

### P109

Budget interceptor: chemical or compact fusion drive, light plate, light and medium lasers, no cargo. Cheaper and slower than the P103a law ship.

### P111

Charter and VIP transport: luxury cabin, Helios deflector and Ionique energy shields, no cargo bay. The P103 still hauls freight; the P111 carries guests.

### P113

Convoy escort: rocket launcher, plate, medium fuel, and a small hold. Support gunship on a civilian frame - not a Wolff-class heavy.

### P115

Station shuttle: four-berth habitat, small fuel, no weapons and no meaningful hold. Hopper work between docks and habitats.

---

## Flare-ON

Produced by the dynamic **Holt-Winters Corporation**, the small Flare-ON is a modern and exciting craft. HW sees the target market as affluent young civilians and have marketed the Flare as a sporty and fast ship. It is highly manoeuvrable and has indeed proved popular, both with the target market and with those who wish to get somewhere fast. HW has released several configurations.

### SS

The Flare-ON SS is the base model and features a Sundancer Compact direct-fusion drive that provides excellent acceleration to this light ship. It is armed with a rotating laser turret for self-defence. This configuration is by far the most common.

**Game instance:** Flare-ON SS - Sundancer Compact, no armour, player starting ship.

### SK

The Flare-ON SK is a cutting edge craft and is becoming an increasingly common sight near the resort worlds of the galaxy. It is driven by a Sundancer Loft gravitic engine that provides excellent thrust where local gravity is strong (near the planet and habitat ring) but falls off in deep orbit and only weak, fluctuating thrust in unspace. It packs a punch with a powerful turbo laser turret and sports all the latest onboard software systems. Although intended as a rich man's toy, this craft has much potential as a second-generation planetary defence fighter.

### CX

Courier trim: Sundancer Compact fusion, a parcel bay, and solo transit air. **Unarmed** - the SS is the sport hull with a laser; the CX only carries the package.

---

## Krypton

The Krypton is the mainstay of **Orion Aerospace** (formerly marketed under Durbin-Watson) in the mid-range space ship market. It is a bizarre looking craft - styled after the flying saucers that appear in the re-popularised cinemagraphs of the mid twentieth century. It is highly manoeuvrable and capable of mounting a range of different equipment.

### K2

This solid craft carries a Bellatrix Main 44 hydro-thermal engine and mounts a basic laser turret. Despite not reaching the load limit of the chassis, this craft is still somewhat underpowered for its weight. It is none-the-less a popular ship that can fulfil a variety of roles.

### K3

The K3 is a large improvement on the K2, sporting a Bellatrix Trace antimatter engine that provides significantly more thrust and acceleration.

### K4

Passenger trim: Orion cabin life support, small cargo, and a light laser. The K2 hauls freight; the K3 is fast; the K4 carries people.

---

## Wolff

The Wolff chassis was originally produced by **Bayes Inc**, and is still in regular service even though production has been discontinued. It is a solidly designed medium-weight craft, originally conceived as an armed freighter. Although it still fills this role today, the Wolff is a highly versatile weapons platform.

### Warrior

The Wolff Warrior is a modification of the original freighter configuration, removing the cargo capability in favour of a Brutus scatter cannon and replacing the fusion engine with antimatter. The published fit is unarmoured: a small antimatter tank, a Glimmer Ember, and an Almanac. The trimmed full load is about 30 t of the 42 t limit. A full tank does not leave room for the Bellatrix rocket and missile racks or the Disruptor. The yard still sells those weapons.

### Gladius

The Gladius is a more modern upgrade of the Warrior: Privy Seal Null antimatter, a deflector, heavier plate, and the same scatter cannon. The rocket rack does not fit a full tank.

### Bastion

The original armed freighter trim: fusion drive, a short unguided rocket rack, light plate, and a ten-tonne hold. A full tank will not lift the twenty-tonne bay. If there is money in the route, somebody has done it in a Bastion.

### Logistico

Bulk freighter trim: ten-tonne hold, habitat bunks, fusion drive, and one light laser - no rocket launcher and no scatter cannon. A full tank will not lift the twenty-tonne bay. The Bastion is armed; the **Logistico** is the hold.

---

## Dragon

The Dragon is the most recent ship from **Seven Bells Inc** (Kolmogorov-Smirnov heritage) and has been designed as a medium weight interceptor. It is one of the smallest vessels to mount its own hyper drive, making it an excellent tactical fighter.

### Bronze

Earlier in-system patrol trim: compact fusion, light laser, light plate - no translation gear.

### Gold

The Gold Dragon mounts a laser turret and a powerful plasma burst cannon, and carries an alpha class hyperdrive.

### Post

Translation courier: alpha hyperdrive, compact fusion, light laser, no plasma. Bronze patrols in-system; Gold is the fighter; Post carries mail and parcels between systems.

---

## Juno

The stubby Juno is an old design now built by **General Industrial**. It is a light craft that is only slightly less popular than the older Pegasus. Known configurations include unarmed freighter **1030**, budget scout **1045**, picket **1060**, mid scout **1088**, and long-hop **1090**.

### 1030

Unarmed cargo freighter: hydro-thermal drive, modest life support, and the largest hold that fits the frame. No weapons.

### 1060

Scout picket: strong sensors for the chassis, small fuel, one light laser, no cargo bay.

---

## Silhouette

The Silhouette is a medium weight tactical fighter from the **Oklahoma Combine**.

### Mk8

The **Mk8** configuration is the popular contract fighter - dual medium hardpoints and a heavy sensor fit.

### Mk6

A lighter contract trim on the same chassis.

### Warden

Patrol picket: strong sensors, turbo laser, light plate, and Bellatrix point defence. The Mk8 is the contract fighter; the Warden holds the orbit.

---

## Mantis

The Mantis is an unusual hull in a galaxy of armed traders: **The Praetorium** designed it as a dedicated interceptor, optimised for manoeuvrability, speed, and firepower rather than cargo or crew comfort. Fittings assume a single pilot with minimal cabin life support and almost no hold space.

### XF900

The **XF900** is the original series, no longer in production. Survivors still appear on used lots and in reserve squadrons.

### XF4400

The **XF4400** is the current mid-tier production model - faster drives and a heavier weapons fit than the retired XF900.

### XF5700

The **XF5700** is the top-line interceptor configuration in current manufacture, pairing Privy Seal Null antimatter with a turbo laser, plus SnedOS electronic shielding and cyberwall for contested lanes. The Chimera plasma burst and its cells do not fit the hull.

---

## Current implementation vs design gaps

| Item | Design | Original POC / notes |
|------|--------|----------------------|
| Pegasus P103a engine | Ionique Annihilon antimatter + plasma | Mark 2 Fusion in XML |
| Chassis hits | 10–40 (design sheet) | 1000 placeholder in XML |
| Weapons on player ships | Mass driver, lasers, etc. | Light laser and mass driver wired in this game |

Flight behaviour uses derived thrust, speed, and maneuver from assembled modules and loaded mass, with in-flight fuel, power, and compute simulation - see [equipment.md](equipment.md) and [architecture.md](../architecture/architecture.md).

### In catalog (`ships.json`)

**Thirty-three** manufacturer templates with launch-legal loadouts. Juno 1045/1088/1090 and Wolff Gladius configurations remain **invented placeholders** where the design doc is sparse; role trims (P105–P115, CX, K4, Logistico, Post, Warden, Juno 1030/1060) extend the roster on existing chassis.

| Template id | Chassis | Notes |
|-------------|---------|-------|
| `flare_on_ss`, `flare_on_sk`, `flare_on_cx` | `flare_on_chassis` | SS = player default; SK = gravitic + turbo laser; CX = unarmed courier |
| `pegasus_p101`, `p103`, `p103a`, `p105`–`p115` | `pegasus_chassis` | P103a = law-enforcement antimatter + plasma; P105–P115 = role trims |
| `krypton_k2`, `krypton_k3`, `krypton_k4` | `krypton_chassis` | K2 fusion / K3 antimatter / K4 passenger |
| `wolff_warrior`, `wolff_gladius`, `wolff_bastion`, `wolff_logistico` | `wolff_chassis` | Bastion = armed freighter; Logistico = bulk hold |
| `dragon_bronze`, `dragon_gold`, `dragon_post` | `dragon_chassis` | Gold/Post = alpha hyperdrive |
| `juno_1030`, `1045`, `1060`, `1088`, `1090` | `juno_chassis` | 1030 unarmed cargo; scouts 1045–1090 |
| `silhouette_mk8`, `silhouette_mk6`, `silhouette_warden` | `silhouette_chassis` | Mk8 contract fighter; Warden picket |
| `mantis_xf900`, `mantis_xf4400`, `mantis_xf5700` | `mantis_chassis` | Praetorium interceptors; XF900 legacy |
