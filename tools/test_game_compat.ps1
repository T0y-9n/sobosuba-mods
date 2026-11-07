param([string]$Manager = (Join-Path $PSScriptRoot '../manager'))
# Runs the real Test-GameCompatibility from manager/package.ps1 (Windows PowerShell 5.1 or 7).
$ErrorActionPreference = 'Stop'
. (Join-Path $Manager 'package.ps1')
$cases = @(
    @('1.3.10', @('1.3.9'), $true),
    @('1.3.11', @('1.3.9'), $true),
    @('1.3.10', @('1.3.9', '1.3.11'), $true),
    @('1.3.9', @('1.3.10'), $false),
    @('1.3.11', @('1.2.3'), $false),
    @('1.2.3', @('1.3.9'), $false),
    @('1.2.3', @('1.2.3'), $true),
    @('1.3.11', @('1.3'), $false),
    @('1.3.11', @('1.4.0'), $false),
    @('1.3.11', @(), $false),
    @('1.3.11', @(('1.3.9' + "`n")), $false),
    @(("1.3.11" + "`n"), @('1.3.9'), $false)
)
$failed = 0
foreach ($case in $cases) {
    $got = Test-GameCompatibility $case[0] $case[1]
    if ($got -ne $case[2]) {
        $failed++
        Write-Output ("FAIL selected=[{0}] declared=[{1}] got={2} want={3}" -f ($case[0] -replace "`n", '\n'), (($case[1] -join '|') -replace "`n", '\n'), $got, $case[2])
    }
}
Write-Output ("passed={0} failed={1}" -f ($cases.Count - $failed), $failed)
if ($failed) { exit 1 }
