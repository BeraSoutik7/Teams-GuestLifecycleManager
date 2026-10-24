<#
================================================================================
SCRIPT NAME : Invoke-TeamsGuestLifecycleGovernor.ps1
DESCRIPTION : Audits, assesses, and remediates stale guest accounts and external
              collaborators across Microsoft Teams channels and Entra ID.
AUTHOR      : Soutik Bera
MODULES REQ : Microsoft.Graph.Authentication, Microsoft.Graph.Users, 
              Microsoft.Graph.Teams, Microsoft.Graph.Groups
================================================================================
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Stale access threshold in days")]
    [int]$InactivityDays = 90,

    [Parameter(Mandatory = $false, HelpMessage = "Action: AuditOnly, RemoveFromTeams, or RevokeGuestAccount")]
    [ValidateSet("AuditOnly", "RemoveFromTeams", "RevokeGuestAccount")]
    [string]$Mode = "AuditOnly",

    [Parameter(Mandatory = $false, HelpMessage = "Directory to store exported governance CSVs")]
    [string]$ReportOutputDir = ".\reports",

    [Parameter(Mandatory = $false, HelpMessage = "List of external domain suffixes to exempt from staling")]
    [string[]]$ExemptDomains = @()
)

$ErrorActionPreference = 'Stop'

# Ensure output directory exists
if (-not (Test-Path -Path $ReportOutputDir)) {
    New-Item -ItemType Directory -Path $ReportOutputDir -Force | Out-Null
}

$Timestamp = (Get-Date -Format "yyyyMMdd-HHmmss")
$CutoffDate = (Get-Date).AddDays(-$InactivityDays)

# ==============================================================================
# SECTION 0: AUTHENTICATION & SESSION PREREQUISITES
# ==============================================================================
Write-Host "[*] Checking Microsoft Graph session..." -ForegroundColor Cyan

$RequiredScopes = @(
    "User.Read.All",
    "AuditLog.Read.All",
    "Team.ReadBasic.All",
    "Group.ReadWrite.All"
)

$context = Get-MgContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "[*] Authenticating to Microsoft Graph..." -ForegroundColor Yellow
    Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
}

# ==============================================================================
# SECTION 1: INVENTORY EXTERNAL GUEST IDENTITIES
# ==============================================================================
Write-Host "`n[*] Discovering guest accounts across tenant Entra ID..." -ForegroundColor Cyan

# Fetch guests with sign-in activity metadata
$GuestUsers = Get-MgUser -Filter "userType eq 'Guest'" -All `
    -Property Id, DisplayName, UserPrincipalName, Mail, ExternalUserState, CreatedDateTime, SignInActivity

Write-Host "[+] Discovered $($GuestUsers.Count) total guest identities." -ForegroundColor Green

if ($GuestUsers.Count -eq 0) {
    Write-Host "[+] No guest accounts present in tenant. Governance check complete." -ForegroundColor Green
    return
}

# ==============================================================================
# SECTION 2: MAP GUEST ASSIGNMENTS ACROSS MICROSOFT TEAMS
# ==============================================================================
Write-Host "`n[*] Mapping guest memberships across Microsoft Teams..." -ForegroundColor Cyan

# Index all Teams
$AllTeams = Get-MgGroup -Filter "resourceProvisioningOptions/Any(x:x eq 'Team')" -All -Property Id, DisplayName

# Map: GuestId -> List of Teams
$GuestTeamMap = @{}
$tCounter = 0

foreach ($team in $AllTeams) {
    $tCounter++
    Write-Progress -Activity "Auditing Teams for External Members" `
                   -Status "Scanning: $($team.DisplayName) ($tCounter of $($AllTeams.Count))" `
                   -PercentComplete (($tCounter / $AllTeams.Count) * 100)

    try {
        # Fetch group members
        $members = Get-MgGroupMember -GroupId $team.Id -All -ErrorAction SilentlyContinue
        foreach ($member in $members) {
            if (-not $GuestTeamMap.ContainsKey($member.Id)) {
                $GuestTeamMap[$member.Id] = [System.Collections.Generic.List[PSCustomObject]]::new()
            }
            $GuestTeamMap[$member.Id].Add([PSCustomObject]@{
                TeamId   = $team.Id
                TeamName = $team.DisplayName
            })
        }
    } catch {
        Write-Warning "[-] Could not enumerate members for team: $($team.DisplayName)"
    }
}
Write-Progress -Activity "Auditing Teams for External Members" -Completed

# ==============================================================================
# SECTION 3: EVALUATE STALE STATUS & LIFECYCLE ACTION
# ==============================================================================
Write-Host "`n[*] Evaluating sign-in posture and inactivity thresholds..." -ForegroundColor Cyan

$GovernanceRecords = [System.Collections.Generic.List[PSCustomObject]]::new()

foreach ($guest in $GuestUsers) {
    # Extract Domain
    $guestEmail = if ($guest.Mail) { $guest.Mail } else { $guest.UserPrincipalName -replace '.*#EXT#@', '' }
    $guestDomain = if ($guestEmail -like "*@*") { $guestEmail.Split('@')[-1] } else { "Unknown" }

    # Check Domain Exemption
    if ($ExemptDomains -contains $guestDomain) {
        Write-Host "[-] Skipping exempt domain guest: $($guest.DisplayName) ($guestDomain)" -ForegroundColor Gray
        continue
    }

    # Evaluate Sign-in activity
    $lastSignIn = [DateTime]::MinValue
    if ($guest.SignInActivity -and $guest.SignInActivity.LastSignInDateTime) {
        $lastSignIn = [DateTime]$guest.SignInActivity.LastSignInDateTime
    } elseif ($guest.CreatedDateTime) {
        # Fall back to creation date if never signed in
        $lastSignIn = [DateTime]$guest.CreatedDateTime
    }

    $daysSinceActivity = if ($lastSignIn -ne [DateTime]::MinValue) {
        [math]::Round(((Get-Date) - $lastSignIn).TotalDays)
    } else {
        999
    }

    $isStale = $daysSinceActivity -ge $InactivityDays
    $assignedTeams = if ($GuestTeamMap.ContainsKey($guest.Id)) { $GuestTeamMap[$guest.Id] } else { @() }
    $teamNames = ($assignedTeams.TeamName) -join " ; "

    $actionTaken = "None (Audit)"

    # Remediation Logic
    if ($isStale) {
        switch ($Mode) {
            "RemoveFromTeams" {
                foreach ($t in $assignedTeams) {
                    if ($PSCmdlet.ShouldProcess("Team: $($t.TeamName)", "Remove Stale Guest '$($guest.DisplayName)'")) {
                        try {
                            Remove-MgGroupMemberByRef -GroupId $t.TeamId -DirectoryObjectId $guest.Id -ErrorAction Stop
                            Write-Host "    [REMOVED] $($guest.DisplayName) from team $($t.TeamName)" -ForegroundColor Yellow
                            $actionTaken = "Removed from Teams"
                        } catch {
                            Write-Warning "[-] Failed removing $($guest.DisplayName) from $($t.TeamName): $_"
                        }
                    }
                }
            }

            "RevokeGuestAccount" {
                if ($PSCmdlet.ShouldProcess($guest.DisplayName, "Disable Account & Revoke Sessions")) {
                    try {
                        # Disable the user account
                        Update-MgUser -UserId $guest.Id -AccountEnabled:$false -ErrorAction Stop
                        # Revoke active sign-in sessions
                        Revoke-MgUserSignInSession -UserId $guest.Id -ErrorAction SilentlyContinue | Out-Null
                        Write-Host "    [DISABLED] Account $($guest.UserPrincipalName) disabled & sessions revoked." -ForegroundColor Red
                        $actionTaken = "Account Disabled & Revoked"
                    } catch {
                        Write-Warning "[-] Failed to disable guest $($guest.DisplayName): $_"
                    }
                }
            }

            Default {
                $actionTaken = "Flagged Stale"
            }
        }
    }

    $GovernanceRecords.Add([PSCustomObject]@{
        DisplayName        = $guest.DisplayName
        UserPrincipalName  = $guest.UserPrincipalName
        Mail               = $guestEmail
        Domain             = $guestDomain
        LastSignInDate     = if ($lastSignIn -ne [DateTime]::MinValue) { $lastSignIn.ToString("yyyy-MM-dd HH:mm:ss") } else { "Never" }
        DaysInactive       = $daysSinceActivity
        IsStale            = $isStale
        TeamCount          = $assignedTeams.Count
        AssignedTeams      = if ($teamNames) { $teamNames } else { "<None / Orphaned Guest>" }
        ActionTaken        = $actionTaken
    })
}

# ==============================================================================
# SECTION 4: OUTPUT & CSV GENERATION
# ==============================================================================
Write-Host "`n[*] Governance Audit Complete!" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------"
Write-Host "Total Guests Evaluated : $($GuestUsers.Count)"
Write-Host "Stale Guests Identified: $(($GovernanceRecords | Where-Object { $_.IsStale -eq $true }).Count)" -ForegroundColor $(if (($GovernanceRecords | Where-Object { $_.IsStale -eq $true }).Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "--------------------------------------------------------`n"

$GovernanceRecords | Format-Table DisplayName, Domain, DaysInactive, IsStale, TeamCount, ActionTaken -AutoSize

$ReportPath = Join-Path $ReportOutputDir "TeamsGuest_LifecycleAudit_$Timestamp.csv"
$GovernanceRecords | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding utf8
Write-Host "[+] Full report saved to: $ReportPath" -ForegroundColor Green