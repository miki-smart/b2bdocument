# UI System Design Guidelines

**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Framework:** Tailwind CSS  
**Theme:** Professional, Trust-Centric, Clean

---

## 🎨 Color Palette

### Primary Colors (Brand)
- **Primary Blue:** `#2563EB` (blue-600) - Main actions, links, active states.
- **Primary Dark:** `#1E40AF` (blue-800) - Hover states, headers.
- **Primary Light:** `#DBEAFE` (blue-100) - Backgrounds, accents.

### Secondary Colors (Functional)
- **Success:** `#16A34A` (green-600) - Completed, Verified, Active.
- **Warning:** `#CA8A04` (yellow-600) - Pending, Review, Expiring Soon.
- **Danger:** `#DC2626` (red-600) - Error, Delete, Blocked, Overdue.
- **Info:** `#0EA5E9` (sky-500) - Information, Tips.

### Neutral Colors
- **Text Primary:** `#1F2937` (gray-800) - Headings, Body text.
- **Text Secondary:** `#6B7280` (gray-500) - Labels, Hints.
- **Border:** `#E5E7EB` (gray-200) - Dividers, Inputs.
- **Background:** `#F3F4F6` (gray-100) - Page background.
- **Surface:** `#FFFFFF` (white) - Cards, Modals.

---

## 🔤 Typography

**Font Family:** 'Inter', sans-serif

### Scale
- **H1 (Page Title):** `text-3xl font-bold text-gray-900`
- **H2 (Section Title):** `text-xl font-semibold text-gray-800`
- **H3 (Card Title):** `text-lg font-medium text-gray-900`
- **Body:** `text-base text-gray-600`
- **Small:** `text-sm text-gray-500`
- **Tiny:** `text-xs text-gray-400`

---

## 🧩 Components

### 1. Buttons

**Primary Button:**
```html
<button class="bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded shadow-sm transition-colors">
  Create RFQ
</button>
```

**Secondary Button:**
```html
<button class="bg-white border border-gray-300 text-gray-700 hover:bg-gray-50 font-medium py-2 px-4 rounded shadow-sm transition-colors">
  Cancel
</button>
```

**Danger Button:**
```html
<button class="bg-red-600 hover:bg-red-700 text-white font-semibold py-2 px-4 rounded shadow-sm transition-colors">
  Delete
</button>
```

### 2. Cards

```html
<div class="bg-white rounded-lg shadow p-6 border border-gray-100">
  <h3 class="text-lg font-medium text-gray-900 mb-2">Card Title</h3>
  <p class="text-gray-600">Card content goes here...</p>
</div>
```

### 3. Badges (Status)

```html
<!-- Success -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
  Active
</span>

<!-- Warning -->
<span class="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-yellow-100 text-yellow-800">
  Pending
</span>
```

### 4. Form Inputs

```html
<div>
  <label class="block text-sm font-medium text-gray-700 mb-1">Email Address</label>
  <input type="email" class="w-full rounded-md border-gray-300 shadow-sm focus:border-blue-500 focus:ring-blue-500 sm:text-sm" placeholder="you@example.com">
</div>
```

---

## 📱 Layouts

### Dashboard Layout (Desktop)
- **Sidebar:** Fixed left, width 64 (16rem), dark blue bg (`bg-slate-900`).
- **Header:** Fixed top, height 16 (4rem), white bg, shadow-sm.
- **Main Content:** `ml-64 mt-16 p-8`.

### Mobile Layout
- **Header:** Fixed top, hamburger menu.
- **Sidebar:** Off-canvas drawer (slide-over).
- **Content:** `p-4`.

---

## ♿ Accessibility

- **Contrast:** Ensure text meets WCAG AA standards (4.5:1).
- **Focus States:** Visible focus rings on all interactive elements (`focus:ring-2`).
- **Semantic HTML:** Use `<button>`, `<nav>`, `<main>`, etc.
- **ARIA:** Use `aria-label` for icon-only buttons.

---

**Documentation Complete!** 🎉
