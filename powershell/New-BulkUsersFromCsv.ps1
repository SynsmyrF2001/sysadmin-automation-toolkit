<#
.SYNOPSIS
    Creates user accounts in bulk from a CSV file.

.DESCRIPTION
    Reads a CSV of new users, validates every row before creating
    anything, then creates each account idempotently -- an account
    that already exists is skipped, not an error, so re-running this
    script on the same CSV is safe. Each new account gets a
    cryptographically random, policy-compliant temporary password and
    is forced to change it at next logon. Supports -WhatIf.

.PARAMETER CsvPath
    Path to the input CSV. Required columns: FirstName, LastName,
    SamAccountName, OU (the target OU's full distinguished name). See
    config/sample-new-users.csv for the shape.

.PARAMETER OutputCsv
    Optional path to write a results CSV: one row per input row, with
    Status (Created / Skipped / Failed) and, for created accounts, the
    generated temporary password.

    SECURITY: this file contains real, working temporary passwords in
    plain text if used. Treat it as a secret -- do not email it, do not
    commit it, delete it once the passwords have reached the actual
    users through a separate channel.

.PARAMETER Credential
    Optional PSCredential to run as a different identity.

.EXAMPLE
    .\New-BulkUsersFromCsv.ps1 -CsvPath .\new-users.csv -WhatIf

.EXAMPLE
    .\New-BulkUsersFromCsv.ps1 -CsvPath .\new-users.csv -OutputCsv C:\Reports\created-users.csv

.NOTES
    Design decisions for this script are logged in docs/DECISIONS.md.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$CsvPath,

    [string]$OutputCsv,

    [System.Management.Automation.PSCredential]
    [System.Management.Automation.Credential()]
    $Credential = [System.Management.Automation.PSCredential]::Empty
)

# ---------------------------------------------------------------------------
# Setup: shared logging module
# ---------------------------------------------------------------------------

Import-Module (Join-Path $PSScriptRoot "modules\Logging.psm1") -Force

$LogDir = Join-Path $PSScriptRoot "..\logs"
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir | Out-Null
}
$LogPath = Join-Path $LogDir "bulk-user-creation_$(Get-Date -Format 'yyyyMMdd').log"

Write-Log -LogPath $LogPath -Level INFO -Message "Starting bulk user creation from $CsvPath"

# ---------------------------------------------------------------------------
# Password generation -- cryptographically secure, policy-compliant
# ---------------------------------------------------------------------------

function New-CompliantPassword {
    [CmdletBinding()]
    param([int]$Length = 16)

    # Character sets deliberately exclude visually ambiguous characters
    # (I/O/0/1/l) -- this password gets typed once by a human at first
    # logon, and "is that a capital I or a lowercase l" is a real
    # source of failed-logon friction.
    $Upper   = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $Lower   = "abcdefghijkmnpqrstuvwxyz"
    $Digit   = "23456789"
    $Special = "!@#$%^&*-_=+"
    $All     = $Upper + $Lower + $Digit + $Special

    # Get-Random is a fast PRNG, not a CSPRNG -- fine for picking a
    # random sample size, wrong for anything credential-shaped. Use the
    # actual cryptographic RNG instead.
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    function Get-RandomChar {
        param([string]$Pool)
        $Bytes = [byte[]]::new(4)
        $Rng.GetBytes($Bytes)
        $Index = [System.BitConverter]::ToUInt32($Bytes, 0) % $Pool.Length
        return $Pool[$Index]
    }

    # Guarantee one character from each required class first (the GPO
    # requires complexity), then fill the rest randomly, then shuffle --
    # otherwise the guaranteed characters would always land in the same
    # positions, which is its own small predictability leak.
    $Chars = @(
        Get-RandomChar $Upper
        Get-RandomChar $Lower
        Get-RandomChar $Digit
        Get-RandomChar $Special
    )
    for ($i = $Chars.Count; $i -lt $Length; $i++) {
        $Chars += Get-RandomChar $All
    }

    for ($i = $Chars.Count - 1; $i -gt 0; $i--) {
        $Bytes = [byte[]]::new(4)
        $Rng.GetBytes($Bytes)
        $j = [System.BitConverter]::ToUInt32($Bytes, 0) % ($i + 1)
        $Tmp = $Chars[$i]; $Chars[$i] = $Chars[$j]; $Chars[$j] = $Tmp
    }

    $Rng.Dispose()
    -join $Chars
}

# ---------------------------------------------------------------------------
# Load + validate the WHOLE csv before creating ANYTHING
# ---------------------------------------------------------------------------

try {
    $Rows = @(Import-Csv -Path $CsvPath -ErrorAction Stop)
}
catch {
    Write-Log -LogPath $LogPath -Level ERROR -Message "Could not read CSV at $CsvPath -- $($_.Exception.Message)"
    exit 1
}

if ($Rows.Count -eq 0) {
    Write-Log -LogPath $LogPath -Level ERROR -Message "CSV at $CsvPath has no data rows"
    exit 1
}

$RequiredColumns = @("FirstName", "LastName", "SamAccountName", "OU")
$ActualColumns = $Rows[0].PSObject.Properties.Name
$MissingColumns = $RequiredColumns | Where-Object { $_ -notin $ActualColumns }
if ($MissingColumns) {
    Write-Log -LogPath $LogPath -Level ERROR -Message "CSV missing required column(s): $($MissingColumns -join ', ')"
    exit 1
}

$ValidationErrors = [System.Collections.Generic.List[string]]::new()
$SeenSamAccountNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

for ($i = 0; $i -lt $Rows.Count; $i++) {
    $Row = $Rows[$i]
    $RowNum = $i + 2  # +2: 1-indexed for humans, plus the header row

    foreach ($Col in $RequiredColumns) {
        if ([string]::IsNullOrWhiteSpace($Row.$Col)) {
            $ValidationErrors.Add("Row $RowNum -- $Col is empty")
        }
    }

    if ($Row.SamAccountName) {
        # AD's sAMAccountName is capped at 20 characters -- a legacy
        # pre-Windows 2000 constraint that still applies today.
        if ($Row.SamAccountName.Length -gt 20) {
            $ValidationErrors.Add("Row $RowNum -- SamAccountName '$($Row.SamAccountName)' exceeds 20 characters")
        }
        # Case-insensitive on purpose: AD treats SamAccountName as
        # case-insensitive, so "jsmith" and "JSmith" in the same CSV
        # are the same collision even though they look different here.
        if (-not $SeenSamAccountNames.Add($Row.SamAccountName)) {
            $ValidationErrors.Add("Row $RowNum -- SamAccountName '$($Row.SamAccountName)' is duplicated elsewhere in this CSV")
        }
    }
}

if ($ValidationErrors.Count -gt 0) {
    Write-Log -LogPath $LogPath -Level ERROR -Message "CSV failed validation -- $($ValidationErrors.Count) problem(s) found, nothing created"
    foreach ($Err in $ValidationErrors) {
        Write-Log -LogPath $LogPath -Level ERROR -Message $Err
        Write-Host $Err -ForegroundColor Red
    }
    exit 1
}

Write-Log -LogPath $LogPath -Level INFO -Message "$($Rows.Count) row(s) passed validation"

# ---------------------------------------------------------------------------
# AD module
# ---------------------------------------------------------------------------

try {
    Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
    Write-Log -LogPath $LogPath -Level ERROR -Message "ActiveDirectory module not available: $($_.Exception.Message)"
    exit 1
}

# ---------------------------------------------------------------------------
# Create -- one row at a time; one row failing does not stop the batch
# ---------------------------------------------------------------------------

$Results = [System.Collections.Generic.List[object]]::new()

foreach ($Row in $Rows) {

    $GetParams = @{
        Identity    = $Row.SamAccountName
        ErrorAction = "Stop"
    }
    if ($Credential.UserName) { $GetParams["Credential"] = $Credential }

    # -Identity (not a string-built -Filter) so untrusted CSV data never
    # gets interpolated into a query -- the AD-filter equivalent of
    # concatenating SQL. A specific caught exception type distinguishes
    # "doesn't exist yet" (expected, fine) from any other failure.
    $Exists = $true
    try {
        Get-ADUser @GetParams | Out-Null
    }
    catch [Microsoft.ActiveDirectory.Management.ADIdentityNotFoundException] {
        $Exists = $false
    }
    catch {
        Write-Log -LogPath $LogPath -Level ERROR -Message "$($Row.SamAccountName): existence check failed -- $($_.Exception.Message)"
        $Results.Add([PSCustomObject]@{
            SamAccountName = $Row.SamAccountName
            Status         = "Failed"
            Password       = $null
            Detail         = $_.Exception.Message
        })
        continue
    }

    if ($Exists) {
        Write-Log -LogPath $LogPath -Level WARN -Message "$($Row.SamAccountName): already exists, skipping"
        $Results.Add([PSCustomObject]@{
            SamAccountName = $Row.SamAccountName
            Status         = "Skipped"
            Password       = $null
            Detail         = "Already exists"
        })
        continue
    }

    $PlainPassword = New-CompliantPassword
    $SecurePassword = ConvertTo-SecureString -String $PlainPassword -AsPlainText -Force

    $NewUserParams = @{
        SamAccountName        = $Row.SamAccountName
        Name                  = "$($Row.FirstName) $($Row.LastName)"
        # Explicit -DisplayName, not left to default: New-ADUser does
        # NOT auto-populate DisplayName from -Name -- almost certainly
        # why some existing lab accounts show a blank DisplayName in
        # Get-PasswordExpiryReport's output. Not repeating that here.
        DisplayName           = "$($Row.FirstName) $($Row.LastName)"
        GivenName             = $Row.FirstName
        Surname                = $Row.LastName
        Path                   = $Row.OU
        AccountPassword        = $SecurePassword
        Enabled                = $true
        ChangePasswordAtLogon  = $true
        # Explicit even though it matches the default -- a security-
        # relevant setting should say what it means, not rely on a
        # reader already knowing New-ADUser's default.
        PasswordNeverExpires   = $false
        ErrorAction             = "Stop"
    }
    if ($Credential.UserName) { $NewUserParams["Credential"] = $Credential }

    $Target = "$($Row.SamAccountName) in $($Row.OU)"
    if ($PSCmdlet.ShouldProcess($Target, "Create AD user")) {
        try {
            New-ADUser @NewUserParams
            Write-Log -LogPath $LogPath -Level INFO -Message "$($Row.SamAccountName): created in $($Row.OU)"
            $Results.Add([PSCustomObject]@{
                SamAccountName = $Row.SamAccountName
                Status         = "Created"
                Password       = $PlainPassword
                Detail         = $null
            })
        }
        catch {
            Write-Log -LogPath $LogPath -Level ERROR -Message "$($Row.SamAccountName): creation failed -- $($_.Exception.Message)"
            $Results.Add([PSCustomObject]@{
                SamAccountName = $Row.SamAccountName
                Status         = "Failed"
                Password       = $null
                Detail         = $_.Exception.Message
            })
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$Results | Select-Object SamAccountName, Status, Detail | Format-Table -AutoSize

$CreatedCount = @($Results | Where-Object Status -eq "Created").Count
$SkippedCount = @($Results | Where-Object Status -eq "Skipped").Count
$FailedCount  = @($Results | Where-Object Status -eq "Failed").Count
Write-Log -LogPath $LogPath -Level INFO -Message "Done: $CreatedCount created, $SkippedCount skipped, $FailedCount failed"

if ($OutputCsv) {
    $Results | Export-Csv -Path $OutputCsv -NoTypeInformation
    Write-Log -LogPath $LogPath -Level WARN -Message "Results (including plaintext temp passwords for created accounts) written to $OutputCsv -- treat as a secret"
}

Write-Log -LogPath $LogPath -Level INFO -Message "Bulk user creation complete"
