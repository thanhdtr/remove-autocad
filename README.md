# Remove-AutoCAD

A single-file PowerShell script that completely removes **all AutoCAD / Autodesk software** from a Windows PC — products, licensing, Genuine Service, and every leftover trace.

Based on [Autodesk's official Clean Uninstall procedure](https://www.autodesk.com/support/technical/article/caas/sfdcarticles/sfdcarticles/Clean-uninstall.html), hardened with techniques from community uninstallers.

## What it removes

| Phase | What |
|---|---|
| 1 | Kills all Autodesk processes (named + **path-based wildcard kill**) & stops services |
| 1b | **Backs up registry keys** to `Desktop\Autodesk_Backup_<timestamp>\` (.reg files) |
| 2 | Silently uninstalls every registered product — handles **ODIS** (2022+), classic MSI, and Identity Manager; loops up to 4 passes for dependency ordering |
| 3 | Removes **Autodesk Genuine Service** (kills its protection markers first) and the **AdskLicensing** service, with `sc delete` + folder fallbacks |
| 4 | Deletes ~17 leftover folder locations (Program Files, ProgramData, FLEXnet, AppData ×2, ODIS cache, CER data, Desktop Connector workspace, `C:\Autodesk` staging — often 5–30 GB), with **takeown/icacls fallback** for locked folders; cleans .NET native image cache |
| 4b | Removes shortcuts (desktop/Start Menu/taskbar pins), scheduled tasks, firewall rules, `ADSKFLEX_LICENSE_FILE` env var, unregisters the DWG shell extension (`AcShellExtension.dll`) |
| 5 | Deep registry clean: Autodesk keys (HKLM/HKCU/WOW6432Node), FLEXlm, COM CLSID/TypeLib deep scan, class keys (`DWGTrueView*`, `acadlt.*`, `adsk.idmgr`…), all 3 Uninstall trees, service keys, dead file associations |
| 6 | Verifies nothing remains; full timestamped log to `%TEMP%` |

## Usage

Right-click PowerShell → **Run as administrator**, then:

```powershell
powershell -ExecutionPolicy Bypass -File .\Remove-AutoCAD.ps1
```

Reboot afterwards to finish the clean.

## ⚠️ Before you run it

- Removes **ALL** Autodesk software, not just AutoCAD.
- Custom user settings (CUI profiles, tool palettes, templates) live in the same AppData folders and **will be deleted** — back them up first if needed.
- Does **not** delete the FlexNet Licensing Service (shared with Adobe products).
- Registry keys are backed up to your Desktop before deletion.

## Requirements

- Windows 10/11
- Administrator PowerShell

## License

MIT
