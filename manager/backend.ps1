param([string]$RequestPath='')
$ErrorActionPreference='Stop'
$env:PSModulePath=Join-Path $PSHOME 'Modules'
. (Join-Path $PSScriptRoot 'package.ps1')
. (Join-Path $PSScriptRoot 'transaction.ps1')
. (Join-Path $PSScriptRoot 'dependencies.ps1')
function Json-Bytes($Value) {return ,([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 15)))}
function Get-Target($Request) {
    $game=Full-Path $Request.game_folder
    $gameNames=if($script:managerWindows){@('sobosuba.exe')}else{@('sobosuba.x86_64','sobosuba')}
    if(-not @($gameNames|Where-Object {[IO.File]::Exists((Join-Path $game $_))}).Count){Stop-Manager 'game_missing' @($game)}
    $version=[string]$Request.game_version
    if($version -notin @('1.2.3','1.3.10','1.3.11')) {Stop-Manager 'unknown_version'}
    $detected='';$build=''
    $steamapps=[IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($game))
    if([IO.Directory]::Exists($steamapps)) {
        foreach($manifest in [IO.Directory]::GetFiles($steamapps,'appmanifest_*.acf')) {
            $text=[IO.File]::ReadAllText($manifest)
            if($text -match '"installdir"\s+"([^"\r\n]+)"' -and $Matches[1] -eq [IO.Path]::GetFileName($game) -and $text -match '"buildid"\s+"([0-9]+)"') {
                $build=$Matches[1]
                $known=@{ '26393791'='1.3.10'; '26465074'='1.3.11' }
                if($Request.game_builds -is [hashtable]){
                    foreach($key in $Request.game_builds.Keys){
                        $named=[string]$Request.game_builds[$key]
                        if($named -in @('1.2.3','1.3.10','1.3.11')){$known[[string]$key]=$named}
                    }
                }
                if($known.ContainsKey($build)){$detected=$known[$build]}
            }
        }
    }
    if($Request.action -eq 'detect' -and $detected){$version=$detected}
    if($detected -and $version -ne $detected) {Stop-Manager 'version_mismatch' @($version,$detected)}
    $user=$Request.user_data
    if(-not $user){
        if($script:managerWindows){$user=Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'Godot/app_userdata/sobosuba'}else{
            $dataRoot=if($env:XDG_DATA_HOME){$env:XDG_DATA_HOME}else{Join-Path $env:HOME '.local/share'}
            $user=Join-Path $dataRoot 'godot/app_userdata/sobosuba'
        }
    }
    $user=Full-Path $user
    # Check links at the root and its parents before using the target.
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
function Public-Config($Target,$Metadata,[bool]$Enable,$Text=$null) {
    $path=Guard-Path (Join-Path $Target.game 'override.cfg') $Target.game
    $text=if($null -ne $Text){[string]$Text}elseif([IO.File]::Exists($path)){[IO.File]::ReadAllText($path)}else{''}
    $folder=(Join-Path $Target.game ('mods/'+$Metadata.id)).Replace('\','/')
    $expected='*'+$folder+'/'+$Metadata.entry
    $lines=[Collections.Generic.List[string]]::new();$inSection=$false;$insert=-1
    foreach($line in ($text -split '\r?\n')) {
        if($line -match '^\s*\[([^\]]+)\]') {if($inSection -and $insert -lt 0){$insert=$lines.Count};$inSection=$Matches[1] -eq 'autoload'}
        elseif($inSection) {
            $entry=Autoload-Entry $line
            if($entry) {
                if($entry.value.StartsWith('*'+$folder+'/',$script:pathComparison)){continue}
                if($Enable -and $entry.key -ceq $Metadata.autoload){Stop-Manager 'file_conflict' @($path)}
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
        if($item -and $item.key -ceq $Receipt.autoload -and $item.value.Equals($expected,$script:pathComparison)){return $true}
    }
    return $false
}
function All-Mods($Target) {
    $mods=@();$seen=@{}
    foreach($root in @($Target.game,$Target.user) | Select-Object -Unique) {
        foreach($r in (Read-Receipts $root)) {
            $r.enabled=Is-Enabled $Target $r;$r.compatible=Test-GameCompatibility $Target.version $r.game_versions;$r.manual=$false
            $mods+=,$r;$seen[$r.layout+'|'+$r.id]=$true
        }
    }
    # List manually installed public mods from mod.json without executing their code.
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
            if(Valid-GameCredit $meta.game_credit){$r.game_credit=$meta.game_credit}
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
function Owned-Operations($Receipt,[bool]$Remove,$Incoming=$null) {
    $ops=@()
    foreach($relative in $Receipt.hashes.Keys) {
        $path=Guard-Path (Join-Path $Receipt.root $relative) $Receipt.root
        $hash=Current-Hash $path
        $same=$Incoming -and $Incoming.contents.ContainsKey($relative) -and $hash -eq (Bytes-Hash $Incoming.contents[$relative])
        if($hash -and $hash -ne $Receipt.hashes[$relative] -and -not $same) {Stop-Manager 'file_conflict' @($path)}
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
function Get-PackageOperations($Target,$Package,$Request,$Context) {
    if($Request.sha256 -ne $Package.sha256) {Stop-Manager 'zip_changed'}
    if(-not (Test-GameCompatibility $Target.version $Package.game_versions)) {Stop-Manager 'version_mismatch' @($Target.version,($Package.game_versions -join ', '))}
    $root=$Target.root;$receiptPath=Receipt-Path $root $Package.id
    foreach($other in (Read-Receipts $root)) {
        if($other.id -eq $Package.id){continue}
        foreach($relative in $Package.files){if($other.hashes.ContainsKey($relative) -or $other.bootstrap -eq $relative){Stop-Manager 'file_conflict' @($relative,$other.name)}}
    }
    $old=@((Read-Receipts $root) | Where-Object {$_.id -eq $Package.id})
    $enabled=$true;$hashes=@{};$operations=@();$hadUnowned=$false
    if($old.Count) {$old=$old[0];$null=Owned-Operations $old $false $Package;$enabled=Is-Enabled $Target $old}else{$old=$null}
    if($Request.ContainsKey('force_enabled')){$enabled=[bool]$Request.force_enabled}
    foreach($relative in $Package.files) {
        $path=Guard-Path (Join-Path $root $relative) $root
        $data=$Package.contents[$relative];$hash=Bytes-Hash $data;$current=Current-Hash $path
        $mutable=$relative -match '\.(cfg|json)$' -and -not $relative.EndsWith('/mod.json')
        if($current -and $mutable){continue}
        # A copy of this mod's own bootstrap in styles/ is replaced by the one in mod_bootstraps/ below.
        $ownCopy=$old -and $relative -eq $Package.bootstrap -and ($current -eq $hash -or $current -eq $old.bootstrap_hash)
        if($current -and -not $ownCopy -and -not ($old -and ($old.hashes.ContainsKey($relative) -or $relative -eq $old.bootstrap))) {
            if($current -ne $hash){Stop-Manager 'file_conflict' @($path)}
            $hadUnowned=$true
        }
        if($relative -eq $Package.bootstrap){continue}
        $operations+=,@{path=$path;bytes=$data};if(-not $mutable){$hashes[$relative]=$hash}
    }
    if($hadUnowned -and -not $Request.adopt){Stop-Manager 'adopt_required'}
    if($old) {foreach($relative in $old.hashes.Keys) {if($relative -notin @($Package.files)) {$operations+=,@{path=(Guard-Path (Join-Path $root $relative) $root);bytes=$null}}}}
    $receipt=@{format=1;id=$Package.id;name=$Package.name;version=$Package.version;game_versions=@($Package.game_versions);layout=$Package.layout;entry=$Package.entry;autoload=$Package.autoload;hashes=$hashes;source_sha256=$Package.sha256}
    foreach($field in @('description','author','readme','readme_text','readme_unavailable','dependencies','game_credit','credit_warning')){$receipt[$field]=$Package[$field]}
    if($Package.layout -eq 'user-data-styles') {
        $place=Bootstrap-Place $Package.id
        $receipt.bootstrap=$place;$receipt.bootstrap_bytes=[Convert]::ToBase64String($Package.contents[$Package.bootstrap]);$receipt.bootstrap_hash=Bytes-Hash $Package.contents[$Package.bootstrap]
        $boot=Guard-Path (Join-Path $root $place) $root
        $current=Current-Hash $boot
        if($current -and $current -ne $receipt.bootstrap_hash -and (-not $old -or $current -ne $old.bootstrap_hash)){Stop-Manager 'file_conflict' @($boot)}
        # The zip names its bootstrap in styles/; a copy left there by an earlier manager or by hand would load twice.
        $left=@($Package.bootstrap);if($old -and $old.bootstrap){$left+=$old.bootstrap}
        foreach($relative in ($left|Select-Object -Unique)) {
            if($relative -eq $place){continue}
            $oldBoot=Guard-Path (Join-Path $root $relative) $root
            $oldHash=Current-Hash $oldBoot
            if($oldHash -and $oldHash -ne $receipt.bootstrap_hash -and (-not $old -or $oldHash -ne $old.bootstrap_hash)){Stop-Manager 'file_conflict' @($oldBoot)}
            if($oldHash){$operations+=,@{path=$oldBoot;bytes=$null}}
        }
        $operations+=,@{path=$boot;bytes=$(if($enabled){$Package.contents[$Package.bootstrap]}else{$null})}
    } else {
        $config=Public-Config $Target $Package $enabled $Context.config_text
        $Context.config_text=[Text.Encoding]::UTF8.GetString($config.bytes);$Context.config_changed=$true
    }
    $operations+=,@{path=$receiptPath;bytes=(Json-Bytes $receipt)}
    return ,$operations
}
# The game loads every .tres in user://styles/ in the order the file system lists them, which differs
# between platforms. The manager keeps the bootstraps it installs in user://mod_bootstraps/ and puts one
# loader in user://styles/ that runs them in the saved order. Mods queued by their bootstrap
# (sobosuba_mod_queue) are added right after their own bootstrap runs, so they keep the same order.
$script:loaderPath='styles/sobosuba_mod_loader.tres'
$script:loaderText=@'
[gd_resource type="Resource" load_steps=2 format=3]

[sub_resource type="GDScript" id="1"]
script/source = "extends Resource

# Sobosuba Mod Manager: runs the bootstraps in user://mod_bootstraps/ in the saved load order.
func _init() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or Engine.has_meta(\"sobosuba_mod_loader\"):
		return
	Engine.set_meta(\"sobosuba_mod_loader\", true)
	if not DirAccess.dir_exists_absolute(\"user://mod_bootstraps\"):
		return
	var order: Array = []
	if FileAccess.file_exists(\"user://mod_load_order.json\"):
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(\"user://mod_load_order.json\"))
		if saved is Dictionary and saved.get(\"order\") is Array:
			order = saved.order
	var ranked: Array = []
	for file: String in DirAccess.get_files_at(\"user://mod_bootstraps\"):
		if file.get_extension() != \"tres\":
			continue
		var rank: int = order.find(file.get_basename())
		ranked.append([rank if rank >= 0 else order.size(), file])
	ranked.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	for item: Array in ranked:
		ResourceLoader.load(\"user://mod_bootstraps/\" + item[1], \"\", ResourceLoader.CACHE_MODE_IGNORE)
		if Engine.has_meta(\"sobosuba_mod_queue\"):
			var waiting: Array = Engine.get_meta(\"sobosuba_mod_queue\")
			Engine.remove_meta(\"sobosuba_mod_queue\")
			for queued: Array in waiting:
				tree.root.add_child.call_deferred(queued[1])
"

[resource]
script = SubResource("1")
'@
function Bootstrap-Place([string]$Id) {return 'mod_bootstraps/'+$Id+'.tres'}
function Loader-Operation($Target) {
    return @{path=(Guard-Path (Join-Path $Target.user $script:loaderPath) $Target.user);bytes=[Text.Encoding]::UTF8.GetBytes($script:loaderText.Replace("`r`n","`n"))}
}
function Receipt-Bytes($Mod,[string]$Place) {
    $receipt=$Mod.Clone()
    foreach($field in @('root','enabled','compatible','manual')){$receipt.Remove($field)}
    $receipt.bootstrap=$Place
    return Json-Bytes $receipt
}
# Move a bootstrap that an earlier manager left in styles/ to its place in mod_bootstraps/.
function Bootstrap-Operations($Mod,[string]$Operation) {
    $place=Bootstrap-Place $Mod.id;$ops=@()
    if($Operation -eq 'move' -and $Mod.bootstrap -eq $place){return ,$ops}
    $boot=Guard-Path (Join-Path $Mod.root $place) $Mod.root;$current=Current-Hash $boot
    if($current -and $current -ne $Mod.bootstrap_hash){Stop-Manager 'file_conflict' @($boot)}
    $enable=$Operation -eq 'enable' -or ($Operation -eq 'move' -and $Mod.enabled)
    if($Mod.bootstrap -ne $place) {
        $old=Guard-Path (Join-Path $Mod.root $Mod.bootstrap) $Mod.root;$oldHash=Current-Hash $old
        if($oldHash -and $oldHash -ne $Mod.bootstrap_hash){Stop-Manager 'file_conflict' @($old)}
        if($oldHash){$ops+=,@{path=$old;bytes=$null}}
        if($Operation -ne 'uninstall'){$ops+=,@{path=(Receipt-Path $Mod.root $Mod.id);bytes=(Receipt-Bytes $Mod $place)}}
    }
    $ops+=,@{path=$boot;bytes=$(if($enable){[Convert]::FromBase64String($Mod.bootstrap_bytes)}else{$null})}
    return ,$ops
}
function Migration-Operations($Target,[string[]]$Skip=@()) {
    $ops=@()
    foreach($mod in (All-Mods $Target)) {
        if($mod.manual -or $mod.layout -ne 'user-data-styles' -or $mod.id -in $Skip){continue}
        $ops+=Bootstrap-Operations $mod 'move'
    }
    return ,$ops
}
# A mod is saved after the installed mods it requires.
function Dependency-Order($Target,[object[]]$Ids) {
    $byId=@{}
    foreach($mod in (All-Mods $Target)){if(-not $mod.manual -and $mod.layout -eq 'user-data-styles'){$byId[$mod.id]=$mod}}
    $result=[Collections.Generic.List[string]]::new();$state=@{}
    function Place-Id([string]$Id) {
        if($state.ContainsKey($Id)){return}
        $state[$Id]=$true
        if($byId.ContainsKey($Id)){foreach($dependency in @($byId[$Id].dependencies)){if($null -ne $dependency -and $byId.ContainsKey($dependency.id)){Place-Id $dependency.id}}}
        $result.Add($Id)
    }
    foreach($id in $Ids){Place-Id $id}
    return ,@($result)
}
# The loader reads this order (user://mod_load_order.json). Game 1.2.3 has no bootstraps.
function Order-Path($Target) {return Guard-Path (Join-Path $Target.user 'mod_load_order.json') $Target.user}
function Read-Order($Target) {
    if($Target.version -eq '1.2.3'){return ,@()}
    $path=Order-Path $Target
    if(-not [IO.File]::Exists($path)){return ,@()}
    try{$saved=Read-Map ([IO.File]::ReadAllText($path))}catch{return ,@()}
    return ,@(@($saved.order)|Where-Object {$_ -is [string] -and (Valid-Id $_)})
}
function Save-Order($Target,$Order) {
    if($Target.version -eq '1.2.3' -or $null -eq $Order){Stop-Manager 'invalid_request'}
    $ids=@($Order);$seen=@{}
    if($ids.Count -gt 64){Stop-Manager 'invalid_request'}
    foreach($id in $ids){
        if($id -isnot [string] -or -not (Valid-Id $id) -or $seen.ContainsKey($id)){Stop-Manager 'invalid_request'}
        $seen[$id]=$true
    }
    $ids=Dependency-Order $Target $ids
    if($ids.Count -gt 64){Stop-Manager 'invalid_request'}
    $ops=@(@{path=(Order-Path $Target);bytes=(Json-Bytes @{order=[object[]]$ids})})
    $ops+=Migration-Operations $Target
    $ops+=,(Loader-Operation $Target)
    Write-Transaction $Target.user $ops
}
function Previous-Path([string]$Root,[string]$Id) {return Guard-Path (Join-Path $Root ('.sobo-mod-manager/previous/'+$Id+'.json')) $Root}
function Save-Previous([string]$Root,$Old) {
    $files=@{}
    $paths=@($Old.hashes.Keys)
    if($Old.bootstrap){$paths+=$Old.bootstrap}
    foreach($relative in ($paths|Select-Object -Unique)) {
        $file=Guard-Path (Join-Path $Root ([string]$relative)) $Root
        if([IO.File]::Exists($file)){$files[[string]$relative]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($file))}
    }
    $copy=@{}
    foreach($key in $Old.Keys){if($key -ne 'root'){$copy[$key]=$Old[$key]}}
    $dest=Previous-Path $Root $Old.id
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))|Out-Null
    [IO.File]::WriteAllText($dest,(ConvertTo-Json -InputObject @{format=1;receipt=$copy;files=$files} -Depth 8 -Compress))
}
function Restore-Previous($Target,[string]$Id) {
    $path=Previous-Path $Target.root $Id
    if(-not [IO.File]::Exists($path)){Stop-Manager 'no_previous' @($Id)}
    $snap=Read-Map ([IO.File]::ReadAllText($path))
    $receipt=$snap.receipt;$files=$snap.files
    if($receipt.id -cne $Id){Stop-Manager 'no_previous' @($Id)}
    $ops=@();$kept=@($files.Keys)
    $current=@((Read-Receipts $Target.root)|Where-Object {$_.id -eq $Id})
    if($current.Count){
        foreach($relative in @($current[0].hashes.Keys)){if([string]$relative -notin $kept){$ops+=,@{path=(Guard-Path (Join-Path $Target.root ([string]$relative)) $Target.root);bytes=$null}}}
        if($current[0].bootstrap -and [string]$current[0].bootstrap -notin $kept){$ops+=,@{path=(Guard-Path (Join-Path $Target.root ([string]$current[0].bootstrap)) $Target.root);bytes=$null}}
    }
    foreach($relative in $files.Keys){$ops+=,@{path=(Guard-Path (Join-Path $Target.root ([string]$relative)) $Target.root);bytes=[Convert]::FromBase64String([string]$files[$relative])}}
    $ops+=,@{path=(Receipt-Path $Target.root $Id);bytes=(Json-Bytes $receipt)}
    $ops+=,@{path=$path;bytes=$null}
    if([string]$receipt.layout -eq 'user-data-styles'){$ops+=,(Loader-Operation $Target)}
    Write-Transaction $Target.root $ops
}
function Collect-Overlaps($Receipts) {
    $rows=@()
    foreach($mine in @($Receipts)) {
        foreach($other in @($Receipts)) {
            if($other.id -eq $mine.id){continue}
            foreach($relative in @($mine.hashes.Keys)) {
                if($other.hashes.ContainsKey($relative) -or [string]$other.bootstrap -eq [string]$relative){$rows+=,@{id=$mine.id;file=[string]$relative;mod_id=$other.id;mod_name=$other.name}}
            }
        }
    }
    return ,$rows
}
function Zip-Overlaps($Root,$Package) {
    $rows=@()
    foreach($other in (Read-Receipts $Root)) {
        if($other.id -eq $Package.id){continue}
        foreach($relative in @($Package.files)) {
            if($other.hashes.ContainsKey($relative) -or [string]$other.bootstrap -eq [string]$relative){$rows+=,@{file=[string]$relative;mod_id=$other.id;mod_name=$other.name}}
        }
    }
    return ,$rows
}
function Game-Exe($Target) {
    $names=if($script:managerWindows){@('sobosuba.exe')}else{@('sobosuba.x86_64','sobosuba')}
    foreach($name in $names){$path=Join-Path $Target.game $name;if([IO.File]::Exists($path)){return $path}}
    Stop-Manager 'game_missing' @($Target.game)
}
function Invoke-Manager($Request) {
    $mutex=[Threading.Mutex]::new($false,'Local\SoboModManager-FileOperations')
    $held=$false
    try {
        try {$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}
        if(-not $held){Stop-Manager 'busy'}
        $target=Get-Target $Request
        if($Request.action -in @('target','detect')) {return @{ok=$true;data=$target}}
        $mutating=$Request.action -in @('install','enable','disable','uninstall','recover','set_order','revert')
        if($mutating) {
            if(@(Get-Process -Name sobosuba,sobosuba.x86_64,sobosuba.exe -ErrorAction SilentlyContinue).Count){Stop-Manager 'game_running'}
            foreach($root in @($target.game,$target.user)|Select-Object -Unique){Recover-Transaction $root}
        }
        if($Request.action -eq 'overlaps') {
            if($Request.zip){$package=Read-Package $Request.zip;return @{ok=$true;data=@{overlaps=(Zip-Overlaps $target.root $package)}}}
            $rows=@()
            foreach($row in (Collect-Overlaps (Read-Receipts $target.root))){if(-not $Request.id -or $row.id -eq $Request.id){$rows+=,$row}}
            return @{ok=$true;data=@{overlaps=$rows}}
        }
        if($Request.action -eq 'launch') {
            if(@(Get-Process -Name sobosuba,sobosuba.x86_64,sobosuba.exe -ErrorAction SilentlyContinue).Count){Stop-Manager 'game_running'}
            $exe=Game-Exe $target
            Start-Process -FilePath $exe -WorkingDirectory $target.game
            return @{ok=$true;data=@{exe=$exe;order=(Read-Order $target)}}
        }
        if($Request.action -eq 'inspect') {
            $p=Read-Package $Request.zip
            if(-not (Test-GameCompatibility $target.version $p.game_versions)){Stop-Manager 'version_mismatch' @($target.version,($p.game_versions -join ', '))}
            $p.Remove('contents');return @{ok=$true;data=$p}
        }
        if($Request.action -eq 'find_dependency'){return @{ok=$true;data=(Find-DependencyZip $Request)}}
        if($Request.action -in @('resolve','install','enable')) {
            foreach($root in @($target.game,$target.user)){if([IO.File]::Exists((Guard-Path (Join-Path $root '.sobo-mod-manager/pending.json') $root))){Stop-Manager 'recovery_needed'}}
            $plan=Get-DependencyPlan $target $Request
            if($Request.action -ne 'resolve') {
                if($Request.token -and $Request.token -ne $plan.token){Stop-Manager 'plan_changed'}
                foreach($change in @($plan.changes)) {
                    if([string]$change.action -eq 'update' -and [string]$change.previous_version -and [string]$change.previous_version -ne [string]$change.version) {
                        $older=@((Read-Receipts $target.root)|Where-Object {$_.id -eq $change.id})
                        if($older.Count){Save-Previous $target.root $older[0]}
                    }
                }
                Write-Transaction $target.root $plan.operations
            }
            $data=$plan.root.Clone();$data.Remove('contents');$data.changes=@($plan.changes);$data.token=$plan.token
            return @{ok=$true;data=$data}
        }
        if($Request.action -eq 'recover'){return @{ok=$true;data=@{}}}
        foreach($root in @($target.game,$target.user)){if([IO.File]::Exists((Guard-Path (Join-Path $root '.sobo-mod-manager/pending.json') $root))){Stop-Manager 'recovery_needed'}}
        if($Request.action -eq 'set_order'){Save-Order $target $Request.order;return @{ok=$true;data=@{order=(Read-Order $target)}}}
        if($Request.action -eq 'revert'){Restore-Previous $target ([string]$Request.id);return @{ok=$true;data=@{id=$Request.id}}}
        $mods=All-Mods $target
        $overlapRows=Collect-Overlaps (Read-Receipts $target.root)
        foreach($mod in @($mods)) {
            $mod.has_previous=[IO.File]::Exists((Previous-Path $target.root ([string]$mod.id)))
            $mod.overlaps=@($overlapRows|Where-Object {$_.id -eq $mod.id})
        }
        if($Request.action -eq 'list'){return @{ok=$true;data=@{mods=@($mods);target=$target;order=(Read-Order $target)}}}
        $m=@($mods | Where-Object {$_.id -eq $Request.id -and (-not $Request.layout -or $_.layout -eq $Request.layout)})
        if($m.Count -ne 1 -or $m[0].manual){Stop-Manager 'adopt_required'};$m=$m[0]
        if($Request.action -notin @('enable','disable','uninstall')){Stop-Manager 'invalid_request'}
        Assert-DependencyRemoval $mods $m $Request.action
        $context=@{config_text=$null;config_changed=$false}
        $ops=Get-StateOperations $target $m $Request.action $context
        if($m.layout -eq 'user-data-styles'){$ops+=Migration-Operations $target @($m.id);$ops+=,(Loader-Operation $target)}
        if($context.config_changed){$ops+=,@{path=(Join-Path $target.game 'override.cfg');bytes=[Text.Encoding]::UTF8.GetBytes($context.config_text)}}
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
    try {$result=Invoke-Manager (Read-Map ([IO.File]::ReadAllText($RequestPath)))} catch {$result=@{ok=$false;error='invalid_request';args=@()}}
    # Return ASCII JSON independently of the Windows console code page.
    $json=ConvertTo-Json -InputObject $result -Depth 18 -Compress
    [Console]::WriteLine([Text.RegularExpressions.Regex]::Replace($json,'[^\x00-\x7f]',{param($match) '\u{0:x4}' -f [int][char]$match.Value}))
}
