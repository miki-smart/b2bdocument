# UI Design Reference (for Stitch/v0/Figma AI) — Movello B2B Mobility Marketplace

**Last verified against code: 2026-07-23**

> **Reframing notice.** This document was originally written as a **from-scratch UI-generation prompt** for an AI design tool (Stitch/v0/Figma AI), describing a blue-600 (`#2563EB`) / dark-navy-sidebar / light-gray palette that **was never the palette actually shipped**. The real app uses a **deep-teal primary / warm-orange secondary** HSL token system (`src/index.css`), and its real screen set is considerably larger and structurally different from the 16 screens originally listed (no Direct Rental, no admin master-data, a flattened bid/award/contract model). Rather than delete this document, it has been rewritten as an **as-built UI reference** — still organized portal-by-portal for the benefit of anyone regenerating mockups or extending the design system, but corrected to match the real palette, real components (shadcn/ui + Radix, not generic Tailwind), and real screen inventory. If you use this document as an AI-design-tool prompt going forward, use the corrected theme block in §1, not the original blue palette.

---

## 1. Corrected Theme Block

```
Framework: Tailwind CSS 3.4 + shadcn/ui (Radix UI primitives) — not generic Tailwind/Bootstrap.
Primary: Deep Teal — hsl(185 64% 34%) ≈ #1c7a7d, with a 50–700 tint/shade ramp
Secondary: Warm Orange — hsl(28 100% 54%) ≈ #ff7f11
Success: hsl(142 76% 36%)   Warning: hsl(38 92% 50%)   Destructive: hsl(0 72% 51%)   Info: hsl(199 89% 48%)
Background: hsl(210 20% 98%)   Card surface: hsl(0 0% 100%)   Border: hsl(214 18% 88%)
Radius: 0.625rem (rounded-lg maps to this)
Body font: Inter (300–800)      Headings/display: Plus Jakarta Sans (400–800)
Dark mode: full HSL token swap under a `.dark` class — background hsl(220 25% 8%), primary lightens to hsl(185 55% 52%)
Shadows: named tokens --shadow-sm/md/lg/xl/card/glow (not default Tailwind shadow-*)
Sidebar: a dedicated dark palette (hsl(220 25% 10%) background) used for the app's persistent dark sidebar look in both light and dark mode
```

Do **not** generate mockups using `#2563EB` blue, `bg-slate-900` ad hoc sidebars, or default Tailwind shadow/radius scales — use the tokens above (exposed through Tailwind as `bg-primary`, `text-primary-foreground`, `shadow-card`, `rounded-lg`, `bg-sidebar`, etc., per `tailwind.config.ts`).

## Instructions for AI Designer (if regenerating mockups from this doc)

1. **Strict ordering:** generate portal-by-portal in the order below — Business, then Provider, then Wallet/Finance (now integrated per-portal, not a separate part), then Admin.
2. **Visual consistency:** one dark sidebar + light header across all authenticated portals; shadcn/ui `Card` for every container; `rounded-lg` (0.625rem) corners throughout.
3. **Data accuracy:** use the field names and control types below — they reflect real form/table shapes in `src/features/*`, not placeholder data.
4. **Action labels:** label buttons exactly as specified (e.g. "Publish RFQ", "Award Selected Bids", "Extend Contract" — never "Renew Contract"; there is no renewal-as-new-contract flow in this app).

---

## PART 1: Business Portal

### 1. Business Dashboard
- Sidebar left (dark), header top.
- Stat cards: "Active RFQs" (FileText icon), "Ongoing Contracts" (Briefcase icon), "Wallet Balance" (Wallet icon) — use `primary`/`secondary`/`success` tokens for icon accents, not raw blue/green/orange hex.
- "Recent Activity" table: Date, Activity Type, Details, Status (`StatusBadge` component).

### 2. Create RFQ — multi-step wizard (one route, not one route per step)
- Step covering: Title, Description, Start/End Date range, Bid Deadline, Location.
- Line-items step: **repeatable line-item rows** — Vehicle Type, Quantity, With Driver (switch), Tags (multi-select) — "+ Add Line Item." An RFQ is a header **plus an array of line items**, not a single vehicle-type/quantity form.
- Sticky summary panel: title, dates, total vehicles across all line items.
- Actions: "Cancel" (ghost), "Save Draft" (outline), "Publish RFQ" (primary/teal).

### 3. RFQ Detail (Business)
- Header: title, `StatusBadge`, "Cancel RFQ" (destructive outline, draft/published states only).
- Info cards: duration, location, total line items.
- Line items table: type, qty, driver flag, tags.
- Bids banner: "N Bids Received" → "Review Bids."

### 4. Bid Review & Split Award (critical screen)
- Grouped **by line item** (tabs or accordion, one group per `RFQLineItem`).
- Per-line-item table: `Select` (checkbox — multi-select supported, this is what enables split awards), masked provider label (blind until award), Qty Offered, Unit Price, Total, Trust Score badge.
- Bottom bar: "Total Escrow Required: ETB X" + "Award Selected Bids" (primary). Awarding a line item across multiple checked rows produces a **split award** — more than one provider can win the same line item's quantity; this is real production behavior (`SplitAwardDialog.tsx`), not a hypothetical.
- After award: a **separate vehicle-assignment step** follows (not shown on this screen) before delivery — do not conflate award with vehicle assignment when mocking flows.

### 5. Contract Detail
- Header: contract number, `StatusBadge` reflecting the real (18-value, string-based) status set — never show a "Suspended" status; it does not exist.
- Sections: contract terms (with a **dual-party OTP e-signature** step required from both business and provider before the contract becomes active — this is not a checkbox/canvas signature), assigned vehicles table (plate, type, status), delivery/return checklist section.
- Actions: "Extend Contract" (opens `ExtendContractDialog` — lengthens the end date; there is no "Renew" button/flow anywhere in this app), "Request Early Return," "Download PDF."

### 6. Direct Rental (missing from the original prompt entirely)
A **fixed-price, non-bidding** vehicle booking flow that runs parallel to the RFQ marketplace:
- Browse vehicles (grid/card view, filter by type/location).
- Vehicle detail page.
- Cart (add vehicles, review, submit request).
- Requests list + request detail (provider accept/reject, status tracking).

---

## PART 2: Provider Portal

### 7. Provider Dashboard
- Stat cards: Active Contracts, Fleet Status (pie: Active/Assigned/Maintenance), Wallet Balance, Trust Score (gauge — this is a real, backend-computed formula value, not a mock number).

### 8. Marketplace (RFQ browse)
- Grid of RFQ cards, left sidebar filters (vehicle type checkboxes, duration radio, location select, debounced title search), sort dropdown (newest/oldest/most-bids/least-bids).
- Card content: title, date range, line-items summary, per-line-item bid-count badge, "Bid Now" (primary) + bookmark icon.

### 9. RFQ Detail & Bid Submission
- Split screen: RFQ info left, bid form right — **per line item**: quantity offered (≤ required), unit price, notes. Provider bids **at the fleet/quantity level — no specific vehicle is chosen at bid time.**

### 10. My Bids + Award-Assign (two screens, not one)
- My Bids: table of submitted bids with status (submitted/awarded/rejected).
- **Award-Assign** (a screen the original prompt omitted entirely): after an award, provider assigns specific vehicles from their fleet to the awarded quantity — the real post-award vehicle-assignment step, mirrored on both mobile apps.

### 11. Fleet — Vehicle Registration & List
- Registration: plate number, type, make/model, year, seat count, tags; insurance section (type, company, policy #, coverage dates, certificate upload); 5-photo grid (front/back/left/right/interior).
- Fleet list + Fleet Capacity Overview (shows cross-checked capacity against both RFQ contract commitments and Direct Rental bookings — `SegmentCapacityMeter`, `FleetCapacityConflictSheet`).

### 12. Contract Delivery / Return Flow
- Delivery OTP verification (6-box input, expiry timer).
- Handover evidence upload (odometer, fuel level, 5 photos, notes).
- A **second, symmetric return-trip flow** with its own OTP and a vehicle inspection checklist — not present in the original prompt at all.

### 13. Wallet / Settlements
- Summary cards: Total Earnings, Available Balance, Pending Settlement.
- Settlement history table + per-settlement breakdown, invoices list.

---

## PART 3: Admin Portal (the largest portal — 3 screens in the original prompt undersold this badly)

### 14. Admin Dashboard
- Metrics: total businesses, providers, active contracts, platform revenue; pending-verification count with link.

### 15. Verification Queue
- Tabs: Pending Businesses, Pending Providers (and vehicle KYC as its own queue).
- Table: name, type, submitted date, documents (link) → Approve / Reject / Request More Info.

### 16. Wallets — 7 distinct pages, not one
All Wallets, Wallet Detail, Platform Wallet Dashboard, Escrow Wallet Management, Escrow Transactions, Withholding Tax, Platform Account Management.

### 17. Master Data (entirely absent from the original prompt)
Full CRUD UI for tiers (provider/business), escrow/contract/settlement policy versions + rules, commission strategies, lookups, geography, banks, platform bank accounts, checklist templates, contract-terms templates.

### 18. Notifications (admin)
Per-channel provider configuration (email/SMS/FCM credentials with live test-send) and notification-template management — an admin-configurable multi-channel system, not a static "send an email" note.

### 19. Operations
Act on RFQs, bids, contracts, settlements, wallets, and Direct Rental requests on behalf of any business/provider — a screen group the original prompt never mentioned.

---

## Design Notes

- All tables: subtle `bg-muted` header row, consistent cell padding, `StatusBadge` for any status column.
- Primary actions always use the **teal** primary token, never blue-600.
- Use shadcn/ui `Card` for every container, `Dialog`/`Sheet` for modals and slide-overs (e.g. `SplitAwardDialog`, `ExtendContractDialog`, `FleetCapacityConflictSheet`).
- Icon-only buttons need `aria-label`; forms use shadcn `Form`/`FormField` composed with React Hook Form + Zod, not raw `<input>` styling.
