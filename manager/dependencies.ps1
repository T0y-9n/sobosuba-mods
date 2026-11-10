# Resolve prerequisites under the caller lock and apply the resulting plan together.
function Get-StateOperations($Target,$Mod,[string]$Operation,$Context) {
    $enable=$Operation -eq 'enable'
    $ops=@();if($Operation -ne 'disable'){$ops=Owned-Operations $Mod ($Operation -eq 'uninstall')}
    if($enable){foreach($relative in $Mod.hashes.Keys){if(-not [IO.File]::Exists((Join-Path $Mod.root $relative))){Stop-Manager 'file_conflict' @($relative)}}}
    if($Mod.layout -eq 'user-data-styles'){
        $boot=Guard-Path (Join-Path $Mod.root $Mod.bootstrap) $Mod.root;$current=Current-Hash $boot
        if($current -and $current -ne $Mod.bootstrap_hash){Stop-Manager 'file_conflict' @($boot)}
        $ops+=,@{path=$boot;bytes=$(if($enable){[Convert]::FromBase64String($Mod.bootstrap_bytes)}else{$null})}
    }else{
        $config=Public-Config $Target $Mod $enable $Context.config_text
        $Context.config_text=[Text.Encoding]::UTF8.GetString($config.bytes);$Context.config_changed=$true
    }
    if($Operation -eq 'uninstall'){$ops+=,@{path=(Receipt-Path $Mod.root $Mod.id);bytes=$null}}
    return ,$ops
}
function Assert-FinalDependencies([object[]]$Mods) {
    foreach($mod in $Mods){
        if(-not $mod.enabled -or $mod.manual){continue}
        foreach($dependency in @($mod.dependencies)){
            if($null -eq $dependency){continue}
            $matches=@($Mods|Where-Object {$_.id -eq $dependency.id -and $_.layout -eq $mod.layout -and -not $_.manual -and $_.enabled -and $_.version -ceq $dependency.version})
            if($matches.Count -ne 1){Stop-Manager 'dependency_required' @($mod.name,$dependency.id,$dependency.version)}
            if($dependency.sha256 -and $matches[0].source_sha256 -ne $dependency.sha256){Stop-Manager 'dependency_required' @($mod.name,$dependency.id,$dependency.version)}
        }
    }
}
function Assert-DependencyRemoval($Mods,$Selected,[string]$Operation) {
    $final=@()
    foreach($mod in $Mods){
        $copy=$mod.Clone()
        if($mod.id -eq $Selected.id -and $mod.layout -eq $Selected.layout){$copy.enabled=$false}
        $final+=,$copy
    }
    Assert-FinalDependencies $final
}
function Find-DependencyZip($Request) {
    if(-not (Valid-Id $Request.id) -or $Request.version -isnot [string] -or @($Request.search_dirs).Count -gt 4){Stop-Manager 'invalid_request'}
    foreach($directory in @($Request.search_dirs)){
        if($directory -isnot [string] -or -not [IO.Directory]::Exists($directory)){continue}
        $paths=@([IO.Directory]::GetFiles($directory,'*.zip')|Sort-Object)
        if($paths.Count -gt 128){Stop-Manager 'dependency_limit'}
        foreach($path in $paths){
            try{$package=Read-Package $path}catch{continue}
            if($package.id -ceq $Request.id -and $package.version -ceq $Request.version -and (Test-GameCompatibility $Request.game_version $package.game_versions) -and (-not $Request.sha256 -or $package.sha256 -eq $Request.sha256)){
                return @{zip=$path;sha256=$package.sha256}
            }
        }
    }
    return @{zip='';sha256=''}
}
function Get-DependencyPlan($Target,$Request) {
    $mods=All-Mods $Target
    $layout=if($Target.version -eq '1.2.3'){'game-autoload'}else{'user-data-styles'}
    $installed=@{}
    foreach($mod in $mods){if($mod.layout -eq $layout -and -not $mod.manual){$installed[$mod.id]=$mod}}
    $packages=@{}
    $inputs=@($Request.dependency_zips|Where-Object {$null -ne $_})
    if($Request.zip){$inputs+=,@{zip=$Request.zip;sha256=$Request.sha256}}
    if($inputs.Count -gt 32){Stop-Manager 'dependency_limit'}
    $total=0L
    foreach($packageInput in $inputs){
        if($packageInput -isnot [hashtable] -or $packageInput.zip -isnot [string] -or $packageInput.sha256 -isnot [string]){Stop-Manager 'invalid_request'}
        $package=Read-Package $packageInput.zip
        if($package.sha256 -ne $packageInput.sha256){Stop-Manager 'zip_changed'}
        if(-not (Test-GameCompatibility $Target.version $package.game_versions) -or $package.layout -ne $layout){Stop-Manager 'version_mismatch' @($Target.version,($package.game_versions -join ', '))}
        if($packages.ContainsKey($package.id) -and $packages[$package.id].sha256 -ne $package.sha256){Stop-Manager 'dependency_version' @($package.id)}
        $packages[$package.id]=$package
        foreach($bytes in $package.contents.Values){$total+=$bytes.Length}
        if($total -gt 256MB){Stop-Manager 'dependency_limit'}
    }
    if($Request.zip){$root=Read-Package $Request.zip;$root=$packages[$root.id]}else{
        $matches=@($mods|Where-Object {$_.id -eq $Request.id -and (-not $Request.layout -or $_.layout -eq $Request.layout)})
        if($matches.Count -ne 1 -or $matches[0].manual){Stop-Manager 'adopt_required'}
        $root=$matches[0]
        if(-not $root.compatible -or $root.layout -ne $layout){Stop-Manager 'version_mismatch' @($Target.version,($root.game_versions -join ', '))}
    }
    if($Request.ContainsKey('expected_version')){
        $oldRoot=$installed[$root.id]
        if($null -eq $oldRoot -or $oldRoot.version -cne $Request.expected_version -or $oldRoot.source_sha256 -cne $Request.expected_source_sha256){Stop-Manager 'plan_changed'}
    }
    $walk=@{states=@{};versions=@{};hashes=@{};order=[Collections.Generic.List[object]]::new()}
    function Visit-Dependency($Node) {
        if($walk.states[$Node.id] -eq 1){Stop-Manager 'dependency_cycle' @($Node.name)}
        if($walk.states[$Node.id] -eq 2){return}
        if($walk.states.Count -ge 32){Stop-Manager 'dependency_limit'}
        $walk.states[$Node.id]=1
        foreach($dependency in @($Node.dependencies)){
            if($null -eq $dependency){continue}
            if($walk.versions.ContainsKey($dependency.id) -and $walk.versions[$dependency.id] -cne $dependency.version){Stop-Manager 'dependency_version' @($dependency.id)}
            if($dependency.sha256 -and $walk.hashes[$dependency.id] -and $walk.hashes[$dependency.id] -ne $dependency.sha256){Stop-Manager 'dependency_version' @($dependency.id)}
            $walk.versions[$dependency.id]=$dependency.version
            if($dependency.sha256){$walk.hashes[$dependency.id]=$dependency.sha256}
            $candidate=$packages[$dependency.id]
            if($null -eq $candidate){$candidate=$installed[$dependency.id]}
            $hash=if($null -ne $candidate -and $candidate.ContainsKey('sha256')){$candidate.sha256}else{$candidate.source_sha256}
            if($null -eq $candidate -or $candidate.version -cne $dependency.version -or ($walk.hashes[$dependency.id] -and $hash -ne $walk.hashes[$dependency.id])){Stop-Manager 'dependency_missing' @($dependency.id,$dependency.version,[string]$walk.hashes[$dependency.id])}
            Visit-Dependency $candidate
        }
        $walk.states[$Node.id]=2;$walk.order.Add($Node)
    }
    Visit-Dependency $root
    # Keep loading entries belonging to other game versions.
    foreach($mod in $mods){
        $adopting=$mod.manual -and $mod.layout -eq $layout -and $walk.states.ContainsKey($mod.id)
        if($mod.enabled -and -not $mod.compatible -and -not $adopting){Stop-Manager 'other_version_active' @($mod.name)}
    }
    $rootEnabled=$true
    if($Request.zip -and $installed.ContainsKey($root.id)){$rootEnabled=[bool]$installed[$root.id].enabled}
    $context=@{config_text=$null;config_changed=$false}
    $operations=@();$changes=@();$final=@{};$tokenLines=[Collections.Generic.List[string]]::new()
    foreach($mod in $mods){$final[$mod.id+'|'+$mod.layout]=$mod.Clone()}
    foreach($node in $walk.order){
        $old=$installed[$node.id]
        $enabled=$rootEnabled -or ($node.id -ne $root.id -and $null -ne $old -and $old.enabled)
        if($packages.ContainsKey($node.id)){
            $options=@{sha256=$node.sha256;adopt=[bool]$Request.adopt;force_enabled=$enabled}
            $operations+=Get-PackageOperations $Target $node $options $context
            $next=$node.Clone();$next.source_sha256=$node.sha256
            $kind=if($null -eq $old){'install'}else{'update'}
        }else{
            $next=$node.Clone()
            if($enabled){$operations+=Get-StateOperations $Target $node 'enable' $context}
            $kind=if($enabled -and -not $node.enabled){'enable'}else{'ready'}
        }
        $next.enabled=$enabled;$next.manual=$false
        $final[$node.id+'|'+$node.layout]=$next
        $changes+=,@{id=$node.id;name=$node.name;version=$node.version;action=$kind;enabled=$enabled;credit_warning=(-not (Valid-GameCredit $node.game_credit));previous_version=$(if($null -ne $old){$old.version}else{''})}
        $tokenLines.Add($node.id+'|'+$node.version+'|'+[string]$next.source_sha256+'|'+[string]$enabled)
    }
    Assert-FinalDependencies @($final.Values)
    if($context.config_changed){$operations+=,@{path=(Join-Path $Target.game 'override.cfg');bytes=[Text.Encoding]::UTF8.GetBytes($context.config_text)}}
    if($operations.Count -gt 1024){Stop-Manager 'dependency_limit'}
    $seen=@{}
    foreach($operation in $operations){
        $path=Guard-Path $operation.path $Target.root
        if($seen.ContainsKey($path)){Stop-Manager 'file_conflict' @($path)};$seen[$path]=$true
        $newHash=if($path.Replace('\','/') -like '*/.sobo-mod-manager/receipts/*.json'){'receipt'}elseif($null -eq $operation.bytes){''}else{Bytes-Hash $operation.bytes}
        $tokenLines.Add($path+'|'+(Current-Hash $path)+'|'+$newHash)
    }
    $tokenLines.Sort([StringComparer]::Ordinal)
    $token=Bytes-Hash ([Text.Encoding]::UTF8.GetBytes(($tokenLines -join "`n")))
    return @{operations=$operations;changes=$changes;token=$token;root=$root}
}
