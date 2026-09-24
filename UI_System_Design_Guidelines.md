# UI System Design Guidelines

**Last verified against code: 2026-07-23**

> **Reframing notice.** The prior version of this document (dated November 26, 2025, "Version 1.0 MVP") specified a **blue-600 (`#2563EB`) primary palette, gray-800/500 neutrals, and a `bg-slate-900` sidebar** as the design system to build. **None of that palette was ever shipped.** The real application, `marketplace-project-implementation/anqelbacarrental-marketplace-core/`, uses a **deep-teal primary / warm-orange secondary** HSL custom-property system defined in `src/index.css` and mapped through `tailwind.config.ts`, with a full light/dark theme (`.dark` class), named shadow/gradient tokens, and a two-font type system (Inter for body, Plus Jakarta Sans for headings) — none of which existed in the prior version. Rather than delete this document, it has been rewritten as an **as-built design-system reference**, verified directly against `src/index.css` and `tailwind.config.ts`. Where this document and those two files disagree in the future, trust the code.

---

## 1. Color Palette (verified against `src/index.css`, light theme)

All colors are HSL CSS custom properties consumed through Tailwind via `hsl(var(--token))` — never hardcoded hex utility classes like `bg-blue-600` or `text-gray-800`.

### Brand
| Token | Value | Approx. hex | Use |
|---|---|---|---|
| `--primary` (`bg-primary`) | `hsl(185 64% 34%)` | `#1c7a7d`-ish deep teal | Primary actions, links, active nav state |
| `--primary-foreground` | `hsl(0 0% 100%)` | white | Text/icons on primary |
| `--primary-50` … `--primary-700` | tint/shade ramp | — | Backgrounds, hover/active accents, subtle highlights |
| `--secondary` (`bg-secondary`) | `hsl(28 100% 54%)` | `#ff7f11`-ish warm orange | Secondary CTAs, energetic accents (e.g. "Bid Now") |
| `--secondary-foreground` | `hsl(0 0% 100%)` | white | Text/icons on secondary |
| `--secondary-50`, `--secondary-100` | light tints | — | Secondary-tinted backgrounds |

### Semantic
| Token | Value | Use |
|---|---|---|
| `--success` | `hsl(142 76% 36%)` | Active, Verified, Completed |
| `--warning` | `hsl(38 92% 50%)` | Pending, Expiring Soon, Review |
| `--destructive` | `hsl(0 72% 51%)` | Error, Delete, Blocked, Overdue |
| `--info` | `hsl(199 89% 48%)` | Informational banners/tips |

### Neutrals & Surfaces
| Token | Value | Use |
|---|---|---|
| `--background` | `hsl(210 20% 98%)` | Page background |
| `--foreground` | `hsl(220 25% 12%)` | Primary body/heading text |
| `--card` / `--card-foreground` | `hsl(0 0% 100%)` / `hsl(220 25% 12%)` | Card and modal surfaces |
| `--muted` / `--muted-foreground` | `hsl(210 15% 94%)` / `hsl(220 10% 46%)` | Secondary text, disabled states, table stripes |
| `--border` / `--input` | `hsl(214 18% 88%)` | Dividers, input borders |
| `--accent` / `--accent-foreground` | `hsl(185 45% 94%)` / `hsl(185 64% 28%)` | Subtle teal-tinted highlight (hover rows, selected chips) |

### Sidebar (its own dedicated dark palette, used in both light and dark app theme)
| Token | Value |
|---|---|
| `--sidebar-background` | `hsl(220 25% 10%)` |
| `--sidebar-foreground` | `hsl(210 15% 85%)` |
| `--sidebar-primary` | `hsl(185 64% 50%)` |
| `--sidebar-accent` | `hsl(220 25% 16%)` |
| `--sidebar-border` | `hsl(220 20% 18%)` |

The persistent dark sidebar is a deliberate, dedicated token set (`bg-sidebar`, `text-sidebar-foreground`, etc. via `tailwind.config.ts`'s `sidebar` color group) — not `bg-slate-900` applied ad hoc, and not the same token as `--background`.

### Dark Mode (`.dark` class, `darkMode: ["class"]`)
Every token above is redefined for dark mode rather than relying on Tailwind's automatic contrast inversion — e.g. `--background: hsl(220 25% 8%)`, `--primary: hsl(185 55% 52%)` (lightened for contrast on dark surfaces), `--card: hsl(220 25% 11%)`. Always reference the semantic token (`bg-background`, `text-foreground`) rather than a light-mode-only hex value, so components work correctly in both themes without extra `dark:` overrides in most cases.

### Gradients & Shadows (real tokens, not default Tailwind)
- Named gradients: `--gradient-primary`, `--gradient-secondary`, `--gradient-hero`, `--gradient-card`, `--gradient-mesh` (radial teal/orange mesh, used sparingly for hero/marketing-style sections) — exposed as utility classes `.gradient-primary`, `.gradient-hero`, etc.
- Named shadows: `--shadow-sm/md/lg/xl/card/glow`, mapped in `tailwind.config.ts`'s `boxShadow` extension (`shadow-card`, `shadow-glow`, …) — **do not use Tailwind's bare default `shadow`/`shadow-md` semantics as the design spec**; use these named tokens so light/dark both resolve correctly.

**Do not** reintroduce `#2563EB`/blue-600, `#1E40AF`/blue-800, `bg-slate-900`, or plain `gray-*` neutral classes when building new screens — use the tokens above via their Tailwind color names (`bg-primary`, `text-muted-foreground`, `border-border`, etc.).

---

## 2. Typography (verified against `src/index.css` + `tailwind.config.ts`)

Two font families, both loaded via Google Fonts `@import` at the top of `src/index.css` — not a single "Inter everywhere" system as the prior version specified:

- **Body text (`font-sans`):** `Inter`, weights 300–800.
- **Headings `h1`–`h6` and `.font-display`:** `Plus Jakarta Sans`, weights 400–800 — applied automatically to every heading tag via `@layer base` (`font-family: 'Plus Jakarta Sans', …` plus `font-semibold tracking-tight`), so headings never need a manual class to get the display font.

### Scale (Tailwind utility classes actually used in the app — no fixed corporate type scale is enforced beyond these conventions)
- **H1 (page title):** `text-3xl font-bold` (heading font applies automatically)
- **H2 (section title):** `text-xl font-semibold`
- **H3 (card title):** `text-lg font-medium`
- **Body:** `text-base text-foreground` / `text-muted-foreground` for secondary body copy
- **Small:** `text-sm text-muted-foreground`
- **Tiny (labels, meta):** `text-xs text-muted-foreground`

Use `text-foreground` / `text-muted-foreground` rather than hardcoded `text-gray-800` / `text-gray-500` — they resolve correctly in both light and dark themes.

---

## 3. Components (shadcn/ui + Radix, not generic hand-rolled HTML)

The prior version's raw Tailwind HTML snippets (`<button class="bg-blue-600 ...">`) do not reflect how the app is actually built. Every primitive below already exists as a component in `src/components/ui/` (shadcn/ui conventions over Radix UI primitives) — build screens by composing these, not by writing new raw `<button>`/`<input>` markup.

### Buttons (`src/components/ui/button.tsx`, `class-variance-authority` variants)
```tsx
<Button>Create RFQ</Button>                       {/* default variant → bg-primary */}
<Button variant="secondary">Cancel</Button>
<Button variant="destructive">Delete</Button>
<Button variant="outline">Save Draft</Button>
<Button variant="ghost">Cancel</Button>
```

### Cards
```tsx
<Card>
  <CardHeader><CardTitle>Card Title</CardTitle></CardHeader>
  <CardContent>Card content goes here…</CardContent>
</Card>
```
Cards render with `shadow-card` and `rounded-lg` (`--radius: 0.625rem`) by default — do not override with plain `shadow` or arbitrary `rounded-md` values.

### Status badges (`src/shared/components/data/StatusBadge.tsx`)
```tsx
<StatusBadge status="active" />     {/* success token */}
<StatusBadge status="pending" />    {/* warning token */}
<StatusBadge status="rejected" />   {/* destructive token */}
```
`StatusBadge` maps real domain status strings (RFQ/contract/bid/wallet statuses) to the semantic color tokens above — do not hand-roll `bg-green-100 text-green-800` badge markup per screen.

### Forms
```tsx
<FormField label="Email Address" error={errors.email?.message}>
  <Input type="email" placeholder="you@example.com" {...register('email')} />
</FormField>
```
Built on shadcn `Form`/`FormField`/`Input` composed with React Hook Form + Zod (`zodResolver`) — every form in the app follows this pattern, not manual `<label>`/`<input>` pairs with ad hoc focus-ring classes.

### Other real shared components (`src/shared/components/`)
`DataTable`, `EmptyState`, `LoadingSkeleton`, `StatCard` (data/); `ValidatedInput`, `FileUpload`, `OTPInput` (forms/); `SplitAwardDialog` (business/); plus dedicated `contracts/`, `wallet/`, `direct-rental/`, `onboarding/`, `profile/`, `brand/` component groups. See `markdown-documentations/Frontend_Architecture_Guide.md` §6 for the fuller component inventory.

---

## 4. Layouts

### Dashboard layout (desktop)
- **Sidebar:** fixed left, dark (`bg-sidebar`/`--sidebar-background`, not `bg-slate-900`), present in `BusinessLayout`, `ProviderLayout`, `AdminLayout` (`src/app/layouts/`).
- **Header:** fixed top, light surface (`bg-card`), houses notification bell (unread count from `useNotificationStore`) and user menu.
- **Main content:** scrollable region offset for the fixed sidebar/header.

### Responsive breakpoints (Tailwind defaults — `tailwind.config.ts` does not override `screens`, only the `2xl` container max-width)
| Breakpoint | Width |
|---|---|
| `sm` | 640px |
| `md` | 768px |
| `lg` | 1024px |
| `xl` | 1280px |
| `2xl` | 1536px (container itself caps at `1400px` via the `container.screens['2xl']` override) |

### Mobile adaptations
- Sidebar collapses to an off-canvas/hamburger pattern.
- Wide tables scroll horizontally inside their own container rather than reflowing to stacked cards everywhere — verify per-screen before assuming a card view exists.
- Modals/dialogs use Radix `Dialog`/`Sheet` primitives, which already handle mobile-appropriate sizing.

---

## 5. Accessibility

- **Contrast:** all token pairs (`--foreground`/`--background`, `--primary-foreground`/`--primary`, etc.) are chosen to meet WCAG AA (4.5:1) in both light and dark mode — don't introduce a one-off color pairing that skips this.
- **Focus states:** Radix primitives ship built-in focus-visible handling; shadcn `Button`/`Input` variants include `focus-visible:ring-2 focus-visible:ring-ring` — use the `ring` token, not a hardcoded `focus:ring-blue-500`.
- **Semantic HTML:** `<button>`, `<nav>`, `<main>` — Radix components already render correct roles for `Dialog`, `Tooltip`, `Tabs`, etc.
- **ARIA:** icon-only buttons require `aria-label` (e.g. notification bell, table row actions).

---

## 6. What This Document No Longer Claims

To avoid re-introducing the errors this rewrite corrects:
- No blue-600/blue-800/gray-800 palette anywhere — the real brand colors are deep teal (`--primary`) and warm orange (`--secondary`).
- No `bg-slate-900` sidebar as a one-off class — the sidebar is its own dedicated token group (`bg-sidebar`, etc.).
- No single-font ("Inter everywhere") type system — headings use Plus Jakarta Sans, body uses Inter.
- No raw hand-rolled `<button>`/`<input>` HTML as the component spec — every primitive is a shadcn/ui component in `src/components/ui/` or a composed component in `src/shared/components/`.

For the fuller architecture and page-by-page breakdown, see `06_FRONTEND_ARCHITECTURE.md`, `FRONTEND_AI_PROMPT.md`, and `UI_DESIGN_GENERATION_PROMPT.md` in this same directory, plus `markdown-documentations/Frontend_Architecture_Guide.md`.
