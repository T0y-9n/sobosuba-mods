param([string]$RequestPath='')
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $PSHOME 'Modules'
. (Join-Path $PSScriptRoot 'package.ps1')
. (Join-Path $PSScriptRoot 'transaction.ps1')
function Json-Bytes($Value) {return ,([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 15)))}
function Get-Target($Request) {
    $game=Full-Path $Request.game_folder
    if(-not [IO.File]::Exists((Join-Path $game 'sobosuba.exe'))) {Stop-Manager 'game_missing' @($game)}
    $version=[string]$Request.game_version
    if($version -notin @('1.2.3','1.3.10')) {Stop-Manager 'unknown_version'}
    $detected='';$build=''
    $steamapps=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($game))
    if([IO.Directory]::Exists($steamapps)) {
        foreach($manifest in [IO.Directory]::GetFiles($steamapps,'appmanifest_*.acf')) {
            $text=[IO.File]::ReadAllText($manifest)
            if($text -match '"installdir"\s+"([^"\r\n]+)"' -and $Matches[1] -eq [IO.Path]::GetFileName($game) -and $text -match '"buildid"\s+"([0-9]+)"') {
                $build=$Matches[1];if($build -eq '26393791'){$detected='1.3.10'}
            }
        }
    }
    if($detected -and $version -ne $detected) {Stop-Manager 'version_mismatch' @($version,$detected)}
    $user=$Request.user_data
    if(-not $user) {$user=Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Godot/app_userdata/sobosuba'}
    $user=Full-Path $user
    # 根とその親のリンクも確認する。ルートの直下を検査用に指定。
    $null=Guard-Path (Join-Path $game '.sobo-mod-manager') $game
    $null=Guard-Path (Join-Path $user '.sobo-mod-manager') $user
    return @{game=$game;user=$user;version=$version;detected=$detected;build=$build;root=$(if($version -eq '1.2.3'){$game}else{$user})}
}
function Read-Receipts([string]$Root) {
    $result=@();$folder=Guard-Path (Join-Path $Root '.sobo-mod-manager/receipts') $Root
    if([IO.Directory]::Exists($folder)) {
        foreach($path in [IO.Directory]::GetFiles($folder,'*.json')) {
            $null=Guard-Path $path $Root
            $r=Read-Map ([IO.File]::ReadAllText($path))
            if(-not (Valid-Id $r.id) -or [IO.Path]::GetFileName($path) -ne $r.id+'.json' -or $r.format -ne 1) {Stop-Manager 'recovery_needed' @($path)}
            $r.root=$Root;$result+=,$r
        }
    }
    return ,$result
}
function Receipt-Path($Root,$Id) {return Guard-Path (Join-Path $Root ('.sobo-mod-manager/receipts/'+$Id+'.json')) $Root}
function Autoload-Entry([string]$Line) {
    if($Line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"\r\n]*)"\s*(?:[;#].*)?$') {
        return @{key=$Matches[1];value=$Matches[2].Replace('\\','/').Replace('\','/')}
    }
    return $null
}
function Public-Config($Target,$Metadata,[bool]$Enable) {
    $path=Guard-Path (Join-Path $Target.game 'override.cfg') $Target.game
    $text=if([IO.File]::Exists($path)){[IO.File]::ReadAllText($path)}else{''}
    $folder=(Join-Path $Target.game ('mods/'+$Metadata.id)).Replace('\','/')
    $expected='*'+$folder+'/'+$Metadata.entry
    $lines=[Collections.Generic.List[string]]::new();$inSection=$false;$insert=-1
    foreach($line in ($text -split '\r?\n')) {
        if($line -match '^\s*\[([^\]]+)\]') {if($inSection -and $insert -lt 0){$insert=$lines.Count};$inSection=$Matches[1] -eq 'autoload'}
        elseif($inSection) {
            $entry=Autoload-Entry $line
            if($entry) {
                if($entry.value.StartsWith('*'+$folder+'/',[StringComparison]::OrdinalIgnoreCase)){continue}
                if($Enable -and $entry.key -eq $Metadata.autoload){Stop-Manager 'file_conflict' @($path)}
            }
        }
        $lines.Add($line)
    }
    if($Enable) {
        if($inSection -and $insert -lt 0){$insert=$lines.Count}
        $entry=$Metadata.autoload+'="'+$expected+'"'
        if($insert -lt 0){$lines.Add('[autoload]');$lines.Add($entry)}else{$lines.Insert($insert,$entry)}
    }
    return @{path=$path;bytes=[Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))}
}
function Is-Enabled($Target,$Receipt) {
    if($Receipt.layout -eq 'user-data-styles') {return (Current-Hash (Guard-Path (Join-Path $Receipt.root $Receipt.bootstrap) $Receipt.root)) -eq $Receipt.bootstrap_hash}
    $path=Join-Path $Target.game 'override.cfg'
    if(-not [IO.File]::Exists($path)){return $false}
    $text=[IO.File]::ReadAllText($path)
    $expected='*'+(Join-Path $Target.game ('mods/'+$Receipt.id+'/'+$Receipt.entry)).Replace('\','/')
    $inAutoload=$false
    foreach($line in ($text -split '\r?\n')) {
        if($line -match '^\s*\[([^\]]+)\]') {$inAutoload=$Matches[1] -eq 'autoload';continue}
        if(-not $inAutoload){continue}
        $item=Autoload-Entry $line
        if($item -and $item.key -eq $Receipt.autoload -and $item.value -eq $expected){return $true}
    }
    return $false
}
function All-Mods($Target) {
    $mods=@();$seen=@{}
    foreach($root in @($Target.game,$Target.user) | Select-Object -Unique) {
        foreach($r in (Read-Receipts $root)) {
            $r.enabled=Is-Enabled $Target $r;$r.compatible=$Target.version -in @($r.game_versions);$r.manual=$false
            $mods+=,$r;$seen[$r.layout+'|'+$r.id]=$true
        }
    }
    # 公開版の手動導入はmod.jsonを読み、コードを実行せずに一覧へ載せる。
    $modsFolder=Guard-Path (Join-Path $Target.game 'mods') $Target.game
    if([IO.Directory]::Exists($modsFolder)) {
        foreach($folder in [IO.Directory]::GetDirectories($modsFolder)) {
            $id=[IO.Path]::GetFileName($folder)
            if(-not (Valid-Id $id) -or $seen.ContainsKey('game-autoload|'+$id)){continue}
            $null=Guard-Path $folder $Target.game
            $metaPath=Guard-Path (Join-Path $folder 'mod.json') $Target.game
            $meta=@{}
            if([IO.File]::Exists($metaPath)) {$meta=Read-Map ([IO.File]::ReadAllText($metaPath))}
            elseif($id -eq 'prime_sobo') {$meta=@{id=$id;name='Prime Sobos';entry='prime_sobo.gd';autoload='PrimeSobo'}}
            elseif($id -eq 'special_sobo') {$meta=@{id=$id;name='Special Sobos';entry='special_sobo.gd';autoload='SpecialSobo'}}
            if($meta.id -ne $id -or -not (Safe-Relative $meta.entry) -or $meta.autoload -cnotmatch '^[A-Za-z_][A-Za-z0-9_]{0,63}$'){continue}
            if(-not [IO.File]::Exists((Guard-Path (Join-Path $folder $meta.entry) $Target.game))){continue}
            $r=@{id=$id;name=$meta.name;version=[string]$meta.version;entry=$meta.entry;autoload=$meta.autoload;manual=$true;compatible=$false;game_versions=@();layout='game-autoload';root=$Target.game}
            $r.enabled=Is-Enabled $Target $r;$mods+=,$r
        }
    }
    foreach($kind in @('prime','special')) {
        $id=$kind+'_sobo';$folder=$kind+'_mod'
        $entry=Guard-Path (Join-Path $Target.user ($folder+'/'+$kind+'_sobo.gd')) $Target.user
        if(-not $seen.ContainsKey('user-data-styles|'+$id) -and [IO.File]::Exists($entry)) {
            $bootstrap=Guard-Path (Join-Path $Target.user ('styles/'+$kind+'_bootstrap.tres')) $Target.user
            $mods+=,@{id=$id;name=$(if($kind -eq 'prime'){'Prime Sobos'}else{'Special Sobos'});version='';manual=$true;enabled=[IO.File]::Exists($bootstrap);compatible=$false;game_versions=@();layout='user-data-styles';root=$Target.user}
        }
    }
    return ,$mods
}
function Owned-Operations($Receipt,[bool]$Remove) {
    $ops=@()
    foreach($relative in $Receipt.hashes.Keys) {
        $path=Guard-Path (Join-Path $Receipt.root $relative) $Receipt.root
        $hash=Current-Hash $path
        if($hash -and $hash -ne $Receipt.hashes[$relative]) {Stop-Manager 'file_conflict' @($path)}
        if($Remove -and $hash){$ops+=,@{path=$path;bytes=$null}}
    }
    return ,$ops
}
function Guard-OtherVersion($Target,[string]$AdoptingId="") {
    foreach($r in (All-Mods $Target)) {
        $selectedLayout=if($Target.version -eq '1.2.3'){'game-autoload'}else{'user-data-styles'}
        if($r.manual -and $r.id -eq $AdoptingId -and $r.layout -eq $selectedLayout){continue}
        if($r.enabled -and -not $r.compatible){Stop-Manager 'other_version_active' @($r.name)}
    }
}
function Install-Package($Target,$Package,$Request) {
    Guard-OtherVersion $Target $Package.id
    if($Request.sha256 -ne $Package.sha256) {Stop-Manager 'zip_changed'}
    if($Target.version -notin @($Package.game_versions)) {Stop-Manager 'version_mismatch' @($Target.version,($Package.game_versions -join ', '))}
    $root=$Target.root;$receiptPath=Receipt-Path $root $Package.id
    foreach($other in (Read-Receipts $root)) {
        if($other.id -eq $Package.id){continue}
        foreach($relative in $Package.files){if($other.hashes.ContainsKey($relative) -or $other.bootstrap -eq $relative){Stop-Manager 'file_conflict' @($relative)}}
    }
    $old=@((Read-Receipts $root) | Where-Object {$_.id -eq $Package.id})
    $enabled=$true;$hashes=@{};$operations=@();$hadUnowned=$false
    if($old.Count) {$old=$old[0];$null=Owned-Operations $old $false;$enabled=Is-Enabled $Target $old}else{$old=$null}
    foreach($relative in $Package.files) {
        $path=Guard-Path (Join-Path $root $relative) $root
        $data=$Package.contents[$relative];$hash=Bytes-Hash $data;$current=Current-Hash $path
        $mutable=$relative -match '\.(cfg|json)$' -and -not $relative.EndsWith('/mod.json')
        if($current -and $mutable){continue}
        if($current -and -not ($old -and ($old.hashes.ContainsKey($relative) -or $relative -eq $old.bootstrap))) {
            if($current -ne $hash){Stop-Manager 'file_conflict' @($path)}
            $hadUnowned=$true
        }
        if($relative -eq $Package.bootstrap){continue}
        $operations+=,@{path=$path;bytes=$data};if(-not $mutable){$hashes[$relative]=$hash}
    }
    if($hadUnowned -and -not $Request.adopt){Stop-Manager 'adopt_required'}
    if($old) {foreach($relative in $old.hashes.Keys) {if($relative -notin @($Package.files)) {$operations+=,@{path=(Guard-Path (Join-Path $root $relative) $root);bytes=$null}}}}
    $receipt=@{format=1;id=$Package.id;name=$Package.name;version=$Package.version;game_versions=@($Package.game_versions);layout=$Package.layout;entry=$Package.entry;autoload=$Package.autoload;hashes=$hashes;source_sha256=$Package.sha256}
    if($Package.layout -eq 'user-data-styles') {
        $receipt.bootstrap=$Package.bootstrap;$receipt.bootstrap_bytes=[Convert]::ToBase64String($Package.contents[$Package.bootstrap]);$receipt.bootstrap_hash=Bytes-Hash $Package.contents[$Package.bootstrap]
        $boot=Guard-Path (Join-Path $root $Package.bootstrap) $root
        $current=Current-Hash $boot
        if($current -and $current -ne $receipt.bootstrap_hash -and (-not $old -or $current -ne $old.bootstrap_hash)){Stop-Manager 'file_conflict' @($boot)}
        if($old -and $old.bootstrap -and $old.bootstrap -ne $Package.bootstrap) {
            $oldBoot=Guard-Path (Join-Path $root $old.bootstrap) $root
            $oldHash=Current-Hash $oldBoot
            if($oldHash -and $oldHash -ne $old.bootstrap_hash){Stop-Manager 'file_conflict' @($oldBoot)}
            if($oldHash){$operations+=,@{path=$oldBoot;bytes=$null}}
        }
        $operations+=,@{path=$boot;bytes=$(if($enabled){$Package.contents[$Package.bootstrap]}else{$null})}
    } else {$operations+=,(Public-Config $Target $Package $enabled)}
    $operations+=,@{path=$receiptPath;bytes=(Json-Bytes $receipt)}
    Write-Transaction $root $operations
}
function Invoke-Manager($Request) {
    $mutex=[Threading.Mutex]::new($false,'Local\SoboModManager-FileOperations')
    $held=$false
    try {
        try {$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){Stop-Manager 'busy'}
        $target=Get-Target $Request
        if($Request.action -eq 'target') {return @{ok=$true;data=$target}}
        $mutating=$Request.action -in @('install','enable','disable','uninstall','recover')
        if($mutating) {
            if(@(Get-Process -Name sobosuba -ErrorAction SilentlyContinue).Count){Stop-Manager 'game_running'}
            foreach($root in @($target.game,$target.user)|Select-Object -Unique){Recover-Transaction $root}
        }
        if($Request.action -eq 'inspect' -or $Request.action -eq 'install') {
            $p=Read-Package $Request.zip
            if($target.version -notin @($p.game_versions)){Stop-Manager 'version_mismatch' @($target.version,($p.game_versions -join ', '))}
            if($Request.action -eq 'install'){Install-Package $target $p $Request}
            $p.Remove('contents');return @{ok=$true;data=$p}
        }
        if($Request.action -eq 'recover'){return @{ok=$true;data=@{}}}
        foreach($root in @($target.game,$target.user)){if([IO.File]::Exists((Guard-Path (Join-Path $root '.sobo-mod-manager/pending.json') $root))){Stop-Manager 'recovery_needed'}}
        $mods=All-Mods $target
        if($Request.action -eq 'list'){return @{ok=$true;data=@{mods=@($mods);target=$target}}}
        $m=@($mods | Where-Object {$_.id -eq $Request.id -and (-not $Request.layout -or $_.layout -eq $Request.layout)})
        if($m.Count -ne 1 -or $m[0].manual){Stop-Manager 'adopt_required'};$m=$m[0]
        if($Request.action -notin @('enable','disable','uninstall')){Stop-Manager 'invalid_request'}
        $enable=$Request.action -eq 'enable'
        if($enable -and -not $m.compatible){Stop-Manager 'version_mismatch' @($target.version,($m.game_versions -join ', '))}
        if($enable){Guard-OtherVersion $target}
        $ops=@();if($Request.action -ne 'disable'){$ops=Owned-Operations $m ($Request.action -eq 'uninstall')}
        if($enable) {foreach($relative in $m.hashes.Keys){if(-not [IO.File]::Exists((Join-Path $m.root $relative))){Stop-Manager 'file_conflict' @($relative)}}}
        if($m.layout -eq 'user-data-styles') {
            $boot=Guard-Path (Join-Path $m.root $m.bootstrap) $m.root;$current=Current-Hash $boot
            if($current -and $current -ne $m.bootstrap_hash){Stop-Manager 'file_conflict' @($boot)}
            $ops+=,@{path=$boot;bytes=$(if($enable){[Convert]::FromBase64String($m.bootstrap_bytes)}else{$null})}
        } else {$ops+=,(Public-Config $target $m $enable)}
        if($Request.action -eq 'uninstall'){$ops+=,@{path=(Receipt-Path $m.root $m.id);bytes=$null}}
        Write-Transaction $m.root $ops
        return @{ok=$true;data=@{}}
    } catch {
        $key=$_.Exception.Data['key'];$arguments=$_.Exception.Data['arguments']
        if(-not $key){$key='io_error';$arguments=@($_.Exception.Message)}
        return @{ok=$false;error=$key;args=@($arguments)}
    } finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
if($RequestPath) {
    [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
    try {$result=Invoke-Manager (Read-Map ([IO.File]::ReadAllText($RequestPath)));$result|ConvertTo-Json -Depth 18 -Compress} catch {@{ok=$false;error='invalid_request';args=@()}|ConvertTo-Json -Compress}
}
