# Auth & Keycloak Module - Specification

**Module Name:** Authentication & Authorization (Keycloak + BFF)  
**Version:** 1.0 MVP  
**Date:** November 26, 2025  
**Pattern:** BFF (Backend-for-Frontend) with Keycloak

---

## 📋 Overview

### Purpose
The Auth & Keycloak Module provides **centralized identity management** and **secure authentication/authorization** for the Movello platform using industry-standard OAuth2/OIDC protocols via Keycloak, with a BFF layer for enhanced security.

### Architecture Pattern: BFF (Backend-for-Frontend)

```
┌─────────────┐
│   Angular   │
│   Frontend  │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────────────────────┐
│    BFF (YARP - .NET 9)          │
│  - Token Management             │
│  - API Aggregation              │
│  - CORS Handling                │
│  - Rate Limiting                │
└──────┬──────────────────────────┘
       │
       ├─► Keycloak (OAuth2/OIDC)
       │
       └─► Marketplace.API (.NET 9)
```

### Why BFF?

✅ **Security Benefits:**
- Refresh tokens never exposed to frontend (httpOnly cookies)
- Centralized token management
- Protection against XSS attacks
- CSRF protection

✅ **Operational Benefits:**
- API aggregation (combine multiple backend calls)
- Rate limiting at gateway level
- CORS handling
- Request/response transformation

---

## 🏗️ Components

### 1. Keycloak (Identity Provider)

**Responsibilities:**
- User authentication
- Token issuance (access + refresh tokens)
- User management
- Role/group management
- Social login (future)
- MFA (future)

**Configuration:**
- Realm: `movello`
- Clients: `movello-web`, `movello-api`
- Roles: `business-admin`, `provider-admin`, `platform-admin`, etc.

---

### 2. BFF (Backend-for-Frontend)

**Technology:** YARP (Yet Another Reverse Proxy) - .NET 9

**Responsibilities:**
- Proxy requests to Keycloak and backend API
- Store refresh tokens securely (httpOnly cookies)
- Token refresh automation
- API route aggregation
- Rate limiting
- CORS policy enforcement

---

### 3. Marketplace.API (Resource Server)

**Responsibilities:**
- Validate JWT access tokens
- Extract user claims (sub, roles, business_id, provider_id)
- Enforce authorization policies
- Process business logic

---

## 🔐 Authentication Flow

### 1. Login Flow (Authorization Code Flow with PKCE)

```
┌─────────┐                ┌─────────┐                ┌──────────┐                ┌──────────────┐
│ Angular │                │   BFF   │                │ Keycloak │                │ Marketplace  │
│ Frontend│                │  (YARP) │                │          │                │     API      │
└────┬────┘                └────┬────┘                └────┬─────┘                └──────┬───────┘
     │                          │                          │                             │
     │ 1. Login Request         │                          │                             │
     ├─────────────────────────►│                          │                             │
     │                          │                          │                             │
     │                          │ 2. Redirect to Keycloak  │                             │
     │                          │  (with PKCE challenge)   │                             │
     │◄─────────────────────────┤                          │                             │
     │                          │                          │                             │
     │ 3. User enters credentials                          │                             │
     ├─────────────────────────────────────────────────────►                             │
     │                          │                          │                             │
     │ 4. Authorization Code    │                          │                             │
     │  (redirected to BFF)     │                          │                             │
     ├─────────────────────────►│                          │                             │
     │                          │                          │                             │
     │                          │ 5. Exchange code for tokens                            │
     │                          │  (with PKCE verifier)    │                             │
     │                          ├─────────────────────────►│                             │
     │                          │                          │                             │
     │                          │ 6. Access + Refresh Token│                             │
     │                          │◄─────────────────────────┤                             │
     │                          │                          │                             │
     │                          │ 7. Store refresh token   │                             │
     │                          │  (httpOnly cookie)       │                             │
     │                          │                          │                             │
     │ 8. Return access token   │                          │                             │
     │  (in response body)      │                          │                             │
     │◄─────────────────────────┤                          │                             │
     │                          │                          │                             │
     │ 9. Store access token    │                          │                             │
     │  (in memory)             │                          │                             │
     │                          │                          │                             │
     │ 10. API Request          │                          │                             │
     │  (Bearer: access_token)  │                          │                             │
     ├─────────────────────────►│                          │                             │
     │                          │                          │                             │
     │                          │ 11. Validate token       │                             │
     │                          │  (signature, expiry)     │                             │
     │                          │                          │                             │
     │                          │ 12. Forward request      │                             │
     │                          │  (with validated token)  │                             │
     │                          ├─────────────────────────────────────────────────────────►
     │                          │                          │                             │
     │                          │                          │ 13. Validate JWT            │
     │                          │                          │     Extract claims          │
     │                          │                          │     Authorize               │
     │                          │                          │                             │
     │                          │ 14. Response             │                             │
     │                          │◄─────────────────────────────────────────────────────────
     │                          │                          │                             │
     │ 15. Response             │                          │                             │
     │◄─────────────────────────┤                          │                             │
     │                          │                          │                             │
```

---

### 2. Token Refresh Flow

```
┌─────────┐                ┌─────────┐                ┌──────────┐
│ Angular │                │   BFF   │                │ Keycloak │
│ Frontend│                │  (YARP) │                │          │
└────┬────┘                └────┬────┘                └────┬─────┘
     │                          │                          │
     │ 1. API Request           │                          │
     │  (expired access token)  │                          │
     ├─────────────────────────►│                          │
     │                          │                          │
     │                          │ 2. Validate token        │
     │                          │  (expired!)              │
     │                          │                          │
     │                          │ 3. Get refresh token     │
     │                          │  (from httpOnly cookie)  │
     │                          │                          │
     │                          │ 4. Request new access token                          │
     │                          ├─────────────────────────►│
     │                          │                          │
     │                          │ 5. New access token      │
     │                          │◄─────────────────────────┤
     │                          │                          │
     │                          │ 6. Retry original request│
     │                          │  (with new token)        │
     │                          │                          │
     │ 7. Response + new token  │                          │
     │◄─────────────────────────┤                          │
     │                          │                          │
     │ 8. Update access token   │                          │
     │  (in memory)             │                          │
     │                          │                          │
```

---

## 🛠️ Implementation

### 1. Keycloak Configuration

#### Realm Setup
```json
{
  "realm": "movello",
  "enabled": true,
  "sslRequired": "external",
  "registrationAllowed": false,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "permanentLockout": false,
  "maxFailureWaitSeconds": 900,
  "minimumQuickLoginWaitSeconds": 60,
  "waitIncrementSeconds": 60,
  "quickLoginCheckMilliSeconds": 1000,
  "maxDeltaTimeSeconds": 43200,
  "failureFactor": 5
}
```

#### Client Configuration (movello-web)
```json
{
  "clientId": "movello-web",
  "enabled": true,
  "protocol": "openid-connect",
  "publicClient": false,
  "standardFlowEnabled": true,
  "implicitFlowEnabled": false,
  "directAccessGrantsEnabled": false,
  "serviceAccountsEnabled": false,
  "authorizationServicesEnabled": false,
  "redirectUris": [
    "https://app.movello.et/*",
    "http://localhost:4200/*"
  ],
  "webOrigins": [
    "https://app.movello.et",
    "http://localhost:4200"
  ],
  "attributes": {
    "pkce.code.challenge.method": "S256"
  }
}
```

#### Roles
```json
{
  "roles": {
    "realm": [
      {
        "name": "business-admin",
        "description": "Business administrator"
      },
      {
        "name": "business-user",
        "description": "Business regular user"
      },
      {
        "name": "provider-admin",
        "description": "Provider administrator"
      },
      {
        "name": "provider-driver",
        "description": "Provider driver"
      },
      {
        "name": "platform-admin",
        "description": "Platform administrator"
      },
      {
        "name": "compliance-officer",
        "description": "Compliance officer"
      },
      {
        "name": "finance-officer",
        "description": "Finance officer"
      }
    ]
  }
}
```

---

### 2. BFF Implementation (YARP)

#### Program.cs
```csharp
var builder = WebApplication.CreateBuilder(args);

// Add services
builder.Services.AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Keycloak:Authority"];
        options.Audience = "movello-api";
        options.RequireHttpsMetadata = true;
        
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.Zero
        };
    });

builder.Services.AddAuthorization();

builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowFrontend", policy =>
    {
        policy.WithOrigins("https://app.movello.et", "http://localhost:4200")
              .AllowAnyMethod()
              .AllowAnyHeader()
              .AllowCredentials(); // For httpOnly cookies
    });
});

// Rate limiting
builder.Services.AddRateLimiter(options =>
{
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            partitionKey: context.User.Identity?.Name ?? context.Request.Headers.Host.ToString(),
            factory: partition => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 100,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1)
            }));
});

var app = builder.Build();

app.UseCors("AllowFrontend");
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapReverseProxy();

app.Run();
```

#### appsettings.json
```json
{
  "Keycloak": {
    "Authority": "https://auth.movello.et/realms/movello",
    "ClientId": "movello-web",
    "ClientSecret": "your-client-secret"
  },
  "ReverseProxy": {
    "Routes": {
      "auth-route": {
        "ClusterId": "keycloak-cluster",
        "Match": {
          "Path": "/auth/{**catch-all}"
        },
        "Transforms": [
          {
            "PathRemovePrefix": "/auth"
          }
        ]
      },
      "api-route": {
        "ClusterId": "api-cluster",
        "Match": {
          "Path": "/api/{**catch-all}"
        },
        "AuthorizationPolicy": "authenticated"
      }
    },
    "Clusters": {
      "keycloak-cluster": {
        "Destinations": {
          "destination1": {
            "Address": "https://auth.movello.et"
          }
        }
      },
      "api-cluster": {
        "Destinations": {
          "destination1": {
            "Address": "https://api-internal.movello.et"
          }
        }
      }
    }
  }
}
```

---

### 3. Marketplace.API JWT Validation

#### Program.cs
```csharp
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Keycloak:Authority"];
        options.Audience = "movello-api";
        options.RequireHttpsMetadata = true;
        
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = builder.Configuration["Keycloak:Authority"],
            ValidateAudience = true,
            ValidAudience = "movello-api",
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            ClockSkew = TimeSpan.Zero
        };
        
        options.Events = new JwtBearerEvents
        {
            OnTokenValidated = async context =>
            {
                // Extract custom claims
                var claimsIdentity = context.Principal.Identity as ClaimsIdentity;
                
                // Map Keycloak user to internal user_account
                var keycloakId = claimsIdentity.FindFirst("sub")?.Value;
                
                var userService = context.HttpContext.RequestServices
                    .GetRequiredService<IUserService>();
                
                var user = await userService.GetByKeycloakIdAsync(keycloakId);
                
                if (user != null)
                {
                    // Add custom claims
                    claimsIdentity.AddClaim(new Claim("user_id", user.Id.ToString()));
                    
                    if (user.UserType == "BUSINESS")
                    {
                        var business = await userService.GetBusinessByUserIdAsync(user.Id);
                        if (business != null)
                        {
                            claimsIdentity.AddClaim(new Claim("business_id", business.Id.ToString()));
                        }
                    }
                    else if (user.UserType == "PROVIDER")
                    {
                        var provider = await userService.GetProviderByUserIdAsync(user.Id);
                        if (provider != null)
                        {
                            claimsIdentity.AddClaim(new Claim("provider_id", provider.Id.ToString()));
                        }
                    }
                }
            }
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("BusinessOwner", policy =>
        policy.RequireRole("business-admin", "business-user")
              .RequireClaim("business_id"));
    
    options.AddPolicy("ProviderOwner", policy =>
        policy.RequireRole("provider-admin", "provider-driver")
              .RequireClaim("provider_id"));
    
    options.AddPolicy("PlatformAdmin", policy =>
        policy.RequireRole("platform-admin"));
});
```

---

### 4. Angular Integration

#### auth.service.ts
```typescript
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { BehaviorSubject, Observable } from 'rxjs';
import { tap } from 'rxjs/operators';

export interface User {
  id: string;
  email: string;
  roles: string[];
  businessId?: string;
  providerId?: string;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private currentUserSubject = new BehaviorSubject<User | null>(null);
  public currentUser$ = this.currentUserSubject.asObservable();
  
  private accessToken: string | null = null;
  
  constructor(private http: HttpClient) {
    this.loadUser();
  }
  
  login(email: string, password: string): Observable<any> {
    return this.http.post('/auth/login', { email, password }, { withCredentials: true })
      .pipe(
        tap((response: any) => {
          this.accessToken = response.accessToken;
          this.currentUserSubject.next(response.user);
          localStorage.setItem('user', JSON.stringify(response.user));
        })
      );
  }
  
  logout(): Observable<any> {
    return this.http.post('/auth/logout', {}, { withCredentials: true })
      .pipe(
        tap(() => {
          this.accessToken = null;
          this.currentUserSubject.next(null);
          localStorage.removeItem('user');
        })
      );
  }
  
  getAccessToken(): string | null {
    return this.accessToken;
  }
  
  refreshToken(): Observable<any> {
    return this.http.post('/auth/refresh', {}, { withCredentials: true })
      .pipe(
        tap((response: any) => {
          this.accessToken = response.accessToken;
        })
      );
  }
  
  private loadUser(): void {
    const userJson = localStorage.getItem('user');
    if (userJson) {
      this.currentUserSubject.next(JSON.parse(userJson));
    }
  }
  
  hasRole(role: string): boolean {
    const user = this.currentUserSubject.value;
    return user?.roles.includes(role) ?? false;
  }
  
  isBusinessUser(): boolean {
    return this.hasRole('business-admin') || this.hasRole('business-user');
  }
  
  isProviderUser(): boolean {
    return this.hasRole('provider-admin') || this.hasRole('provider-driver');
  }
}
```

#### http.interceptor.ts
```typescript
import { Injectable } from '@angular/core';
import { HttpInterceptor, HttpRequest, HttpHandler, HttpEvent, HttpErrorResponse } from '@angular/common/http';
import { Observable, throwError, BehaviorSubject } from 'rxjs';
import { catchError, filter, take, switchMap } from 'rxjs/operators';
import { AuthService } from './auth.service';

@Injectable()
export class AuthInterceptor implements HttpInterceptor {
  private isRefreshing = false;
  private refreshTokenSubject = new BehaviorSubject<string | null>(null);
  
  constructor(private authService: AuthService) {}
  
  intercept(req: HttpRequest<any>, next: HttpHandler): Observable<HttpEvent<any>> {
    // Add access token to request
    const accessToken = this.authService.getAccessToken();
    
    if (accessToken) {
      req = this.addToken(req, accessToken);
    }
    
    return next.handle(req).pipe(
      catchError((error: HttpErrorResponse) => {
        if (error.status === 401) {
          return this.handle401Error(req, next);
        }
        return throwError(() => error);
      })
    );
  }
  
  private addToken(req: HttpRequest<any>, token: string): HttpRequest<any> {
    return req.clone({
      setHeaders: {
        Authorization: `Bearer ${token}`
      }
    });
  }
  
  private handle401Error(req: HttpRequest<any>, next: HttpHandler): Observable<HttpEvent<any>> {
    if (!this.isRefreshing) {
      this.isRefreshing = true;
      this.refreshTokenSubject.next(null);
      
      return this.authService.refreshToken().pipe(
        switchMap((response: any) => {
          this.isRefreshing = false;
          this.refreshTokenSubject.next(response.accessToken);
          return next.handle(this.addToken(req, response.accessToken));
        }),
        catchError((error) => {
          this.isRefreshing = false;
          this.authService.logout();
          return throwError(() => error);
        })
      );
    } else {
      return this.refreshTokenSubject.pipe(
        filter(token => token != null),
        take(1),
        switchMap(token => next.handle(this.addToken(req, token!)))
      );
    }
  }
}
```

---

## 🔒 Security Best Practices

### 1. Token Storage
- ✅ **Access Token:** In-memory (Angular service)
- ✅ **Refresh Token:** httpOnly cookie (BFF manages)
- ❌ **Never:** localStorage or sessionStorage for refresh tokens

### 2. Token Expiry
- **Access Token:** 15 minutes
- **Refresh Token:** 7 days
- **Absolute Session:** 30 days

### 3. PKCE (Proof Key for Code Exchange)
- Always use PKCE for authorization code flow
- Protects against authorization code interception

### 4. CORS
- Strict origin validation
- Allow credentials for httpOnly cookies

### 5. Rate Limiting
- 100 requests per minute per user
- 10 login attempts per minute per IP

---

## ✅ Business Rules

1. **Session Duration:** 30 days absolute maximum
2. **Token Refresh:** Automatic via BFF
3. **Concurrent Sessions:** Allowed (same user, multiple devices)
4. **Password Policy:**
   - Minimum 8 characters
   - At least 1 uppercase, 1 lowercase, 1 number
   - No common passwords
5. **Account Lockout:** 5 failed attempts = 15-minute lockout
6. **MFA:** Optional for MVP, mandatory for platform admins
7. **Role Assignment:** Manual by platform admin
8. **User Deactivation:** Soft delete (status = INACTIVE)

---

## 📊 Monitoring & Logging

### Key Metrics
- Login success/failure rate
- Token refresh frequency
- Average session duration
- Failed authentication attempts
- Role distribution

### Audit Events
- User login/logout
- Role changes
- Password resets
- Account lockouts
- Token refresh failures

---

**This completes the Auth & Keycloak Module specification!** 🎉

**Total MVP Documentation Progress:** 11 of 17 documents (65% complete)
