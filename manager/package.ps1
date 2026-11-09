# Read ZIPs with .NET without executing archive contents.
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
function Test-GameCompatibility([string]$SelectedVersion,[object[]]$DeclaredVersions) {
    if($SelectedVersion -in $DeclaredVersions){return $true}
    if($SelectedVersion -cnotmatch '^1\.3\.(0|[1-9][0-9]*)\z'){return $false}
    $selectedPatch=0
    if(-not [int]::TryParse($Matches[1],[ref]$selectedPatch)){return $false}
    foreach($declared in $DeclaredVersions){
        if($declared -isnot [string] -or $declared -cnotmatch '^1\.3\.(0|[1-9][0-9]*)\z'){continue}
        $declaredPatch=0
        if([int]::TryParse($Matches[1],[ref]$declaredPatch) -and $declaredPatch -le $selectedPatch){return $true}
    }
    return $false
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
function Valid-GameCredit($Credit) {
    if($Credit -isnot [hashtable]){return $false}
    return @($Credit.Keys) -ccontains 'text' -and @($Credit.Keys) -ccontains 'store_url' -and
        $Credit.text -is [string] -and $Credit.store_url -is [string] -and
        $Credit.text -ceq 'sobosuba by keepee' -and $Credit.store_url -ceq 'https://store.steampowered.com/app/1946560/sobosuba'
}
function Assert-PackageCredit($Package) {
    if(Valid-GameCredit $Package.game_credit){return}
    $exceptions=@{
        'sobosandbox|1.3.0'='9cac7816ae47c0236d4477468a7a4d72acd5214399eb9a4f668c6f5644c66c60'
        'greenscreensobos|1.0.0'='493140f1ebc50cba868563b8c7ec8d94dbd6d71a5d888579a64918e1673fca13'
    }
    # Catalog credit supplements only these exact, already published archives.
    if($exceptions[$Package.id+'|'+$Package.version] -ceq $Package.sha256) {
        $path=Join-Path $PSScriptRoot 'catalog.json'
        if([IO.File]::Exists($path)) {
            $catalog=Read-Map ([IO.File]::ReadAllText($path))
            foreach($mod in @($catalog.mods)) {
                if($mod -isnot [hashtable]){continue}
                foreach($candidate in @($mod)+@($mod.variants)) {
                    if($candidate -isnot [hashtable]){continue}
                    $id=if($candidate.ContainsKey('id')){$candidate.id}else{$mod.id}
                    if($id -is [string] -and $candidate.version -is [string] -and $candidate.sha256 -is [string] -and $id -ceq $Package.id -and $candidate.version -ceq $Package.version -and $candidate.sha256 -ceq $Package.sha256 -and (Valid-GameCredit $candidate.game_credit)) {
                        $Package.game_credit=$candidate.game_credit;return
                    }
                }
            }
        }
    }
    Stop-Manager 'credit_required' @($Package.name)
}
function Read-PackageNotes($Metadata,$Files) {
    if($Metadata.ContainsKey('game_credit') -and -not (Valid-GameCredit $Metadata.game_credit)){Stop-Manager 'invalid_metadata'}
    $description=$Metadata.description
    if($description -is [hashtable]){
        if($description.Count -gt 22){Stop-Manager 'invalid_metadata'}
        foreach($language in $description.Keys){
            if($language -cnotmatch '^[a-z]{2,3}(?:_[A-Za-z0-9]{2,8})*$' -or $description[$language] -isnot [string] -or $description[$language].Length -gt 4000){Stop-Manager 'invalid_metadata'}
        }
    } elseif($Metadata.ContainsKey('description') -and ($description -isnot [string] -or $description.Length -gt 4000)){Stop-Manager 'invalid_metadata'}
    if($Metadata.ContainsKey('author') -and ($Metadata.author -isnot [string] -or $Metadata.author.Length -gt 120)){Stop-Manager 'invalid_metadata'}
    foreach($field in @('description','author')){if(-not $Metadata.ContainsKey($field)){$Metadata[$field]=''}}
    if($Metadata.ContainsKey('readme') -and $Metadata.readme -isnot [string]){Stop-Manager 'invalid_metadata'}
    $readme=[string]$Metadata.readme
    $specified=-not [string]::IsNullOrEmpty($readme)
    if(-not $readme){
        foreach($candidate in @('README-en.md','README.md','README-en.txt','README.txt')) {
            if($Files.ContainsKey($candidate)){$readme=$candidate;break}
        }
    }
    $Metadata.readme=$readme;$Metadata.readme_text='';$Metadata.readme_unavailable=$false
    if($readme){
        if(-not (Safe-Relative $readme) -or $readme -notmatch '\.(md|txt)$' -or -not $Files.ContainsKey($readme)){Stop-Manager 'invalid_metadata'}
        try {
            if($Files[$readme].Length -gt 64KB){throw 'readme_size'}
            $Metadata.readme_text=([Text.UTF8Encoding]::new($false,$true)).GetString($Files[$readme]).TrimStart([char]0xFEFF)
        } catch {
            if($specified){Stop-Manager 'invalid_metadata'}
            $Metadata.readme_unavailable=$true
        }
    }
}
# The .NET Framework ZIP reader does not verify CRCs.
# Stream archive contents through the system reader to check CRCs without extraction.
function Check-ArchiveIntegrity([string]$Path) {
    $windows=[IO.Path]::DirectorySeparatorChar -eq '\'
    $tar=if($windows){Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/tar.exe'}else{'/usr/bin/python3'}
    if(-not [IO.File]::Exists($tar)){Stop-Manager 'zip_read' @($Path)}
    $process=[Diagnostics.Process]::new()
    $process.StartInfo.FileName=$tar
    if($windows){$process.StartInfo.Arguments='-xOf "'+[IO.Path]::GetFullPath($Path)+'"'}else{
        $process.StartInfo.ArgumentList.Add('-I')
        $process.StartInfo.ArgumentList.Add('-c')
        $process.StartInfo.ArgumentList.Add('import sys,zipfile; z=zipfile.ZipFile(sys.argv[1]); sys.exit(1 if z.testzip() else 0)')
        $process.StartInfo.ArgumentList.Add([IO.Path]::GetFullPath($Path))
    }
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
        # Reject file and directory name collisions on Windows.
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
                if($name -notmatch '\.(gd|tscn|tres|cfg|json)$') {Stop-Manager 'invalid_metadata'}
                $payload[$name]=$files[$name]
            }
            if(-not $payload.ContainsKey($meta.bootstrap) -or -not $payload.ContainsKey($meta.payload_root+'/'+$meta.entry)) {Stop-Manager 'invalid_metadata'}
        } else {
            # Accept legacy archives without metadata only by their verified hashes.
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
                foreach($name in $files.Keys) {if($name.StartsWith($meta.payload_root+'/')) {if($name -match '\.(md|txt)$'){continue};if($name -notmatch '\.(gd|tres|cfg|json)$') {Stop-Manager 'invalid_metadata'};$payload[$name]=$files[$name]}}
                if(-not $payload.ContainsKey($meta.payload_root+'/'+$meta.entry)) {Stop-Manager 'invalid_metadata'}
            }
        }
        if($meta.name -isnot [string] -or $meta.name.Length -lt 1 -or $meta.name.Length -gt 120 -or $meta.version -isnot [string] -or [string]::IsNullOrWhiteSpace($meta.version) -or $meta.version.Length -gt 80 -or $meta.autoload -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,63}$' -or @($meta.game_versions).Count -eq 0) {Stop-Manager 'invalid_metadata'}
        $meta.game_versions=@($meta.game_versions)
        foreach($v in @($meta.game_versions)) {
            if($v -isnot [string] -or [string]::IsNullOrWhiteSpace($v)){Stop-Manager 'invalid_metadata'}
            if(($v -eq '1.2.3') -ne ($meta.layout -eq 'game-autoload')){Stop-Manager 'invalid_metadata'}
        }
        if(-not $meta.ContainsKey('dependencies')){$meta.dependencies=@()}
        if($meta.dependencies -isnot [array] -or $meta.dependencies.Count -gt 32){Stop-Manager 'invalid_metadata'}
        $dependencyIds=@{}
        foreach($dependency in $meta.dependencies){
            if($dependency -isnot [hashtable] -or -not (Valid-Id $dependency.id) -or $dependency.version -isnot [string] -or [string]::IsNullOrWhiteSpace($dependency.version) -or $dependency.version.Length -gt 80 -or $dependencyIds.ContainsKey($dependency.id)){Stop-Manager 'invalid_metadata'}
            if($dependency.ContainsKey('sha256') -and ($dependency.sha256 -isnot [string] -or $dependency.sha256 -cnotmatch '^[a-fA-F0-9]{64}$')){Stop-Manager 'invalid_metadata'}
            $dependencyIds[$dependency.id]=$true
        }
        Read-PackageNotes $meta $files
        $meta.sha256=$sha;$meta.files=@($payload.Keys | Sort-Object);$meta.contents=$payload
        Assert-PackageCredit $meta
        return $meta
    } catch {
        if($_.Exception.Data['key']) {throw}
        Stop-Manager 'zip_read' @($Path)
    } finally {if($archive) {$archive.Dispose()};$stream.Dispose()}
    } finally {$archiveLock.Dispose()}
}
