param([Parameter(Mandatory=$true)][string]$Zip)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
. (Join-Path $PSScriptRoot '../manager/package.ps1')
try {
    $package=Read-Package ([IO.Path]::GetFullPath($Zip))
    $package.Remove('contents')
    $result=@{ok=$true;data=$package}
} catch {
    $key=$_.Exception.Data['key']
    if(-not $key){$key='io_error'}
    $result=@{ok=$false;error=$key}
}
$json=ConvertTo-Json -InputObject $result -Depth 18 -Compress
[Console]::WriteLine([Text.RegularExpressions.Regex]::Replace($json,'[^\x00-\x7f]',{param($match) '\u{0:x4}' -f [int][char]$match.Value}))
