# Onboarding & Document Upload Guide
## Movello Frontend - React Implementation

**Version:** 1.0  
**Related:** [LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md](./LOVABLE_FRONTEND_DEVELOPMENT_GUIDE.md)

---

## 📋 Table of Contents

1. [Business Onboarding Wizard](#business-onboarding-wizard)
2. [Provider Onboarding Wizard](#provider-onboarding-wizard)
3. [Document Upload Component](#document-upload-component)
4. [Validation Rules](#validation-rules)
5. [Step Navigation](#step-navigation)

---

## 🏢 Business Onboarding Wizard

### Overview

Business onboarding is a **3-step wizard** that collects business information and required KYB documents.

### Step 1: Business Details

**Route:** `/register/business/step-1`  
**Component:** `src/features/auth/pages/RegisterBusinessStep1.tsx`

**Fields:**
- Business Name (required, min 3 chars)
- Business Type (dropdown: PLC, NGO, GOV)
- TIN Number (required, exactly 10 digits, async uniqueness check)
- Registration Number (optional)

**Validation:**
```typescript
const step1Schema = z.object({
  businessName: z.string().min(3, 'Business name must be at least 3 characters'),
  businessType: z.enum(['PLC', 'NGO', 'GOV']),
  tinNumber: z.string()
    .length(10, 'TIN must be exactly 10 digits')
    .regex(/^[0-9]{10}$/, 'TIN must contain only numbers')
    .refine(async (tin) => {
      // Async uniqueness check
      const exists = await checkTINExists(tin);
      return !exists;
    }, 'TIN number already registered'),
  registrationNumber: z.string().optional(),
});
```

**Component Implementation:**

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { useNavigate } from 'react-router-dom';
import { Stepper } from '@/shared/components/forms/stepper';
import { FormField } from '@/shared/components/forms/form-field';
import { Select } from '@/shared/components/ui/select';

const BUSINESS_TYPES = [
  { value: 'PLC', label: 'Public Limited Company' },
  { value: 'NGO', label: 'Non-Governmental Organization' },
  { value: 'GOV', label: 'Government Entity' },
];

export const RegisterBusinessStep1 = () => {
  const navigate = useNavigate();
  const { register, handleSubmit, formState: { errors }, watch } = useForm({
    resolver: zodResolver(step1Schema),
  });

  const onSubmit = (data) => {
    // Store in onboarding store or localStorage
    localStorage.setItem('businessOnboarding', JSON.stringify({ step1: data }));
    navigate('/register/business/step-2');
  };

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-2xl mx-auto">
        <Stepper currentStep={1} totalSteps={3} />
        
        <Card className="mt-8 p-8">
          <h2 className="text-2xl font-bold mb-6">Business Information</h2>
          
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            <FormField
              label="Business Name"
              error={errors.businessName?.message}
              required
            >
              <Input
                {...register('businessName')}
                placeholder="Enter your business name"
              />
            </FormField>

            <FormField
              label="Business Type"
              error={errors.businessType?.message}
              required
            >
              <Select {...register('businessType')}>
                <option value="">Select business type</option>
                {BUSINESS_TYPES.map((type) => (
                  <option key={type.value} value={type.value}>
                    {type.label}
                  </option>
                ))}
              </Select>
            </FormField>

            <FormField
              label="TIN Number"
              error={errors.tinNumber?.message}
              required
              helperText="10-digit Tax Identification Number"
            >
              <Input
                {...register('tinNumber')}
                placeholder="1234567890"
                maxLength={10}
                pattern="[0-9]{10}"
              />
            </FormField>

            <FormField
              label="Registration Number (Optional)"
              error={errors.registrationNumber?.message}
            >
              <Input
                {...register('registrationNumber')}
                placeholder="Enter registration number"
              />
            </FormField>

            <div className="flex justify-end">
              <Button type="submit">Next: Contact Information</Button>
            </div>
          </form>
        </Card>
      </div>
    </div>
  );
};
```

### Step 2: Contact & Address

**Route:** `/register/business/step-2`  
**Component:** `src/features/auth/pages/RegisterBusinessStep2.tsx`

**Fields:**
- Contact Person:
  - Full Name (required)
  - Email (required, valid email)
  - Phone (required, format: +251XXXXXXXXX)
- Address:
  - City (required, dropdown)
  - Subcity (required)
  - Woreda (required)
  - House Number (optional)

**Component Implementation:**

```typescript
export const RegisterBusinessStep2 = () => {
  const navigate = useNavigate();
  const { register, handleSubmit, formState: { errors } } = useForm({
    resolver: zodResolver(step2Schema),
    defaultValues: JSON.parse(localStorage.getItem('businessOnboarding') || '{}').step2 || {},
  });

  const onSubmit = (data) => {
    const existing = JSON.parse(localStorage.getItem('businessOnboarding') || '{}');
    localStorage.setItem('businessOnboarding', JSON.stringify({
      ...existing,
      step2: data,
    }));
    navigate('/register/business/step-3');
  };

  const onBack = () => {
    navigate('/register/business/step-1');
  };

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-2xl mx-auto">
        <Stepper currentStep={2} totalSteps={3} />
        
        <Card className="mt-8 p-8">
          <h2 className="text-2xl font-bold mb-6">Contact Information</h2>
          
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            <div className="space-y-4">
              <h3 className="font-semibold">Contact Person</h3>
              
              <FormField
                label="Full Name"
                error={errors.contactPerson?.fullName?.message}
                required
              >
                <Input {...register('contactPerson.fullName')} />
              </FormField>

              <FormField
                label="Email"
                error={errors.contactPerson?.email?.message}
                required
              >
                <Input type="email" {...register('contactPerson.email')} />
              </FormField>

              <FormField
                label="Phone"
                error={errors.contactPerson?.phone?.message}
                required
                helperText="Format: +251XXXXXXXXX"
              >
                <Input {...register('contactPerson.phone')} />
              </FormField>
            </div>

            <div className="space-y-4">
              <h3 className="font-semibold">Business Address</h3>
              
              <FormField
                label="City"
                error={errors.address?.city?.message}
                required
              >
                <Select {...register('address.city')}>
                  <option value="">Select city</option>
                  <option value="AA">Addis Ababa</option>
                  <option value="DR">Dire Dawa</option>
                  {/* More cities */}
                </Select>
              </FormField>

              <FormField
                label="Subcity"
                error={errors.address?.subcity?.message}
                required
              >
                <Input {...register('address.subcity')} />
              </FormField>

              <FormField
                label="Woreda"
                error={errors.address?.woreda?.message}
                required
              >
                <Input {...register('address.woreda')} />
              </FormField>

              <FormField
                label="House Number (Optional)"
                error={errors.address?.houseNumber?.message}
              >
                <Input {...register('address.houseNumber')} />
              </FormField>
            </div>

            <div className="flex justify-between">
              <Button type="button" variant="outline" onClick={onBack}>
                Back
              </Button>
              <Button type="submit">Next: Upload Documents</Button>
            </div>
          </form>
        </Card>
      </div>
    </div>
  );
};
```

### Step 3: Document Upload

**Route:** `/register/business/step-3`  
**Component:** `src/features/auth/pages/RegisterBusinessStep3.tsx`

**CRITICAL:** Document types must be fetched from master data, not hardcoded.

**Implementation:**

```typescript
import { useQuery } from '@tanstack/react-query';
import { masterDataService } from '@/shared/services/master-data-service';

export const RegisterBusinessStep3 = () => {
  const { data: kycRequirements } = useQuery({
    queryKey: ['kyc-requirements', 'BUSINESS'],
    queryFn: () => masterDataService.getKYCRequirements({
      entityType: 'BUSINESS',
    }),
  });

  const { data: documentTypes } = useQuery({
    queryKey: ['document-types'],
    queryFn: () => masterDataService.getDocumentTypes(),
  });

  // Map KYC requirements to document types
  const requiredDocuments = useMemo(() => {
    if (!kycRequirements || !documentTypes) return [];
    
    return kycRequirements
      .filter(req => req.isRequired)
      .map(req => {
        const docType = documentTypes.find(dt => dt.id === req.documentTypeId);
        return {
          id: req.id,
          documentTypeId: req.documentTypeId,
          label: docType?.name || 'Unknown',
          description: req.description || docType?.description,
          maxSize: req.maxFileSize || 5 * 1024 * 1024, // Default 5MB
          acceptedTypes: req.allowedFileTypes || ['application/pdf', 'image/jpeg', 'image/png'],
          isRequired: req.isRequired,
        };
      });
  }, [kycRequirements, documentTypes]);

  // Use requiredDocuments instead of hardcoded REQUIRED_DOCUMENTS
};
```

**Note:** Document requirements are dynamically loaded from `/api/kyc-requirements?entityType=BUSINESS`.

**Component Implementation:**

```typescript
import { FileUpload } from '@/shared/components/forms/file-upload';
import { businessService } from '@/features/business/services/business-service';

const REQUIRED_DOCUMENTS = [
  {
    id: 'businessLicense',
    label: 'Business License',
    description: 'Upload your business license (PDF or Image, max 5MB)',
    required: true,
    maxSize: 5 * 1024 * 1024, // 5MB
    acceptedTypes: ['application/pdf', 'image/jpeg', 'image/png'],
  },
  {
    id: 'tinCertificate',
    label: 'TIN Certificate',
    description: 'Upload your TIN certificate (PDF or Image, max 5MB)',
    required: true,
    maxSize: 5 * 1024 * 1024,
    acceptedTypes: ['application/pdf', 'image/jpeg', 'image/png'],
  },
  {
    id: 'articlesOfAssociation',
    label: 'Articles of Association',
    description: 'Upload articles of association (PDF, max 10MB)',
    required: true,
    maxSize: 10 * 1024 * 1024, // 10MB
    acceptedTypes: ['application/pdf'],
  },
  {
    id: 'representativeId',
    label: 'ID of Representative',
    description: 'Upload ID of authorized representative (PDF or Image, max 5MB)',
    required: true,
    maxSize: 5 * 1024 * 1024,
    acceptedTypes: ['application/pdf', 'image/jpeg', 'image/png'],
  },
];

export const RegisterBusinessStep3 = () => {
  const navigate = useNavigate();
  const [uploadedFiles, setUploadedFiles] = useState<Record<string, File>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [uploadProgress, setUploadProgress] = useState<Record<string, number>>({});

  const handleFileUpload = (documentId: string, file: File) => {
    setUploadedFiles((prev) => ({ ...prev, [documentId]: file }));
  };

  const handleRemove = (documentId: string) => {
    setUploadedFiles((prev) => {
      const updated = { ...prev };
      delete updated[documentId];
      return updated;
    });
  };

  const onSubmit = async () => {
    setIsSubmitting(true);
    
    try {
      // Get data from previous steps
      const onboardingData = JSON.parse(
        localStorage.getItem('businessOnboarding') || '{}'
      );

      // Create business profile
      const business = await businessService.createBusiness({
        ...onboardingData.step1,
        contactPerson: onboardingData.step2.contactPerson,
        address: onboardingData.step2.address,
      });

      // Upload documents
      for (const [documentId, file] of Object.entries(uploadedFiles)) {
        const documentType = documentId.toUpperCase();
        await businessService.uploadDocument(
          business.id,
          file,
          documentType,
          (progress) => {
            setUploadProgress((prev) => ({ ...prev, [documentId]: progress }));
          }
        );
      }

      // Clear onboarding data
      localStorage.removeItem('businessOnboarding');

      // Redirect to verification pending page
      navigate('/business/onboarding/verification-pending');
    } catch (error) {
      console.error('Onboarding failed:', error);
      toast.error('Failed to complete registration. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  };

  const allDocumentsUploaded = REQUIRED_DOCUMENTS.every(
    (doc) => uploadedFiles[doc.id]
  );

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-3xl mx-auto">
        <Stepper currentStep={3} totalSteps={3} />
        
        <Card className="mt-8 p-8">
          <h2 className="text-2xl font-bold mb-6">Upload Documents</h2>
          <p className="text-gray-600 mb-8">
            Please upload the required documents for KYB verification.
            Review time: 24-48 hours.
          </p>

          <div className="space-y-6">
            {REQUIRED_DOCUMENTS.map((doc) => (
              <div key={doc.id} className="border rounded-lg p-6">
                <div className="mb-4">
                  <h3 className="font-semibold mb-1">{doc.label}</h3>
                  <p className="text-sm text-gray-600">{doc.description}</p>
                </div>

                {uploadedFiles[doc.id] ? (
                  <div className="flex items-center justify-between p-4 bg-green-50 rounded">
                    <div className="flex items-center gap-3">
                      <CheckCircle className="text-green-600" />
                      <div>
                        <p className="font-medium">{uploadedFiles[doc.id].name}</p>
                        <p className="text-sm text-gray-600">
                          {(uploadedFiles[doc.id].size / 1024 / 1024).toFixed(2)} MB
                        </p>
                      </div>
                    </div>
                    {uploadProgress[doc.id] && uploadProgress[doc.id] < 100 && (
                      <div className="w-32">
                        <Progress value={uploadProgress[doc.id]} />
                      </div>
                    )}
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleRemove(doc.id)}
                      disabled={isSubmitting}
                    >
                      Remove
                    </Button>
                  </div>
                ) : (
                  <FileUpload
                    onFileSelect={(file) => handleFileUpload(doc.id, file)}
                    accept={doc.acceptedTypes.join(',')}
                    maxSize={doc.maxSize}
                    disabled={isSubmitting}
                  />
                )}
              </div>
            ))}
          </div>

          <div className="mt-8 flex justify-between">
            <Button
              type="button"
              variant="outline"
              onClick={() => navigate('/register/business/step-2')}
              disabled={isSubmitting}
            >
              Back
            </Button>
            <Button
              onClick={onSubmit}
              disabled={!allDocumentsUploaded || isSubmitting}
            >
              {isSubmitting ? 'Submitting...' : 'Submit for Verification'}
            </Button>
          </div>
        </Card>
      </div>
    </div>
  );
};
```

### Verification Pending Page

**Route:** `/business/onboarding/verification-pending`  
**Component:** `src/features/business/onboarding/VerificationPendingPage.tsx`

```typescript
export const VerificationPendingPage = () => {
  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-2xl mx-auto">
        <Card className="p-8 text-center">
          <div className="text-6xl mb-4">⏳</div>
          <h2 className="text-2xl font-bold mb-4">Verification Pending</h2>
          <p className="text-gray-600 mb-6">
            Your documents are under review. We'll notify you once verification is complete.
          </p>
          <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
            <p className="text-sm text-blue-800">
              <strong>Estimated review time:</strong> 24-48 hours
            </p>
          </div>
          <Button onClick={() => navigate('/login')}>
            Go to Login
          </Button>
        </Card>
      </div>
    </div>
  );
};
```

---

## 🚗 Provider Onboarding Wizard

### Step 1: Provider Type Selection

**Route:** `/register/provider/step-1`  
**Component:** `src/features/auth/pages/RegisterProviderStep1.tsx`

**Fields:**
- Provider Type (required, radio buttons):
  - Individual (1-5 vehicles)
  - Agent (6-20 vehicles)
  - Company (20+ vehicles)
- Name (required)
- TIN Number (optional for Individual, required for Company)

**Component Implementation:**

```typescript
export const RegisterProviderStep1 = () => {
  const [providerType, setProviderType] = useState<'INDIVIDUAL' | 'AGENT' | 'COMPANY' | null>(null);
  const { register, handleSubmit, formState: { errors }, watch } = useForm({
    resolver: zodResolver(step1Schema),
  });

  const selectedType = watch('providerType');

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-2xl mx-auto">
        <Stepper currentStep={1} totalSteps={3} />
        
        <Card className="mt-8 p-8">
          <h2 className="text-2xl font-bold mb-6">Provider Type</h2>
          
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            <FormField
              label="Provider Type"
              error={errors.providerType?.message}
              required
            >
              <div className="space-y-3">
                <label className="flex items-center p-4 border rounded-lg cursor-pointer hover:bg-gray-50">
                  <input
                    type="radio"
                    value="INDIVIDUAL"
                    {...register('providerType')}
                    className="mr-3"
                  />
                  <div>
                    <p className="font-medium">Individual</p>
                    <p className="text-sm text-gray-600">1-5 vehicles</p>
                  </div>
                </label>
                
                <label className="flex items-center p-4 border rounded-lg cursor-pointer hover:bg-gray-50">
                  <input
                    type="radio"
                    value="AGENT"
                    {...register('providerType')}
                    className="mr-3"
                  />
                  <div>
                    <p className="font-medium">Agent</p>
                    <p className="text-sm text-gray-600">6-20 vehicles</p>
                  </div>
                </label>
                
                <label className="flex items-center p-4 border rounded-lg cursor-pointer hover:bg-gray-50">
                  <input
                    type="radio"
                    value="COMPANY"
                    {...register('providerType')}
                    className="mr-3"
                  />
                  <div>
                    <p className="font-medium">Company</p>
                    <p className="text-sm text-gray-600">20+ vehicles</p>
                  </div>
                </label>
              </div>
            </FormField>

            <FormField
              label="Name"
              error={errors.name?.message}
              required
            >
              <Input {...register('name')} />
            </FormField>

            {selectedType === 'COMPANY' && (
              <FormField
                label="TIN Number"
                error={errors.tinNumber?.message}
                required
              >
                <Input
                  {...register('tinNumber')}
                  maxLength={10}
                  pattern="[0-9]{10}"
                />
              </FormField>
            )}

            <div className="flex justify-end">
              <Button type="submit">Next</Button>
            </div>
          </form>
        </Card>
      </div>
    </div>
  );
};
```

### Step 2: Contact Information

Similar to Business Step 2, but with provider-specific fields.

### Step 3: Document Upload

**CRITICAL:** Document types must be fetched from master data, not hardcoded.

**Implementation:**

```typescript
import { useQuery } from '@tanstack/react-query';
import { masterDataService } from '@/shared/services/master-data-service';

export const RegisterProviderStep3 = () => {
  const { data: kycRequirements } = useQuery({
    queryKey: ['kyc-requirements', 'PROVIDER', providerType],
    queryFn: () => masterDataService.getKYCRequirements({
      entityType: 'PROVIDER',
      providerType: providerType, // INDIVIDUAL, AGENT, or COMPANY
    }),
  });

  const { data: documentTypes } = useQuery({
    queryKey: ['document-types'],
    queryFn: () => masterDataService.getDocumentTypes(),
  });

  // Map KYC requirements to document types
  const requiredDocuments = useMemo(() => {
    if (!kycRequirements || !documentTypes) return [];
    
    return kycRequirements
      .filter(req => req.isRequired)
      .map(req => {
        const docType = documentTypes.find(dt => dt.id === req.documentTypeId);
        return {
          id: req.id,
          documentTypeId: req.documentTypeId,
          label: docType?.name || 'Unknown',
          description: req.description || docType?.description,
          maxSize: req.maxFileSize || 5 * 1024 * 1024, // Default 5MB
          acceptedTypes: req.allowedFileTypes || ['application/pdf', 'image/jpeg', 'image/png'],
          isRequired: req.isRequired,
        };
      });
  }, [kycRequirements, documentTypes]);

  // Rest of component...
};
```

**Note:** Document requirements are dynamically loaded from `/api/kyc-requirements` based on provider type.

### Step 4: Vehicle Registration

**Route:** `/register/provider/step-4`  
**Component:** `src/features/auth/pages/RegisterProviderStep4.tsx`

**CRITICAL:** Providers can register vehicles during onboarding to complete their profile.

**Features:**
- Register at least 1 vehicle (required to complete onboarding)
- Can register multiple vehicles
- Same 3-step vehicle registration flow as in fleet management:
  1. Vehicle Information
  2. Photo Upload (5 photos)
  3. Insurance Information

**Component:**

```typescript
export const RegisterProviderStep4 = ({ onBack, onSubmit }) => {
  const [vehicles, setVehicles] = useState<VehicleFormData[]>([]);
  const [currentVehicleStep, setCurrentVehicleStep] = useState(1);
  const [currentVehicleIndex, setCurrentVehicleIndex] = useState(0);

  const handleVehicleComplete = (vehicleData: VehicleFormData) => {
    const updated = [...vehicles];
    updated[currentVehicleIndex] = vehicleData;
    setVehicles(updated);
    
    // Move to next vehicle or finish
    if (currentVehicleIndex < vehicles.length - 1) {
      setCurrentVehicleIndex(currentVehicleIndex + 1);
      setCurrentVehicleStep(1);
    } else {
      // All vehicles registered
      onSubmit({ vehicles });
    }
  };

  const handleAddAnotherVehicle = () => {
    setVehicles([...vehicles, {}]);
    setCurrentVehicleIndex(vehicles.length);
    setCurrentVehicleStep(1);
  };

  return (
    <div className="min-h-screen bg-gray-50 py-12">
      <div className="max-w-4xl mx-auto">
        <Stepper currentStep={4} totalSteps={4} />
        
        <Card className="mt-8 p-8">
          <h2 className="text-2xl font-bold mb-6">Register Vehicles</h2>
          <p className="text-gray-600 mb-6">
            Register at least one vehicle to complete your provider profile.
            You can add more vehicles later from your dashboard.
          </p>

          {vehicles.length === 0 ? (
            <div className="text-center py-12">
              <p className="text-gray-600 mb-4">No vehicles registered yet</p>
              <Button onClick={() => setVehicles([{}])}>
                Register First Vehicle
              </Button>
            </div>
          ) : (
            <div className="space-y-6">
              <div className="flex justify-between items-center">
                <h3 className="font-semibold">
                  Vehicle {currentVehicleIndex + 1} of {vehicles.length}
                </h3>
                {vehicles.length > 1 && (
                  <Button
                    variant="outline"
                    onClick={() => {
                      setVehicles(vehicles.filter((_, i) => i !== currentVehicleIndex));
                      if (currentVehicleIndex >= vehicles.length - 1) {
                        setCurrentVehicleIndex(Math.max(0, currentVehicleIndex - 1));
                      }
                    }}
                  >
                    Remove Vehicle
                  </Button>
                )}
              </div>

              {/* Vehicle Registration Steps - Same as in Fleet Management */}
              {currentVehicleStep === 1 && (
                <VehicleInfoStep
                  data={vehicles[currentVehicleIndex]?.vehicleInfo}
                  onNext={(data) => {
                    const updated = [...vehicles];
                    updated[currentVehicleIndex] = {
                      ...updated[currentVehicleIndex],
                      vehicleInfo: data,
                    };
                    setVehicles(updated);
                    setCurrentVehicleStep(2);
                  }}
                />
              )}

              {currentVehicleStep === 2 && (
                <PhotoUploadStep
                  photos={vehicles[currentVehicleIndex]?.photos || {}}
                  onPhotosChange={(photos) => {
                    const updated = [...vehicles];
                    updated[currentVehicleIndex] = {
                      ...updated[currentVehicleIndex],
                      photos,
                    };
                    setVehicles(updated);
                  }}
                  onBack={() => setCurrentVehicleStep(1)}
                  onNext={() => setCurrentVehicleStep(3)}
                />
              )}

              {currentVehicleStep === 3 && (
                <InsuranceStep
                  data={vehicles[currentVehicleIndex]?.insurance}
                  onBack={() => setCurrentVehicleStep(2)}
                  onSubmit={(data) => {
                    handleVehicleComplete({
                      ...vehicles[currentVehicleIndex],
                      insurance: data,
                    });
                  }}
                />
              )}

              {currentVehicleStep === 3 && currentVehicleIndex === vehicles.length - 1 && (
                <div className="flex justify-between mt-6">
                  <Button
                    variant="outline"
                    onClick={handleAddAnotherVehicle}
                  >
                    Add Another Vehicle
                  </Button>
                  <Button
                    onClick={() => onSubmit({ vehicles })}
                    disabled={vehicles.length === 0}
                  >
                    Complete Onboarding
                  </Button>
                </div>
              )}
            </div>
          )}

          <div className="mt-8 flex justify-between">
            <Button variant="outline" onClick={onBack}>
              Back
            </Button>
            {vehicles.length > 0 && (
              <Button
                onClick={() => onSubmit({ vehicles })}
                disabled={vehicles.some(v => !v.vehicleInfo || !v.photos || !v.insurance)}
              >
                Complete Onboarding
              </Button>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
};
```

**Note:** Vehicle registration during onboarding is optional but recommended. Providers can complete onboarding without vehicles and register them later, but they won't be able to bid on RFQs until they have at least one verified vehicle.

---

## 📤 Document Upload Component

**File:** `src/shared/components/forms/file-upload.tsx`

```typescript
import { useCallback, useState } from 'react';
import { useDropzone } from 'react-dropzone';
import { Upload, X, File } from 'lucide-react';
import { Button } from '@/shared/components/ui/button';

interface FileUploadProps {
  onFileSelect: (file: File) => void;
  accept?: string;
  maxSize?: number;
  disabled?: boolean;
  currentFile?: File;
  onRemove?: () => void;
}

export const FileUpload: FC<FileUploadProps> = ({
  onFileSelect,
  accept,
  maxSize = 5 * 1024 * 1024, // 5MB default
  disabled,
  currentFile,
  onRemove,
}) => {
  const [error, setError] = useState<string | null>(null);

  const onDrop = useCallback(
    (acceptedFiles: File[], rejectedFiles: any[]) => {
      setError(null);

      if (rejectedFiles.length > 0) {
        const rejection = rejectedFiles[0];
        if (rejection.errors.some((e: any) => e.code === 'file-too-large')) {
          setError(`File size must be less than ${(maxSize / 1024 / 1024).toFixed(0)}MB`);
        } else if (rejection.errors.some((e: any) => e.code === 'file-invalid-type')) {
          setError('Invalid file type. Please upload a valid file.');
        } else {
          setError('File upload failed. Please try again.');
        }
        return;
      }

      if (acceptedFiles.length > 0) {
        onFileSelect(acceptedFiles[0]);
      }
    },
    [onFileSelect, maxSize]
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: accept ? { [accept]: [] } : undefined,
    maxSize,
    multiple: false,
    disabled,
  });

  if (currentFile) {
    return (
      <div className="border-2 border-dashed border-gray-300 rounded-lg p-6">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <File className="text-blue-600" />
            <div>
              <p className="font-medium">{currentFile.name}</p>
              <p className="text-sm text-gray-600">
                {(currentFile.size / 1024 / 1024).toFixed(2)} MB
              </p>
            </div>
          </div>
          {onRemove && (
            <Button
              variant="ghost"
              size="sm"
              onClick={onRemove}
              disabled={disabled}
            >
              <X className="h-4 w-4" />
            </Button>
          )}
        </div>
      </div>
    );
  }

  return (
    <div>
      <div
        {...getRootProps()}
        className={`
          border-2 border-dashed rounded-lg p-8 text-center cursor-pointer
          transition-colors
          ${isDragActive ? 'border-blue-500 bg-blue-50' : 'border-gray-300'}
          ${disabled ? 'opacity-50 cursor-not-allowed' : 'hover:border-gray-400'}
        `}
      >
        <input {...getInputProps()} />
        <Upload className="mx-auto h-12 w-12 text-gray-400 mb-4" />
        {isDragActive ? (
          <p className="text-blue-600">Drop the file here...</p>
        ) : (
          <div>
            <p className="text-gray-600 mb-2">
              Drag and drop a file here, or click to select
            </p>
            <Button type="button" variant="outline" disabled={disabled}>
              Select File
            </Button>
          </div>
        )}
        <p className="text-xs text-gray-500 mt-4">
          Max file size: {(maxSize / 1024 / 1024).toFixed(0)}MB
        </p>
      </div>
      {error && (
        <p className="text-red-600 text-sm mt-2">{error}</p>
      )}
    </div>
  );
};
```

---

## ✅ Validation Rules

### Business Onboarding

| Field | Rules |
|-------|-------|
| Business Name | Min 3 characters, required |
| Business Type | Must be PLC, NGO, or GOV |
| TIN Number | Exactly 10 digits, unique, required |
| Contact Email | Valid email format, required |
| Phone | Format: +251XXXXXXXXX, required |
| Documents | All 4 documents required, file size limits apply |

### Provider Onboarding

| Field | Rules |
|-------|-------|
| Provider Type | Must be INDIVIDUAL, AGENT, or COMPANY |
| Name | Min 2 characters, required |
| TIN Number | Required for COMPANY, optional for others |
| Documents | Varies by provider type (see Step 3) |

### File Upload Validation

- **File Types:** PDF, JPEG, PNG
- **File Sizes:**
  - Business License: Max 5MB
  - TIN Certificate: Max 5MB
  - Articles of Association: Max 10MB
  - ID Documents: Max 5MB
- **Required:** All specified documents must be uploaded

---

## 🧭 Step Navigation

### Stepper Component

**File:** `src/shared/components/forms/stepper.tsx`

```typescript
interface StepperProps {
  currentStep: number;
  totalSteps: number;
  steps?: string[];
}

export const Stepper: FC<StepperProps> = ({
  currentStep,
  totalSteps,
  steps,
}) => {
  return (
    <div className="flex items-center justify-between mb-8">
      {Array.from({ length: totalSteps }).map((_, index) => {
        const stepNumber = index + 1;
        const isCompleted = stepNumber < currentStep;
        const isCurrent = stepNumber === currentStep;

        return (
          <div key={stepNumber} className="flex items-center flex-1">
            <div className="flex flex-col items-center flex-1">
              <div
                className={`
                  w-10 h-10 rounded-full flex items-center justify-center
                  ${isCompleted ? 'bg-blue-600 text-white' : ''}
                  ${isCurrent ? 'bg-blue-600 text-white border-2 border-blue-700' : ''}
                  ${!isCompleted && !isCurrent ? 'bg-gray-200 text-gray-600' : ''}
                `}
              >
                {isCompleted ? (
                  <Check className="h-5 w-5" />
                ) : (
                  stepNumber
                )}
              </div>
              {steps && (
                <p className="mt-2 text-sm text-gray-600">{steps[index]}</p>
              )}
            </div>
            {stepNumber < totalSteps && (
              <div
                className={`
                  h-1 flex-1 mx-2
                  ${isCompleted ? 'bg-blue-600' : 'bg-gray-200'}
                `}
              />
            )}
          </div>
        );
      })}
    </div>
  );
};
```

---

## 🧪 Testing Scenarios

### Business Onboarding
- ✅ Complete all 3 steps successfully
- ✅ Validate TIN uniqueness check
- ✅ Validate file upload limits
- ✅ Handle missing documents
- ✅ Handle invalid file types
- ✅ Handle file size exceeded
- ✅ Navigate back and forth between steps
- ✅ Persist data across steps

### Provider Onboarding
- ✅ Select different provider types
- ✅ Conditional TIN requirement
- ✅ Conditional document requirements
- ✅ Complete onboarding for each type

---

**END OF ONBOARDING GUIDE**

*For portal-specific screens, see [BUSINESS_PORTAL_GUIDE.md](./BUSINESS_PORTAL_GUIDE.md) and [PROVIDER_PORTAL_GUIDE.md](./PROVIDER_PORTAL_GUIDE.md)*

