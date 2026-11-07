$script:managerWindows=[IO.Path]::DirectorySeparatorChar -eq '\'
$script:pathComparison=if($script:managerWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
function Full-Path([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path)
    if($full -eq [IO.Path]::GetPathRoot($full)){return $full}
    return $full.TrimEnd([IO.Path]::DirectorySeparatorChar)
}
function Guard-Path([string]$Path,[string]$Root) {
    $full=Full-Path $Path; $base=Full-Path $Root
    if(-not $full.StartsWith($base.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar,$script:pathComparison)) {Stop-Manager 'unsafe_path' @($full)}
    $part=$full
    while($part) {
        if(Test-Path -LiteralPath $part) {
            $item=Get-Item -LiteralPath $part -Force
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {Stop-Manager 'unsafe_path' @($part)}
        }
        $parent=[IO.Path]::GetDirectoryName($part);if($parent -eq $part) {break};$part=$parent
    }
    return $full
}
function Atomic-Write([string]$Path,[byte[]]$Bytes) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $mode=$null
    if(-not $script:managerWindows -and [IO.File]::Exists($Path)){$mode=[IO.File]::GetUnixFileMode($Path)}
    $tmp=$Path+'.sobo-'+[guid]::NewGuid().ToString('N')+'.tmp'
    $stream=[IO.FileStream]::new($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    try {
        if($null -ne $mode){[IO.File]::SetUnixFileMode($tmp,$mode)}
        if([IO.File]::Exists($Path)) {[IO.File]::Replace($tmp,$Path,[NullString]::Value)}else{[IO.File]::Move($tmp,$Path)}
    } finally {if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
}
function Current-Hash([string]$Path) {
    if([IO.File]::Exists($Path)) {return Bytes-Hash ([IO.File]::ReadAllBytes($Path))}
    if([IO.Directory]::Exists($Path)) {Stop-Manager 'file_conflict' @($Path)}
    return ''
}
function Recover-Transaction([string]$Root) {
    $journal=Guard-Path (Join-Path $Root '.sobo-mod-manager/pending.json') $Root
    if(-not [IO.File]::Exists($journal)) {return}
    $record=Read-Map ([IO.File]::ReadAllText($journal))
    if($record.format -ne 1 -or $record.root -ne (Full-Path $Root) -or @($record.operations).Count -gt 1024) {Stop-Manager 'recovery_needed' @($journal)}
    foreach($item in @($record.operations)) {
        $path=Guard-Path $item.path $Root
        $current=Current-Hash $path
        if($current -ne $item.old_hash -and $current -ne $item.new_hash) {Stop-Manager 'recovery_needed' @($path)}
    }
    $operations=@($record.operations);[array]::Reverse($operations)
    foreach($item in $operations) {
        $path=Guard-Path $item.path $Root
        if((Current-Hash $path) -eq $item.old_hash) {continue}
        if($item.existed) {Atomic-Write $path ([Convert]::FromBase64String($item.old))} elseif([IO.File]::Exists($path)) {[IO.File]::Delete($path)}
    }
    [IO.File]::Delete($journal)
}
function Write-Transaction([string]$Root,[object[]]$Operations) {
    if($Operations.Count -gt 1024){Stop-Manager 'dependency_limit'}
    Recover-Transaction $Root
    $journal=Guard-Path (Join-Path $Root '.sobo-mod-manager/pending.json') $Root
    $items=@();$seen=@{}
    foreach($op in $Operations) {
        $path=Guard-Path $op.path $Root
        if($seen.ContainsKey($path)) {Stop-Manager 'file_conflict' @($path)};$seen[$path]=$true
        $existed=[IO.File]::Exists($path)
        $old=[byte[]]@();if($existed){$old=[IO.File]::ReadAllBytes($path)}
        $items+=@{path=$path;existed=$existed;old=[Convert]::ToBase64String($old);old_hash=$(if($existed){Bytes-Hash $old}else{''});new_hash=$(if($null -ne $op.bytes){Bytes-Hash $op.bytes}else{''})}
    }
    $record=@{format=1;root=(Full-Path $Root);operations=$items}
    Atomic-Write $journal ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $record -Depth 12)))
    try {
        for($i=0;$i -lt $Operations.Count;$i++) {
            $path=Guard-Path $Operations[$i].path $Root
            if((Current-Hash $path) -ne $items[$i].old_hash) {Stop-Manager 'file_conflict' @($path)}
            if($null -eq $Operations[$i].bytes) {if([IO.File]::Exists($path)){[IO.File]::Delete($path)}}else{Atomic-Write $path $Operations[$i].bytes}
        }
        [IO.File]::Delete($journal)
    } catch {
        try {Recover-Transaction $Root} catch {Stop-Manager 'recovery_needed' @($journal)}
        throw
    }
}
