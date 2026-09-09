# Ships

**Status:** Seven ship families below are **setting intent** from original `Ships.doc`. The **Tester** background starts with **Flare-ON SS** (first in fleet) plus one parked instance of every catalog template for shipyard testing at Proxima Habitat. Other backgrounds start with a single hull appropriate to their kit — see [overview.md](overview.md#player-backgrounds).

**Hull sales at Proxima Habitat:** **Concord Scouts** stocks used, manufacturer-fitted scout templates from the catalog. **Skyedge Space Ships** sells unfitted chassis frames; the Habitat Workshop fits modules. Used ship price is chassis list cost plus half the fitted module value.

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
| Pegasus | GVW Corp (defunct) | Civilian cargo / workhorse | P101, P103, P103a |
| Flare-ON | Holt-Winters | Sporty light craft | SS, SK |
| Krypton | Durbin-Watson | Mid-range saucer | K2, K3 |
| Wolff | Bayes Inc | Armed freighter / gunship | Warrior, Gladius |
| Dragon | Kolmogorov-Smirnov | Interceptor w/ hyperdrive | Gold |
| Juno | Bayes Inc | Light scout | 1045, 1088, 1090 |
| Silhouette | Oklahoma Combine | Tactical fighter | Mk8 |

---

## Pegasus

Originally designed and manufactured fifty years ago by the now defunct **GVW Corporation**, the Pegasus is arguably the most numerous space ship in the galaxy. It is a simple yet elegant design that has stood the test of time. Today there are multitudes still in service and maintenance is easily available, and indeed spare parts and chassis are still manufactured on many worlds. Many different configurations are available, but three are commonly found.

### P101

The original model and still the most common civilian configuration. The P101 heralded a revolution in space travel when it was marketed as the first affordable private space ship. It is mounted with a basic Mark 1 fusion engine and in modern times a mass driver cannon for defence. The original had a basic A1 life support system, making it an uncomfortable vessel by modern standards.

**Game instance:** Pegasus P101 — Mark 1 fusion, 5mm Chitanium armour, parked at Proxima Habitat.

### P103

The P103 was billed as the luxury model Pegasus when it was released. It features a similar configuration with the addition of a luxurious A3 life support system.

### P103a

Just before the liquidation of GVW, they released the P103a Pegasus. This craft featured a then cutting edge antimatter engine and a powerful nose mounted plasma cannon. It had limited success in the civilian market, but with the addition of an advanced targeting system it has become a common law enforcement vehicle throughout the galaxy.

---

## Flare-ON

Produced by the dynamic **Holt-Winters Corporation**, the small Flare-ON is a modern and exciting craft. HW sees the target market as affluent young civilians and have marketed the Flare as a sporty and fast ship. It is highly manoeuvrable and has indeed proved popular, both with the target market and with those who wish to get somewhere fast. HW has released two configurations.

### SS

The Flare-ON SS is the base model and features a powerful Mark 3 fusion engine that provides excellent acceleration to this light ship. It is armed with a rotating laser turret for self-defence. This configuration is by far the most common.

**Game instance:** Flare-ON SS — Mark 3 fusion, no armour, player starting ship.

### SK

The Flare-ON SK is a cutting edge craft and is becoming an increasingly common sight near the resort worlds of the galaxy. It is driven by a new gravitic engine that provides excellent near-orbit performance but limits its independent hyper-travel distance. It packs a punch with a powerful turbo laser turret and sports all the latest onboard software systems. Although intended as a rich man's toy, this craft has much potential as a second-generation planetary defence fighter.

---

## Krypton

The Krypton is the mainstay of the **Durbin-Watson Corporation** in the mid-range space ship market. It is a bizarre looking craft — styled after the flying saucers that appear in the re-popularised cinemagraphs of the mid twentieth century. It is highly manoeuvrable and capable of mounting a range of different equipment. DW market two major configurations.

### K2

This solid craft carries a Mark 3 fusion engine and mounts a basic laser turret. Despite not reaching the load limit of the chassis, this craft is still somewhat underpowered for its weight. It is none-the-less a popular ship that can fulfil a variety of roles.

### K3

The K3 is a large improvement on the K2, sporting an antimatter engine that provides significantly more thrust and acceleration.

---

## Wolff

The Wolff chassis was originally produced by **Bayes Inc**, and is still in regular service even though production has been discontinued. It is a solidly designed medium-weight craft, originally conceived as an armed freighter. Although it still fills this role today, the Wolff is a highly versatile weapons platform. Two configurations are commonly seen.

### Warrior

The Wolff Warrior is a modification of the original freighter configuration, removing the cargo capability in favour of a heavy scatter cannon to complement the existing unguided missile launcher. It also replaces the original fusion engine with a more powerful antimatter drive, making this a formidable craft in a fight.

### Gladius

The Gladius is a more modern upgrade of the Warrior.

---

## Dragon

The Dragon is the most recent ship produced by **Kolmogorov-Smirnov** and has been designed as a medium weight interceptor. It is one of the smallest vessels to mount its own hyper drive, making it an excellent tactical fighter. Only one configuration has been released to date.

### Gold

The Gold Dragon mounts a laser turret and a powerful plasma burst cannon, and carries an alpha class hyperdrive.

---

## Juno

The stubby Juno is an old design from **Bayes Inc**. It is a light craft that is only slightly less popular than the older Pegasus. Known configurations are the **1045**, **1088**, and **1090**.

---

## Silhouette

The Silhouette is a medium weight tactical fighter from the **Oklahoma Combine**. The **Mk8** configuration is most popular.

---

## Current implementation vs design gaps

| Item | Design | Original POC / notes |
|------|--------|----------------------|
| Pegasus P103a engine | Mark 2 Antimatter + plasma | Mark 2 Fusion in XML |
| Chassis hits | 10–40 (design sheet) | 1000 placeholder in XML |
| Weapons on player ships | Mass driver, lasers, etc. | Light laser and mass driver wired in this game |
| Hyperdrive on Dragon Gold | Alpha class | Not in current JSON |

Flight behaviour uses derived thrust, speed, and maneuver from assembled modules and loaded mass, with in-flight fuel, power, and compute simulation — see [equipment.md](equipment.md) and [architecture.md](../design/architecture.md).

### In prototype JSON (`ships.json`)

All fourteen manufacturer templates are catalogued with placeholder loadouts. Juno 1045/1088/1090 and Wolff Gladius configurations are **invented placeholders** where the design doc is sparse.

| Template id | Chassis | Notes |
|-------------|---------|-------|
| `flare_on_ss`, `flare_on_sk` | `flare_on_chassis` | SS = player default; SK = gravitic + turbo laser |
| `pegasus_p101`, `p103`, `p103a` | `pegasus_chassis` | P103a = law-enforcement antimatter + plasma |
| `krypton_k2`, `krypton_k3` | `krypton_chassis` | K2 fusion / K3 antimatter saucer |
| `wolff_warrior`, `wolff_gladius` | `wolff_chassis` | Missile + scatter gunship |
| `dragon_gold` | `dragon_chassis` | Interceptor + alpha hyperdrive (catalog only) |
| `juno_1045`, `1088`, `1090` | `juno_chassis` | Scout progression (placeholder) |
| `silhouette_mk8` | `silhouette_chassis` | Tactical fighter |
