# Almanac themes

Four selectable themes share one layout system. Every screen exists in every theme (see design/themes/*.dc.html). Values are points; colors are sRGB.

## Structural switches

| | Ticker | Color Blocks | Nocturne | Candy Glass |
|---|---|---|---|---|
| Navigation | 80 pt icon rail | glass sidebar 224 | glass sidebar 224 | glass sidebar 224 |
| App Store layout | watchlist (400) + full-height chart | bento grid | bento grid | bento grid |
| Metric tiles | card, color = direction (green/red) | solid color fill per metric | card + metric color | card + gradient icon |
| Hero container | none | solid accent card | none (glow behind) | gradient card |
| Background | true black | flat gray | dark violet + 2 soft radial glows | pastel radial wallpaper |
| Font | SF Pro | SF Pro Display | SF Pro Display | SF Pro Rounded |

## Tokens

| Token | Ticker (2e) | Color Blocks (2f) | Nocturne (1a) | Candy Glass (1c) |
|---|---|---|---|---|
| font | `-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif` | `-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif` | `-apple-system,BlinkMacSystemFont,"SF Pro Display",sans-serif` | `ui-rounded,"SF Pro Rounded",-apple-system,BlinkMacSystemFont,sans-serif` |
| bg | `#000000` | `#EDECF1` | `#0E0A1C` | `radial-gradient(60% 70% at 8% 0%, #FFD8C8 0%, rgba(255,216,200,0) 100%), radial-gradient(60% 70% at 95% 5%, #D7D1FF 0%, rgba(215,209,255,0) 100%), radial-gradient(70% 60% at 55% 105%, #C6EEFF 0%, rgba(198,238,255,0) 100%), #F6F4FA` |
| desktop | `#0A0A0B` | `#DCDBE3` | `#0B0816` | `#E9E5F2` |
| label | `#FFFFFF` | `#111111` | `#FFFFFF` | `#1D1D1F` |
| label2 | `#8E8E93` | `#62626C` | `rgba(255,255,255,0.62)` | `#6E6E73` |
| label3 | `#48484A` | `#A9A9B2` | `rgba(255,255,255,0.34)` | `#AEAEB2` |
| sep | `#1C1C1E` | `rgba(0,0,0,0.07)` | `rgba(255,255,255,0.08)` | `rgba(0,0,0,0.06)` |
| sep2 | `#2C2C2E` | `rgba(0,0,0,0.14)` | `rgba(255,255,255,0.16)` | `rgba(0,0,0,0.12)` |
| fill | `#1C1C1E` | `rgba(0,0,0,0.05)` | `rgba(255,255,255,0.08)` | `rgba(0,0,0,0.05)` |
| fill2 | `#0D0D0E` | `rgba(0,0,0,0.03)` | `rgba(255,255,255,0.035)` | `rgba(255,255,255,0.5)` |
| side | `#0D0D0E` | `#FFFFFF` | `rgba(255,255,255,0.05)` | `rgba(255,255,255,0.55)` |
| sideBorder | `#1C1C1E` | `transparent` | `rgba(255,255,255,0.08)` | `rgba(255,255,255,0.85)` |
| sideShadow | `none` | `none` | `none` | `0 8px 30px rgba(80,60,140,0.08)` |
| navSel | `#2C2C2E` | `#EDECF1` | `rgba(255,255,255,0.1)` | `rgba(255,255,255,0.95)` |
| card | `#0D0D0E` | `#FFFFFF` | `rgba(255,255,255,0.055)` | `rgba(255,255,255,0.72)` |
| cardBorder | `#1C1C1E` | `transparent` | `rgba(255,255,255,0.08)` | `rgba(255,255,255,0.95)` |
| cardShadow | `none` | `none` | `none` | `0 8px 24px rgba(80,60,140,0.07)` |
| cardBlur | `none` | `none` | `blur(20px)` | `blur(24px)` |
| r | `16px` | `28px` | `20px` | `24px` |
| rS | `8px` | `12px` | `10px` | `12px` |
| accent | `#30D158` | `#4433E0` | `#8B6CFF` | `#7A4CF0` |
| accentText | `#30D158` | `#4433E0` | `#B9A8FF` | `#6A3DE0` |
| accentSoft | `rgba(48,209,88,0.16)` | `rgba(68,51,224,0.12)` | `rgba(139,108,255,0.22)` | `rgba(122,76,240,0.12)` |
| onAccent | `#000000` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| pos | `#30D158` | `#12804A` | `#4BE3A0` | `#1E9E62` |
| neg | `#FF453A` | `#D93025` | `#FF6B7A` | `#E5484D` |
| warn | `#FF9F0A` | `#C25E00` | `#FFB547` | `#D9730D` |
| glass | `#1C1C1E` | `#FFFFFF` | `rgba(255,255,255,0.08)` | `rgba(255,255,255,0.72)` |
| glassBorder | `#2C2C2E` | `transparent` | `rgba(255,255,255,0.1)` | `rgba(255,255,255,0.95)` |
| segSel | `#3A3A3C` | `#111111` | `#FFFFFF` | `#1D1D1F` |
| segText | `#FFFFFF` | `#FFFFFF` | `#0E0A1C` | `#FFFFFF` |
| hero | `76px` | `124px` | `112px` | `88px` |
| heroW | `700` | `800` | `700` | `800` |
| heroTrack | `-0.03em` | `-0.05em` | `-0.045em` | `-0.035em` |
| num | `30px` | `48px` | `32px` | `30px` |
| numW | `600` | `800` | `600` | `800` |
| title | `22px` | `22px` | `22px` | `22px` |
| titleW | `800` | `800` | `700` | `800` |
| heroBg | `transparent` | `#4433E0` | `transparent` | `linear-gradient(135deg,#6C5CFF 0%,#A44EF2 55%,#FF6EAE 100%)` |
| heroFg | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` | `#FFFFFF` |
| heroFg2 | `#8E8E93` | `rgba(255,255,255,0.8)` | `rgba(255,255,255,0.62)` | `rgba(255,255,255,0.86)` |
| heroPad | `0px` | `28px` | `0px` | `28px` |
| popover | `#1C1C1E` | `#FFFFFF` | `#221B3A` | `#FFFFFF` |
| field | `#0D0D0E` | `#FFFFFF` | `rgba(255,255,255,0.06)` | `rgba(255,255,255,0.9)` |
| scrim | `rgba(0,0,0,0.6)` | `rgba(20,18,40,0.28)` | `rgba(6,4,14,0.62)` | `rgba(60,40,110,0.18)` |
| sheet | `#161618` | `#FFFFFF` | `#1B1530` | `rgba(255,255,255,0.94)` |
| mapBase | `#1C1C1E` | `#E4E3EA` | `rgba(255,255,255,0.07)` | `#E7E3F0` |
| winShadow | `0 0 0 1px rgba(255,255,255,0.14), 0 30px 70px rgba(0,0,0,0.35)` | `0 0 0 1px rgba(0,0,0,0.08), 0 30px 70px rgba(0,0,0,0.14)` | `0 0 0 1px rgba(255,255,255,0.08), 0 30px 70px rgba(0,0,0,0.35)` | `0 0 0 1px rgba(0,0,0,0.08), 0 30px 70px rgba(0,0,0,0.16)` |

## Metric colors

| Metric | Ticker (2e) | Color Blocks (2f) | Nocturne (1a) | Candy Glass (1c) |
|---|---|---|---|---|
| imp | green ↑ / red ↓ | `#FF6A4D on #1F0E08` | `#4DA3FF` | `#4C7DFF` |
| pv | green ↑ / red ↓ | `#C9F26B on #18200A` | `#9B7BFF` | `#7B5CFF` |
| ttr | green ↑ / red ↓ | `#141414 on #FFFFFF` | `#FF5FA2` | `#FF4F8B` |
| dl | green ↑ / red ↓ | `#4433E0 on #FFFFFF` | `#FFB547` | `#A44EF2` |
| redl | green ↑ / red ↓ | `#7CC6FF on #08243A` | `#2FE0C8` | `#1FB6C9` |
| conv | green ↑ / red ↓ | `#FFFFFF on #111111` | `#3DD68C` | `#FF8A3D` |

## Section colors (sidebar icon squares)

| Section | Color Blocks (2f) | Nocturne (1a) | Candy Glass (1c) |
|---|---|---|---|
| insights | `#FF6A4D` | `#FFB547` | `linear-gradient(135deg,#FFC65C,#FF8A3D)` |
| listing | `#7CC6FF` | `#4DA3FF` | `linear-gradient(135deg,#5AB8FF,#4C7DFF)` |
| reviews | `#C9F26B` | `#FF5FA2` | `linear-gradient(135deg,#FF8BC0,#FF4F8B)` |
| appstore | `#4433E0` | `#8B6CFF` | `linear-gradient(135deg,#A88BFF,#7B5CFF)` |
| sales | `#141414` | `#3DD68C` | `linear-gradient(135deg,#5BE39B,#1FB87A)` |
| usage | `#FFB020` | `#FF8A3D` | `linear-gradient(135deg,#FFA65C,#FF6A3D)` |
| territories | `#2BB673` | `#2FE0C8` | `linear-gradient(135deg,#3FE3C0,#1FB6C9)` |

## Layout rules (all themes)

- 8-pt grid; 4 only inside a component. Window radius 24. Card radius = theme `r`; small controls = `rS`; sidebar/inspector = `r − 4`; settings groups = `r − 8`.
- Toolbar 72 high, title 22 pt (weight = theme `titleW`) + 12 pt subtitle. Title block starts ≥ 20 pt from the window top; content leading edge = title leading edge (28 pt from sidebar).
- Content insets: 12 top, 24 trailing/bottom. Nothing may end closer than 24 pt to the window edge; text never closer than 20 pt to any card edge (card padding 20–28).
- Empty space rule: cards hug their content. When a row must stretch (grid rows sharing height), the extra space goes to the chart or sparkline in that card (flex-grow, capped at 72 pt for sparklines), never between a label and its value. Use fixed gaps (12–24), not "push to bottom", unless the bottom element is an action row.
- A grid row that holds no chart sizes to content (`auto`); only chart rows may be `1fr`.
- One hero number per screen at theme `hero` size; tile values at `num`. Contrast ratio between hero and body ≥ 6×.
- Sheets and popovers: always centered in the window, on a scrim (`scrim`) with a 10 pt background blur; width 600; content hugs (no fixed-height text areas).
- Changes: relative % for counts, percentage points for rates; |Δ| < 0.05 pts shows "No change" in secondary color.
- Truncation: single-line labels ellipsize; never clip text against a container edge.
