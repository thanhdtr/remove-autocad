# Remove-AutoCAD

A single-file PowerShell script that completely removes **ALL Autodesk software** from a Windows PC — AutoCAD, Revit, Inventor, Maya, 3ds Max, Civil 3D, Navisworks, Fusion, Vault, DWG TrueView, Desktop Connector, Material Libraries, and more — plus licensing, Genuine Service, and every leftover trace.

Based on [Autodesk's official Clean Uninstall procedure](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Clean-uninstall.html), hardened with techniques from community uninstallers.

## What it removes

| Phase | What |
|---|---|
| 1 | **Auto-closes all Autodesk applications** — no need to close anything yourself: graceful close attempt → force-kill (named + **path-based wildcard kill**) → verifies none remain. Stops services too |
| 1b | **Backs up registry keys** to `Desktop\Autodesk_Backup_<timestamp>\` (.reg files) |
| 2 | Silently uninstalls every registered product — handles **ODIS** (2022+), classic MSI, and Identity Manager; loops up to 4 passes for dependency ordering |
| 3 | Removes **Autodesk Genuine Service** (kills its protection markers first) and the **AdskLicensing** service, with `sc delete` + folder fallbacks |
| 4 | Deletes ~17 leftover folder locations (Program Files, ProgramData, FLEXnet, AppData ×2, ODIS cache, CER data, Desktop Connector workspace, `C:\Autodesk` staging — often 5–30 GB), with **takeown/icacls fallback** for locked folders; cleans .NET native image cache |
| 4b | Removes shortcuts (desktop/Start Menu/taskbar pins), scheduled tasks, firewall rules, `ADSKFLEX_LICENSE_FILE` env var, unregisters the DWG shell extension (`AcShellExtension.dll`) |
| 5 | Deep registry clean: Autodesk keys (HKLM/HKCU/WOW6432Node), FLEXlm, COM CLSID/TypeLib deep scan, class keys (`DWGTrueView*`, `acadlt.*`, `adsk.idmgr`…), all 3 Uninstall trees, service keys, dead file associations |
| 6 | Verifies nothing remains; full timestamped log to `%TEMP%` |

## Quick Run (one line)

Open **any** PowerShell (no admin needed — it self-elevates) and paste:

```powershell
irm https://raw.githubusercontent.com/thanhdtr/remove-autocad/master/Remove-AutoCAD.ps1 | iex
```

That's it — downloads the latest script from this repo, prompts UAC for admin, and runs. No cloning, no execution-policy changes.

## Manual usage

Right-click PowerShell → **Run as administrator**, then:

```powershell
powershell -ExecutionPolicy Bypass -File .\Remove-AutoCAD.ps1
```

Reboot afterwards to finish the clean.

## ⚠️ Before you run it

- **No need to uninstall anything yourself** — the script detects and removes ALL Autodesk software automatically: AutoCAD, Revit, Inventor, Maya, 3ds Max, Civil 3D, Navisworks, Fusion, Vault, InfraWorks, ReCap, DWG TrueView, Desktop Connector, Material Libraries and every other Autodesk-published product on the machine. There is no "keep one product" option.
- **No need to close anything yourself** — the script automatically closes all running Autodesk applications (graceful close attempt, then force-kill, then verifies none remain). Unsaved work in open Autodesk apps will be lost.
- Custom user data **will be permanently deleted**: CUI profiles, tool palettes, plot styles (CTB/STB), templates (DWT/DWT), Revit families, custom LISP routines, Desktop Connector local sync workspace (`%USERPROFILE%\DC`). Back these up first if you need them.
- Your Autodesk licenses/sign-ins are removed — a future reinstall will ask you to sign in again.
- Does **not** delete the FlexNet Licensing Service (shared with Adobe products).
- Registry keys are automatically backed up to `Desktop\Autodesk_Backup_<timestamp>\` (.reg files) before deletion — double-click to restore if ever needed.
- Antivirus may flag the script because it modifies the registry and stops services — it's plain-text PowerShell; read it before running.
- Reboot after the script finishes to release any locked files.

## Requirements

- Windows 10/11
- Administrator PowerShell

## License

MIT
