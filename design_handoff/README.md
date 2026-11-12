# Handoff: Almanac — macOS 26 redesign

## Overview
Almanac is a native macOS 26 app (SwiftUI, Liquid Glass) for indie iOS developers: App Store Connect analytics, stored and processed locally, no server. This package redesigns the whole app so it reads like a first-party Apple app (Stocks, Xcode Organizer), fixing: inconsistent spacing, unfinished-looking placeholders, large empty areas, uneven card heights, weak hierarchy between page controls and content.

Target user: a solo developer who opens the app daily for ~30 seconds. Each screen has **one** number that must read at a glance (the "hero").

## Start here: themes (current direction)
The chosen direction is **four selectable themes** sharing one layout system: **Ticker**, **Color Blocks**, **Nocturne**, **Candy Glass**. Build the theme engine first, then the screens once.
- `THEMES.md`: structural switches, full token table per theme, metric and section colors, and the **layout rules** (margins, empty-space rule, centered blurred sheets, change formatting). These rules override the base spec where they differ.
- `Themes.swift`: the four themes as data (`AlmanacTheme.all`), ready for a Settings → Appearance picker.
- `design/themes/Almanac <Theme>.dc.html`: every screen in that theme (Insights, inspector, Nothing to flag, App Store, Data arriving, Metric detail, Territories, Reviews, Reply sheet, Listing, Weekly report, Settings). `design/themes/AlmanacThemed.dc.html` is the single component; its logic class holds the theme tokens (`THEMES`), sample data and chart math.
- Per-theme structure: Ticker uses an 80 pt icon rail and a watchlist + chart App Store; the others use the glass sidebar and a bento App Store grid. Everything else is identical across themes.

The sections below describe the original restrained version (`design/Almanac.dc.html`). Screen content, copy, states and interactions still apply to every theme. The "Hard rules" on color and gradients apply only to that restrained version; the themes intentionally relax them.

## About the design files
Files in `design/` are **design references built in HTML**: prototypes showing the intended look and behavior, not code to ship. Recreate them in SwiftUI using the codebase's existing patterns (or standard SwiftUI if the codebase has none). Open `design/Almanac.dc.html` in a browser to see every screen in light and dark at 1240 × 820; each window is interactive. `design/AlmanacWindow.dc.html` is the single window component (all screens live in it, switched by the `screen` prop); its logic class at the bottom of the file contains the sample data and the chart math.

## Fidelity
**High fidelity.** Colors, type, spacing, radii and copy are final. Match them using system components (`NavigationSplitView`, `.toolbar`, `.inspector`, `.sheet`, `Table`, Swift Charts, `Form` with `.formStyle(.grouped)`), and let Liquid Glass come from the system — do not hand-draw glass.

## Hard rules (restrained version)
- SF Pro only (system font). `.monospacedDigit()` on every number. No monospace labels.
- No uppercase or tracked labels, no pill badges, no emoji.
- One accent per app, sampled from its icon, applied with `.tint()`. Green/red **only** for change values. Orange **only** for listing validation. Otherwise grays.
- No gradients except the area fill under the detail chart (accent 20% → 0%).
- 8-pt grid (4 allowed inside a component). One card radius (12), one card padding (16).
- Page controls go in the toolbar; content starts with the hero number.
- Empty and pending states are real states: what happened, what happens next, when.

## Window structure (all main screens)
- `NavigationSplitView`, window 1240 × 820 reference size, corner radius 24 (system).
- **Sidebar**: system glass sidebar, 232 wide, inset 8 from window edges, radius 16.
  - Traffic-light row 44 high.
  - App switcher: 48 high row, radius 10, fill `fill`; 32 pt app icon (radius 7.5) + name (13 Semibold) + "iOS · Version 2.4.1" (11 secondary) + up/down chevron. Menu lists the developer's apps.
  - Group 1 (no header): Insights (count "3", plain secondary text, not a badge), Listing, Reviews ("7").
  - "Analytics" header (11 Semibold secondary, 16 above / 4 below): App Store, Sales, Usage, Territories.
  - "Pinned charts" header: user-pinned metrics (e.g. First-time downloads, Conversion rate, Proceeds). Empty: "Pin any chart to keep it here. Pinned charts refresh with the rest of your data." (11 secondary).
  - Footer: refresh glyph + "Updated today at 6:12 AM" (11 secondary) / "Next refresh at 6:00 PM" (11 tertiary).
  - Rows 28 high, radius 8, 16 pt SF Symbol in accent, label 13 Regular. Selected: `accentSoft` fill, text stays primary.
  - Suggested symbols: lightbulb, doc.text, text.bubble, chart.bar, dollarsign.circle, waveform.path.ecg, globe, chart.line.uptrend.xyaxis.
- **Toolbar**: 52 high. Leading: `.navigationTitle` (15 Bold) + `.navigationSubtitle` (11 secondary). Trailing: screen controls as glass groups (32 high, items 24), then an inspector toggle (sparkles) on every main screen. Title leading edge = content leading edge.
- **Content**: insets top 12, sides 24, bottom 24. Section gap 24, card gap 16.
- **Inspector** ("Ask about this screen"): `.inspector`, 304 wide. Available on Insights, App Store, Metric detail.

## Screens

### 1. Insights (`screen=insights`)
Hero: the lead insight.
- Toolbar: "All categories" filter menu.
- Group label "New" (13 Semibold) + "3 since yesterday" (13 secondary).
- **Lead card** (full width, wraps to stacked under ~600 pt): left column (min 260): meta row (11 secondary: category glyph + "Conversion", date "Today" trailing), title 17 Semibold ("Tap-through rate fell 31%"), one-sentence explanation 13 secondary, actions pinned bottom. Right column (min 300): value 28 Semibold ("8.1%") + change 13 Semibold red ("−31%") + "vs 11.8% baseline" 13 secondary; 88 pt line chart, dashed baseline, a release rule labelled "Nov 4 · 2.4.1"; axis labels "Oct 15" / "Nov 11" (10 secondary).
- Then grid `LazyVGrid(.adaptive(minimum: 280))`, gap 16. Every card has the same structure so rows are equal height: meta row → title 15 Semibold → explanation 13 secondary (min 2 lines) → evidence area (min 56: mini chart with dashed baseline, keyword string, or quote well) → actions (`margin-top:auto`).
- Cards: "Best day ever: 412 downloads" (chart + record line "Previous record 301" + dot on peak), "Your keywords repeat words from your name" (keyword list, repeated words struck through in warning orange; action "Fix…" in accent text → Listing), group "Earlier this week": "Three 1-star reviews mention a crash" (quote well + "Lena K. · Translated from German"; Open → Reviews), "Redownloads are up 18%" (chart).
- Actions: "Ask" (sparkles, opens inspector with the card as context, card gets 1 pt accent border) and "Open" / "Fix…". Small bordered buttons, 24 high, radius 6, fill `fill`, 12 Medium.

### 1b. Inspector open
Header "Ask about this screen" (13 Semibold) + "Claude · Insights, Oct 15 – Nov 11" (11 secondary) + close. User bubble: accent fill, white 13, radius 14, right aligned. Assistant answer plain 13/18 with a numbered list. Source line 11 secondary: "Based on impressions, page views and search terms, Oct 15 – Nov 11. Nothing else left this Mac." Suggested follow-ups as full-width small buttons. Input: 36 high capsule field "Ask about Insights…" + 24 pt accent send button.

### 1c. Insights empty — "Nothing to flag" (`insights-empty`)
- Status card (padding 24): 40 pt `accentSoft` circle with checkmark, title 22 Bold "Nothing to flag", body 13 secondary (max 560): what was checked and that nothing needs action; meta 11 secondary "Checked today at 6:12 AM · Next check at 6:00 PM"; "Check Now" button.
- "Watching — Last 28 days against each metric's usual range": 3 × 2 grid of compact cards: label 13 secondary, value 20 Semibold + unit, "Usual range …" 11 secondary, 96 × 48 sparkline over a `fill` band showing the usual range.
- "Recently resolved": list card, rows 44, checkmark + title + "Back to usual range · Nov 9" trailing.

### 2. App Store overview (`appstore`)
- Toolbar: segmented "7 Days | 28 Days | 90 Days | Year".
- Hero row: "First-time downloads, last 28 days" (13 secondary), "5,412" 34 Bold, "+12.4%" 15 Semibold green, "vs previous 28 days". Trailing: date range + comparison range (11 secondary, right aligned).
- Tiles: 3 × 2 grid, funnel order: Impressions, Product page views, Tap-through rate, First-time downloads, Redownloads, Conversion rate. Each: label 13 secondary, value 28 Semibold, change 12 Semibold colored + "was …" 12 secondary, 56 pt sparkline (accent line 1.5 + flat 8% fill). For periods > 90 days the sparkline is weekly. Clicking a tile opens Metric detail.
- Funnel card: title "Funnel" 15 Semibold + "How impressions become downloads". 5 columns: stage (Impressions) · step ("Tap through →" rate 17 Semibold, change vs previous) · stage (Product page views, "x% of impressions") · step ("Download →") · stage (First-time downloads). Each stage has a 12 pt bar showing its share of impressions (min 4 pt). Footer row (separator above): lightbulb + one-sentence takeaway + "Open Insight".

### 2b. Data arriving in 24–48 h (`appstore-arriving`, second app "Pebble", teal accent)
- Status card: clock in `accentSoft` circle, "Your first App Store report arrives in 24–48 hours", explanation of Apple's delay and that Almanac will notify; "Check Now".
- 4 progress steps: ✓ Key verified (Today, 9:40 AM) · ✓ Sales history imported (214 days) · ◷ Analytics report requested (Apple is preparing it) · ○ First insights (After 7 days, around Nov 19).
- "Available now": sales card (Units, Proceeds, sparkline, "Open Sales").
- "Waiting for Apple": one card, 3 × 2 cells, clock glyph + metric + "Expected Nov 13 · covers Nov 11". No skeletons.

### 3. Metric detail (`metric`)
- Toolbar: "Day | Week | Month"; group: "All territories" menu + "Last year" checkbox toggle; group: pin (filled accent when pinned) + "Export CSV".
- Hero: range label, total 34 Bold, change vs previous period; second block "Same period last year" 22 Semibold secondary + change "this year". Legend trailing (This year / Last year dashed / Release).
- Chart card: Swift Charts, 256 high. Line 2 pt accent + area gradient (accent 20% → 0%), last year dashed 1.5 `label3`, y grid 5 lines max with nice steps, release rules (1 pt secondary 50%) with version label 10 Semibold at top. Hover: vertical rule, dot (4.5, card-colored ring), popover 184 wide (date, this year, last year, change). Day = 28 days, Week = 26 weeks, Month = 12 calendar months.
- Table: `Table`, rows 32, alternating `fill2`. Columns: Date, Downloads (sorted, bold), Last year, vs last year (colored), Impressions, Page views, Conversion.

### 4. Territories (`territories`)
- Toolbar: period segmented.
- Map card: world choropleth (Natural Earth projection), 5 bins of accent mixed into a neutral base (20/34/50/70/92%), countries without data at 7%. Side panel: title "First-time downloads by territory", then three takeaways separated by rules: Largest market, Fastest growing (green change), Highest conversion; legend at bottom.
- Table: Territory (flag + name), Impressions, Conversion, Downloads (bold), Change (colored), Share (bar + %). All headers sortable (▾/▴ on active). Shows top 9 + footer "Top 9 of 112 territories · Show All".

### 5. Reviews (`reviews`)
- Toolbar: "All | Needs reply"; group: "All ratings", "All territories", "All versions" menus; search.
- Left column 256: summary card ("4.6" 48 Bold, 5 monochrome stars, "1,284 ratings", 5→1 histogram bars in secondary); "Version 2.4.1 · since Nov 4" card (4.2, −0.5 red vs 2.4.0); "Waiting for a reply" card (7).
- Right: list card. Row padding 16: stars (12 pt, primary/tertiary) + title 13 Semibold + date trailing; body 13/18; meta "Name · Country · Version" 11 secondary; trailing actions "Translate" (foreign-language only) and "Reply…" (accent text, sparkles; only if not replied). Replied reviews show a `fill2` well "Your reply" + text.

### 5b. Suggested reply sheet
576 wide, radius 20, padding 24. Title "Reply to Lena K.", meta line; translated review in a well + "Translated from German · Show Original"; "Suggested reply — Drafted by Claude in German" + segmented "Friendly | Brief"; editable text (focused: accent border + 3 pt `accentSoft` ring); caption + counter "x / 5,970"; footer: "Regenerate" (leading), "Cancel", "Send Reply" (accent, default button).

### 6. Listing (`listing`)
- Toolbar: "Compare with Live", "Discard Changes", prominent "Upload to App Store Connect".
- Left 208: "Localizations" list (selected `accentSoft`; status line in secondary or warning color), "Add Language…".
- Right form: Name (30) + Subtitle (30) side by side; Keywords (100, caption "Comma-separated, no spaces needed"); Promotional text (170, caption "Can change without a new version"); Description (4,000, fills remaining height). Each: label 13 Semibold, counter "23 / 30" 11 secondary trailing, field (radius 6, 1 pt `separator` strong), 2 pt budget bar under it (accent fill). Over budget → counter red.
- Keyword validation: tokens that repeat words from the app name are orange with a wavy underline; below the field a warning row (orange 9% tint, triangle) "“sleep” and “sounds” are already in your app name. Apple indexes the name, so these 13 characters add nothing." + "Remove Repeated Words".
- Rule: split name on non-letters, lowercase, compare to each comma token; characters saved = token length + comma.

### 7. Weekly / Monthly / Yearly report (`report`, separate window, no sidebar)
- Toolbar: title "Weekly Report" / "Nightjar · Nov 3 – 9, 2026"; "Weekly | Monthly | Yearly"; previous/next; "Share", "Export PDF".
- 880 wide centered column. KPI row: one card split in 5 cells by rules (label, value 28 Semibold, change 12 colored "vs last week").
- Below: 176 table of contents (selected `accentSoft`) + caption "Written by Claude on this Mac…"; reading column max 640: headings 17 Semibold, paragraphs 15/24; Acquisition includes a 7-bar daily chart (peak in accent, others accent 35%).

### 8. Settings (`settings`)
Settings window 640 × 760, `Form` `.grouped`:
- App Store Connect (caption: where to create the key): Issuer ID, Key ID, Private key (.p8 file name + "Stored in your Keychain" + "Choose File…"), Vendor number, status row "Connected · verified today at 6:12 AM · 2 apps" + "Test Connection".
- Refresh: "Refresh in the background" toggle (caption: ~6 AM and 6 PM, even when the window is closed), "Notify me about new insights" toggle.
- Assistant: Provider segmented "Claude | Codex CLI" with a detail line showing the detected CLI path and sign-in status; "Share with the assistant" menu ("Numbers on the current screen"); footnote: raw reports and the private key never leave the Mac.
- Data: "Stored on this Mac · 48 MB", path, "Show in Finder".

## Interactions & state
- `selectedApp`, `selectedSection` (sidebar), `inspectorPresented`, `period` (7/28/90/365), `granularity` (day/week/month), `compareLastYear` (Bool), `pinnedMetrics` ([MetricID]), `territorySort` (key + direction), `reviewFilter` (all / needsReply), `replyDraft` (text, tone), `aiProvider` (claude / codex), `backgroundRefresh`, `notifyInsights`.
- Ask (any card) → opens inspector with that card as context and outlines it in accent.
- Tile click → Metric detail. Insight "Open" → relevant screen; "Fix…" → Listing with the keywords field focused.
- Granularity change resets hover. Period change recomputes hero, tiles, funnel.
- Data pipeline: App Store Connect API (sales + analytics reports) downloaded on schedule, stored locally; insights computed by comparing the last 7/28 days with each metric's 28-day baseline. Analytics reports lag 24–48 h; show the arriving state until the first report exists.
- No custom animations beyond system defaults (sheet, inspector, selection).

## Design tokens
See `SPEC.md` (tables) and `Tokens.swift` (drop-in SwiftUI constants, fonts, colors, `AlmCard`).

## Assets
- App icons in the mock are placeholders (Nightjar crescent on indigo, Pebble stone on teal). Use the developer's real app icons from App Store Connect.
- Icons: use SF Symbols (names suggested above); the mock's line icons are stand-ins.
- Flags: mock loads flagcdn.com; in the app use a bundled flag set or region emoji-free images.
- Map: mock uses Natural Earth 110m (world-atlas TopoJSON). Bundle a GeoJSON and draw with `Path` / MapKit overlays.
- All numbers are sample data generated in the logic class of `AlmanacWindow.dc.html`.

## Files
- `design/Almanac.dc.html` — canvas with every screen, light + dark, plus spec board. Open in a browser (needs `support.js` next to it).
- `design/AlmanacWindow.dc.html` — the window component; prop `screen` ∈ insights, insights-empty, appstore, appstore-arriving, metric, territories, reviews, listing, report, settings; `theme` ∈ light, dark; `inspector`, `sheet` booleans.
- `SPEC.md` — spacing, type, color, chart and state rules.
- `Tokens.swift` — SwiftUI tokens.
- `PROMPT.md` — kickoff prompt for the coding model.
