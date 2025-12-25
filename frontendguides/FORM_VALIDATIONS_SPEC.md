# Form Validations Specification
## Movello Frontend - React Implementation

**Version:** 1.0  
**Validation Library:** Zod  
**Form Library:** React Hook Form  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Validation Setup](#validation-setup)
2. [Authentication Validations](#authentication-validations)
3. [Business Onboarding Validations](#business-onboarding-validations)
4. [Provider Onboarding Validations](#provider-onboarding-validations)
5. [RFQ Validations](#rfq-validations)
6. [Bid Validations](#bid-validations)
7. [Vehicle Validations](#vehicle-validations)
8. [Wallet Validations](#wallet-validations)

---

## 🔧 Validation Setup

### Zod Schema Pattern

```typescript
import { z } from 'zod';

// Base schema
const baseSchema = z.object({
  // fields
});

// Refined schema with custom validations
const refinedSchema = baseSchema.refine(
  (data) => {
    // custom validation logic
    return condition;
  },
  {
    message: 'Error message',
    path: ['fieldName'], // where to show error
  }
);

// Async validation
const asyncSchema = baseSchema.refine(
  async (data) => {
    const exists = await checkUniqueness(data.field);
    return !exists;
  },
  {
    message: 'Field must be unique',
  }
);
```

### React Hook Form Integration

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';

const MyForm = () => {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
    control, // for controlled components
  } = useForm({
    resolver: zodResolver(mySchema),
    defaultValues: {
      // initial values
    },
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      {/* form fields */}
    </form>
  );
};
```

---

## 🔐 Authentication Validations

### Login Schema

```typescript
export const loginSchema = z.object({
  email: z.string()
    .email('Invalid email address')
    .min(1, 'Email is required'),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .min(1, 'Password is required'),
  rememberMe: z.boolean().optional(),
});
```

### Registration Schema

```typescript
export const registerSchema = z.object({
  email: z.string()
    .email('Invalid email address')
    .min(1, 'Email is required'),
  password: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[0-9]/, 'Password must contain at least one number')
    .regex(/[^A-Za-z0-9]/, 'Password must contain at least one special character'),
  confirmPassword: z.string(),
  role: z.enum(['business', 'provider']),
}).refine((data) => data.password === data.confirmPassword, {
  message: "Passwords don't match",
  path: ['confirmPassword'],
});
```

### Change Password Schema

```typescript
export const changePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required'),
  newPassword: z.string()
    .min(8, 'Password must be at least 8 characters')
    .regex(/[A-Z]/, 'Password must contain at least one uppercase letter')
    .regex(/[0-9]/, 'Password must contain at least one number')
    .regex(/[^A-Za-z0-9]/, 'Password must contain at least one special character'),
  confirmPassword: z.string(),
}).refine((data) => data.newPassword === data.confirmPassword, {
  message: "Passwords don't match",
  path: ['confirmPassword'],
});
```

---

## 🏢 Business Onboarding Validations

### Step 1: Business Details

```typescript
export const businessStep1Schema = z.object({
  businessName: z.string()
    .min(3, 'Business name must be at least 3 characters')
    .max(100, 'Business name must be less than 100 characters'),
  businessType: z.enum(['PLC', 'NGO', 'GOV'], {
    errorMap: () => ({ message: 'Please select a business type' }),
  }),
  tinNumber: z.string()
    .length(10, 'TIN must be exactly 10 digits')
    .regex(/^[0-9]{10}$/, 'TIN must contain only numbers')
    .refine(
      async (tin) => {
        const exists = await checkTINExists(tin);
        return !exists;
      },
      {
        message: 'TIN number already registered',
      }
    ),
  registrationNumber: z.string().optional(),
});
```

### Step 2: Contact & Address

```typescript
export const businessStep2Schema = z.object({
  contactPerson: z.object({
    fullName: z.string()
      .min(2, 'Full name must be at least 2 characters')
      .max(100, 'Full name must be less than 100 characters'),
    email: z.string()
      .email('Invalid email address')
      .min(1, 'Email is required'),
    phone: z.string()
      .regex(/^\+251[0-9]{9}$/, 'Phone must be in format +251XXXXXXXXX')
      .min(1, 'Phone is required'),
  }),
  address: z.object({
    city: z.string().min(1, 'City is required'),
    subcity: z.string()
      .min(1, 'Subcity is required')
      .max(100, 'Subcity must be less than 100 characters'),
    woreda: z.string()
      .min(1, 'Woreda is required')
      .max(50, 'Woreda must be less than 50 characters'),
    houseNumber: z.string().optional(),
  }),
});
```

### Step 3: Document Upload

```typescript
export const documentUploadSchema = z.object({
  businessLicense: z.instanceof(File, { message: 'Business license is required' })
    .refine((file) => file.size <= 5 * 1024 * 1024, 'File size must be less than 5MB')
    .refine(
      (file) => ['application/pdf', 'image/jpeg', 'image/png'].includes(file.type),
      'File must be PDF, JPEG, or PNG'
    ),
  tinCertificate: z.instanceof(File, { message: 'TIN certificate is required' })
    .refine((file) => file.size <= 5 * 1024 * 1024, 'File size must be less than 5MB')
    .refine(
      (file) => ['application/pdf', 'image/jpeg', 'image/png'].includes(file.type),
      'File must be PDF, JPEG, or PNG'
    ),
  articlesOfAssociation: z.instanceof(File, { message: 'Articles of association is required' })
    .refine((file) => file.size <= 10 * 1024 * 1024, 'File size must be less than 10MB')
    .refine((file) => file.type === 'application/pdf', 'File must be PDF'),
  representativeId: z.instanceof(File, { message: 'Representative ID is required' })
    .refine((file) => file.size <= 5 * 1024 * 1024, 'File size must be less than 5MB')
    .refine(
      (file) => ['application/pdf', 'image/jpeg', 'image/png'].includes(file.type),
      'File must be PDF, JPEG, or PNG'
    ),
});
```

---

## 🚗 Provider Onboarding Validations

### Step 1: Provider Type

```typescript
export const providerStep1Schema = z.object({
  providerType: z.enum(['INDIVIDUAL', 'AGENT', 'COMPANY'], {
    errorMap: () => ({ message: 'Please select a provider type' }),
  }),
  name: z.string()
    .min(2, 'Name must be at least 2 characters')
    .max(100, 'Name must be less than 100 characters'),
  tinNumber: z.string()
    .length(10, 'TIN must be exactly 10 digits')
    .regex(/^[0-9]{10}$/, 'TIN must contain only numbers')
    .optional()
    .refine(
      async (data, ctx) => {
        if (data.providerType === 'COMPANY' && !data.tinNumber) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            message: 'TIN is required for companies',
            path: ['tinNumber'],
          });
          return false;
        }
        if (data.tinNumber) {
          const exists = await checkTINExists(data.tinNumber);
          if (exists) {
            ctx.addIssue({
              code: z.ZodIssueCode.custom,
              message: 'TIN number already registered',
              path: ['tinNumber'],
            });
            return false;
          }
        }
        return true;
      }
    ),
});
```

---

## 📝 RFQ Validations

### Create RFQ Schema

```typescript
export const createRFQSchema = z.object({
  title: z.string()
    .min(5, 'Title must be at least 5 characters')
    .max(200, 'Title must be less than 200 characters'),
  description: z.string()
    .max(2000, 'Description must be less than 2000 characters')
    .optional(),
  startDate: z.date()
    .refine(
      (date) => isAfter(date, addDays(new Date(), 3)),
      {
        message: 'Start date must be at least 3 days from now',
      }
    ),
  endDate: z.date(),
  bidDeadline: z.date(),
  lineItems: z.array(z.object({
    vehicleTypeCode: z.string().min(1, 'Vehicle type is required'),
    engineTypeCode: z.string().min(1, 'Engine type is required'),
    quantityRequired: z.number()
      .int('Quantity must be a whole number')
      .min(1, 'Quantity must be at least 1')
      .max(50, 'Quantity cannot exceed 50'),
    withDriver: z.boolean(),
    preferredTags: z.array(z.string()).optional(),
  }))
    .min(1, 'At least one line item is required')
    .refine(
      (items) => {
        const total = items.reduce((sum, item) => sum + item.quantityRequired, 0);
        return total <= 50;
      },
      {
        message: 'Total vehicles across all line items cannot exceed 50',
      }
    ),
}).refine(
  (data) => isAfter(data.endDate, data.startDate),
  {
    message: 'End date must be after start date',
    path: ['endDate'],
  }
).refine(
  (data) => isBefore(data.bidDeadline, data.startDate),
  {
    message: 'Bid deadline must be before start date',
    path: ['bidDeadline'],
  }
);
```

---

## 💰 Bid Validations

### Submit Bid Schema

```typescript
export const submitBidSchema = z.object({
  lineItemBids: z.array(z.object({
    lineItemId: z.string().uuid('Invalid line item ID'),
    quantityOffered: z.number()
      .int('Quantity must be a whole number')
      .min(1, 'Quantity must be at least 1'),
    unitPrice: z.number()
      .positive('Price must be positive')
      .min(100, 'Price must be at least 100 ETB')
      .max(100000, 'Price cannot exceed 100,000 ETB'),
    notes: z.string().max(500, 'Notes must be less than 500 characters').optional(),
  }))
    .min(1, 'At least one line item bid is required'),
}).refine(
  async (data, ctx) => {
    // Validate price ranges per vehicle type
    for (const bid of data.lineItemBids) {
      const lineItem = await getLineItem(bid.lineItemId);
      const priceRange = await getMarketPriceRange(lineItem.vehicleTypeCode);
      
      if (bid.unitPrice < priceRange.floor || bid.unitPrice > priceRange.ceiling) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Price must be between ${priceRange.floor} and ${priceRange.ceiling} ETB for ${lineItem.vehicleTypeCode}`,
          path: ['lineItemBids'],
        });
        return false;
      }

      // Validate quantity doesn't exceed required
      if (bid.quantityOffered > lineItem.quantityRequired) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          message: `Quantity offered cannot exceed quantity required (${lineItem.quantityRequired})`,
          path: ['lineItemBids'],
        });
        return false;
      }
    }
    return true;
  }
);
```

---

## 🚙 Vehicle Validations

### Vehicle Registration Schema

```typescript
export const vehicleRegistrationSchema = z.object({
  plateNumber: z.string()
    .regex(/^[A-Z]{2}-[0-9]{5}$/, 'Plate number must be in format AA-12345')
    .refine(
      async (plate) => {
        const exists = await checkPlateExists(plate);
        return !exists;
      },
      {
        message: 'Plate number already registered',
      }
    ),
  vehicleTypeCode: z.string().min(1, 'Vehicle type is required'),
  engineTypeCode: z.string().min(1, 'Engine type is required'),
  brand: z.string()
    .min(1, 'Brand is required')
    .max(50, 'Brand must be less than 50 characters'),
  model: z.string()
    .min(1, 'Model is required')
    .max(50, 'Model must be less than 50 characters'),
  modelYear: z.number()
    .int('Year must be a whole number')
    .min(2010, 'Vehicle must be from 2010 or later')
    .max(new Date().getFullYear() + 1, 'Year cannot be in the future'),
  seatCount: z.number()
    .int('Seat count must be a whole number')
    .min(2, 'Seat count must be at least 2')
    .max(50, 'Seat count cannot exceed 50'),
  tags: z.array(z.string()).optional(),
  photos: z.object({
    front: z.instanceof(File, { message: 'Front photo is required' }),
    back: z.instanceof(File, { message: 'Back photo is required' }),
    left: z.instanceof(File, { message: 'Left photo is required' }),
    right: z.instanceof(File, { message: 'Right photo is required' }),
    interior: z.instanceof(File, { message: 'Interior photo is required' }),
  }).refine(
    (photos) => {
      return Object.values(photos).every(photo =>
        photo.size <= 5 * 1024 * 1024 && // 5MB
        ['image/jpeg', 'image/png'].includes(photo.type)
      );
    },
    {
      message: 'All photos must be JPEG or PNG and less than 5MB',
    }
  ),
  insurance: z.object({
    insuranceType: z.enum(['COMPREHENSIVE', 'THIRD_PARTY']),
    companyName: z.string().min(1, 'Insurance company name is required'),
    policyNumber: z.string().min(1, 'Policy number is required'),
    insuredAmount: z.number()
      .positive('Insured amount must be positive')
      .min(100000, 'Insured amount must be at least 100,000 ETB'),
    coverageStartDate: z.date(),
    coverageEndDate: z.date(),
    certificate: z.instanceof(File, { message: 'Insurance certificate is required' })
      .refine((file) => file.type === 'application/pdf', 'Certificate must be PDF')
      .refine((file) => file.size <= 5 * 1024 * 1024, 'Certificate must be less than 5MB'),
  }).refine(
    (data) => isAfter(data.coverageEndDate, data.coverageStartDate),
    {
      message: 'Coverage end date must be after start date',
      path: ['coverageEndDate'],
    }
  ).refine(
    (data) => isAfter(data.coverageEndDate, addDays(new Date(), 30)),
    {
      message: 'Insurance must be valid for at least 30 days from now',
      path: ['coverageEndDate'],
    }
  ),
});
```

---

## 💳 Wallet Validations

### Deposit Schema

```typescript
export const depositSchema = z.object({
  amount: z.number()
    .positive('Amount must be positive')
    .min(100, 'Minimum deposit is 100 ETB')
    .max(1000000, 'Maximum deposit is 1,000,000 ETB'),
  paymentMethod: z.enum(['CHAPA', 'TELEBIRR'], {
    errorMap: () => ({ message: 'Please select a payment method' }),
  }),
});
```

### Withdrawal Schema (Provider)

```typescript
export const withdrawalSchema = z.object({
  amount: z.number()
    .positive('Amount must be positive')
    .min(500, 'Minimum withdrawal is 500 ETB'),
}).refine(
  async (data, ctx) => {
    const wallet = await getWallet();
    if (data.amount > wallet.availableBalance) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: `Insufficient balance. Available: ${wallet.availableBalance} ETB`,
        path: ['amount'],
      });
      return false;
    }
    return true;
  }
);
```

---

## 📅 Date Validations

### Date Validation Utilities

```typescript
import { addDays, isAfter, isBefore, isFuture } from 'date-fns';

export const dateValidators = {
  // Start date must be at least 3 days from now
  minStartDate: (date: Date) => {
    return isAfter(date, addDays(new Date(), 3)) || 
      'Start date must be at least 3 days from now';
  },

  // End date must be after start date
  endAfterStart: (endDate: Date, startDate: Date) => {
    return isAfter(endDate, startDate) || 
      'End date must be after start date';
  },

  // Bid deadline must be before start date
  deadlineBeforeStart: (deadline: Date, startDate: Date) => {
    return isBefore(deadline, startDate) || 
      'Bid deadline must be before start date';
  },

  // Insurance must be valid for 30+ days
  insuranceValidFor30Days: (endDate: Date) => {
    return isAfter(endDate, addDays(new Date(), 30)) || 
      'Insurance must be valid for at least 30 days from now';
  },
};
```

---

## 🔄 Async Validations

### TIN Uniqueness Check

```typescript
export const checkTINExists = async (tin: string): Promise<boolean> => {
  try {
    const response = await apiClient.get(`/api/businesses/check-tin?tin=${tin}`);
    return response.exists;
  } catch (error) {
    return false;
  }
};

// Usage in schema
tinNumber: z.string()
  .refine(
    async (tin) => {
      const exists = await checkTINExists(tin);
      return !exists;
    },
    {
      message: 'TIN number already registered',
    }
  ),
```

### Email Uniqueness Check

```typescript
export const checkEmailExists = async (email: string): Promise<boolean> => {
  try {
    const response = await apiClient.get(`/api/users/check-email?email=${email}`);
    return response.exists;
  } catch (error) {
    return false;
  }
};
```

### Plate Number Uniqueness

```typescript
export const checkPlateExists = async (plate: string): Promise<boolean> => {
  try {
    const response = await apiClient.get(`/api/vehicles/check-plate?plate=${plate}`);
    return response.exists;
  } catch (error) {
    return false;
  }
};
```

---

## 🎨 Error Message Display

### FormField Component with Error

```typescript
interface FormFieldProps {
  label: string;
  error?: string;
  required?: boolean;
  helperText?: string;
  children: React.ReactNode;
}

export const FormField: FC<FormFieldProps> = ({
  label,
  error,
  required,
  helperText,
  children,
}) => {
  return (
    <div className="space-y-2">
      <label className="block text-sm font-medium">
        {label}
        {required && <span className="text-red-500 ml-1">*</span>}
      </label>
      {children}
      {helperText && !error && (
        <p className="text-xs text-gray-500">{helperText}</p>
      )}
      {error && (
        <p className="text-xs text-red-600 flex items-center gap-1">
          <AlertCircle className="h-3 w-3" />
          {error}
        </p>
      )}
    </div>
  );
};
```

---

## ✅ Validation Best Practices

1. **Client-side validation** for immediate feedback
2. **Server-side validation** for security (always validate on backend)
3. **Async validation** with debounce (300ms) for uniqueness checks
4. **Clear error messages** that guide users
5. **Real-time validation** on blur or change
6. **Disable submit button** until form is valid
7. **Show validation errors** only after first submit attempt or field blur
8. **Group related validations** in refine() for complex rules
9. **Use Zod's built-in validators** when possible
10. **Custom error messages** for better UX

---

**END OF FORM VALIDATIONS SPEC**

*For form implementations, see portal-specific guides*

