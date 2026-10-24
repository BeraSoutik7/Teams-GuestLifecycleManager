# Teams-GuestLifecycleManager

[![PowerShell](https://img.shields.io/badge/PowerShell-7.2+-blue.svg)](https://github.com/PowerShell/PowerShell)
[![Platform](https://img.shields.io/badge/Platform-Microsoft%20Teams%20%7C%20Entra%20ID-0078D4.svg)](https://learn.microsoft.com/microsoftteams/)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

An enterprise governance and auto-staling engine for **Microsoft Teams Guest Users and External Federation Collaborators**.

`Teams-GuestLifecycleManager` discovers external guest identities across your Microsoft 365 tenant, maps their memberships across Teams channels, audits Entra ID sign-in activity (`signInActivity`), and enforces lifecycle governance actions to remediate stale external access.

---

## 🎯 What Problem Does It Solve?

External collaboration in Microsoft Teams often leads to unmonitored identity sprawl:
* Contractors, vendors, and external partners complete engagements, but their guest accounts remain active in Entra ID indefinitely.
* Former guests retain access to confidential team files, chat history, and internal SharePoint resources.
* IT teams lack unified point-in-time visibility into which teams an external guest belongs to versus when they last authenticated.

**Teams-GuestLifecycleManager** bridges this operational gap by cataloging all external identities, calculating real days of inactivity, and providing safe, multi-tiered remediation.

---

## 🚀 Key Features

* **Tenant-Wide Guest Inventory:** Extracts all Entra ID accounts where `userType eq 'Guest'`, isolating guest domains and invitation states.
* **Full Teams Membership Mapping:** Traverses all Microsoft 365 Groups provisioned as Teams to map which teams each external identity belongs to.
* **Sign-In Posture Auditing:** Evaluates real-time Entra ID `signInActivity` timestamps against configurable inactivity thresholds (e.g., 90 days).
* **Multi-Tier Execution Modes:**
  * `AuditOnly`: Read-only discovery and CSV export.
  * `RemoveFromTeams`: Ejects stale guests from Teams while preserving directory objects.
  * `RevokeGuestAccount`: Disables Entra ID guest accounts and forcibly terminates active user sessions.
* **Domain Exemption Support:** Whitelist strategic external partner domains from staling rules via `-ExemptDomains`.
* **PowerShell `-WhatIf` Safety:** Full simulation guardrail support (`SupportsShouldProcess`).

---

## 📋 Prerequisites & Permissions

### Modules Required
* `Microsoft.Graph.Authentication`
* `Microsoft.Graph.Users`
* `Microsoft.Graph.Teams`
* `Microsoft.Graph.Groups`

```powershell
Install-Module -Name Microsoft.Graph.Authentication -Scope CurrentUser -Repository PSGallery -Force
Install-Module -Name Microsoft.Graph.Users -Scope CurrentUser -Repository PSGallery -Force
Install-Module -Name Microsoft.Graph.Teams -Scope CurrentUser -Repository PSGallery -Force
Install-Module -Name Microsoft.Graph.Groups -Scope CurrentUser -Repository PSGallery -Force

Usage Examples
1. Read-Only Compliance Audit (Default: 90 Days)

.\src\Invoke-TeamsGuestLifecycleGovernor.ps1 -InactivityDays 90 -Mode AuditOnly

2. Whitelist Partner Domains
PowerShell

.\src\Invoke-TeamsGuestLifecycleGovernor.ps1 -InactivityDays 60 -ExemptDomains "trustedpartner.com", "vendorcorp.com"

3. Dry-Run Simulation of Account Revocation (-WhatIf)

.\src\Invoke-TeamsGuestLifecycleGovernor.ps1 -InactivityDays 90 -Mode RevokeGuestAccount -WhatIf