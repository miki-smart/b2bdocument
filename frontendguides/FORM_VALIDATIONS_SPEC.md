# Form Validations Specification

## Anqelba Car Rental Frontend - React Implementation

**Version:** 2.0
**Validation Library:** Zod 3.25
**Form Library:** React Hook Form 7.61 (+ `@hookform/resolvers/zod`)
**Last verified against code: 2026-07-23** — full rewrite. The v1.0 spec's core library choice (Zod + RHF) was correct, but several concrete schemas (async TIN/plate/email uniqueness via `refine()`, a 50-vehicle single-vehicle-type RFQ model, a combined multi-file `z.instanceof(File)` object for vehicle photos) do not match what's actually implemented. This version was checked against the real schema code under `src/features/*/pages/**` and `src/shared/lib/validation.ts`.
**Related:** [API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md), [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md)

---

## Table of Contents

1. [Validation Setup](#validation-setup)
2. [Authentication Validations](#authentication-validations)
3. [Business Onboarding Validations](#business-onboarding-validations)
4. [Provider Onboarding Validations](#provider-onboarding-validations)
5. [RFQ Validations (Real Worked Example)](#rfq-validations-real-worked-example)
6. [Bid Validations](#bid-validations)
7. [Vehicle Validations](#vehicle-validations)
8. [Wallet Forms — No Zod Schema Today](#wallet-forms--no-zod-schema-today)
9. [Shared Validation Helpers](#shared-validation-helpers)
10. [Async / Server-Side Uniqueness Checks](#async--server-side-uniqueness-checks)
11. [Error Display Pattern](#error-display-pattern)
12. [Validation Best Practices](#validation-best-practices)

---

## Validation Setup

**There are no standalone `.schema.ts` files in this codebase.** Zod schemas are defined **inline, at the top of the page/component file that uses them** (e.g. `const loginSchema = z.object({...})` at the top of `LoginPage.tsx`), not imported from a separate schema module. This is a real, consistent pattern across `src/features/` — not an oversight to "fix" by extracting schemas; follow it for new forms unless a schema is genuinely reused across multiple components.

**Standard pattern** (real, e.g. `src/features/auth/pages/login/LoginPage.tsx`):

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

const mySchema = z.object({
  // fields
}).refine((data) => /* cross-field rule */, { message: '...', path: ['fieldName'] });

type MyFormValues = z.infer<typeof mySchema>;

export const MyForm = () => {
  const { register, handleSubmit, formState: { errors }, control } = useForm<MyFormValues>({
    resolver: zodResolver(mySchema),
    defaultValues: { /* ... */ },
  });

  return <form onSubmit={handleSubmit(onSubmit)}>{/* fields */}</form>;
};
```

Two RHF wiring styles both appear in the real codebase, depending on whether the field is a native input or a custom/controlled component:

- **`register()`** for plain inputs/textareas (`{...register('email')}`) — used throughout `LoginPage.tsx`, `RegisterPage.tsx`, `RFQCreateStep2.tsx`'s text fields.
- **`Controller`** for custom components that don't expose a native `ref`/`onChange` signature RHF can `register()` directly (shadcn `Select`, `DatePicker`, custom `ValidatedInput` wrappers used inside `Controller` render props) — used throughout the onboarding wizards (`BusinessStep1.tsx`, `ProviderStep1.tsx`).

There is no third pattern — no manual `setError()` loops, no inline `validate` callback functions bypassing Zod. Every form gets a `zodResolver(schema)`; this is a hard convention (`.agent/roles/frontend-developer.md` §Non-Negotiables #3).

---

## Authentication Validations

Real schemas, verbatim from the pages that use them (see [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md) for the full flow each belongs to).

### Login (`src/features/auth/pages/login/LoginPage.tsx`)

```typescript
const loginSchema = z.object({
  email: z.string().email('Please enter a valid email address'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  rememberMe: z.boolean().optional(),
});
```

### Registration (`src/features/auth/pages/register/RegisterPage.tsx`)

```typescript
// Ethiopian phone: +251 then mobile (9 + 8 digits) or landline (11 + 7 digits)
const ethiopianPhoneRegex = /^\+251(9\d{8}|11\d{7})$/;

const registerSchema = z.object({
  firstName: z.string().trim().min(2, 'First name must be at least 2 characters').max(50),
  lastName: z.string().trim().min(2, 'Last name must be at least 2 characters').max(50),
  email: z.string().trim().email('Please enter a valid email address').max(255),
  phoneNumber: z.string().trim().regex(ethiopianPhoneRegex, 'Phone must be Ethiopian format: +2519XXXXXXXX'),
  companyName: z.string().trim().min(2, 'Company name must be at least 2 characters').max(100),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[0-9]/, 'Password must contain at least one number')
    .regex(/[!@#$%^&*(),.?":{}|<>]/, 'Password must contain at least one special character'),
  confirmPassword: z.string(),
  acceptTerms: z.boolean().refine((val) => val === true, { message: 'You must accept the terms and conditions' }),
}).refine((data) => data.password === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});
```

**Important divergence from a naive "validate everything client-side" assumption:** there is **no async email-uniqueness `.refine()`** here. Duplicate emails are caught server-side (`409` from `POST /web/register`) and surfaced as a toast/form-level error after submit — see [Async / Server-Side Uniqueness Checks](#async--server-side-uniqueness-checks).

### Forgot Password (OTP-based, 3-step — `src/features/auth/pages/forgot-password/ForgotPasswordPage.tsx`)

```typescript
const forgotPasswordSchema = z.object({
  email: z.string().trim().email('Please enter a valid email address').max(255),
});

const resetPasswordSchema = z.object({
  newPassword: z.string().min(8, 'Password must be at least 8 characters'),
  confirmPassword: z.string(),
}).refine((data) => data.newPassword === data.confirmPassword, {
  message: 'Passwords do not match',
  path: ['confirmPassword'],
});
```

The OTP code itself (6 digits, `InputOTP` component) is **not** Zod-validated as a form field — it's tracked as local component state and sent directly to `authService.verifyResetOtp()`, since the "form" for that step is just the OTP input plus a resend-cooldown timer, not a schema-driven multi-field form.

---

## Business Onboarding Validations

### Step 1 — Business Details (`src/features/onboarding/pages/business-onboarding/BusinessStep1.tsx`, real, in full)

```typescript
const step1Schema = z.object({
  businessName: z.string().min(3, 'Business name must be at least 3 characters'),
  businessType: z.string().min(1, 'Please select a business type'),
  tinNumber: z.string()
    .length(10, 'TIN must be exactly 10 digits')
    .regex(/^[0-9]{10}$/, 'TIN must contain only numbers'),
  licenseNumber: z.string().optional(),
  registrationNumber: z.string().optional(),
  industry: z.string().optional(),
  employeeCount: z.string().optional(),
});
```

Note: **no async TIN-uniqueness `.refine()`** — TIN format is validated client-side only; a duplicate TIN is a server-side rejection surfaced after submit, exactly like the email-uniqueness case above. Do not add a `checkTINExists()`-style async refine to this schema without confirming the backend actually exposes a check-TIN endpoint first (it does not, as of this writing).

Document upload (business license, TIN certificate, etc.) in Step 3 goes through the `FileUpload` component (`src/shared/components/forms/FileUpload.tsx`) with file-count/type/size constraints enforced by that component's own props, not by a `z.instanceof(File)` Zod schema — Zod in this codebase validates text/date/select fields, not file objects.

---

## Provider Onboarding Validations

### Step 1 — Provider Type & Identity (`src/features/onboarding/pages/provider-onboarding/ProviderStep1.tsx`, real, in full)

```typescript
const step1Schema = z.object({
  providerType: z.enum(['INDIVIDUAL', 'AGENCY', 'COMPANY']),   // NOTE: 'AGENCY', not 'AGENT'
  name: z.string().min(2, 'Name is required'),
  tinNumber: z.string().optional(),
  licenseNumber: z.string().optional(),
  nationalId: z.string().max(20, 'National ID cannot exceed 20 characters').optional(),
  registrationNumber: z.string().optional(),
}).superRefine((data, ctx) => {
  // TIN is required for ALL provider types (not just COMPANY) — checked in superRefine
  // rather than a base z.string() constraint because it's conditionally validated
  // together with a second field below.
  if (!data.tinNumber || data.tinNumber.length !== 10) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'TIN is required (10 digits)', path: ['tinNumber'] });
  }
  if (data.providerType === 'INDIVIDUAL' && !data.nationalId) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'National ID is required', path: ['nationalId'] });
  }
});
```

Two corrections against a plausible-but-wrong assumption:

1. **TIN is required for every provider type**, not just `COMPANY` — the real rule is stricter than "companies need a TIN, individuals don't."
2. **The enum is `'INDIVIDUAL' | 'AGENCY' | 'COMPANY'`** — `'AGENCY'`, not `'AGENT'`. Getting this wrong breaks the `z.enum` type check silently at the TypeScript level in a way that's easy to miss in review.

`superRefine` (not chained `.refine()`) is the real tool used here because it needs to add issues to two different, conditionally-required fields (`tinNumber` unconditionally, `nationalId` conditionally) in one pass — reach for `superRefine` over multiple `.refine()` calls when validation rules interact across more than one field pair.

---

## RFQ Validations (Real Worked Example)

This is the most fully-specified real validation flow in the app and a good template for any future multi-line-item form. Real code, `src/features/business/pages/rfq/create/RFQCreateStep2.tsx`, in full:

```typescript
const SHORT_TERM_MAX_DAYS = 30;

// Matches backend's Math.Ceiling((RequiredTo - RequiredFrom).TotalDays) exactly —
// the frontend and backend must agree on duration math or the client will accept
// values the server then rejects.
const calculateDurationDays = (from: Date, to: Date): number =>
  Math.ceil((to.getTime() - from.getTime()) / (1000 * 60 * 60 * 24));

const lineItemSchema = z.object({
  id: z.string().optional(),                 // present when editing an existing line item
  vehicleType: z.string().min(1, 'Vehicle type is required'),
  quantity: z.coerce.number()
    .min(1, 'Minimum quantity is 1')
    .max(50, 'Maximum quantity is 50'),        // per-line-item cap
  term: z.enum(['SHORT_TERM', 'LONG_TERM'], {
    required_error: 'Term is required',
    invalid_type_error: 'Term must be SHORT_TERM or LONG_TERM',
  }),
  purpose: z.string().min(1, 'Purpose is required').max(500, 'Purpose must be less than 500 characters'),
  fuelType: z.string().nullable().optional(), // null = "no preference", not "unset"
  requiredFrom: z.date({ required_error: 'Start date is required' }),
  requiredTo: z.date({ required_error: 'End date is required' }),
  pickupLocation: z.string().optional().or(z.literal('')),
  dropoffLocation: z.string().optional().or(z.literal('')),
  specifications: z.string().max(200, 'Maximum 200 characters').optional().or(z.literal('')),
})
  .refine((data) => isBefore(data.requiredFrom, data.requiredTo), {
    message: 'End date must be after start date',
    path: ['requiredTo'],
  })
  .refine(
    (data) => {
      // The concrete business rule this whole schema exists to enforce: SHORT_TERM
      // rentals are capped at 30 days. Selecting LONG_TERM lifts the cap entirely.
      if (data.term === 'SHORT_TERM') {
        return calculateDurationDays(data.requiredFrom, data.requiredTo) <= SHORT_TERM_MAX_DAYS;
      }
      return true;
    },
    {
      message: `Short-term rentals must not exceed ${SHORT_TERM_MAX_DAYS} days. Please select Long-term for rentals over ${SHORT_TERM_MAX_DAYS} days.`,
      path: ['requiredTo'],
    }
  );

const step2Schema = z.object({
  lineItems: z.array(lineItemSchema)
    .min(1, 'At least one line item is required')
    .max(10, 'Maximum 10 line items allowed'),   // cap on number of distinct line items per RFQ
}).refine(
  (data) => {
    const totalVehicles = data.lineItems.reduce((sum, item) => sum + (item.quantity || 0), 0);
    return totalVehicles <= 50;                   // cap on TOTAL vehicles across ALL line items
  },
  { message: 'Total vehicles cannot exceed 50', path: ['lineItems'] }
);

export type LineItemData = z.infer<typeof lineItemSchema>;
export type Step2Data = z.infer<typeof step2Schema>;
```

**The three caps this schema enforces, and why each exists:**

| Cap | Value | Enforced by |
|---|---|---|
| Quantity per line item | 1–50 | `lineItemSchema.quantity` |
| Line items per RFQ | 1–10 | `step2Schema.lineItems` array bounds |
| Total vehicles across all line items | ≤ 50 | `step2Schema`'s top-level `.refine()` |
| SHORT_TERM duration | ≤ 30 days | `lineItemSchema`'s second `.refine()`, using the same `Math.ceil` duration formula the backend uses |

**UX detail worth preserving in any similar form:** when a user switches an existing line item's `term` from `LONG_TERM` to `SHORT_TERM` and the current date range already exceeds 30 days, the component **auto-clamps** `requiredTo` to `requiredFrom + 30 days` (via `form.setValue(..., { shouldValidate: true })`) rather than just showing a validation error and leaving the user to fix it manually:

```typescript
if (newTerm === 'SHORT_TERM') {
  const currentDuration = calculateDurationDays(startDate, endDate);
  if (currentDuration > SHORT_TERM_MAX_DAYS) {
    form.setValue(`lineItems.${index}.requiredTo`, addDays(startDate, SHORT_TERM_MAX_DAYS), { shouldValidate: true });
  }
}
```

The `DatePicker` for `requiredTo` also sets `maxDate` dynamically to `requiredFrom + 30 days` whenever `term === 'SHORT_TERM'` — the schema `.refine()` is the source of truth (and what actually blocks submission), but the UI additionally prevents the invalid state from being reachable in the first place. Prefer this two-layer pattern (schema refine + UI constraint) for any hard numeric/date business cap.

`useFieldArray` (RHF) drives the repeatable line-item rows; `min(1)`/`max(10)` on the array is enforced by Zod at submit time, while the "Add Line Item" button is separately disabled in the UI once `fields.length >= 10` — again, both a hard schema check and a soft UI affordance.

---

## Bid Validations

Real schema, `src/features/provider/pages/marketplace/pages/BidSubmissionPage.tsx`:

```typescript
const bidSchema = z.object({
  quantity: z.number().min(1, 'Quantity must be at least 1'),
  unitPrice: z.number().min(1, 'Unit price must be greater than 0'),
  notes: z.string().optional(),
  termsAccepted: z.literal(true, {
    errorMap: () => ({ message: 'You must accept the terms and conditions' }),
  }),
});
```

Notably **simpler** than a "price floor/ceiling per vehicle type" model — there is no async market-price-range `.refine()` here (the market-price feature is explicitly disabled for MVP; `rfqService.getMarketPrice()` throws `'Market price feature disabled for MVP'` by design, not by omission). The `quantity <= lineItem.quantityRequired` check is enforced by the UI (input `max` bound to the line item's remaining quantity) and re-validated server-side, not by a Zod `.refine()` reaching into fetched line-item data. `termsAccepted: z.literal(true, ...)` is the idiomatic Zod way to force a checkbox to be checked — prefer this over `z.boolean().refine(v => v === true)` for a plain required-checkbox field (both work; `z.literal(true)` is the pattern actually used here).

---

## Vehicle Validations

Real schema, `src/features/provider/pages/fleet/pages/AddVehiclePage.tsx` — split across two schemas for two wizard tabs, notably simpler than a single mega-schema:

```typescript
const vehicleInfoSchema = z.object({
  plateNumber: z.string().min(1, 'Plate number is required'),
  make: z.string().min(2, 'Make is required'),
  model: z.string().min(2, 'Model is required'),
  year: z.number().min(2000, 'Year must be 2000 or later').max(new Date().getFullYear() + 1),
  color: z.string().min(2, 'Color is required'),
  vehicleType: z.string().min(1, 'Vehicle type is required'),
  fuelType: z.string().min(1, 'Fuel type is required'),
  capacity: z.number().min(1, 'Must be at least 1').max(100, 'Maximum capacity is 100 seats'),
  vin: z.string().optional(),
});

const insuranceSchema = z.object({
  policyNumber: z.string().min(5, 'Policy number is required'),
  insuranceCompany: z.string().min(2, 'Insurance company is required'),
  insuranceExpiry: z.date().min(new Date(), 'Must be a future date'),
  coverageType: z.string().min(1, 'Coverage type is required'),
  coverageAmount: z.number().optional(),
  startDate: z.date(),
});
```

**Corrections against a plausible-but-wrong assumption:**

- **No plate-number regex.** `plateNumber` is just `.min(1)` — there is no `^[A-Z]{2}-[0-9]{5}$`-style format enforced by Zod, and no async plate-uniqueness `.refine()`.
- **No `insuranceExpiry` "valid for 30+ more days" rule.** The only date rule is `insuranceExpiry >= today` — there is no additional "must still be valid 30 days from now" minimum-validity window in the schema.
- **Vehicle photos are not part of either Zod schema at all.** Photo capture (front/back/left/right/interior — five required angles, `PHOTO_ANGLES` array) is handled entirely by the `FileUpload` component and local `useState<Record<PhotoKey, UploadedFile[]>>`, outside `react-hook-form`/Zod. If you need file-level validation (size/type), it lives in the `FileUpload` component's own props/logic, not in a `z.instanceof(File)` schema field — this codebase does not validate `File` objects through Zod anywhere found in the current tree.
- **Required documents** (`REQUIRED_DOCUMENTS`: vehicle registration/"Libre", insurance policy, Bolo/plate certificate) are tracked as a checklist against uploaded document codes, again outside the Zod schema.

---

## Wallet Forms — No Zod Schema Today

Unlike RFQ/bid/vehicle/onboarding forms, **no deposit or withdrawal form in the current codebase uses a Zod schema** — a repo-wide search for `z.object` combined with an `amount` field turns up only `AddVehiclePage.tsx` (insurance coverage amount) and `BidSubmissionPage.tsx` (unit price), neither of which is a wallet form. Deposit/withdrawal amount inputs are validated with plain component-level logic (min-amount checks, `disabled` submit buttons) rather than `useForm` + `zodResolver`. **Do not assume** a `depositSchema`/`withdrawalSchema` exists to import — if you're building a new wallet form, this is a gap worth closing with a proper Zod schema (following the patterns above), not an existing convention to copy verbatim.

---

## Shared Validation Helpers

`src/shared/lib/validation.ts` — plain regex/helper functions used *alongside* Zod (some schemas call these regexes directly inside a `.regex()`; others just reuse the same pattern inline), not a validation framework of their own:

```typescript
export const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const phoneRegex = /^\+251[0-9]{9}$/;        // simple form — note RegisterPage.tsx uses a
                                                      // stricter variant distinguishing mobile/landline
export const tinRegex = /^[0-9]{10}$/;
export const nationalIdRegex = /^[A-Z0-9]{8,16}$/;

export const passwordRequirements = {
  minLength: 8,
  hasUppercase: /[A-Z]/,
  hasLowercase: /[a-z]/,
  hasNumber: /[0-9]/,
  hasSpecial: /[^A-Za-z0-9]/,
};

export const validatePassword = (password: string): { valid: boolean; errors: string[] } => { /* ... */ };

export const isValidFileSize = (file: File, maxSizeMB: number = 5): boolean =>
  file.size <= maxSizeMB * 1024 * 1024;
export const isValidFileType = (file: File, allowedTypes: string[]): boolean =>
  allowedTypes.includes(file.type);

export const FILE_TYPES = {
  IMAGES: ['image/jpeg', 'image/png', 'image/gif', 'image/webp'],
  DOCUMENTS: ['application/pdf'],
  ALL_DOCS: ['application/pdf', 'image/jpeg', 'image/png'],
} as const;
```

Note the `phoneRegex` inconsistency that exists in real code today: `validation.ts`'s `phoneRegex` (`+251` + any 9 digits) is looser than `RegisterPage.tsx`'s inline `ethiopianPhoneRegex` (`+251` + mobile-`9`-prefix-8-digits OR landline-`11`-prefix-7-digits). Both are real, both are in active use in different forms — this is a genuine, unreconciled inconsistency, not a documentation error on one side. If you're adding Ethiopian phone validation to a new form, prefer the stricter `ethiopianPhoneRegex` pattern from `RegisterPage.tsx` and consider raising the inconsistency for cleanup rather than silently picking whichever regex is closest at hand.

---

## Async / Server-Side Uniqueness Checks

**This is the single biggest correction from v1.0:** there are **no async Zod `.refine()` calls anywhere in the current codebase** — no `checkTINExists()`, `checkEmailExists()`, or `checkPlateExists()` helper functions exist, and no schema calls `apiClient` from inside a `.refine()`. Every uniqueness constraint (email, TIN, plate number) is:

1. Validated client-side for **format only** (regex/length), via the synchronous Zod rules shown above.
2. Enforced server-side, and surfaced to the user as an error **after form submission**, via the normal mutation `onError`/`catch` path described in [API_INTEGRATION_SPEC.md § Error Handling in Components](./API_INTEGRATION_SPEC.md#error-handling-in-components) — e.g. `authService.register()` translates a `409` into `{ code: 'EMAIL_ALREADY_EXISTS' }` for the caller to display via `toast.error(...)`.

If a future form genuinely needs live "is this TIN already taken?" feedback before submit, that would be new work (a debounced `onBlur` check calling a real backend endpoint, wired through `.refine()` with `async`), not a pattern to copy from existing code — there is nothing in the current codebase to model it on.

---

## Error Display Pattern

**File:** `src/shared/components/forms/FormField.tsx` (real, in full):

```typescript
export interface FormFieldProps {
  label?: string;
  error?: string;
  required?: boolean;
  helpText?: string;
  children: React.ReactNode;
  className?: string;
  htmlFor?: string;
}

export const FormField = React.forwardRef<HTMLDivElement, FormFieldProps>(
  ({ label, error, required, helpText, children, className, htmlFor }, ref) => (
    <div ref={ref} className={cn('space-y-2', className)}>
      {label && (
        <Label htmlFor={htmlFor} className={cn('text-sm font-medium text-foreground', error && 'text-destructive')}>
          {label}{required && <span className="text-destructive ml-1">*</span>}
        </Label>
      )}
      {children}
      {helpText && !error && <p className="text-xs text-muted-foreground">{helpText}</p>}
      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}
    </div>
  )
);
```

Usage — pass `errors.fieldName?.message` straight from RHF's `formState.errors` as the `error` prop, one `FormField` per input:

```tsx
<FormField label="Business Name" required error={errors.businessName?.message}>
  <ValidatedInput placeholder="Enter your business name" {...register('businessName')} />
</FormField>
```

Note the prop is **`helpText`**, not `helperText` — and there is no `AlertCircle` icon rendered next to the error message in the real component (just a plain `role="alert"` paragraph styled with the destructive color token). Nested array errors (RFQ line items, etc.) are indexed manually: `errors.lineItems?.[index]?.quantity?.message`.

---

## Validation Best Practices

1. **Inline schemas, not a `schemas/` folder** — define `const xSchema = z.object({...})` at the top of the page that uses it; only extract to a shared file if genuinely reused across ≥2 components.
2. **`zodResolver` on every form, no exceptions** — including admin-only and internal tooling forms.
3. **Match backend date-math exactly for date-range business rules** — see `calculateDurationDays` in the RFQ example; a mismatched rounding rule between frontend and backend produces client-accepted-but-server-rejected submissions.
4. **Pair a hard schema `.refine()` with a soft UI constraint** where a numeric/date cap matters (line-item quantity `max`, `DatePicker`'s `maxDate`) — don't rely on the error message alone to guide the user to a valid value.
5. **`superRefine` over chained `.refine()`** when two or more fields' requiredness depends on each other (see `ProviderStep1`'s TIN/National-ID example) — it's clearer and avoids issue-ordering surprises.
6. **Do not invent async uniqueness checks** — there are none in this codebase today; format-validate client-side, let the server reject duplicates, surface that via the existing mutation-error → toast path.
7. **File validation lives in the upload component, not in Zod** — `FileUpload`'s own props/logic, not `z.instanceof(File)`.
8. **`z.literal(true, { errorMap: ... })`** for required-checkbox fields (terms acceptance), matching the real `bidSchema`/`registerSchema` pattern.
9. **Reuse `src/shared/lib/validation.ts`'s regexes where a stricter inline one isn't already established for that field** — but be aware of the known `phoneRegex` vs. `ethiopianPhoneRegex` inconsistency noted above.
10. **`FormField`'s prop is `helpText`**, its error styling has no icon — don't invent props this component doesn't have.

---

**END OF FORM VALIDATIONS SPEC**

*API/error-handling conventions these forms submit into: [API_INTEGRATION_SPEC.md](./API_INTEGRATION_SPEC.md). Auth-specific schemas in full context: [AUTHENTICATION_GUIDE.md](./AUTHENTICATION_GUIDE.md). Frontend conventions: `.agent/roles/frontend-developer.md`.*
