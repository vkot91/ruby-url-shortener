# Design: URL Shortener MVP

**Branch**: `001-url-shortener-mvp` | **Date**: 2026-08-27 | **Spec**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md)

**Status**: Accepted — canvas published, see §10

## Purpose

`spec.md` says what the product must do and `plan.md` says how it is built, but neither says what
any of it looks like. Consequently every frontend task in `tasks.md` — T068 through T070, T080,
T081, T094, T095, and the two server-rendered pages T037 and T084 — currently asks a developer to
invent visual decisions on the spot, nine separate times. This document removes that.

It is the visual counterpart to `contracts/openapi.yaml`: the API contract fixes the shape of the
data, this fixes the shape of the interface. Where the two disagree, the API contract wins on data
and this document wins on presentation.

### Scope

Covers all nine MVP surfaces in both light and dark themes. Does not cover a marketing landing
page, a settings area, or any charting — none of those exist in MVP scope, and `plan.md`
explicitly excludes a charting library.

### Product name

**Snip** is a placeholder used throughout this document and in mockups so that layouts have a real
wordmark to lay out against. It is not a naming decision. The short domain shown in examples,
`snp.to`, is likewise a placeholder. Both appear in exactly one place in code — the app shell
header and the `SHORT_DOMAIN` environment variable — so replacing them later is a two-line change.

### How to use this document

- **Implementing a screen**: read §2 (principles), then the relevant subsection of §6. §6 names the
  components; §5 says which are stock shadcn and which are ours.
- **Generating mockups with Claude Design**: see §10. That section is written as a brief and is
  meant to be handed over as-is.
- **Adding a screen not listed here**: derive it from §2 and §7 rather than inventing new tokens.
  A new token means this document is wrong and should be edited first.

---

## 1. Direction

**Warm and approachable.** The person in User Story 1 is a marketer, not an engineer. They arrive
with a long URL and one question — did the post work — and they should never feel they have opened
a piece of infrastructure tooling.

Warm here is a specific, checkable thing, not a mood:

- Neutrals carry a warm hue (55–85° in OKLCH), so surfaces read as paper rather than as gray.
- The accent is a terracotta orange, not the default blue that signals "generic SaaS".
- Corners are generous (12px base radius rather than shadcn's 10px default).
- Shadows are tinted with the warm foreground hue rather than pure black, so elevation looks like
  light falling on paper instead of a drop shadow floating over it.

What warmth does **not** license: decorative illustration, playful microcopy that obscures what
happened, or lowered contrast in service of softness. The accessibility budget in §9 is not
negotiable against the aesthetic.

---

## 2. Design principles

These are derived from the spec, not from taste. Each is traceable.

### P1. The short code is the primary object on every screen it appears on

US1 and FR-005 make the whole product a machine for producing one copyable string. That string —
`snp.to/k7Bx2mQ` — gets the strongest typographic treatment available on the row: monospace, full
foreground color, larger than its neighbours. The destination URL, by contrast, is supporting
information and is set in muted foreground at body size.

**Consequence**: no screen puts the destination URL above the short code in the visual hierarchy,
even though the destination is what the creator typed.

### P2. Copying is a first-class action with a persistent confirmation

FR-005 requires one-click copy, and SC-003 gives a first-time user two minutes to produce a
working link without instruction. A confirmation that fades away can be missed.

**Consequence**: the copy control is a button that swaps its own icon and label to a success state
for 2 seconds in place — not a toast. It is never hidden behind a hover state, because a hover
state does not exist on touch and half of link-sharing happens from a phone.

### P3. One number per link, rendered as typography

FR-023 asks for a total count. `plan.md` deliberately excludes a charting library and puts deep
analytics out of MVP scope. The click count is therefore a number set in tabular figures, not a
sparkline, a gauge, or a progress bar.

**Consequence**: nothing on the dashboard implies a trend line exists. No "▲ 12%" affordance, no
axis, no empty chart frame promising future data.

### P4. Polled updates must not disturb the page

T108 refetches counts every 30 seconds (SC-009). A user reading their dashboard must not see the
table flash, reflow, or show a spinner over content they are already reading.

**Consequence**: click counts render in tabular-figure numerals in a fixed-width column, so 9 → 10
→ 100 causes no reflow. Background refetches change the number and nothing else; the only
indication of a refetch is a `aria-live="polite"` announcement. The full-table loading state
appears on first load only.

### P5. One error pattern, six error codes

`contracts/openapi.yaml` returns six distinguishable `error.code` values on link creation:
`invalid_url`, `unsupported_scheme`, `private_address`, `self_referential`, `blocked_domain`,
`link_limit_reached`. T070 maps all six to field-level errors.

**Consequence**: this document specifies one field-error pattern and one form-level error pattern,
and §6.4 gives the copy for all six. Five of the six attach to the destination field.
`link_limit_reached` is an account condition rather than a field condition and is the single
form-level case — it also gets a preemptive treatment, see §6.4.

### P6. The admin area cannot display marketing statistics

FR-034 forbids exposing a creator's statistics to administrators in normal operation, and
Principle V of the constitution makes this structural rather than a matter of care.

**Consequence**: no admin table in §6.7 or §6.8 has a click-count column. This is a design
constraint that survives into the component API — the admin link row is a distinct component from
the creator link row, not the same component with a prop turned off.

### P7. The two server-rendered pages share the vocabulary but not the stylesheet

T037 (`not_found.html.erb`) and T084 (`banned.html.erb`) are rendered by Rails, in a build that has
no Tailwind pipeline and no React. They are also the only pages an anonymous visitor ever sees, and
FR-017 requires the not-found page to explain what the service is rather than show a bare error.

**Consequence**: §8 defines a small inlined CSS subset — roughly 40 lines — that reproduces the
type scale and the color tokens these two pages need, and nothing else. They are visually of the
same family as the app without importing any of its machinery.

---

## 3. Color

Tokens are authored in OKLCH and slot directly into the existing `:root` and `.dark` blocks in
`frontend/src/app/globals.css`. The variable names are exactly the ones shadcn/ui already emits, so
adopting this palette is a value replacement, not a restructure. Two names are added
(`--input-border`, `--success` and its foreground); everything else is a substitution.

### 3.1 Light theme

| Token | OKLCH | Hex | Role |
|---|---|---|---|
| `--background` | `0.985 0.006 85` | `#fcfaf6` | Page ground — warm off-white |
| `--foreground` | `0.255 0.018 55` | `#2a211b` | Body text — warm near-black |
| `--card` | `1 0.002 85` | `#fffffe` | Raised surface: cards, table, dialogs |
| `--card-foreground` | `0.255 0.018 55` | `#2a211b` | Text on raised surfaces |
| `--popover` | `1 0.002 85` | `#fffffe` | Popover, dropdown, command |
| `--popover-foreground` | `0.255 0.018 55` | `#2a211b` | |
| `--primary` | `0.555 0.155 42` | `#ba4c18` | Terracotta — primary action, links, focus |
| `--primary-foreground` | `0.99 0.012 85` | `#fffbf3` | Text on primary |
| `--secondary` | `0.945 0.014 78` | `#f2ece3` | Secondary button ground |
| `--secondary-foreground` | `0.30 0.02 55` | `#362b24` | |
| `--muted` | `0.955 0.011 80` | `#f4efe8` | Table header, inert fill |
| `--muted-foreground` | `0.505 0.022 62` | `#6e6258` | Supporting text, destination URLs |
| `--accent` | `0.925 0.035 72` | `#f5e3cd` | Hover ground, selected row |
| `--accent-foreground` | `0.30 0.03 50` | `#3a2a20` | |
| `--destructive` | `0.545 0.205 27` | `#cd2023` | Delete, ban, error text |
| `--destructive-foreground` | `0.99 0.01 85` | `#fffbf4` | |
| `--success` | `0.505 0.115 150` | `#28763f` | Copy confirmation, resolved report |
| `--success-foreground` | `0.99 0.01 85` | `#fffbf4` | |
| `--border` | `0.895 0.013 78` | `#e1dbd3` | Decorative rules: card edges, table dividers |
| `--input-border` | `0.62 0.018 72` | `#8d857b` | Interactive control boundary — see §3.3 |
| `--ring` | `0.555 0.155 42` | `#ba4c18` | Focus ring |

### 3.2 Dark theme

Dark is a warm charcoal, not a blue-black. The primary lightens to `0.72 L` because terracotta at
`0.555 L` on a dark ground fails text contrast.

| Token | OKLCH | Hex | Role |
|---|---|---|---|
| `--background` | `0.185 0.012 58` | `#17110d` | Page ground — warm charcoal |
| `--foreground` | `0.955 0.008 85` | `#f3f0ea` | Body text |
| `--card` | `0.235 0.014 58` | `#231d18` | Raised surface |
| `--card-foreground` | `0.955 0.008 85` | `#f3f0ea` | |
| `--popover` | `0.235 0.014 58` | `#231d18` | |
| `--popover-foreground` | `0.955 0.008 85` | `#f3f0ea` | |
| `--primary` | `0.72 0.145 48` | `#ec854d` | Lightened terracotta |
| `--primary-foreground` | `0.20 0.025 48` | `#1f130c` | |
| `--secondary` | `0.30 0.016 58` | `#342c26` | |
| `--secondary-foreground` | `0.955 0.008 85` | `#f3f0ea` | |
| `--muted` | `0.285 0.014 58` | `#302923` | |
| `--muted-foreground` | `0.735 0.016 75` | `#afa89e` | |
| `--accent` | `0.34 0.030 58` | `#443429` | |
| `--accent-foreground` | `0.96 0.01 85` | `#f5f1ea` | |
| `--destructive` | `0.665 0.185 25` | `#f05b57` | |
| `--destructive-foreground` | `0.16 0.02 30` | `#150a08` | |
| `--success` | `0.735 0.125 155` | `#61c086` | |
| `--success-foreground` | `0.16 0.02 30` | `#150a08` | |
| `--border` | `0.33 0.014 58` | `#3b342e` | |
| `--input-border` | `0.54 0.018 60` | `#776c64` | |
| `--ring` | `0.72 0.145 48` | `#ec854d` | |

### 3.3 Why `--border` and `--input-border` are separate

WCAG 1.4.11 requires 3:1 for boundaries that are the only means of identifying a control. It does
not require it for decorative rules. `--border` at 1.31:1 (light) and 1.52:1 (dark) is a
deliberately quiet card edge and would be wrong for a text input; `--input-border` at 3.50:1 and
3.67:1 is what every input, select, textarea, and outline-variant button uses.

Collapsing the two — which shadcn's default palette does — either makes card edges shout or makes
form fields fail. Keeping both is the reason this palette needs one extra token.

### 3.4 Contrast budget (measured, not estimated)

Ratios computed from the OKLCH values above via sRGB conversion and the WCAG relative-luminance
formula. Threshold is 4.5:1 for text and 3:1 for non-text boundaries.

| Pair | Light | Dark |
|---|---|---|
| foreground on background | 15.16 | 16.37 |
| foreground on card | 15.81 | 14.66 |
| muted-foreground on background | 5.65 | 7.94 |
| muted-foreground on card | 5.90 | 7.11 |
| muted-foreground on muted | 5.17 | 6.12 |
| primary-foreground on primary | 4.93 | 6.99 |
| primary as text on background | 4.87 | 7.17 |
| primary as text on card | 5.07 | 6.42 |
| destructive as text on background | 5.27 | 5.61 |
| destructive-foreground on destructive | 5.35 | 5.86 |
| success as text on background | 5.33 | 8.37 |
| input-border on background | 3.50 | 3.67 |
| ring on background | 4.87 | 7.17 |

**One rule falls out of this table**: `--primary` as *text* on `--muted` measures 4.45:1 in light
theme and therefore fails. Primary-colored text is permitted on `--background` and `--card` only.
On a muted ground — the table header, a filled input — use `--foreground`.

---

## 4. Typography

### 4.1 Families

| Role | Family | Fallback stack | Rationale |
|---|---|---|---|
| UI and body | **Figtree** | `ui-sans-serif, system-ui, sans-serif` | Humanist geometric with open apertures and a tall x-height. Friendly at 14px without becoming a rounded novelty face, and it holds up in a dense admin table. |
| Codes, URLs, numbers | **JetBrains Mono** | `ui-monospace, SFMono-Regular, Menlo, monospace` | Chosen for one reason: a 7-character random code (FR-009) is read and re-typed by humans. JetBrains Mono has a slashed zero and visually distinct `l`/`1`/`I` and `O`/`0`, which the stock `--font-geist-mono` does not disambiguate as strongly. |

Both load from Google Fonts via `next/font/google`, which self-hosts at build time — no runtime
request to a third party, which matters given Principle V.

This replaces the current `--font-geist-mono` binding in `globals.css`. `--font-heading` stays
aliased to `--font-sans`; the warmth comes from weight and size contrast, not a second display
face.

### 4.2 Scale

| Token | Size / line-height | Weight | Used for |
|---|---|---|---|
| `display` | 32px / 40px | 600 | Page title on auth and the two Rails pages |
| `h1` | 24px / 32px | 600 | Screen title (Your links, Moderation queue) |
| `h2` | 18px / 26px | 600 | Card and section headings |
| `body` | 15px / 24px | 400 | Default. 15px, not 14px — this is a reading interface, not a spreadsheet |
| `body-sm` | 13px / 20px | 400 | Table meta, timestamps, helper text |
| `label` | 13px / 18px | 500 | Form labels, table headers |
| `code` | 15px / 24px | 500, mono | Short codes and destination URLs |
| `metric` | 20px / 28px | 600, mono, `tabular-nums` | The click count, and only the click count |

`font-variant-numeric: tabular-nums` is mandatory on `metric` and on any table cell holding a
number. This is what makes P4 work.

### 4.3 Rules

- Short codes are never truncated. Destination URLs are truncated at the middle
  (`https://example.com/…/campaign`), never at the end, because the tail carries the tracking
  parameters the creator is checking for.
- Full destination is always available as a `title` attribute and in the edit form.
- Sentence case everywhere. No ALL-CAPS labels; they read as shouting in a warm palette.

---

## 5. Spacing, radius, elevation, motion

### 5.1 Spacing

4px base. Permitted steps: **4, 8, 12, 16, 24, 32, 48, 64**. Nothing between steps, no arbitrary
values. Card padding is 24px, form field vertical rhythm is 16px, table row vertical padding is
12px.

### 5.2 Radius

`--radius: 0.75rem` (12px), up from shadcn's 0.625rem default. The existing derived scale in
`globals.css` (`--radius-sm` through `--radius-4xl`) needs no change — it is computed from
`--radius` and follows automatically.

| Element | Radius |
|---|---|
| Input, button, badge | `--radius-md` (9.6px) |
| Card, dialog, table container | `--radius-lg` (12px) |
| Short-code chip | `--radius-sm` (7.2px) |

### 5.3 Elevation

Three levels only. Shadow color is the foreground hue at low alpha, never `rgb(0 0 0)`.

| Level | Light | Dark | Used for |
|---|---|---|---|
| `flat` | none, `1px` `--border` | none, `1px` `--border` | Table container, inline cards |
| `raised` | `0 1px 2px oklch(0.255 0.018 55 / 0.06), 0 2px 8px oklch(0.255 0.018 55 / 0.04)` | `0 1px 2px oklch(0 0 0 / 0.4)` | Auth card, create-link card |
| `overlay` | `0 8px 32px oklch(0.255 0.018 55 / 0.12)` | `0 8px 32px oklch(0 0 0 / 0.55)` | Dialog, dropdown, popover |

Dark theme substitutes near-black shadows because a warm-tinted shadow on a warm dark ground is
invisible; separation there comes from `--card` being lighter than `--background`.

### 5.4 Motion

| Transition | Duration | Easing |
|---|---|---|
| Hover, focus, color change | 120ms | `ease-out` |
| Copy-button state swap | 160ms | `ease-out` |
| Dialog enter / exit | 200ms / 150ms | `cubic-bezier(0.32, 0.72, 0, 1)` |

Everything above is wrapped in `@media (prefers-reduced-motion: reduce)` fallbacks that drop
duration to 0ms while preserving the end state. No animation on data arriving — see P4.

---

## 6. Screen specifications

Nine surfaces. Each names its route, its task ID, its states, and the requirements it serves.

### 6.1 App shell — `frontend/src/app/(dashboard)/layout.tsx`

Not currently a task. See §11 — it is added as T120.

- **Header**, 64px, `--card` ground, `flat` elevation, full width, sticky.
  - Left: wordmark "Snip" at `h2` weight 600. No logo mark in MVP.
  - Right: theme toggle (system / light / dark), then account menu — email at `body-sm` muted,
    dropdown with Sign out. Admin accounts get an "Admin" item above Sign out; creator accounts
    have no admin affordance rendered at all, not a disabled one (FR-003).
- **Content**: max-width 1120px, centered, 32px horizontal padding, 32px top padding.
- No sidebar. Four screens do not justify persistent navigation, and the sidebar tokens already in
  `globals.css` go unused in MVP.

### 6.2 Sign up / Sign in — `frontend/src/app/(auth)/` — T068

Two near-identical screens; specifying once.

- Single centered card, 400px wide, `raised`, 32px padding, vertically centered with a 48px minimum
  top margin so it does not collide with small viewports.
- Wordmark above the card at `display`. Below it, one line at `body-sm` muted stating what the
  product does — this is a first-time visitor's only explanation before they commit (SC-003).
- Fields: email, password. Sign-up adds no confirm-password field; it adds a password-visibility
  toggle instead, which is the more effective error-prevention control.
- Primary button full width. Beneath it, one link to the other screen.
- **Error state**: FR-036 requires that a refused attempt not reveal whether an email is
  registered. The form therefore has exactly one failure message, rendered form-level above the
  fields in `--destructive`: *"That email and password combination didn't work."* Sign-up uses the
  same wording for an already-registered address. No field-level "email already taken" is ever
  rendered — that string leaks the fact the API is required to conceal.
- **Rate-limited state (429)**: form-level, *"Too many attempts. Try again in a few minutes."*
  Submit button disabled, fields left enabled.
- **Pending state**: submit button shows a spinner and keeps its label; fields disabled.

### 6.3 Link list — `frontend/src/app/(dashboard)/links/page.tsx` — T069, T108

The screen the product is judged on.

- **Header row**: `h1` "Your links", and on the right a primary "New link" button. Under the title,
  `body-sm` muted: "12 of 50 links used" (FR-004). At 45 of 50 this line turns `--destructive`; see
  §6.4 on why it matters here and not only at the point of failure.
- **Table**, `flat`, `--card` ground, `--muted` header row:

| Column | Width | Content | Type |
|---|---|---|---|
| Short link | 260px | `snp.to/k7Bx2mQ` + copy button | `code`, foreground |
| Destination | flexible | Middle-truncated URL, `title` = full | `body`, muted-foreground |
| Created | 120px | Relative under 7 days ("3 days ago"), absolute after | `body-sm`, muted |
| Clicks | 100px, right-aligned | Integer, tabular | `metric` |
| — | 48px | Row actions `⋯` → Edit, Delete | icon button |

- The `snp.to/` prefix renders in `--muted-foreground` and the 7-character code in `--foreground`,
  so the code reads as the object and the domain as context (P1).
- Row hover: `--accent` ground. No hover-revealed actions — the `⋯` is always visible (P2).
- **Copy button**: ghost icon button in the Short link cell. On click, swaps to a check icon in
  `--success` with the accessible label "Copied", holds 2 seconds, reverts. Announced via
  `aria-live="polite"`.
- **First load**: five skeleton rows in `--muted`, matching final row height so nothing jumps.
- **Background refetch** (30s): no visual change other than the number (P4).
- **Empty state**: inside the table container, 64px vertical padding, centered. `h2` "No links
  yet", one `body` muted line, and a primary "Create your first link" button. No illustration.
- **Error state**: table container replaced by a `flat` panel, `body` in `--destructive`,
  "Couldn't load your links." plus a secondary "Try again" button. The header row and New link
  button remain usable.
- **Pagination**: appears only above 25 links. Previous / Next, plus "Showing 1–25 of 43" at
  `body-sm` muted. No page-number list.

### 6.4 Create link — `frontend/src/app/(dashboard)/links/new/page.tsx` — T070

- Single card, 640px, `raised`, on an otherwise empty screen. Back link to the list above the card.
- Fields:
  - **Destination URL** — `code` type, single line, autofocus, `inputMode="url"`. Helper text at
    `body-sm` muted: "The address people should land on."
  - **Name (optional)** — `body` type. Helper: "Only you see this."
- Primary "Create link", secondary "Cancel".
- **Success**: the form is replaced in place — not navigated away from — by a success panel showing
  the new short link at `code` size 20px, a full-width primary "Copy link" button, and two
  secondary links: "Create another" and "Back to links". Copying is the goal of the screen, so it
  becomes the biggest control on it the moment a link exists (P2, SC-003).
- **Field errors**, all five attached to the Destination field, rendered `body-sm` in
  `--destructive` beneath it with the field border switching to `--destructive`:

| `error.code` | Message |
|---|---|
| `invalid_url` | That doesn't look like a web address. Check for typos. |
| `unsupported_scheme` | Links must start with `http://` or `https://`. |
| `private_address` | That address points inside a private network, so it wouldn't work for your visitors. |
| `self_referential` | That's already a Snip link. Share it directly instead. |
| `blocked_domain` | That destination is on our blocked list and can't be shortened. |

- **Form-level error**, `link_limit_reached`: a panel above the fields, `--destructive` text on
  `--card`, "You've reached the 50-link limit on the free plan. Delete a link to make room." Submit
  disabled.
- **429 on creation** (FR-004 hourly rate): form-level, "You're creating links faster than the
  hourly limit allows. Try again shortly — your existing links are unaffected." That second clause
  is required: FR-019 guarantees redirects keep working, and a user hitting this limit needs to
  know their published links are fine.
- **Preemptive limit treatment**: at 50 of 50 links, the "New link" button on §6.3 is disabled with
  the limit explanation in a tooltip, rather than letting the user fill a form that cannot succeed.
  The form-level error above still exists, because the count can change in another tab.

### 6.5 Edit link — `frontend/src/app/(dashboard)/links/[id]/edit/page.tsx` — T080

Same card as §6.4 with three differences.

- A **read-only short-code row** sits above the editable fields: label "Short link", the full
  `snp.to/k7Bx2mQ` at `code`, a copy button, and `body-sm` muted beneath: "The short link can't be
  changed. A different code would be a different link." This states FR-026 as a fact rather than
  rendering a disabled input the user will try to click.
- Destination and Name are prefilled and reuse the zod schema and the entire error table from §6.4.
- Primary "Save changes"; on success, navigate to the list with the edited row briefly grounded in
  `--accent` for 1.5 seconds so the user can find what they changed.

### 6.6 Delete link — `frontend/src/app/(dashboard)/links/[id]/page.tsx` — T081

A dialog, not a page.

- Title `h2`: "Delete this link?"
- Body: the short link at `code`, then two `body` lines that state exactly what FR-028 and FR-029
  do — "Visitors who open it will see a not-found page." and "Its click history is kept, and the
  code stays reserved for 30 days."
- Destructive primary "Delete link", secondary "Cancel". Cancel is focused on open.
- No type-to-confirm. The action is recoverable in the sense that matters (statistics survive) and
  a friction ritual here would be theatre.

### 6.7 Admin moderation queue — `frontend/src/app/admin/reports/page.tsx` — T094, T109

SC-010 gives an administrator 60 seconds from opening this queue to banning a reported link. The
layout is built backwards from that number.

- `h1` "Moderation queue". Beneath it a segmented filter: Open / Reviewed / All, defaulting to
  Open, oldest first (FR-033).
- Table on `--card`:

| Column | Content |
|---|---|
| Reported | Relative time, `body-sm` muted |
| Short link | `code` |
| Destination | Middle-truncated, full in `title` |
| Reports | Integer count, tabular |
| Status | Badge — Open (`--accent`), Reviewed (`--muted`), Banned (`--destructive`) |
| Actions | "Ban link" and "Ban account", both destructive, inline on the row |

- **No clicks column.** FR-034 and P6.
- Ban actions are inline rather than behind a row menu or a detail page: a detail navigation would
  spend most of the 60-second budget. Each opens a confirmation dialog naming which of the two
  scopes is being applied, because banning an account is a much larger action than banning a link
  and the two buttons sit adjacent.
- After a ban, the row updates in place to the Banned badge and the action buttons are replaced by
  `body-sm` muted "Banned just now". The row is not removed — the administrator needs to see that
  what they clicked took effect.
- **Empty state**: "Nothing in the queue." at `h2` with a muted line beneath. This is the good
  outcome and should not read as an error.

### 6.8 Admin link search and health — `frontend/src/app/admin/` — T095

Two routes sharing the shell.

**Link search** (FR-030): a single search input at the top, full width of the content column,
`code` type, placeholder "Search by short code or destination". Results use the §6.7 table minus
the Reported and Reports columns, plus an Owner column showing the account email. Still no clicks
column. Empty query renders guidance, not an empty table. No results renders "No links match that
code or destination."

**Health** (FR-035): four `metric` tiles in a row on `--card`, each a label at `label` and a value
at `display` in mono tabular — cache hit rate as a percentage, redirect p50 and p99 in
milliseconds, redirects per second, click backlog as a count. Beneath the tiles, a `body-sm` muted
line stating the measurement window and the time of the last sample. These are operational
numbers, not customer analytics, so they are the one place large figures are allowed — and per P3
they are still numbers, not charts.

### 6.9 Server-rendered pages — T037, T084

See §8 for the CSS subset. Both are single-column, centered, max-width 480px, 64px top padding,
and both work with no JavaScript.

**Not found** (`not_found.html.erb`, FR-017): `display` heading "This link doesn't exist", one
`body` paragraph — "It may have been deleted, or the address may have a typo." Then a short
paragraph explaining what Snip is, because FR-017 requires the page to explain the service rather
than show a bare error, and this page is the most common first contact an anonymous visitor has
with the product. One secondary link to the sign-up page. HTTP 404.

**Safety warning** (`banned.html.erb`, FR-018): a `--destructive` heading "This link has been
blocked", one `body` paragraph stating it was found to be unsafe and that the visitor has not been
forwarded. Below, the report control required by FR-033 — a single button, no form fields, no
CAPTCHA, posting the code that was requested. After posting, the same page renders "Thanks — this
link is already with our moderators." The destination URL is never displayed on this page; showing
it would defeat the block. HTTP 403.

Neither page is themed by the class-based dark variant, since there is no JavaScript to set the
class. Both use `@media (prefers-color-scheme: dark)` directly.

---

## 7. Component inventory

| Component | Source | Notes |
|---|---|---|
| Button, Input, Label, Card, Dialog, DropdownMenu, Badge, Skeleton, Tooltip, Table | shadcn/ui (`base-nova`) | Stock. Only the token values change. |
| Form, FormField, FormMessage | shadcn/ui | Wired to react-hook-form + zod per T070 |
| `<ShortLink>` | **Ours** | Renders the `snp.to/` prefix muted and the code in foreground, at `code` type. Used on §6.3, §6.4, §6.5, §6.6, §6.7, §6.8. The single place P1 is implemented. |
| `<CopyButton>` | **Ours** | Wraps `<ShortLink>` or stands alone. Owns the 2-second success swap and the `aria-live` announcement. The single place P2 is implemented. |
| `<ClickCount>` | **Ours** | `metric` type, tabular figures, fixed-width container. The single place P3 and P4 are implemented. |
| `<CreatorLinkRow>` | **Ours** | Creator table row. Has a clicks column. |
| `<AdminLinkRow>` | **Ours** | Admin table row. Has an owner column and structurally no clicks column. Deliberately *not* the same component as `<CreatorLinkRow>` with a flag — see P6. |
| `<EmptyState>` | **Ours** | Heading, one line, optional action. Used by §6.3 and §6.7. |
| `<ThemeToggle>` | **Ours** | system / light / dark, persisted in `localStorage`, applied by a pre-hydration inline script to avoid a flash of light theme. |

Charting library: none, and adding one is a spec change, not an implementation detail.

---

## 8. CSS subset for the Rails pages

`not_found.html.erb` and `banned.html.erb` render from a build with no Tailwind. They inline a
`<style>` block containing only what §6.9 needs:

- The six tokens they use: `--background`, `--foreground`, `--muted-foreground`, `--primary`,
  `--destructive`, `--border` — under `:root` and again under
  `@media (prefers-color-scheme: dark)`.
- Three type rules: `display`, `body`, `body-sm`.
- A system font stack. These pages do **not** load Figtree or JetBrains Mono — a webfont request on
  the anonymous-visitor path buys nothing and costs a round trip on the one path the whole project
  optimises for.
- One `.container` (max-width 480px, centered), one `.btn` (primary), one `.link`.

Roughly 40 lines. This block is duplicated in both templates rather than extracted into a shared
partial: two copies of 40 lines that never change is cheaper to reason about than an asset-pipeline
dependency on the redirect path, and Principle I makes anything added to that path expensive to
justify.

---

## 9. Accessibility budget

Non-negotiable against §1.

- **Contrast**: every text pair in §3.4 meets 4.5:1; every interactive boundary meets 3:1. New
  combinations must be measured, not eyeballed.
- **Focus**: a 2px `--ring` outline with a 2px offset on every interactive element. Never
  `outline: none` without a replacement. Focus is visible in both themes.
- **Keyboard**: every action reachable by keyboard. Dialogs trap focus, close on Escape, and return
  focus to their trigger. Row action menus are keyboard-openable.
- **Targets**: 44×44px minimum for touch. The copy button and the row `⋯` both meet this via
  padding, not by growing the icon.
- **Announcements**: copy confirmations, background count updates, and form errors are announced
  via `aria-live="polite"`. Destructive confirmations use `role="alertdialog"`.
- **Color is never the only signal**: error fields get a message and a border change, not just red
  text. Status badges carry a word, not just a color.
- **Zoom**: layouts hold to 200% zoom without horizontal scroll. Tables scroll horizontally within
  their container rather than forcing the page to.
- **Motion**: `prefers-reduced-motion` honoured throughout (§5.4).

---

## 10. Brief for Claude Design

Hand this section to Claude Design when generating the canvas (T123). It restates what a mockup
generator needs and nothing else.

**Published canvas**: <https://claude.ai/design/p/1c7890e4-1395-4ad5-b26d-8549c6fb9694?file=Snip+Design+Canvas.dc.html>
(*Snip Design Canvas*, generated with Claude Design, 2026-08-27.)

The canvas is the reference for spacing, proportion, and visual weight. This document remains the
reference for tokens, copy, and states. Where they disagree, this document wins and the canvas is
regenerated — a canvas that drifts from the tokens in §3 is out of date, not a new decision.

The brief below is kept verbatim rather than deleted, so a regeneration starts from the same
instructions the first one did.

**Product**: Snip (placeholder name), a URL shortener. Short domain `snp.to`.

**Audience**: a marketer, not an engineer. Warm and approachable, never enterprise-cold.

**Palette**: exactly the hex values in §3.1 and §3.2. Do not introduce colors outside those tables.

**Type**: Figtree for UI, JetBrains Mono for codes, URLs and numbers. Scale in §4.2.

**Geometry**: 12px base radius, 4px spacing grid using only 4/8/12/16/24/32/48/64, three elevation
levels from §5.3.

**Artboards to produce** — 11 total, at 1280×832 unless noted:

1. Sign in (§6.2) — light
2. Sign up (§6.2) — light
3. Link list with 6 rows of realistic data (§6.3) — **light and dark, two artboards**
4. Link list, empty state (§6.3) — light
5. Create link, form state (§6.4) — light
6. Create link, success state with the copy button (§6.4) — light
7. Edit link with the read-only code row (§6.5) — light
8. Delete confirmation dialog over a dimmed list (§6.6) — light
9. Admin moderation queue with 5 reports (§6.7) — **light and dark, two artboards**
10. Admin health tiles (§6.8) — light
11. Not-found and safety-warning pages side by side (§6.9) — 640×832 each

**Sample data to use**, so mockups are comparable to each other:

| Code | Destination | Created | Clicks |
|---|---|---|---|
| `k7Bx2mQ` | `https://acme.example/spring-sale?utm_source=twitter` | 3 days ago | 1,284 |
| `p9Wd4tL` | `https://acme.example/blog/how-we-cut-latency-in-half` | 5 days ago | 96 |
| `zR2fN8v` | `https://acme.example/careers/senior-designer` | 1 week ago | 8 |
| `mT5hK1c` | `https://docs.example.com/getting-started` | 2 weeks ago | 4,051 |
| `bQ8sV3r` | `https://acme.example/webinar/2026-03-11` | 3 weeks ago | 0 |
| `xL6nJ9d` | `https://acme.example/pricing` | 1 month ago | 372 |

Note the deliberate range: a zero, a single digit, and a four-digit count, so the tabular-figure
column alignment from P4 is actually visible in the mockup.

**Do not draw**: charts, sparklines, trend arrows, a sidebar, a clicks column in any admin table,
or illustrations in empty states.

---

## 11. Traceability

### Requirements this document serves

| Requirement | Where |
|---|---|
| FR-003 (admin role separation) | §6.1 — no admin affordance rendered for creators |
| FR-004 (50-link and hourly limits) | §6.3 usage line, §6.4 preemptive and form-level treatments |
| FR-005 (short address, one-click copy) | P1, P2, §6.3, §6.4 |
| FR-017 (not-found explains the service) | §6.9 |
| FR-018 (safety warning, not a redirect) | §6.9 |
| FR-019 (redirects never blocked) | §6.4 — stated in the 429 copy |
| FR-023 (click count per link) | P3, §6.3 |
| FR-026 (code is immutable) | §6.5 read-only row |
| FR-028, FR-029 (soft delete, 30-day hold) | §6.6 dialog copy |
| FR-030 (admin link search) | §6.8 |
| FR-031 (ban link or account) | §6.7 |
| FR-033 (report control) | §6.7 queue, §6.9 warning page |
| FR-034 (no customer analytics to admins) | P6, §6.7, §6.8 |
| FR-035 (operational health) | §6.8 |
| FR-036 (indistinguishable auth refusal) | §6.2 single failure message |
| SC-003 (first link under 2 minutes) | §6.2 explanatory line, §6.4 success panel |
| SC-009 (count fresh within 30s) | P4, §6.3 |
| SC-010 (ban in under 1 minute) | §6.7 inline actions |

### Tasks this document adds

Four tasks are required before any screen can be built to this specification. They are added to
`tasks.md` at the next free IDs, per that file's Task IDs convention.

- **T123** — Generate the canvas with Claude Design from the brief in §10 and record its URL there.
  Phase 2, before T121 and T122. **Done** — URL recorded in §10.
- **T120** — Replace the `:root` and `.dark` token blocks in `frontend/src/app/globals.css` with
  §3, bind Figtree and JetBrains Mono via `next/font/google` in `frontend/src/app/layout.tsx`, and
  set `--radius` to `0.75rem`. Phase 2.
- **T121** — Install the shadcn components listed in §7 and build the app shell from §6.1,
  including `<ThemeToggle>` with the pre-hydration script. Phase 2.
- **T122** — Build the shared components from §7 — `<ShortLink>`, `<CopyButton>`, `<ClickCount>`,
  `<EmptyState>` — with component tests for the copy success swap and the tabular-figure column
  width. Phase 4, before T069.

### Tasks this document constrains

T037, T068, T069, T070, T080, T081, T084, T094, T095, T108 each gain a pointer to their section
here.
