# Onboarding — As-Built Reference

## Movello Web Frontend (React 18.3 + Vite + TanStack Query + Zustand)

**Last verified against code: 2026-07-23**

> **Reframing note:** This file was originally written as a from-scratch *build guide* (the kind fed to an AI scaffolding tool such as Lovable), including illustrative code for wizards that didn't exist yet. Both onboarding wizards have since been built, plus an admin-initiated variant the original guide never anticipated at all. This version documents **what actually exists in code today**, verified against `marketplace-project-implementation/movello-marketplace-core/src/features/onboarding/**`, `src/features/admin/pages/verifications/onboarding/**`, and the route table in `src/App.tsx`.

| Route | Component | Who |
|---|---|---|
| `/business/onboarding` | `BusinessOnboarding.tsx` | Self-service, business role |
| `/provider/onboarding` | `ProviderOnboarding.tsx` | Self-service, provider role |
| `/admin/verifications/businesses/create` | `AdminBusinessOnboarding.tsx` | Admin, on behalf of a business |
| `/admin/verifications/providers/create` | `AdminProviderOnboarding.tsx` | Admin, on behalf of a provider |

Both self-service wizards are reached only after registration/email-phone verification (see `AUTHENTICATION_GUIDE.md`) and are route-guarded by role. **Neither wizard includes vehicle registration as a step** — that is the single largest correction to the original guide, which built a 4th "Register Vehicles" step into provider onboarding. Vehicle registration is a fully separate, later flow under Fleet Management (`/provider/fleet/add`, see `PROVIDER_PORTAL_GUIDE.md` §3); a provider can complete onboarding and reach their dashboard with zero vehicles.

---

## Table of Contents

1. [Business Onboarding Wizard](#1-business-onboarding-wizard)
2. [Provider Onboarding Wizard](#2-provider-onboarding-wizard)
3. [Document Upload — Dynamic, Not Hardcoded](#3-document-upload--dynamic-not-hardcoded)
4. [Admin-Initiated Onboarding](#4-admin-initiated-onboarding)
5. [Draft Persistence & Resume Behavior](#5-draft-persistence--resume-behavior)
6. [Divergences From the Original Guide](#6-divergences-from-the-original-guide)

---

## 1. Business Onboarding Wizard

**Route:** `/business/onboarding` · **Component:** `src/features/onboarding/pages/business-onboarding/BusinessOnboarding.tsx`, composing `BusinessStep1.tsx` (Company Info), `BusinessStep3.tsx` (Contact & Address), `BusinessStep2.tsx` (Documents), `BusinessStep4.tsx` (Review & Submit).

It is a real **4-step wizard**, matching the original guide's step count, but note the component files are numbered by *content*, not by *wizard position* — the `STEPS` array order is Business Info → Contact & Address → Documents → Review, which renders `BusinessStep1` → `BusinessStep3` → `BusinessStep2` → `BusinessStep4` in that order. Don't assume `BusinessStep2.tsx` is the second screen shown.

**Step 1 — Company Information** (`BusinessStep1.tsx`):
- `businessName` (min 3 chars)
- `businessType` (dropdown, sourced from `lookupService.getBusinessTypes()` — **not hardcoded to PLC/NGO/GOV** the way the original guide assumed; it renders whatever the master-data lookup returns)
- `tinNumber` (exactly 10 digits, numeric)
- `licenseNumber` (optional)
- `registrationNumber` (optional)
- `industry` (optional dropdown, from `lookupService.getIndustries()`)
- `employeeCount` (optional dropdown: 1-10 / 11-50 / 51-200 / 201-500 / 500+)

Note: **no async TIN-uniqueness check exists in this form's zod schema** — the original guide had one; the real client-side validation is just length/format, and there is no live `checkTINExists` style refinement wired into the resolver.

**Step 2 — Contact & Address** (`BusinessStep3.tsx`): contact person full name/email/phone/position, plus address (city — from `lookupService.getCities()` — subcity, woreda, street, house number). Saved via `businessOnboardingService.updateContactPerson` + `updateBusiness`, then `updateOnboardingStep(businessId, 2)`.

**Step 3 — Documents** (`BusinessStep2.tsx`): dynamic, see §3.

**Step 4 — Review & Submit** (`BusinessStep4.tsx`): read-only summary of everything entered (business info, contact, address, document count), a **Submit** action that calls `updateOnboardingStep(businessId, 4)` then `completeOnboarding(businessId)`, and navigates to `/business/dashboard` on success with a "pending verification" toast. There is no separate "Verification Pending" page/route in the real app the way the original guide built one — the pending-verification messaging is a toast plus whatever the dashboard itself shows for an unverified account (see `mapAccountStatus`/account-status banner pattern used on both portal dashboards).

---

## 2. Provider Onboarding Wizard

**Route:** `/provider/onboarding` · **Component:** `ProviderOnboarding.tsx`, composing `ProviderTypeStep.tsx` → `ProviderStep1.tsx` (Provider Info) → `ProviderStep3.tsx` (Contact & Address) → `ProviderStep2.tsx` (Documents).

Also a real **4-step wizard**, again with component files numbered by content rather than position. **Unlike the business wizard, there is no separate Review step** — the 4th and final step (`ProviderStep2.tsx`, Documents) uploads documents and immediately calls `updateOnboardingStep` + `completeOnboarding` in the same mutation, navigating straight to `/provider/dashboard`. Don't design around a review/confirmation screen for providers; it doesn't exist.

**Step 1 — Provider Type** (`ProviderTypeStep.tsx`): three options — **`INDIVIDUAL`** (1–5 vehicles), **`AGENCY`** (6–20 vehicles), **`COMPANY`** (20+ vehicles). **Correction to the original guide: the middle tier's code value is `AGENCY`, not `AGENT`.** This selection just sets local state and advances — it isn't persisted to the backend until Step 2 submits.

**Step 2 — Provider Info** (`ProviderStep1.tsx`, real zod schema):
- `providerType` (carried over from Step 1)
- `name` (min 2 chars)
- `tinNumber` — **required for every provider type, 10 digits.** This directly contradicts the original guide's "optional for Individual, required for Company" rule; the real `superRefine` requires a valid 10-digit TIN regardless of `providerType`.
- `nationalId` (max 20 chars) — **required specifically when `providerType === 'INDIVIDUAL'`**, a conditional requirement the original guide didn't have at all.
- `licenseNumber`, `registrationNumber` — optional for all types.

**Step 3 — Contact & Address** (`ProviderStep3.tsx`): service areas, contact person, address — structurally similar to the business wizard's equivalent step, saved via `providerOnboardingService.updateProvider({ serviceAreas, contactPerson, address })`.

**Step 4 — Documents** (`ProviderStep2.tsx`): dynamic per provider type, see §3; on submit, uploads then completes onboarding in one mutation (no intermediate review).

---

## 3. Document Upload — Dynamic, Not Hardcoded

Both wizards' document steps get their required/optional document list from **`lookupService.getKYCRequirements(entityType)`** (`'BUSINESS'` for the business wizard; the selected `providerType` string for the provider wizard) — this matches the original guide's stated intent ("must be fetched from master data, not hardcoded"), and the original guide's fallback `REQUIRED_DOCUMENTS` hardcoded arrays (Business License / TIN Certificate / Articles of Association / ID of Representative) should be treated as illustrative only, not as the real document set — the real set is whatever an admin has configured via `ADMIN_PORTAL_GUIDE.md` §4's KYC-requirements/document-types master data, and can change without a frontend deploy.

Each requirement renders through a shared `DocumentUpload` component (`src/shared/components/onboarding`), split into **Required Documents** and **Optional Documents** sections, with per-file max size and allowed MIME types coming from the requirement record (defaulting to 5MB / PDF+JPEG+PNG if unset). Uploads report progress per document type via a callback threaded up into the wizard's `uploadProgress` state. The business wizard additionally resumes previously-uploaded documents on redraft (`existingDocumentsByType`, matched by document-type code or requirement ID) so a business doesn't have to re-upload after navigating away mid-flow.

---

## 4. Admin-Initiated Onboarding

**Entirely absent from the original guide.** A real, fully-built feature flagged as undocumented in the coverage audit.

| Route | Component |
|---|---|
| `/admin/verifications/businesses/create` | `AdminBusinessOnboarding.tsx` (+ `AdminBusinessPreStep.tsx`, `AdminBusinessStep1-4.tsx`) |
| `/admin/verifications/providers/create` | `AdminProviderOnboarding.tsx` (+ equivalent pre-step/steps) |

Both mirror their self-service counterparts' step sequence (Business/Provider Info → Contact & Address → Documents → Review) but insert a **pre-step** first: `AdminBusinessPreStep.tsx` collects the account credentials themselves (email, password, first/last name, phone number, preferred language) so the admin can create the login **and** the business/provider profile in one flow, on behalf of someone who isn't self-registering. If the admin opens the page with a `?businessId=` (or `?providerId=`) query param already set, the pre-step is skipped entirely and the wizard resumes an existing in-progress draft instead of creating a new account — the same component serves both "create from scratch" and "resume an admin-started draft" cases.

---

## 5. Draft Persistence & Resume Behavior

Both self-service wizards check for an existing in-progress record on mount (`getBusinessByUserId`/`getProviderByUserId`) and, if found, **resume at `currentStep + 1`** (capped at the last step) rather than restarting — each step's save mutation calls `updateOnboardingStep(id, N)` to persist progress server-side, so refreshing the browser or logging back in later resumes correctly, backed by the database rather than `localStorage` the way the original guide's RFQ-wizard-style draft persistence worked. A toast ("Resuming from your previous progress") confirms this to the user. This is a materially more robust resume model than the original guide assumed.

---

## 6. Divergences From the Original Guide

- **No vehicle-registration step in provider onboarding.** Vehicle registration is entirely separate, later, under Fleet Management — see `PROVIDER_PORTAL_GUIDE.md` §3. A provider reaches their dashboard with zero vehicles if they choose to.
- **Provider type codes are `INDIVIDUAL` / `AGENCY` / `COMPANY`** — the middle one is `AGENCY`, not `AGENT`.
- **TIN is required for every provider type**, not just Company; `nationalId` is required specifically for `INDIVIDUAL`.
- **No async TIN-uniqueness check** in the business wizard's client-side schema.
- **Provider onboarding has no separate Review step** — Documents is the final step and submits directly. Business onboarding does have a Review step.
- **No dedicated "Verification Pending" route** — completion is a toast + dashboard account-status banner, not a standalone page.
- **Document requirements are genuinely dynamic** (admin-configured master data), consistent with the original guide's stated intent but with a materially different fallback document set than the original guide's hardcoded list.
- **Admin-initiated onboarding (§4)** is a whole additional entry point, with its own account-creation pre-step, absent from the original guide entirely.
- **Draft resume is server-persisted** (`currentStep` column, resumed via API), not `localStorage`-only.

For the epic-level status of onboarding across all four platform surfaces (web, both mobile apps, backend), see `project-docs/18_Implementation_Coverage_Audit.md` §2 (epics 01–02) — note in particular that admin-initiated onboarding and the OTP-gated bank-account-change flow are both called out there as undocumented-in-epic features that this doc now covers for the web surface.
