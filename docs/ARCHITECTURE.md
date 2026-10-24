# Architecture Specification: Teams Guest Lifecycle Governor

This document details the identity evaluation pipeline, Graph API property resolution, and lifecycle remediation model implemented in `Invoke-TeamsGuestLifecycleGovernor.ps1`.

---

## 1. Identity Evaluation Pipeline


Entra ID Tenant Directory
          │
          ▼
Get-MgUser (userType eq 'Guest')
  ├── Extract: Id, DisplayName, Mail, ExternalUserState
  └── Ingest: signInActivity.lastSignInDateTime
          │
          ▼
Map Group Memberships (resourceProvisioningOptions: Team)
          │
          ▼
Inactivity Calculation: [DateTime]::UtcNow - LastSignInDateTime
          │
   ┌──────┴──────┐
   ▼             ▼
< Threshold   >= Threshold (Stale)
(Active)         │
                 ├── Domain in Exemptions? ──> Skip
                 └── Remediation Router
                       ├── Mode: AuditOnly
                       ├── Mode: RemoveFromTeams
                       └── Mode: RevokeGuestAccount
