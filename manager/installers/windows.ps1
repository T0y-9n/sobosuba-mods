param(
    [Parameter(Mandatory=$true)][string]$Prefix,
    [string]$Source,
    [string]$Version,
    [int]$Language = 1033,
    [int]$NoShortcuts = 0,
    [switch]$Uninstall,
    [switch]$DesktopOnly
)
$ErrorActionPreference = 'Stop'
$env:PSModulePath = Join-Path $PSHOME 'Modules'
$appName = 'Sobosuba Mod Manager'
$registryKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\SobosubaModManager'
$registry = $null
$files = @('SobosubaModManager.exe', 'Uninstall.exe', '.sobosuba-manager-install')
$mutex = New-Object Threading.Mutex($false, 'Global\SobosubaModManagerSetup')
$locked = $false
$stage = $null
$committed = $false
$registryWritten = $false
$registered = $null
$backups = New-Object Collections.ArrayList

function Assert-RegularPath([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Setup does not follow links or junctions: $current"
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Set-Shortcut([string]$Path, [string]$Target, [string]$Mode) {
    if ($Mode -eq 'Remove' -and -not (Test-Path -LiteralPath $Path)) { return }
    try { Assert-RegularPath $Path }
    catch { if ($Mode -eq 'Remove') { return }; throw }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $exists = Test-Path -LiteralPath $Path
        $link = $shell.CreateShortcut($Path)
        if ($exists -and -not [string]::Equals($link.TargetPath, $Target, [StringComparison]::OrdinalIgnoreCase)) {
            if ($Mode -eq 'Remove') { return }
            throw "A different shortcut already exists: $Path"
        }
        if ($Mode -eq 'Create') {
            New-Item -ItemType Directory -Force -Path ([IO.Path]::GetDirectoryName($Path)) | Out-Null
            $link.TargetPath = $Target
            $link.WorkingDirectory = $Prefix
            $link.Save()
        }
        if ($Mode -eq 'Remove' -and $exists) { Remove-Item -LiteralPath $Path }
    } finally {
        [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }
}

function Test-InstalledManager([string]$Binary) {
    $appdata = Join-Path $stage 'probe/appdata'
    $local = Join-Path $stage 'probe/localappdata'
    [IO.Directory]::CreateDirectory($appdata) | Out-Null
    [IO.Directory]::CreateDirectory($local) | Out-Null
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Binary
    $start.Arguments = '--headless -- --update-probe'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.EnvironmentVariables['APPDATA'] = $appdata
    $start.EnvironmentVariables['LOCALAPPDATA'] = $local
    $process = [Diagnostics.Process]::Start($start)
    try {
        if (-not $process.WaitForExit(45000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'The manager startup check timed out.'
        }
        if ($process.ExitCode -ne 0) { throw 'The manager startup check failed.' }
    } finally { $process.Dispose() }
    $result = Get-Content -LiteralPath (Join-Path $appdata 'Godot/app_userdata/Sobosuba Mod Manager/update-probe.json') -Raw | ConvertFrom-Json
    if ($result.ok -ne $true -or $result.version -cne $Version -or $result.sha256 -ine (Get-FileHash -LiteralPath $Binary -Algorithm SHA256).Hash) {
        throw 'The installed manager did not report the expected version and hash.'
    }
}

function Protect-InstallDirectory {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    foreach ($entry in @(@('S-1-5-18', 'FullControl'), @('S-1-5-32-544', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $sid = New-Object Security.Principal.SecurityIdentifier($entry[0])
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $entry[1], $inherit, 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    [IO.Directory]::SetAccessControl($Prefix, $acl)
}

try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another setup or removal is running.' }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Administrator approval is required for this setup.'
    }
    $Prefix = [IO.Path]::GetFullPath($Prefix).TrimEnd('\')
    if ($Prefix -eq [IO.Path]::GetPathRoot($Prefix).TrimEnd('\') -or $Prefix -eq $env:USERPROFILE) {
        throw 'Choose a dedicated application folder.'
    }
    Assert-RegularPath $Prefix
    $protectedRoots = @([Environment]::GetFolderPath('ProgramFilesX86'), $env:ProgramW6432) | Where-Object { $_ }
    $programRoot = [IO.Path]::GetDirectoryName($Prefix)
    if ($programRoot -notin $protectedRoots) { throw 'Choose a dedicated folder directly inside Program Files or Program Files (x86).' }
    $scope = 'machine'
    $registry = 'HKLM:\' + $registryKey
    $legacy = Get-ItemProperty -LiteralPath ('HKCU:\'+$registryKey) -ErrorAction SilentlyContinue
    if (-not $Uninstall -and -not $DesktopOnly -and $legacy) {
        throw 'Uninstall the previous per-user manager before installing for all users. Its settings will be kept.'
    }
    foreach ($name in $files) {
        $path = Join-Path $Prefix $name
        Assert-RegularPath $path
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "A folder occupies an application file path: $path"
        }
    }
    $marker = Join-Path $Prefix '.sobosuba-manager-install'
    $owned = $false
    if (Test-Path -LiteralPath $marker) {
        $text = [IO.File]::ReadAllText($marker)
        if ($text -eq $appName) { $owned = $true }
        else {
            $record = $text | ConvertFrom-Json
            $owned = $record.application -eq $appName -and $record.scope -eq $scope
        }
    }
    $registered = Get-ItemProperty -LiteralPath $registry -ErrorAction SilentlyContinue
    if ($registered -and $registered.InstallLocation -ne $Prefix) {
        throw 'Remove the existing installation before choosing another folder.'
    }
    $programs = Join-Path ([Environment]::GetFolderPath('CommonPrograms')) $appName
    $start = Join-Path $programs "$appName.lnk"
    $remove = Join-Path $programs 'Uninstall.lnk'
    $desktop = Join-Path ([Environment]::GetFolderPath('CommonDesktopDirectory')) "$appName.lnk"
    $exe = Join-Path $Prefix 'SobosubaModManager.exe'
    $uninstaller = Join-Path $Prefix 'Uninstall.exe'
    if ($Uninstall) {
        if (-not $owned) { throw 'This folder is not a managed installation.' }
        if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe }
        Set-Shortcut $start $exe 'Remove'
        Set-Shortcut $remove $uninstaller 'Remove'
        Set-Shortcut $desktop $exe 'Remove'
        if ((Test-Path -LiteralPath $programs) -and @(Get-ChildItem -LiteralPath $programs -Force).Count -eq 0) {
            Remove-Item -LiteralPath $programs
        }
        if ($registered) { Remove-Item -LiteralPath $registry }
        if (Test-Path -LiteralPath $uninstaller) { Remove-Item -LiteralPath $uninstaller }
        Remove-Item -LiteralPath $marker
        if (@(Get-ChildItem -LiteralPath $Prefix -Force).Count -eq 0) { Remove-Item -LiteralPath $Prefix }
        Write-Output 'The manager was removed. Settings, mods and other files were kept.'
        exit 0
    }
    if ($DesktopOnly) {
        if (-not $owned) { throw 'The application must be installed first.' }
        Set-Shortcut $desktop $exe 'Create'
        exit 0
    }
    if (-not $owned) {
        foreach ($name in $files) {
            if (Test-Path -LiteralPath (Join-Path $Prefix $name)) { throw "The folder contains an unmanaged file: $name" }
        }
        if ((Test-Path -LiteralPath $Prefix) -and @(Get-ChildItem -LiteralPath $Prefix -Force).Count -gt 0) {
            throw 'Choose an empty folder dedicated to this application.'
        }
    }
    if ($NoShortcuts -eq 0) {
        Set-Shortcut $start $exe 'Check'
        Set-Shortcut $remove $uninstaller 'Check'
    }
    New-Item -ItemType Directory -Force -Path $Prefix | Out-Null
    Protect-InstallDirectory
    $stage = Join-Path $programRoot ('.sobosuba-setup-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stage | Out-Null
    foreach ($name in @('SobosubaModManager.exe', 'Uninstall.exe')) {
        Copy-Item -LiteralPath (Join-Path $Source $name) -Destination (Join-Path $stage $name)
    }
    Test-InstalledManager (Join-Path $stage 'SobosubaModManager.exe')
    $record = @{ application = $appName; scope = $scope } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $stage '.sobosuba-manager-install'), $record)
    foreach ($name in $files) {
        $target = Join-Path $Prefix $name
        $backup = $null
        if (Test-Path -LiteralPath $target) {
            $backup = Join-Path $stage ($name + '.old')
            Copy-Item -LiteralPath $target -Destination $backup
            [IO.File]::Replace((Join-Path $stage $name), $target, $backup)
        } else {
            [IO.File]::Copy((Join-Path $stage $name), $target, $false)
        }
        [void]$backups.Add(@{ Target = $target; Backup = $backup })
        $fileAcl = Get-Acl -LiteralPath $target
        $fileAcl.SetAccessRuleProtection($false, $false)
        foreach ($rule in @($fileAcl.Access | Where-Object { -not $_.IsInherited })) { $fileAcl.RemoveAccessRuleSpecific($rule) }
        $fileAcl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        Set-Acl -LiteralPath $target -AclObject $fileAcl
    }
    New-Item -Path $registry -Force | Out-Null
    $registryWritten = $true
    $values = @{
        DisplayName = $appName; DisplayVersion = $Version; InstallLocation = $Prefix
        DisplayIcon = ('"' + $exe + '",0')
        UninstallString = ('"' + $uninstaller + '"')
        QuietUninstallString = ('"' + $uninstaller + '" /S')
    }
    foreach ($name in $values.Keys) {
        New-ItemProperty -LiteralPath $registry -Name $name -Value $values[$name] -PropertyType String -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $registry -Name NoModify -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $registry -Name NoRepair -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -LiteralPath $registry -Name InstallerLanguage -Value $Language -PropertyType DWord -Force | Out-Null
    $committed = $true
    if ($NoShortcuts -eq 0) {
        Set-Shortcut $start $exe 'Create'
        Set-Shortcut $remove $uninstaller 'Create'
    }
    Write-Output "Installed $appName in $Prefix"
} catch {
    $failure = $_.Exception.Message
    if (-not $committed) {
        $backups.Reverse()
        foreach ($entry in $backups) {
            try {
                if ($entry.Backup) { Copy-Item -LiteralPath $entry.Backup -Destination $entry.Target -Force }
                else { Remove-Item -LiteralPath $entry.Target }
            } catch { Write-Warning "Recovery copy kept in $stage"; $stage = $null }
        }
        if ($registryWritten) {
            if (-not $registered) { Remove-Item -LiteralPath $registry }
            else {
                foreach ($property in $registered.PSObject.Properties) {
                    if ($property.Name -notmatch '^PS') {
                        Set-ItemProperty -LiteralPath $registry -Name $property.Name -Value $property.Value
                    }
                }
            }
        }
    }
    Write-Output "Setup stopped: $failure"
    exit 1
} finally {
    if ($stage -and (Test-Path -LiteralPath $stage)) {
        Assert-RegularPath $stage
        if ([IO.Path]::GetDirectoryName($stage) -ne $programRoot -or [IO.Path]::GetFileName($stage) -notmatch '^\.sobosuba-setup-[a-f0-9]{32}$') {
            throw 'Unexpected setup temporary folder.'
        }
        Remove-Item -LiteralPath $stage -Recurse
    }
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
