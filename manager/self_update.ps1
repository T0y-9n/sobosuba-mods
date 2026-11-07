param([ValidateSet('prepare','apply','recover')][string]$Mode,[string]$Job)

$ErrorActionPreference='Stop'

$env:PSModulePath=Join-Path $PSHOME 'Modules'

. (Join-Path $PSScriptRoot 'package.ps1')

. (Join-Path $PSScriptRoot 'transaction.ps1')

$helperParent=[IO.Path]::GetDirectoryName($PSScriptRoot)

if([IO.Path]::GetFileName($helperParent) -ne 'update-helpers' -or [IO.Path]::GetFileName($PSScriptRoot) -notmatch '^[a-f0-9]{64}$'){throw 'Invalid helper location'}

$script:updateAppRoot=[IO.Path]::GetDirectoryName($helperParent)



function Write-UpdateJson($Path,$Value){Atomic-Write $Path ([Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Value -Depth 8)))}

function Read-UpdateRequest {

    $jobs=Join-Path $script:updateAppRoot 'self-update/jobs'

    $script:jobPath=Guard-Path $Job $jobs

    if([IO.Path]::GetDirectoryName($jobPath) -ne (Full-Path $jobs) -or [IO.Path]::GetFileName($jobPath) -notmatch '^[a-f0-9]{32}$'){throw 'Invalid update job'}

    $script:request=Read-Map ([IO.File]::ReadAllText((Guard-Path (Join-Path $jobPath 'request.json') $jobPath)))

    if($request.version -isnot [string] -or $request.version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$' -or $request.sha256 -notmatch '^[a-f0-9]{64}$' -or $request.old_sha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid update metadata'}

    $script:target=Full-Path $request.target

    $script:binaryName=if($script:managerWindows){'SobosubaModManager.exe'}else{'SobosubaModManager.x86_64'}
    $extension=if($script:managerWindows){'.exe'}else{'.x86_64'}
    if([IO.Path]::GetExtension($target) -cne $extension){throw 'Invalid update target'}

    $script:targetRoot=[IO.Path]::GetDirectoryName($target)

    $null=Guard-Path $target $targetRoot

    $script:candidate=Guard-Path (Join-Path $jobPath 'candidate.exe') $jobPath

    $script:backup=Guard-Path ($target+'.sobo-update-backup') $targetRoot

    $script:journal=Guard-Path ($target+'.sobo-update.json') $targetRoot

}

function Assert-Parent([bool]$Recovering=$false) {

    $parent=Get-Process -Id ([int]$request.parent_pid) -ErrorAction Stop

    if(-not (Full-Path $parent.Path).Equals($target,$script:pathComparison)){throw 'Update target is not the requesting application'}

    $expected=$request.old_sha256

    if($Recovering){

        $record=Read-Map ([IO.File]::ReadAllText($journal))

        if($record.job -ine $jobPath -or $record.old_sha256 -cne $request.old_sha256){throw 'Update recovery mismatch'}

        if((Current-Hash $target) -eq $record.candidate_sha256){$expected=$record.candidate_sha256}

    }

    if((Current-Hash $target) -cne $expected){throw 'Update application hash mismatch'}

    return $parent

}

function Prepare-Update {

    $null=Assert-Parent

    if($request.installer -eq $true){
        if(-not $script:managerWindows){throw 'Setup updates require Windows'}
        $package=Guard-Path (Join-Path $jobPath 'package.exe') $jobPath
        if((Get-Item -LiteralPath $package).Length -gt 128MB -or (Current-Hash $package) -cne $request.sha256){throw 'Setup package hash mismatch'}
        $bytes=[IO.File]::ReadAllBytes($package)
        if($bytes.Length -lt 1MB -or $bytes[0] -ne 77 -or $bytes[1] -ne 90){throw 'Invalid setup executable'}
        Atomic-Write $candidate $bytes
        Write-UpdateJson (Join-Path $jobPath 'prepared.json') @{candidate_sha256=$request.sha256;target=$target;old_sha256=$request.old_sha256;version=$request.version;sha256=$request.sha256;installer=$true}
        return
    }

    $zip=Guard-Path (Join-Path $jobPath 'package.zip') $jobPath

    if((Get-Item -LiteralPath $zip).Length -gt 128MB -or (Current-Hash $zip) -cne $request.sha256){throw 'Update package hash mismatch'}

    $archive=[IO.Compression.ZipFile]::OpenRead($zip)

    try{

        if($archive.Entries.Count -gt 32){throw 'Too many update entries'}

        $seen=@{};$exe=$null;$version=$null;$size=0L

        foreach($entry in $archive.Entries){

            $name=$entry.FullName

            if($name -match '[\\:]' -or $name.StartsWith('/') -or @($name.Split('/')|Where-Object {$_ -in @('.','..')}).Count){throw 'Unsafe update path'}

            if($seen.ContainsKey($name)){throw 'Duplicate update path'};$seen[$name]=$true

            $size+=$entry.Length

            if($size -gt 256MB){throw 'Update is too large'}

            if($name -ceq $script:binaryName){$exe=$entry}

            elseif($name -eq 'VERSION.txt'){$version=$entry}

            elseif($name -match '\.exe$'){throw 'Unexpected executable'}

        }

        if($null -eq $exe -or $null -eq $version -or $version.Length -gt 128 -or $exe.Length -lt 1MB){throw 'Missing update files'}

        $reader=[IO.StreamReader]::new($version.Open())

        try{if($reader.ReadToEnd().Trim() -cne $request.version){throw 'Update version mismatch'}}finally{$reader.Dispose()}

        $stream=$exe.Open();$memory=[IO.MemoryStream]::new()

        try{$stream.CopyTo($memory);$bytes=$memory.ToArray();$magic=if($script:managerWindows){@(77,90)}else{@(127,69,76,70)}
            for($i=0;$i -lt $magic.Count;$i++){if($bytes[$i] -ne $magic[$i]){throw 'Invalid executable'}};Atomic-Write $candidate $bytes}finally{$stream.Dispose();$memory.Dispose()}

    }finally{$archive.Dispose()}

    Write-UpdateJson (Join-Path $jobPath 'prepared.json') @{candidate_sha256=(Current-Hash $candidate);target=$target;old_sha256=$request.old_sha256;version=$request.version;sha256=$request.sha256}

}

function Probe-Update([string]$ExpectedHash){

    # Avoid deeply nested job folders because of Windows path limits.

    $probeDirectory=[IO.Path]::Combine($script:updateAppRoot,('.probe-'+[guid]::NewGuid().ToString('N').Substring(0,12)))

    $probe=Guard-Path -Path $probeDirectory -Root $script:updateAppRoot

    $appdata=Join-Path $probe 'appdata';$local=Join-Path $probe 'localappdata'

    [IO.Directory]::CreateDirectory($appdata)|Out-Null;[IO.Directory]::CreateDirectory($local)|Out-Null

    $start=[Diagnostics.ProcessStartInfo]::new()

    $start.FileName=$target;$start.Arguments='--headless -- --update-probe';$start.UseShellExecute=$false;$start.CreateNoWindow=$true

    if($script:managerWindows){
        $start.EnvironmentVariables['APPDATA']=$appdata;$start.EnvironmentVariables['LOCALAPPDATA']=$local
    }else{
        $start.EnvironmentVariables['HOME']=Join-Path $probe 'home'
        $start.EnvironmentVariables['XDG_DATA_HOME']=$appdata
        $start.EnvironmentVariables['XDG_CONFIG_HOME']=Join-Path $probe 'config'
        $start.EnvironmentVariables['XDG_CACHE_HOME']=$local
    }

    $process=[Diagnostics.Process]::Start($start)

    try{

        if(-not $process.WaitForExit(45000)){$process.Kill();$process.WaitForExit();throw 'Update probe timed out'}

        if($process.ExitCode -ne 0){throw 'Update probe failed'}

    }finally{$process.Dispose()}

    $dataFolder=if($script:managerWindows){'Godot'}else{'godot'}
    $response=Join-Path $appdata ($dataFolder+'/app_userdata/Sobosuba Mod Manager/update-probe.json')

    $result=Read-Map ([IO.File]::ReadAllText($response))

    if($result.version -cne $request.version -or $result.sha256 -cne $ExpectedHash -or $result.ok -ne $true){throw 'Update probe response mismatch'}

}

function Restore-Update($Record){

    if((Current-Hash $backup) -cne $Record.old_sha256){throw 'Update backup changed'}

    $current=Current-Hash $target

    if($current -cne $Record.old_sha256 -and $current -cne $Record.candidate_sha256){throw 'Update target changed'}

    if($current -cne $Record.old_sha256){Atomic-Write $target ([IO.File]::ReadAllBytes($backup))}

    [IO.File]::Delete($journal)

}

function Recover-Update {

    if(-not [IO.File]::Exists($journal)){return}

    $record=Read-Map ([IO.File]::ReadAllText($journal))

    if($record.job -ine $jobPath -or $record.old_sha256 -cne $request.old_sha256){throw 'Update recovery mismatch'}

    # Restore the previous version on the next start if the probe result was not saved.

    Restore-Update $record

    Write-UpdateJson (Join-Path $jobPath 'result.json') @{ok=$false;restored=$true;reason='interrupted'}

}



$held=$false;$mutex=$null

try{

    Read-UpdateRequest

    $mutex=[Threading.Mutex]::new($false,('Local\SoboManagerUpdate-'+(Bytes-Hash ([Text.Encoding]::UTF8.GetBytes($(if($script:managerWindows){$target.ToLowerInvariant()}else{$target}))))))

    try{$held=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$held=$true}

    if(-not $held){throw 'Update already running'}

    if($Mode -eq 'prepare'){Prepare-Update}

    elseif($Mode -eq 'recover'){

        # Hand recovery to apply, which waits until the running Windows executable exits.

        if([IO.File]::Exists($journal)){throw 'Interrupted update requires closing the application'}

    }else{

        $interrupted=[IO.File]::Exists($journal)

        $parent=Assert-Parent $interrupted

        $prepared=Read-Map ([IO.File]::ReadAllText((Join-Path $jobPath 'prepared.json')))

        if($prepared.target -ine $target -or $prepared.old_sha256 -cne $request.old_sha256 -or $prepared.version -cne $request.version -or $prepared.sha256 -cne $request.sha256 -or (Current-Hash $candidate) -cne $prepared.candidate_sha256){throw 'Prepared update changed'}

        Write-UpdateJson (Join-Path $jobPath 'ready.json') @{parent_pid=$parent.Id;helper_pid=$PID}

        # Retain the Process object so PID reuse cannot select an unrelated process.

        if(-not $parent.WaitForExit(120000)){throw 'Application did not close'}

        if($interrupted){Recover-Update;[Console]::WriteLine('{"ok":false,"restored":true}');exit 1}

        if((Current-Hash $target) -cne $request.old_sha256){throw 'Application changed before update'}

        if($request.installer -eq $true){
            if(-not $script:managerWindows -or $prepared.installer -ne $true -or (Current-Hash $candidate) -cne $request.sha256){throw 'Setup update metadata changed'}
            # Only the replacement setup requests elevation; the manager and helper stay unelevated.
            $options=@{FilePath=$candidate;ArgumentList=('/S /NoShortcuts /ExpectedVersion='+$request.version+' /D='+$targetRoot);Verb='RunAs';Wait=$true;PassThru=$true}
            $setupProcess=Start-Process @options
            try{if($setupProcess.ExitCode -ne 0){throw 'Setup update failed'}}finally{$setupProcess.Dispose()}
            $updatedHash=Current-Hash $target
            if($updatedHash -ceq $request.old_sha256){throw 'Setup did not update the manager'}
            # The setup restores the old version if its isolated startup probe fails.
            Probe-Update $updatedHash
            Write-UpdateJson (Join-Path $jobPath 'result.json') @{ok=$true;version=$request.version}
            if($request.restart -eq $true){Start-Process -FilePath $target -WorkingDirectory $targetRoot -WindowStyle Hidden|Out-Null}
            [Console]::WriteLine('{"ok":true}')
            exit 0
        }

        if([IO.File]::Exists($backup) -and (Current-Hash $backup) -cne $request.old_sha256){

            $ownership=Read-Map ([IO.File]::ReadAllText($backup+'.json'))

            if($ownership.sha256 -cne (Current-Hash $backup) -or $ownership.current_sha256 -cne $request.old_sha256){throw 'Keep unrecognized update backup'}

        }

        Atomic-Write $backup ([IO.File]::ReadAllBytes($target))

        Write-UpdateJson $journal @{job=$jobPath;old_sha256=$request.old_sha256;candidate_sha256=$prepared.candidate_sha256}

        try{

            $candidateBytes=[IO.File]::ReadAllBytes($candidate)

            if((Bytes-Hash $candidateBytes) -cne $prepared.candidate_sha256){throw 'Update candidate changed'}

            Atomic-Write $target $candidateBytes

            Probe-Update $prepared.candidate_sha256

        }catch{Restore-Update $prepared;throw}

        # Replace only a verified backup owned by a previous successful update.

        Write-UpdateJson ($backup+'.json') @{sha256=(Current-Hash $backup);current_sha256=$prepared.candidate_sha256}

        [IO.File]::Delete($journal)

        Write-UpdateJson (Join-Path $jobPath 'result.json') @{ok=$true;version=$request.version}

        if($request.restart -eq $true){
            $options=@{FilePath=$target;WorkingDirectory=$targetRoot}
            if($script:managerWindows){$options.WindowStyle='Hidden'}
            Start-Process @options|Out-Null
        }

    }

    [Console]::WriteLine('{"ok":true}')

}catch{

    if($jobPath -and [IO.Directory]::Exists($jobPath)){

        $reason=$_.Exception.Message;$location=$_.ScriptStackTrace

        try{Write-UpdateJson (Join-Path $jobPath 'result.json') @{ok=$false;error='manager_update_failed';reason=$reason;location=$location}}catch{}

    }

    [Console]::WriteLine('{"ok":false,"error":"manager_update_failed"}')

    exit 1

}finally{if($held){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
