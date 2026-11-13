# Mac redesign — implementation notes

Decisions taken while implementing the handoff (`design_handoff_almanac_macos`), where the spec was silent or reality disagreed with the mockups.

## Themes and chrome
- Default theme: **Nocturne**. Each theme keeps a fixed scheme: Ticker and Nocturne dark, Color Blocks and Candy Glass light. The system appearance is ignored.
- Theme tokens live verbatim in `Theme/Themes.swift`; `ThemeStyle.swift` gives them types.
- Unified empty toolbar, so the traffic lights sit inside the sidebar's rounded corner. Ticker uses a 92 pt icon rail instead of the sidebar.
- Screen header: 8 pt more space on top than the mockup (title block at 20 pt), at Adrien's request. The mockups felt bottom-heavy.
- UI in English, with en_US number and date formats everywhere, whatever the Mac's locale (forced through `AppleLocale` in `main.swift`; the insight engine formats with an explicit en_US locale).
- Sales and Usage were not in the kit; they're designed in the kit's language:
  - Sales: summary card (totals + stacked bars, release chips on their bar) over a table capped to its rows, fixed column widths and row height, a Release column, "Partial" on incomplete periods.
  - Usage: sessions/crashes cards plus a Ratings card (total, written-review distribution, latest reviews).
- Screen header: if title and controls don't fit (chat open), the controls wrap to a second row instead of truncating the title.
- Sheets (Settings, reply, keyword fix) blur the screen behind without darkening it.
- Opens on App Store (the dashboard). Insights shows a red dot in the sidebar/rail while it holds insights you haven't opened yet; opening the screen clears it.
- Tiles are links: a Watching card or a Usage card opens its metric (Ratings opens Reviews), an insight card opens what its Open button opens, and the Reviews context numbers open Downloads / Usage.
- Navigation history: ⌘[ / ⌘] and a two-finger horizontal swipe (system swipe tracking, honours "Swipe between pages"). The swipe shows an arrow bubble sliding in from the edge, filled with the accent once it will go through; the screen itself doesn't move.
- Opening the chat widens the window by the panel's width (as far as the display allows) and closing it gives the width back, so screens keep their layout. A screen still too wide is clipped on the right, never pushing the sidebar off.
- Fixed-layout screens (Territories, Reviews, Listing, quiet Insights) fill the window at any size, full screen included: Territories gives ~45% of the height to the map and fits as many table rows as the rest allows; Reviews is two full-height panes (the list scrolls inside its own; with 4 reviews or fewer, the room under them shows "Reviews against downloads": downloads per review, answered, days since the last one, ratings count, and weekly downloads with each review pinned on its week); quiet Insights stretches the Watching cards.
- The insight engine also runs at launch, so stored insights pick up format changes (charts, number formats) before the next sync.
- Chat answers: the prompt asks for no tables or headings; the panel renders bullets, numbered items and headings, and turns any table into plain rows. Metrics with no data are sent as "not available yet", not 0. The Insights context includes the Watching numbers, and the prompt forbids claiming Almanac lacks a number it shows or sending the user to App Store Connect for it.

## Settings
- Settings has four tabs (General, App Store Connect, Assistant, Data); it opens on App Store Connect until a key is saved. The sheet stays centered and sizes to the tab, animating its height; the screen behind is blurred at 32 pt. Its cards use the small radius, since they sit inside the sheet.
- Settings is a sheet **inside** the main window (blurred backdrop, theme colors), not a separate window. It opens with ⌘, from the menu, or with the gear at the bottom of the sidebar (or of the rail in Ticker).
- Themes are picked from four live miniatures drawn in each theme's own colors.
- Things the mockup shows but the app doesn't have were left out rather than faked:
  - the "Share with the assistant" picker;
  - "signed in" for the CLI. The app only knows whether the command is in PATH, so it shows that path.
- "Notify me about new insights" is real. The background agent reads `notifyInsights`.
- Added beyond the mockup: the Vane-on-iPhone QR code, the Claude model field, the Appearance section, and "Open Demo Window" (Data), which launches a second instance with `--demo` so sample data never mixes with real data.

## Data honesty
- Charts show complete buckets only. Yearly charts use complete weeks: a partial first or last week would draw a false drop.
- Comparisons ("vs last week") appear only when the previous period has full history. Otherwise "No earlier data" in reports and "—" in App Store pills.
- The recomputed lead change was removed.
- Values that aren't available yet read "Expected in 24–48 hours". No skeletons.
- Apple sends each analytics report separately. Once sessions have arrived, the App Store banner says so ("Sessions since …") and waits only for the impressions report; Crashes reads "No crash report from Apple yet" instead of 0.
- Before Apple's first analytics report, App Store keeps the kit layout with "—" tiles and a pending banner; downloads already come from sales reports.
- Sparse Insights (≤ 3, nothing new) show "Recent" plus a "Watching" grid of the metrics being tracked, instead of a half-empty page.
- Metric detail table: Impressions, Page views and Conversion read "—" for periods without analytics, never 0.
- Usual range = p10 to p90 of the 63 prior days.
- Insights:
  - Dismissed insights are shown as "Recently resolved".
  - "Nothing to flag" stays honest before analytics arrive.
- Territories: first-time downloads only, log-scaled color bins, a growth floor so tiny markets don't top the list.
- Reviews:
  - The version is inferred from the review date.
  - Written reviews are counted, not total ratings.
  - Translation runs automatically only if the language pack is already installed.

## Listing
- Upload sends only the fields that changed.
- "Add Language…" is omitted: it needs a create call to the API, out of scope.
- Selected locale, compare toggle and the upload message live in scene storage, because the detail view is re-created after each store change.

- Listing: languages show a check, "Edited" or a warning dot. An issue every language shares is said once under the list. Fields have no progress bars, and the counter turns orange past 90%. Under the list, an "In search" preview shows icon, name and subtitle, the keyword chips (repeats in orange) and the product-page text.

## Report window
- Its own themed window with no sidebar. It shows complete periods only; prev/next are disabled outside the data span.
- The prose is templated from the numbers, not "Written by Claude".
- Headline:
  - with analytics: first-time downloads, impressions, tap-through rate, conversion, proceeds;
  - without analytics: downloads, plus proceeds, ratings and subscriptions when they're non-zero.
- Lone KPI cards are capped at 220 pt wide.
- Removed the "Write with AI" and "Chat about this" buttons. Share sends plain text; Export PDF renders the report.

## iOS
- Vane keeps the Legacy views until its own redesign. Mac-only screens are wrapped in `#if os(macOS)`.
- After adding Swift files, run `xcodegen generate` in `ios/`.

## Launch flags (screenshots and testing)
`open -n build/Almanac.app --args …`

| Flag | Effect |
|------|--------|
| `--demo` | Demo database (temp dir, persists between launches; delete `$(getconf DARWIN_USER_TEMP_DIR)almanac-demo.sqlite*` to reset) |
| `--pane <name>` | Opens that screen |
| `--report week\|month\|year` | Opens the report window for the current app |
| `--settings` | Opens the Settings sheet |
| `--chat` | Opens the inspector chat |
| `--swipe-preview <-1…1>` | Freezes the swipe arrow (negative = forward) |
| `-theme <ticker\|blocks\|nocturne\|candy>` | Overrides the theme for this launch |
