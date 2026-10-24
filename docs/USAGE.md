Usage Examples
1. Read-Only Compliance Audit (Default: 90 Days)

.\src\Invoke-TeamsGuestLifecycleGovernor.ps1 -InactivityDays 90 -Mode AuditOnly

2. Whitelist Partner Domains
PowerShell

.\src\Invoke-TeamsGuestLifecycleGovernor.ps1 -InactivityDays 60 -ExemptDomains "trustedpartner.com", "vendorcorp.com"

3. Dry-Run Simulation of Account Revocation (-WhatIf)

.\src\Invoke-TeamsGuestLifecycleGovernor.ps1 -InactivityDays 90 -Mode RevokeGuestAccount -WhatIf