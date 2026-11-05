# Windows標準.NETによるZIP読取り。ZIP内のコードは実行しない。
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
function Stop-Manager([string]$Key, [object[]]$Arguments=@()) {
    $e = [Exception]::new($Key)
    $e.Data['key']=$Key; $e.Data['arguments']=$Arguments
    throw $e
}
function Read-Map([string]$Text) {
    function Convert-Map($Value) {
        if ($null -eq $Value) {return $null}
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $result=@{}; foreach($p in $Value.PSObject.Properties) {$result[$p.Name]=Convert-Map $p.Value};return $result
        }
        if ($Value -is [array]) {return ,@($Value | ForEach-Object {Convert-Map $_})}
        return $Value
    }
    try {return Convert-Map (ConvertFrom-Json -InputObject $Text)} catch {Stop-Manager 'invalid_metadata'}
}
function Bytes-Hash([byte[]]$Bytes) {
    $hash=[Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($hash.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant()} finally {$hash.Dispose()}
}
function Safe-Relative([string]$Name) {
    if([string]::IsNullOrWhiteSpace($Name) -or $Name.Length -gt 200 -or $Name -match '[\\:\x00-\x1f<>"|?*]' -or $Name.StartsWith('/')) {return $false}
    foreach($part in $Name.Split('/')) {
        if($part -in @('','..','.') -or $part.EndsWith('.') -or $part.EndsWith(' ') -or $part -match '^(?i:con|prn|aux|nul|com[0-9¹²³]|lpt[0-9¹²³])(?:\.|$)') {return $false}
    }
    return $true
}
function Valid-Id([string]$Id) {return $Id -cmatch '^[a-z][a-z0-9_]{0,63}$' -and (Safe-Relative $Id)}
# .NET FrameworkのZIP展開はCRCを照合しない。Windows標準tarで全体を
# 標準出力へ読み流し、CRC不一致を含む破損を検査する。ディスクへ展開しない。
function Check-ArchiveIntegrity([string]$Path) {
    $tar=Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/tar.exe'
    if(-not [IO.File]::Exists($tar)){Stop-Manager 'zip_read' @($Path)}
    $process=[Diagnostics.Process]::new()
    $process.StartInfo.FileName=$tar
    $process.StartInfo.Arguments='-xOf "'+[IO.Path]::GetFullPath($Path)+'"'
    $process.StartInfo.UseShellExecute=$false
    $process.StartInfo.CreateNoWindow=$true
    $process.StartInfo.RedirectStandardOutput=$true
    $process.StartInfo.RedirectStandardError=$true
    try {
        $null=$process.Start()
        $drain=$process.StandardOutput.BaseStream.CopyToAsync([IO.Stream]::Null)
        $errors=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(15000)){$process.Kill();$process.WaitForExit();Stop-Manager 'zip_read' @($Path)}
        $null=$drain.GetAwaiter().GetResult();$null=$errors.GetAwaiter().GetResult()
        if($process.ExitCode -ne 0){Stop-Manager 'zip_read' @($Path)}
    } finally {$process.Dispose()}
}
function Read-Package([string]$Path) {
    if(-not [IO.File]::Exists($Path)) {Stop-Manager 'zip_read' @($Path)}
    $archiveLock=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
    if($archiveLock.Length -gt 32MB) {Stop-Manager 'unsafe_zip'}
    $bytes=[IO.File]::ReadAllBytes($Path)
    $sha=Bytes-Hash $bytes
    $stream=[IO.MemoryStream]::new($bytes,$false)
    $archive=$null
    try {
        $archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read)
        if($archive.Entries.Count -gt 512) {Stop-Manager 'unsafe_zip'}
        $names=@{}; $files=@{}; $total=0L
        foreach($entry in $archive.Entries) {
            $name=$entry.FullName.TrimEnd('/')
            if(-not (Safe-Relative $name) -or $names.ContainsKey($name)) {Stop-Manager 'unsafe_zip' @($entry.FullName)}
            $names[$name]=$true
            $kind=($entry.ExternalAttributes -shr 16) -band 0xF000
            if($kind -eq 0xA000 -or ($entry.ExternalAttributes -band 0x400) -ne 0) {Stop-Manager 'unsafe_zip' @($name)}
            if($entry.FullName.EndsWith('/')) {continue}
            if($entry.Length -gt 16MB) {Stop-Manager 'unsafe_zip'}
            $total+=$entry.Length; if($total -gt 64MB) {Stop-Manager 'unsafe_zip'}
            $input=$entry.Open();$buffer=[IO.MemoryStream]::new()
            try {
                $block=[byte[]]::new(65536)
                while(($count=$input.Read($block,0,$block.Length)) -gt 0) {
                    if($buffer.Length+$count -gt $entry.Length -or $buffer.Length+$count -gt 16MB){Stop-Manager 'unsafe_zip'}
                    $buffer.Write($block,0,$count)
                }
                $data=$buffer.ToArray()
            } finally {$input.Dispose();$buffer.Dispose()}
            if($data.Length -ne $entry.Length) {Stop-Manager 'unsafe_zip'}
            $files[$name]=$data
        }
        # Windows上でファイルとフォルダが同名になるZIPも拒否。
        foreach($name in $files.Keys) {
            $parent=[IO.Path]::GetDirectoryName($name).Replace('\','/')
            while($parent) {if($files.ContainsKey($parent)) {Stop-Manager 'unsafe_zip'};$parent=[IO.Path]::GetDirectoryName($parent).Replace('\','/')}
        }
        Check-ArchiveIntegrity $Path
        $meta=@{}; $payload=@{}
        if($files.ContainsKey('mod-package.json')) {
            $meta=Read-Map ([Text.Encoding]::UTF8.GetString($files['mod-package.json']))
            if($meta.format_version -ne 1 -or $meta.install_layout -ne 'user-data-styles' -or -not (Valid-Id $meta.id) -or -not (Valid-Id $meta.payload_root) -or -not (Safe-Relative $meta.entry) -or $meta.entry -notmatch '\.gd$' -or $meta.bootstrap -cnotmatch '^styles/[a-z][a-z0-9_]*_bootstrap\.tres$') {Stop-Manager 'invalid_metadata'}
            $meta.layout='user-data-styles'
            foreach($name in @($meta.files)) {
                if($name -isnot [string] -or -not (Safe-Relative $name) -or -not $files.ContainsKey($name) -or ($name -ne $meta.bootstrap -and -not $name.StartsWith($meta.payload_root+'/')) -or $payload.ContainsKey($name)) {Stop-Manager 'invalid_metadata'}
                if($name -notmatch '\.(gd|tres|cfg|json)$') {Stop-Manager 'invalid_metadata'}
                $payload[$name]=$files[$name]
            }
            if(-not $payload.ContainsKey($meta.bootstrap) -or -not $payload.ContainsKey($meta.payload_root+'/'+$meta.entry)) {Stop-Manager 'invalid_metadata'}
        } else {
            # 既配布で定義書のないZIPは、確認した同一バイト列のみ受け付ける。
            $known=@{
                '1afc76d6d47c0c80de047c9b3ffc730f293b289b49177ff5a0329f19b3c0f461'=@{id='special_sobo';name='Special Sobos';version='1.3.10-magnet-tuning';game_versions=@('1.3.10');layout='user-data-styles';payload_root='special_mod';entry='special_sobo.gd';autoload='SpecialSobo';bootstrap='styles/special_bootstrap.tres'}
                '70f6bdf97ca24536351381ba71119a46fbf12b52d4b69d98335ecb543537f890'=@{id='special_sobo';name='Special Sobos';version='1.3.10-alpha';game_versions=@('1.3.10');layout='user-data-styles';payload_root='special_mod';entry='special_sobo.gd';autoload='SpecialSobo';bootstrap='styles/special_bootstrap.tres'}
            }
            if($known.ContainsKey($sha)) {
                $meta=$known[$sha]
                foreach($name in $files.Keys) {if($name.StartsWith($meta.payload_root+'/') -or $name -eq $meta.bootstrap) {$payload[$name]=$files[$name]}}
            } else {
                $metadataNames=@($files.Keys | Where-Object {$_ -cmatch '^mods/[a-z][a-z0-9_]*/mod\.json$'})
                if($metadataNames.Count -eq 1) {
                    $meta=Read-Map ([Text.Encoding]::UTF8.GetString($files[$metadataNames[0]]))
                    if(-not (Valid-Id $meta.id) -or $metadataNames[0] -cne ('mods/'+$meta.id+'/mod.json') -or -not (Safe-Relative $meta.entry) -or $meta.entry -notmatch '\.gd$') {Stop-Manager 'invalid_metadata'}
                    $meta.game_versions=@($meta.game_version); $meta.layout='game-autoload';$meta.payload_root='mods/'+$meta.id
                } elseif($sha -eq '7a7130cf61b2e494d6208446c149cf96b1379e85f0cc6b84dfb2eaacc3115df0') {
                    $meta=@{id='prime_sobo';name='Prime Sobos';version='1.2.3-1.0.2';game_versions=@('1.2.3');layout='game-autoload';payload_root='mods/prime_sobo';entry='prime_sobo.gd';autoload='PrimeSobo'}
                } else {Stop-Manager 'invalid_metadata'}
                foreach($name in $files.Keys) {if($name.StartsWith($meta.payload_root+'/')) {if($name -notmatch '\.(gd|tres|cfg|json)$') {Stop-Manager 'invalid_metadata'};$payload[$name]=$files[$name]}}
                if(-not $payload.ContainsKey($meta.payload_root+'/'+$meta.entry)) {Stop-Manager 'invalid_metadata'}
            }
        }
        if($meta.name -isnot [string] -or $meta.name.Length -lt 1 -or $meta.name.Length -gt 120 -or $meta.version -isnot [string] -or $meta.version.Length -gt 80 -or $meta.autoload -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,63}$' -or @($meta.game_versions).Count -eq 0) {Stop-Manager 'invalid_metadata'}
        foreach($v in @($meta.game_versions)) {if($v -notin @('1.2.3','1.3.10')) {Stop-Manager 'unknown_version'};if(($v -eq '1.2.3') -ne ($meta.layout -eq 'game-autoload')) {Stop-Manager 'invalid_metadata'}}
        $meta.sha256=$sha;$meta.files=@($payload.Keys | Sort-Object);$meta.contents=$payload
        return $meta
    } catch {
        if($_.Exception.Data['key']) {throw}
        Stop-Manager 'zip_read' @($Path)
    } finally {if($archive) {$archive.Dispose()};$stream.Dispose()}
    } finally {$archiveLock.Dispose()}
}
