param([Parameter(Mandatory=$true)][string]$Zip)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../manager/package.ps1')
try {
    $package=Read-Package ([IO.Path]::GetFullPath($Zip))
    if(-not (Valid-GameCredit $package.game_credit)){Stop-Manager 'credit_required'}
    [ordered]@{
        id=$package.id
        version=$package.version
        sha256=$package.sha256
        game_versions=$package.game_versions
        game_credit=$package.game_credit
    } | ConvertTo-Json -Depth 6
} catch {
    Write-Error ('MOD release rejected: '+$_.Exception.Message)
    exit 1
}
