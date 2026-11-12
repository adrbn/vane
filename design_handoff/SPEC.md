# Almanac — macOS 26 rebuild spec

All values in points. SF Pro only; `.monospacedDigit()` on every number. No uppercase, no tracking, no badges.

## Layout

| Element | Value |
|---|---|
| Base grid | 8 (4 only inside a component: icon↔label, label↔value) |
| Window corner radius | 24 (system default with toolbar) |
| Sidebar | `NavigationSplitView` default glass sidebar, 232 wide, inset 8, radius 16 |
| Sidebar row | 28 high, radius 8, icon 16 in accent, label 13 |
| Sidebar section header | 11 Semibold `.secondary`, 16 above / 4 below |
| Toolbar | 52 high; title + subtitle via `.navigationTitle` / `.navigationSubtitle` |
| Toolbar glass group / item | 32 / 24 high, capsule (`.glassEffect()` via default toolbar grouping) |
| Content insets | top 12, leading/trailing 24, bottom 24; toolbar title leading = content leading |
| Section gap | 24 |
| Card gap | 16 |
| Card | padding 16, radius 12, 1 pt `cardBorder`, fill `card` |
| Status / empty-state card | padding 24, 40 pt icon circle in `accentSoft` |
| Content button | `.controlSize(.small)`, 24 high, radius 6, fill `fill` |
| Table row / form row | 32 / 40 (52 with a caption) |
| Inspector | `.inspector` 304 wide |
| Sheet | 576 wide, radius 20 |
| Grids | `LazyVGrid(columns: [.flexible(minimum: 280)])`, rows stretch so cards in a row are equal height |

## Type scale

| Role | Size / line | Weight | SwiftUI |
|---|---|---|---|
| Hero number (one per screen) | 34 / 40 | Bold | `.system(size: 34, weight: .bold)` |
| Tile value | 28 / 34 | Semibold | `.system(size: 28, weight: .semibold)` |
| Status title | 22 / 28 | Bold | `.title2.bold()` |
| Lead insight, sheet title, report heading | 17 / 22 | Semibold | `.title3.weight(.semibold)` |
| Report prose | 15 / 24 | Regular | `.system(size: 15)` + `.lineSpacing(9)` |
| Toolbar title | 15 / 20 | Bold | system |
| Card title | 15 / 20 | Semibold | `.headline` scaled |
| Body, table cell | 13 / 18 | Regular | `.body` |
| Group label | 13 / 18 | Semibold | `.headline` |
| Control label | 12 / 16 | Medium | small control size |
| Caption, meta | 11 / 14 | Regular | `.caption` |
| Chart axis | 10 / 12 | Regular | `.caption2` |

## Color tokens

| Token | Light | Dark | SwiftUI |
|---|---|---|---|
| background | #FBFBFC | #1C1C1E | `Color(nsColor: .windowBackgroundColor)` |
| card | #FFFFFF | #262628 | `Color(nsColor: .controlBackgroundColor)` |
| cardBorder | black 8% | white 7% | `.separator` at 1 pt |
| label | black 88% | white 92% | `.primary` |
| label2 | black 56% | white 60% | `.secondary` |
| label3 | black 30% | white 32% | `.tertiary` (baselines, empty values) |
| separator | black 8% | white 8% | `.separator` |
| fill | black 5% | white 8% | `.fill.quaternary` (buttons, bar tracks) |
| fill2 | black 3% | white 4% | alternating table rows, quote wells |
| accent | from app icon | lighter variant | `.tint(app.accent)` |
| accentSoft | accent 13% | accent 26% | selection, icon wells |
| positive | #248A3D | #30D158 | `.green`, changes only |
| negative | #D70015 | #FF6B61 | `.red`, changes only |
| warning | #C93400 | #FFA733 | `.orange`, listing validation only |
| map ramp | accent mixed 20 / 34 / 50 / 70 / 92% into #E8E8EC / #37373B | | 5 bins, single hue |

Per-app accents used in the mockups: Nightjar indigo #5856D6 / #6865F0, Pebble teal #00829A / #2FB8CF.

## Charts

- Line 2 pt (detail) / 1.5 pt (sparklines) in accent; area fill accent 20% → 0% (detail) or flat 8% (sparklines). This is the only gradient.
- Baseline / last year: 1.5 pt dashed `label3`.
- Release markers: 1 pt `label2` at 50%, label 10 Semibold above.
- Hover: 1 pt rule, 4.5 pt dot with 2 pt card-colored ring, popover 184 wide.

## States

- **Nothing to flag**: status card (what was checked, when, next check) + "Watching" grid of each metric against its usual range band + "Recently resolved" list.
- **Data arriving (24–48 h)**: status card with 4 progress steps (done / waiting / to do), "Available now" sales card, "Waiting for Apple" grid saying when each metric fills in.
- Loading never shows skeleton bars; a value that isn't available is "—" in `label3` with the date it's expected.
