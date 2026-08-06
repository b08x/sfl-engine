# Syncopated Notes — Design System

> *Irregular notes and observations.*

Syncopated Notes is a personal knowledge base / digital garden in the **"Field Note"**
idiom: a paper-notebook aesthetic — cream parchment surfaces, dark ink, a single
terracotta accent, and **Space Mono everywhere**. Border-driven and monospace-forward,
it reads like a researcher's index card — badges, field-note cards, command/output
panels, Obsidian-style callouts — rather than a polished blog. Light parchment is the
default; a warm lamp-lit night mode is the companion.

This repository is the design system that makes that look reproducible: tokens,
fonts, reusable React primitives, a knowledgebase UI kit, and a flagship slide
template.

---

## Source material

This system was reverse-engineered from the real product and its marketing site.
You do **not** need access to these — they are recorded so a future maintainer can go deeper.

- **GitHub — `b08x/b08x.github.io`** (`https://github.com/b08x/b08x.github.io`)
  The Jekyll site for Syncopated Notes (landing) + *HindsightAI* (a satirical/fictional
  research startup). Defines the published **"Field Note"** theme (`_includes/theme-tokens.html`):
  cream parchment, terracotta amber, Space Mono. Explore it to understand the warm,
  field-notebook side of the brand and the badge / field-note / code-panel components.
- **Attached codebase — `assets/`** (the live knowledgebase app build)
  The actual product CSS/JS: Tailwind v4 + Jekyll SCSS, dual light/dark theme manager,
  Obsidian callouts (12 types), Rouge syntax highlighting mapped to a `--chart-1…5`
  palette, and a pan/zoom canvas viewer. This is the **primary** source for the IDE
  aesthetic captured here. Key files: `assets/css/components/_callouts.css`,
  `_syntax-highlighting.css`, `assets/js/theme-manager.js`, `assets/css/AGENTS.md`.
- **Fonts** — Space Mono (primary, via Google Fonts, exactly as the live site loads it)
  + JetBrains Mono, Inter, Hack, Mononoki shipped as alternates in `fonts/`.

> The brand has two faces: the warm **Field Note** theme (cream parchment + Space Mono +
> terracotta) and an **IDE knowledgebase** product theme (paper/ink + JetBrains Mono +
> cyan). This system canonicalizes the **Field Note** theme — the documented house style
> — and keeps the IDE monos and the editor syntax palette available as alternates. The
> earthy status palette (dusty blue / olive / ochre / brick red) reads like Visio circa
> 2003–2008, which is exactly the register the flagship deck wants.

---

## CONTENT FUNDAMENTALS — how Syncopated Notes writes

The voice is a **working engineer's field notebook**: precise, dry, a little wry,
never marketing-slick. Notes are observations, not announcements.

- **Person & stance.** Mostly impersonal and declarative ("Networks accumulated DNS,
  DHCP, NAT…"). Second person appears as instruction inside prompts/protocols
  ("Design the AI's interaction to mirror human conversational rhythm"). First person
  is rare and informal when it shows up. The reader is treated as a peer who already
  knows the domain — no hand-holding.
- **Casing.** The wordmark and most chrome are **lowercase** ("syncopated notes").
  Section headers are **Title Case** or terse phrases ("The Claim vs. The Leak",
  "SFL Metadata"). Tags are **kebab-case** (`prompt-engineering`, `natural-pacing`).
  Code, IDs, and addresses stay verbatim (`10.1.20.0/24`, `OSPF / BGP`).
- **Tone & vibe.** Analytical and structural. Loves a clean analogy carried all the way
  through ("OSPF flooding ≈ planner fan-out — same shape, new payload"). Comfortable
  with jargon; defines it only when the point depends on it. Favors the rhetorical
  pivot: a **Claim** followed by **The Leak** (the messy reality that erodes it).
- **Brevity.** The product literally encodes an anti-verbosity protocol — avoid
  "essay mode", boilerplate openers ("I hope this helps"), and restating the question.
  Prefer sentence fragments and contractions in conversational copy; prefer dense,
  scannable structure (bullets, tables, callouts) in reference copy.
- **Emoji.** Not used in prose or UI chrome. The **only** emoji-like marks are the
  callout glyphs (✎ ⚡ 🔥 ✓ ⚠ ✗ ◈ “) that label admonition types — treat these as an
  icon set, not decoration. Unicode symbols (→, ☁, ◐, │) are used structurally in
  diagrams. Don't sprinkle emoji anywhere else.
- **Examples of the house style.**
  - Title: *"Enterprise Network (2004) → Agentic Infrastructure (2026)"*
  - Eyebrow: *"I'VE SEEN THIS DIAGRAM BEFORE"*
  - Callout: *"The orchestrator just routes tasks." — then the leak.*
  - Meta line: *"Last Modified: 2026-02-02 06:37:57 PM"*

---

## VISUAL FOUNDATIONS

**Overall.** A field notebook in print. Structure comes from **1px hairline borders**,
not shadow. **Space Mono carries the entire identity** — chrome, headings, body, and
code are all the same monospace voice. Generous whitespace, dense scannable chrome,
two-rail reading layout (nav · article · TOC).

- **Color.** Cream parchment surfaces (`--background #EDE6D6` → `--surface #E3DBC8` →
  `--bg-code`) under dark ink (`--foreground #2A2420`). One warm accent — **terracotta**
  (`--accent #B5654A`, headings + primary actions) — with a **dusty slate-blue**
  (`--cyan #5C7C99`) for the wordmark + links. A five-stop **earthy palette**
  (`--chart-1…5`: blue/ochre/olive/plum/red) does double duty as syntax highlighting
  *and* data/diagram colors. A muted, Visio-era **status** set
  (info/abstract/success/question/warning/danger/special) drives callouts and badges.
  The logo mark is a distinct deep **plum `#8B0A5F`**, used *only* in the mark.
  **Dark mode** (`.dark` on `<html>`) is a warm lamp-lit night (`#211C17` bg, brighter
  terracotta `#C97A5E`, warm cream ink) — never a cold IDE black.
- **Type.** Space Mono (400/700 + italics) for *everything* — display, UI, code,
  metadata, and body. Headings are bold, terracotta, tight tracking. Eyebrows are
  uppercase with wide tracking. Body is 15px / 1.7. JetBrains Mono, Hack & Mononoki
  ship as alternate monos; Inter as an alternate sans — none used by default.
- **Spacing & layout.** 8px rhythm with a 4px sub-step for dense chrome. Fixed rails
  (`--sidebar-w 232px`, `--toc-w 220px`), article column 860px, sticky 56px header with
  `backdrop-filter: blur(8px)`.
- **Backgrounds.** Mostly flat paper. Signature decorative motif is a **faint blueprint
  grid** (48px, hairline) on hero/diagram surfaces — never gradients. No photographic
  hero imagery in chrome; imagery appears as embedded note media (diagrams, canvas maps).
- **Corners & cards.** Minimal radii (3/4/8/12px; 20px reserved for canvas nodes/hero).
  Cards = `--surface` fill + 1px `--border` + `--shadow-sm`, optionally a 3px coral
  left-rule for emphasis. Callouts add a mono title bar with a glyph and an italic body.
  The classic **field-note card** variant uses a full 1px dark-ink border (not a
  hairline) on cream — an index card.
- **Borders & shadows.** Borders are the primary structural device (1px standard, 2px
  active/focus, 3px accent rules). Shadows are soft, neutral, and **rare** — `xs`→`lg`,
  used only to lift popovers/cards a touch. A `--shadow-glow` (coral ring) marks active
  canvas/focus states.
- **Motion.** Restrained. `fadeIn` (opacity + 10px rise, 0.5s ease-out) for entering
  content; 120–200ms ease-out for interactions. No bouncing, no infinite loops.
- **Hover / press.** Hover = subtle surface shift (`--surface`/`--popover`) or accent
  darken; links underline. Press = **scale down** (buttons 0.97, icon buttons 0.92).
  Icon buttons scale **up** 1.05 on hover. Focus = terracotta ring (`0 0 0 3px var(--ring)`).
- **Transparency & blur.** Used sparingly and purposefully: the sticky header
  (`color-mix` translucent + blur) and the canvas viewport. Not a general aesthetic.
- **Imagery vibe.** When present, technical and neutral — diagrams, network/agent graphs,
  HL7/protocol screenshots. Cool, flat, documentary. No warm filters or grain.

---

## ICONOGRAPHY

The product is **deliberately light on iconography** — its "icons" are mostly
**typographic**:

- **Callout glyphs.** The signature icon set is the 12 Obsidian-style callout markers,
  rendered as Unicode glyphs colored by status: ✎ note · ℹ info · ☐ todo · ⚡ abstract ·
  🔥 tip · ✓ success · ? question · ⚠ warning · ✗ error · ◈ example · “ quote. These live
  in the `Callout` component — reuse them, don't invent new ones.
- **Structural Unicode.** Diagrams use →, ☁, ◐, │, ┌┴┐-style rules drawn as 1–2px divs.
- **Line SVG.** UI affordances (theme sun/moon, copy, search, chevron, calendar, hash)
  are tiny inline **stroke SVGs at 1.4–1.5 weight**, `currentColor`. They're defined
  inline in the UI kit (`ui_kits/knowledgebase/app.jsx`) — copy from there. There is no
  packaged icon font; if you need more, match that stroke weight (Lucide/Feather are the
  closest CDN match — flag any substitution).
- **Brand mark.** `assets/brand/icon.svg` / `logo.svg` — a plum (`#8B0A5F`) rounded square
  with white circle/quarter-disc "node" motifs (a syncopated-rhythm graph). Favicon &
  touch-icon in `assets/brand/`.
- **Emoji** are not used as UI icons (see Content Fundamentals).

---

## Index / manifest

**Root**
- `styles.css` — the single entry point consumers link (imports only).
- `tokens/` — `fonts.css` · `colors.css` · `typography.css` · `spacing.css` ·
  `elevation.css` · `base.css`.
- `fonts/` — JetBrains Mono, Inter, Hack, Mononoki webfonts.
- `assets/brand/` — logo, icon, favicon, touch-icon, sample note imagery.
- `SKILL.md` — Agent-Skill manifest (for use in Claude Code).

**Foundations** (`guidelines/`, shown in the Design System tab)
- Colors: Brand Accents · Surfaces · Ink & Text · Editor/Chart Palette ·
  Status & Diagram Layers · Night/IDE Theme.
- Type: Display & Headings · Prose Body · Mono/Code/Meta · Type Scale.
- Spacing: Spacing Scale · Radius & Borders · Elevation.
- Brand: Logo & Mark.

**Components** (`components/`, namespace `window.SyncopatedNotesDesignSystem_*`)
- `core/` — Button · IconButton · Badge · Tag · Card
- `forms/` — Input · Select · Switch · Checkbox
- `feedback/` — Callout · CodePanel
- `navigation/` — Tabs · NavItem
- Each has `.jsx` + `.d.ts` + `.prompt.md`; one `@dsCard` demo per directory.

**UI kit** (`ui_kits/knowledgebase/`)
- The live note-reader recreation: header + nav rail + article + TOC, light/dark toggle.
  Composes the primitives. `index.html` mounts `app.jsx`.

**Template** (`templates/agentic-infrastructure-deck/`)
- *Agentic Infrastructure Deck* — a 6-slide DC deck in Cisco-Visio grammar mapping the
  2004 enterprise network onto 2026 agent infrastructure. Edit `ds-base.js`'s `base` line
  to rebind in a consuming project.

---

## Using it

- **Foundations / brand rules** → read this file + the `guidelines/` cards.
- **Build a screen** → link `styles.css`, load `_ds_bundle.js`, read components via
  `const { Button, Callout } = window.SyncopatedNotesDesignSystem_*` (run
  `check_design_system` for the exact namespace).
- **Build a deck** → start from the `templates/` DC.
- **Throwaway artifact** → copy assets out and emit static HTML using the tokens.
