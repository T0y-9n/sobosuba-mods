#requires -Version 7.2
[CmdletBinding(DefaultParameterSetName = 'Plan')]
param(
    [Parameter(ParameterSetName = 'Plan')][switch]$DryRun,
    [Parameter(Mandatory, ParameterSetName = 'Run')][switch]$Execute,
    [string]$AccountId = '',
    [string]$HealthUrl = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# This return is deliberately before tool discovery, reads, random generation,
# environment mutation, and all network/file operations. DryRun needs no tools.
if (-not $Execute) {
    Write-Output 'DryRun: no commands executed, no files changed, no connections.'
    Write-Output '1. wrangler whoami --json (confirm the selected account; login separately if needed)'
    Write-Output '2. wrangler d1 list --json; if absent: wrangler d1 create prime-sobo-production --update-config=false; list again'
    Write-Output '3. write wrangler.production.toml (ignored by Git, database id only, no secret)'
    Write-Output '4. wrangler d1 migrations apply prime-sobo-production --remote --config wrangler.production.toml'
    Write-Output '5. generate secret in memory -> wrangler secret put IP_HASH_SECRET --config wrangler.production.toml (stdin only)'
    Write-Output '6. wrangler deploy --config wrangler.production.toml'
    Write-Output '7. GET <approved HTTPS worker origin>/v1/health'
    return
}

# Execute is an operator-only gate. It has not been exercised by local tests.
if ($AccountId -cnotmatch '^[0-9a-f]{32}$') { throw 'Execute requires the approved -AccountId (32 lowercase hex characters).' }
$health = $null
if (-not [Uri]::TryCreate($HealthUrl, [UriKind]::Absolute, [ref]$health) -or
    $health.Scheme -ne 'https' -or $health.UserInfo -or $health.Query -or $health.Fragment -or
    $health.AbsolutePath -ne '/v1/health' -or -not $health.IsDefaultPort) {
    throw 'Execute requires the approved -HealthUrl: https://<worker host>/v1/health.'
}

Set-PSDebug -Off
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$serverRoot = Split-Path -Parent $PSScriptRoot
$production = Join-Path $serverRoot 'wrangler.production.toml'
$node = (Get-Command node -CommandType Application -ErrorAction Stop).Source
$wrangler = Join-Path $serverRoot 'node_modules/wrangler/bin/wrangler.js'
if (-not (Test-Path -LiteralPath $wrangler -PathType Leaf)) { throw 'Run npm ci --ignore-scripts in server first.' }

function Invoke-Wrangler([string[]]$CommandArgs) {
    # Never call this helper with secret material in arguments.
    $output = & $node $wrangler @CommandArgs
    if ($LASTEXITCODE -ne 0) { throw "Wrangler failed at $($CommandArgs[0]); stopped before the next step." }
    return ($output -join "`n")
}

$oldAccount = $env:CLOUDFLARE_ACCOUNT_ID
$oldMetrics = $env:WRANGLER_SEND_METRICS
$oldBrowser = $env:BROWSER
$oldCI = $env:CI
$oldSanitize = $env:WRANGLER_LOG_SANITIZE
$secretBytes = $null
$secret = $null
Push-Location -LiteralPath $serverRoot
try {
    $env:CLOUDFLARE_ACCOUNT_ID = $AccountId
    $env:WRANGLER_SEND_METRICS = 'false'
    $env:BROWSER = 'none'
    $env:CI = 'true'
    # Wrangler logs API bodies at debug level if sanitization is disabled.
    $env:WRANGLER_LOG_SANITIZE = 'true'

    Write-Output '1/7 Checking authentication (no automatic login).'
    $identity = (Invoke-Wrangler -CommandArgs @('whoami', '--json')) | ConvertFrom-Json
    if (-not (@($identity.accounts | Where-Object { $_.id -ceq $AccountId }).Count)) {
        throw 'The approved account was not found in whoami. Login separately and review the account.'
    }

    Write-Output '2/7 Finding or creating prime-sobo-production.'
    $databases = (Invoke-Wrangler -CommandArgs @('d1', 'list', '--json')) | ConvertFrom-Json
    $database = @($databases | Where-Object { $_.name -ceq 'prime-sobo-production' })
    if ($database.Count -eq 0) {
        Invoke-Wrangler -CommandArgs @('d1', 'create', 'prime-sobo-production', '--update-config=false') | Out-Null
        $databases = (Invoke-Wrangler -CommandArgs @('d1', 'list', '--json')) | ConvertFrom-Json
        $database = @($databases | Where-Object { $_.name -ceq 'prime-sobo-production' })
    }
    if ($database.Count -ne 1 -or $database[0].uuid -cnotmatch '^[0-9a-f-]{36}$') {
        throw 'Could not uniquely resolve the production database id.'
    }

    Write-Output '3/7 Writing ignored production config (no secret).'
    $config = [IO.File]::ReadAllText((Join-Path $serverRoot 'wrangler.toml'))
    $config = $config.Replace('name = "sobosuba-ranking-local"', 'name = "sobosuba-ranking"')
    $config = $config.Replace('workers_dev = false', 'workers_dev = true')
    $config = $config.Replace('database_name = "prime-sobo-local"', 'database_name = "prime-sobo-production"')
    $config = $config.Replace('database_id = "local-only"', ('database_id = "' + $database[0].uuid + '"'))
    $config = "account_id = `"$AccountId`"`n" + $config
    if ($config.Contains('local-only')) { throw 'Local database placeholder remains; inspect wrangler.toml before deployment.' }
    [IO.File]::WriteAllText($production, $config, [Text.UTF8Encoding]::new($false))

    Write-Output '4/7 Applying remote migrations.'
    Invoke-Wrangler -CommandArgs @('d1', 'migrations', 'apply', 'prime-sobo-production', '--remote', '--config', $production) | Out-Null

    Write-Output '5/7 Setting IP_HASH_SECRET from memory (value suppressed).'
    $secretBytes = [byte[]]::new(32)
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($secretBytes) } finally { $rng.Dispose() }
    $secret = [Convert]::ToHexString($secretBytes).ToLowerInvariant()
    # Redirect both streams: even child diagnostics must not disclose stdin.
    $secret | & $node $wrangler secret put IP_HASH_SECRET --config $production 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Secret registration failed; value suppressed. Deployment stopped.' }
    $secret = $null
    [Array]::Clear($secretBytes, 0, $secretBytes.Length)

    Write-Output '6/7 Deploying the approved Worker.'
    Invoke-Wrangler -CommandArgs @('deploy', '--config', $production) | Out-Null

    Write-Output '7/7 Checking production health.'
    $response = Invoke-WebRequest -Uri $health.AbsoluteUri -Method Get -TimeoutSec 15 -MaximumRedirection 0
    $body = $response.Content | ConvertFrom-Json
    if ($response.StatusCode -ne 200 -or $body.ok -ne $true) { throw 'Production health did not return HTTP 200 / ok=true.' }
    Write-Output 'Production health returned HTTP 200 / ok=true. Game acceptance is separate.'
} finally {
    $secret = $null
    if ($null -ne $secretBytes) { [Array]::Clear($secretBytes, 0, $secretBytes.Length) }
    $env:CLOUDFLARE_ACCOUNT_ID = $oldAccount
    $env:WRANGLER_SEND_METRICS = $oldMetrics
    $env:BROWSER = $oldBrowser
    $env:CI = $oldCI
    $env:WRANGLER_LOG_SANITIZE = $oldSanitize
    Pop-Location
}
