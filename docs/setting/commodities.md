# Commodity roster

**Status:** The closed eleven-category roster is implemented in `data/catalog/commodities.json`. Every habitat Exchange lists daily quotes from `CommodityEconomy`. See [trade_network.md](trade_network.md).

## Overview

The interplanetary economy uses eleven broad commodity categories. These represent the principal classes of physical and informational goods traded through the Unspace network.

Categories are deliberately broad. Individual products are not simulated separately unless a particular gameplay system requires that level of detail.

The commodity roster should remain **closed** unless a future economic or gameplay requirement identifies a meaningful class of trade that cannot be represented by one of these categories.

## Categories

### 1. Food Products

Agricultural and processed food products intended for human consumption.

This includes ordinary foodstuffs, preserved foods, nutritional products, and other consumable food commodities.

### 2. Pharmaceuticals

Medicines and pharmaceutical products.

This represents medical commodities that are sufficiently valuable and standardised to be traded between worlds.

### 3. Consumer Goods

Ordinary manufactured goods intended for civilian consumption.

This is a broad category covering the everyday products of an industrial consumer economy that are imported rather than produced locally.

### 4. Data

Information transported physically between worlds on storage media.

Data is treated as a tradable commodity rather than as an abstract service. The cargo therefore occupies physical cargo capacity despite potentially representing enormous quantities of information.

The category includes commercially valuable information and digital products where the information itself is the object being transported.

### 5. Energy

Energy stored in transportable media.

This category covers charged storage cells, packs, and capacitors shipped to markets that consume more power than they store locally. It is physical cargo, not grid electricity as an abstract service.

### 6. Industrial Components

Manufactured components and equipment used as inputs to industrial production and infrastructure.

This represents the ordinary hardware required to maintain, repair, and expand industrial systems.

### 7. Chemicals

Chemical products used as industrial, agricultural, and other production inputs.

The category encompasses commodity chemicals without requiring individual chemical substances to be simulated separately.

### 8. Advanced Raw Materials

Specialised raw materials and advanced physical materials used in high-value industrial production.

These are distinct from ordinary Chemicals and Industrial Components and represent materials whose particular properties make them economically valuable.

### 9. Luxury Goods

High-value discretionary goods associated with wealth, status, leisure, and premium consumption.

Luxury Goods are primarily consumed by affluent populations and are therefore particularly sensitive to differences in wealth and market demand between worlds.

### 10. Military Goods

Goods intended for military, security, and defence applications.

This provides a single broad commodity category for military equipment and supplies rather than modelling individual weapons or military systems.

### 11. Compute

Specialised computational hardware.

Compute Cores are distinct from Data: Data represents information being transported, while Compute Cores represent the physical computational infrastructure required to process that information.

They are potentially high-value, compact industrial goods and can therefore be economically significant despite the limited cargo capacity of Unspace-capable ships.

## Summary

| # | Commodity | Catalog id |
| -: | ---------------------- | ------------------------ |
| 1 | Food Products | `food_products` |
| 2 | Pharmaceuticals | `pharmaceuticals` |
| 3 | Consumer Goods | `consumer_goods` |
| 4 | Data | `data` |
| 5 | Energy | `energy` |
| 6 | Industrial Components | `industrial_components` |
| 7 | Chemicals | `chemicals` |
| 8 | Advanced Raw Materials | `advanced_raw_materials` |
| 9 | Luxury Goods | `luxury_goods` |
| 10 | Military Goods | `military_goods` |
| 11 | Compute | `compute_cores` |

## Distinctions

| Pair | Distinction |
|------|-------------|
| **Energy vs Chemicals** | Energy is stored power in transportable media; Chemicals are production inputs, not a power source. |
| **Data vs Compute Cores** | Data is the information itself; Compute Cores are the physical hardware required to process it. |
| **Chemicals vs Advanced Raw Materials** | Chemicals are commodity production inputs; Advanced Raw Materials are specialised materials whose particular properties make them economically valuable. |
| **Industrial Components vs ship spare parts** | Industrial Components are tradable cargo. Ship module spare parts (`spare_parts` in session state) are a separate shipyard inventory system. |

## Cargo hold requirements

Seven categories require installed cargo-bay **capabilities** on the carrying ship (AND of flags; any bay may supply each flag). See [equipment.md](equipment.md) (Cargo bays).

| Category | Required capability |
|----------|-------------------|
| Food Products | `refrigerated` |
| Pharmaceuticals, Chemicals | `biohazard` |
| Luxury Goods, Data | `secure_cargo` |
| Military Goods | `military_grade` |

Consumer Goods, Energy, Industrial Components, and Advanced Raw Materials use ordinary dry holds. The Exchange **blocks buys** when the selected ship lacks the required hold; **sells** remain allowed so you can offload cargo after refitting.

## Current implementation

| Feature | Status |
|---------|--------|
| Eleven categories in catalog | Implemented |
| Per-ship cargo holds | Implemented |
| Cargo-bay capability flags on modules | Implemented |
| Exchange buy gated by hold capabilities | Implemented |
| Habitat Exchange buy/sell | Implemented (daily quotes, all eleven habitats) |
| Multi-market arbitrage | Implemented (graph-driven price differences) |
| Market stock depletion | Not implemented (contract depth is display-only) |
| Planet production/consumption | Implemented (`economies.json` + daily reset) |
| Economic events / blockades | Not implemented (`route_friction_delta` reserved) |
