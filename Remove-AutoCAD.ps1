<#
.SYNOPSIS
  Remove ALL AutoCAD / Autodesk software from a Windows PC.
  Based on Autodesk's official Clean Uninstall procedure.
.DESCRIPTION
  Phases:
    1. Stop Autodesk processes & services
    2. Uninstall all registered Autodesk products (ODIS 2022+ and MSI)
       - loops up to 4x because some components depend on others
    3. Remove Autodesk Genuine Service + licensing service
    4. Delete leftover folders (Program Files, ProgramData, AppData, Public Documents)
    5. Delete leftover registry keys
    6. Report what was done
.NOTES
  Run from elevated PowerShell:  powershell -ExecutionPolicy Bypass -File .\Remove-AutoCAD.ps1
  WARNING: removes ALL Autodesk software, not just AutoCAD. Reboot recommended after.
#>

$Log = "$env:TEMP\Remove-AutoCAD-$(Get-Date -Format yyyyMMdd-HHmmss).log"

# Admin check (replaces #Requires so the script works via irm | iex)
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script requires Administrator privileges. Relaunching elevated..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm https://raw.githubusercontent.com/thanhdtr/remove-autocad/master/Remove-AutoCAD.ps1 | iex`""
    exit
}

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format HH:mm:ss), $msg
    Write-Host $line
    Add-Content -Path $Log -Value $line
}

Log "=== Phase 1: auto-close ALL Autodesk applications ==="
# 1) Ask running Autodesk apps to close gracefully first (saves nothing, but lets them clean up)
$autodeskProcs = {
    Get-Process | Where-Object {
        $_.Name -match '^(acad|AcadLT|accoreconsole|AdskAccessCore|AdskIdentityManager|AdskLicensingService|AdSSO|FNPLicensingService|GenuineService|AutodeskAccess|AdAppMgr|AdskAccessServiceHost|AcQMod|senddmp|DesktopConnector|AdskAccess|AdSSO|FileSyncAgent|AdWorker|autocad|revit|RevitWorker|3dsmax|maya|inventor|navisworks|navisworksroamer|trueview|dwgviewr|dwgtruview|ReCap|AdUnit|AdDownload|AdEula)'
    }
}
& $autodeskProcs | ForEach-Object {
    Log "Requesting graceful close: $($_.Name) (PID $($_.Id))"
    $_.CloseMainWindow() | Out-Null
}
Start-Sleep -Seconds 5

# 2) Force-kill anything still open - named patterns...
Get-Process | Where-Object { $_.Name -match '^(acad|AcadLT|accoreconsole|AdskAccessCore|AdskIdentityManager|AdskLicensingService|AdSSO|FNPLicensingService|GenuineService|AutodeskAccess|AdAppMgr|AdskAccessServiceHost|AcQMod|senddmp|DesktopConnector|AdskAccess|FileSyncAgent|AdWorker|autocad|revit|RevitWorker|3dsmax|maya|inventor|navisworks|navisworksroamer|trueview|dwgviewr|dwgtruview|ReCap|AdUnit|AdDownload|AdEula)' } |
    ForEach-Object { Log "Force-killing $($_.Name) (PID $($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
# ...then wildcard kill: ANY process whose executable lives under an Autodesk path
Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -match 'Autodesk' } |
    ForEach-Object { Log "Path-kill: $($_.Name) (PID $($_.ProcessId)) $($_.ExecutablePath)"; Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

# 3) Verify: wait until no Autodesk processes remain (up to ~30s)
$deadline = (Get-Date).AddSeconds(30)
do {
    Start-Sleep -Seconds 3
    $left = @(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -match 'Autodesk' })
} while ($left.Count -gt 0 -and (Get-Date) -lt $deadline)
if ($left.Count -gt 0) {
    Log "WARNING: $($left.Count) Autodesk process(es) still alive after force-kill:"
    $left | ForEach-Object { Log "  - $($_.Name) (PID $($_.ProcessId))" }
    $left | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} else {
    Log "All Autodesk applications closed."
}

Log "=== Phase 1b: backup registry before deletion ==="
$backupDir = "$env:USERPROFILE\Desktop\Autodesk_Backup_$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
foreach ($k in @('HKLM\SOFTWARE\Autodesk', 'HKLM\SOFTWARE\WOW6432Node\Autodesk', 'HKCU\SOFTWARE\Autodesk')) {
    $name = ($k -replace '[\\:]', '_')
    & reg.exe export "$k" "$backupDir\$name.reg" /y 2>$null | Out-Null
    if (Test-Path "$backupDir\$name.reg") { Log "Backed up: $k -> $backupDir\$name.reg" }
}

# Autodesk desktop services (Genuine Service etc.)
Get-Service | Where-Object { $_.DisplayName -match 'Autodesk' -and $_.Status -eq 'Running' } |
    ForEach-Object { Log "Stopping service $($_.Name)"; Stop-Service $_.Name -Force -ErrorAction SilentlyContinue }

Log "=== Phase 2: uninstall all Autodesk products ==="

function Get-AutodeskApps {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object {
            # Publisher-based detection catches ALL products (Revit, Maya, 3ds Max,
            # Inventor, Civil 3D...) even when their name lacks "Autodesk"
            ($_.Publisher -match 'Autodesk') -or
            ($_.DisplayName -match 'Autodesk|AutoCAD|AutoLISP|Genuine Service|Revit|Inventor|Maya|3ds Max|Civil 3D|Navisworks|Fusion|Vault|InfraWorks|ReCap|DWG TrueView|Desktop Connector|Material Library')
        } |
        Select-Object DisplayName, Publisher, PSChildName, UninstallString -Unique
}

for ($round = 1; $round -le 4; $round++) {
    $apps = @(Get-AutodeskApps)
    if ($apps.Count -eq 0) { break }
    Log "--- Pass $round : $($apps.Count) product(s) found ---"

    foreach ($app in $apps) {
        Log ("Uninstalling: " + $app.DisplayName)

        # ODIS-installed (2022+): must use Installer.exe, not msiexec
        if ($app.UninstallString -match 'Installer\.exe' -or $app.PSChildName -match '^\{.*\}$' -and (Test-Path "C:\ProgramData\Autodesk\ODIS\metadata\$($app.PSChildName)")) {
            $meta = "C:\ProgramData\Autodesk\ODIS\metadata\$($app.PSChildName)"
            $pkgXml = Get-ChildItem $meta -Filter *.xml -ErrorAction SilentlyContinue |
                      Where-Object Name -match '^pkg\.|^bundleManifest\.xml' | Select-Object -First 1
            if ($pkgXml) {
                Start-Process -FilePath "C:\Program Files\Autodesk\AdODIS\V1\Installer.exe" `
                    -ArgumentList "-q -i uninstall --trigger_point system -m `"$($pkgXml.FullName)`"" `
                    -Wait -NoNewWindow -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                continue
            }
        }

        # Autodesk Identity Manager
        if ($app.DisplayName -match 'Identity') {
            Start-Process "C:\Program Files\Autodesk\AdskIdentityManager\uninstall.exe" -ArgumentList "--mode unattended" -Wait -ErrorAction SilentlyContinue
            continue
        }

        # Everything else: MSI product code
        if ($app.PSChildName -match '^\{[0-9A-Fa-f-]+\}$') {
            Start-Process msiexec.exe -ArgumentList "/x $($app.PSChildName) /qn /norestart" -Wait
            Start-Sleep -Seconds 3
        }
        elseif ($app.QuietUninstallString) {
            Start-Process cmd.exe -ArgumentList "/c $($app.QuietUninstallString)" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        }
        elseif ($app.UninstallString) {
            Start-Process cmd.exe -ArgumentList "/c $($app.UninstallString) /qn /S" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
        }
    }
}

Log "=== Phase 3: remove Autodesk Genuine Service & licensing ==="
# Kill Genuine Service / licensing processes first - they lock their own folders & resist uninstall
Get-Process | Where-Object { $_.Name -match 'GenuineService|AdskLicensingService|FNPLicensingService|AdskAccessServiceHost' } |
    ForEach-Object { Log "Killing $($_.Name) (PID $($_.Id))"; Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }

# Genuine Service protects its own uninstall; delete its license marker first
Remove-Item "$env:ALLUSERSPROFILE\Autodesk\Adlm\ProductInformation.pit" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:userprofile\AppData\Local\Autodesk\Genuine Autodesk Service\id.dat" -Force -ErrorAction SilentlyContinue
$gsvcs = @('{21DE6405-91DE-4A69-A8FB-483847F702C6}', '{7F68A0CC-1B47-47AA-9DB7-BA31E7EB85D8}')
foreach ($gs in $gsvcs) {
    Start-Process msiexec.exe -ArgumentList "/x $gs /qn" -Wait -ErrorAction SilentlyContinue
}
# Licensing Desktop Service (official step: run its bundled Uninstall.exe)
if (Test-Path 'C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\uninstall.exe') {
    Start-Process 'C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\uninstall.exe' -Verb RunAs -Wait -ErrorAction SilentlyContinue
}
else {
    Log "AdskLicensing uninstaller not found - removing licensing manually"
}
# Fallbacks in case either MSI/uninstaller failed:
# 1) stop & delete the Windows services outright
foreach ($svc in @('AdskLicensingService', 'FlexNet Licensing Service', 'GenuineService')) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Log "Removing service: $svc"
        Stop-Service $svc -Force -ErrorAction SilentlyContinue
        Start-Process sc.exe -ArgumentList "delete `"$svc`"" -Wait -WindowStyle Hidden
    }
}
# 2) delete the licensing & genuine-service folders outright (Phase 4 covers Program Files\Autodesk,
#    these two live elsewhere)
foreach ($f in @(
    'C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing',
    "$env:LOCALAPPDATA\Autodesk\Genuine Autodesk Service",
    'C:\Program Files\Autodesk\AdODIS',
    'C:\Program Files\Autodesk\AdskIdentityManager'
)) {
    if (Test-Path $f) {
        Log "Fallback removal: $f"
        Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Log "=== Phase 4: delete leftover folders ==="
$folders = @(
    'C:\Program Files\Autodesk',
    'C:\Program Files (x86)\Autodesk',
    'C:\Program Files\Common Files\Autodesk Shared',
    'C:\Program Files (x86)\Common Files\Autodesk Shared',
    'C:\Program Files\Common Files\Autodesk',
    'C:\Program Files (x86)\Common Files\Autodesk',
    'C:\ProgramData\Autodesk',
    'C:\ProgramData\FLEXnet',                       # Autodesk license cache
    'C:\Program Files\Common Files\Macrovision Shared',
    "$env:ALLUSERSPROFILE\Autodesk",
    "$env:PUBLIC\Documents\Autodesk",
    "$env:APPDATA\Autodesk",
    "$env:LOCALAPPDATA\Autodesk",
    "$env:LOCALAPPDATA\Programs\Autodesk",
    "$env:LOCALAPPDATA\Temp\odis_download_dest",    # ODIS download cache
    "$env:LOCALAPPDATA\com.autodesk.cer-dialog",    # CER error dialog data
    "$env:USERPROFILE\DC",                          # Desktop Connector workspace (opt-out by deleting this line)
    'C:\Autodesk'                                   # install-download cache, often 5-30+ GB
)
foreach ($f in $folders) {
    if (Test-Path $f) {
        Log "Removing folder: $f"
        Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $f) {
            # locked - take ownership and retry once
            Log "Folder locked, takeown/icacls fallback: $f"
            Start-Process takeown.exe -ArgumentList "/f `"$f`" /r /d y" -Wait -WindowStyle Hidden
            Start-Process icacls.exe  -ArgumentList "`"$f`" /grant administrators:F /t" -Wait -WindowStyle Hidden
            Remove-Item $f -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
# .NET native image cache leftovers
Get-ChildItem 'C:\Windows\assembly\NativeImages_v4.0.30319_*' -Directory -ErrorAction SilentlyContinue |
    Where-Object Name -match 'Autodesk' |
    ForEach-Object { Log "Removing native image cache: $($_.FullName)"; Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }

Log "=== Phase 4b: shortcuts, scheduled tasks, firewall rules, env vars ==="
# Shortcuts: desktop (all users + user), Start Menu, taskbar pins
Get-ChildItem @(
    "$env:PUBLIC\Desktop", "$env:USERPROFILE\Desktop",
    "$env:ProgramData\Microsoft\Windows\Start Menu\Programs",
    "$env:APPDATA\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
) -Filter *.lnk -Recurse -ErrorAction SilentlyContinue |
    ForEach-Object {
        $sh = New-Object -ComObject WScript.Shell
        if ($sh.CreateShortcut($_.FullName).TargetPath -match 'Autodesk|AutoCAD') {
            Log "Removing shortcut: $($_.FullName)"
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
# Scheduled tasks
Get-ScheduledTask | Where-Object { $_.TaskName -match 'Autodesk|Adsk|AutoCAD|DesktopConnector' } |
    ForEach-Object { Log "Deleting task: $($_.TaskName)"; Unregister-ScheduledTask -TaskName $_.TaskName -Confirm:$false -ErrorAction SilentlyContinue }
# Firewall rules
Get-NetFirewallRule | Where-Object { $_.DisplayName -match 'Autodesk|AutoCAD|Adsk' } |
    ForEach-Object { Log "Removing firewall rule: $($_.DisplayName)"; Remove-NetFirewallRule -Name $_.Name -ErrorAction SilentlyContinue }
# Environment variables
foreach ($v in @('ADSKFLEX_LICENSE_FILE', 'LM_LICENSE_FILE')) {
    [Environment]::SetEnvironmentVariable($v, $null, 'Machine')
    [Environment]::SetEnvironmentVariable($v, $null, 'User')
    Log "Cleared env var (if set): $v"
}
# Shell extension: DWG thumbnail handler (AcShellExtension.dll)
$acx = Get-ChildItem 'C:\Program Files\Common Files\Autodesk Shared\AcShellExtension.dll',
                   'C:\Program Files\Autodesk\*\AcShellExtension.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($acx) {
    Log "Unregistering shell extension: $($acx.FullName)"
    Start-Process regsvr32.exe -ArgumentList "/u /s `"$($acx.FullName)`"" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
}

Log "=== Phase 5: delete leftover registry keys ==="
$keys = @(
    'HKLM:\SOFTWARE\Autodesk',
    'HKLM:\SOFTWARE\WOW6432Node\Autodesk',
    'HKLM:\SOFTWARE\FLEXlm License Manager',
    'HKLM:\SOFTWARE\Wow6432Node\FLEXlm License Manager',
    'HKCU:\SOFTWARE\Autodesk',
    # per-product keys that live OUTSIDE \Autodesk
    'HKLM:\SOFTWARE\Autodesk\AutoCAD',
    'HKLM:\SOFTWARE\Classes\AutoCAD.Application',        # COM registration (+ .1/.2 versioned subkeys removed below)
    'HKCU:\Software\Classes\VirtualStore\MACHINE\SOFTWARE\Autodesk'
)
foreach ($k in $keys) {
    if (Test-Path $k) {
        Log "Removing key: $k"
        Remove-Item $k -Recurse -Force -ErrorAction SilentlyContinue
    }
}
# versioned COM registrations: AutoCAD.Application.24 / .25 etc.
Get-ChildItem 'HKLM:\SOFTWARE\Classes' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^AutoCAD\.Application\.' } |
    ForEach-Object {
        Log "Removing COM reg: $($_.PSChildName)"
        Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
# per-product uninstall remnants under ALL Uninstall trees (incl. HKCU and per-user)
$uninstallRoots = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
    'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
)
Get-ChildItem $uninstallRoots -ErrorAction SilentlyContinue |
    ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
    Where-Object { ($_.Publisher -match 'Autodesk') -or ($_.DisplayName -match 'Autodesk|AutoCAD|Revit|Inventor|Maya|3ds Max|Civil 3D|Navisworks|Fusion|Vault|InfraWorks|ReCap|DWG TrueView|Desktop Connector') } |
    ForEach-Object {
        Log "Removing orphan uninstall entry: $($_.DisplayName)"
        Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
# Autodesk Windows services remnants (licensing/genuine service already sc-deleted in Phase 3;
# this sweeps any other Autodesk-named service registrations)
Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match 'Adsk|Autodesk|FlexNet' } |
    ForEach-Object {
        Log "Removing service key: $($_.PSChildName)"
        Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
# file-type / shell associations pointing at deleted AutoCAD (only removes keys whose default value references Autodesk paths)
foreach ($root in @('HKCU:\SOFTWARE\Classes', 'HKLM:\SOFTWARE\Classes')) {
    foreach ($ext in @('.dwg', '.dwt', '.dws', '.dwf', '.bak')) {
        $k = Get-Item "$root\$ext" -ErrorAction SilentlyContinue
        if ($k -and ($k.GetValue('') -match 'AutoCAD') ) {
            Log "Removing file association: $($root)\$($ext) -> $($k.GetValue(''))"
            Remove-ItemProperty -Path "$root\$ext" -Name '(default)' -Force -ErrorAction SilentlyContinue
        }
    }
}
# Autodesk-named ProgID/class keys: DWGTrueView*, acadlt.*, adsk.idmgr, AutoLISPFile, dwgviewr, etc.
Get-ChildItem 'HKCU:\SOFTWARE\Classes', 'HKLM:\SOFTWARE\Classes' -ErrorAction SilentlyContinue |
    Where-Object { $_.PSChildName -match '^(DWGTrueView|acadlt|adsk\.idmgr|adskidmgr|AutoLISPFile|3dsFile|dwgviewr|AutodeskDGN|AutodeskAutoCAD)' } |
    ForEach-Object {
        Log "Removing class key: $($_.PSPath -replace 'Microsoft.PowerShell.Core\\Registry::','')"
        Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
    }
# COM deep scan: CLSIDs and TypeLibs whose InprocServer/Default value references Autodesk paths
foreach ($hive in @('HKLM:\SOFTWARE\Classes\CLSID', 'HKLM:\SOFTWARE\Classes\Wow6432Node\CLSID', 'HKCU:\SOFTWARE\Classes\CLSID')) {
    Get-ChildItem $hive -ErrorAction SilentlyContinue | ForEach-Object {
        $dll = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(default)'
        $inproc = Get-ChildItem $_.PSPath -ErrorAction SilentlyContinue |
                  Where-Object PSChildName -eq 'InprocServer32' |
                  ForEach-Object { (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).'(default)' }
        if (($dll -match 'Autodesk') -or ($inproc -match 'Autodesk')) {
            Log "Removing COM CLSID: $($_.PSChildName)"
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
foreach ($tlb in @('HKLM:\SOFTWARE\Classes\TypeLib', 'HKLM:\SOFTWARE\Classes\Wow6432Node\TypeLib')) {
    Get-ChildItem $tlb -ErrorAction SilentlyContinue | ForEach-Object {
        $hasAutodesk = Get-ChildItem $_.PSPath -Recurse -ErrorAction SilentlyContinue |
                       ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } |
                       Where-Object { ($_.'(default)') -match 'Autodesk' } | Select-Object -First 1
        if ($hasAutodesk) {
            Log "Removing TypeLib: $($_.PSChildName)"
            Remove-Item $_.PSPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Log "=== Phase 6: verification ==="
$leftover = @(Get-AutodeskApps)
if ($leftover.Count -eq 0) { Log "SUCCESS: no Autodesk/AutoCAD entries remain in Add/Remove Programs." }
else { Log "WARNING: still registered:"; $leftover | ForEach-Object { Log "  - $($_.DisplayName)" } }
foreach ($f in $folders) { if (Test-Path $f) { Log "Folder remains (in use?): $f" } }

Log "Done. Full log: $Log"
Log ">>> REBOOT the PC to finish the clean uninstall <<<"
