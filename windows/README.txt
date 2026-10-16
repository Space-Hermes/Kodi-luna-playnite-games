Kodi Playnite Bridge - Windows source component

Requires Windows PowerShell 5.1, Playnite 10 scripting, Sunshine, and the paired
CoreELEC client component. Keep the controller connected to the PC. This source
package contains no Moonlight executable, pairing credentials or game library.

1. Copy playnite/ runtime files (extension.yaml, PlayniteBridgeCatalogue.psm1 and
   Sync-Catalogue.ps1) into a Playnite Extensions folder. Restart Playnite and
   use Extensions > PlayniteBridge > Export PlayniteBridge catalogue. Export includes all games;
   the Kodi browser excludes hidden entries. Playnite 11 compatibility is untested.
2. Copy host/settings.example.json to settings.json and supply the full Playnite
   executable path, extension directory and exact monitor identity. Obtain the
   identity read-only in Windows PowerShell:
     . .\host\Start-PlayniteBridgeGame.ps1 -LibraryOnly
     [PlayniteBridgeDisplay.Native]::Capture() | Select Name,MonitorId,Primary
   Choose the TV monitor. Sunshine capture must independently target that same
   display. Wrapper rejects an absent/ambiguous monitor, but cannot establish that
   the selected monitor is physically the user's TV. Existing Playnite must close
   before starting an owned session. Recovery restores the previous display layout.
3. Optional cache sync: copy playnite/sync-config.example.json as sync-config.json
   beside the installed extension. Configure host and already-trusted known_hosts
   alias. OpenSSH key authentication as root must work without prompts. Only the
   CoreELEC plugin cache is written; no remote files are deleted. Transfers run in
   the background, publish JSON last, and report in sync-status.txt. In owned gaming
   sessions, WMI starts the sync independently of Sunshine's application job.
4. Manual registration: run host/Build-Apps.ps1 with -SettingsPath, -ExistingApps
   (a copy of Sunshine apps.json), and -OutputPath (a new file). Review output and
   back up live configuration before applying it while Sunshine is idle. Existing
   apps outside the reserved PlayniteBridge- prefix are preserved. Repeat after installs
   or removals. The builder does not restart services or replace live configuration.
5. Optional automatic registration: fill registration.example.json locally, then
   run Install-Registration.ps1 -RegistrationConfig <absolute JSON path> from an
   elevated 64-bit Windows PowerShell running as the same user as Playnite. It
   installs only the updater and its validated settings into Program Files/PlayniteBridge
   with Administrator ownership, SYSTEM/Admin write and Users read/execute. The
   fixed elevated task reads that protected config; catalogue data supplies only
   validated GUIDs/booleans, never executable paths or commands. Generated apps
   explicitly run unelevated. Review this installation before running it; it has
   offline tests but this portable installer has not been deployed or live-tested.
   Verify task result and apps-update-status.json, then create an empty file named
   registration-enabled beside the Playnite extension. Exports request the task
   after startup, library updates, installation, removal and game stop. Active
   streaming defers updates until another export; trigger the manual export later.
   No arbitrary user-supplied updater commands or elevated script hooks exist.
   Automatic registration supports only Program Files/Sunshine/config/apps.json.
   Sunshine's directory, config directory and apps file must be owned by SYSTEM,
   Administrators or TrustedInstaller, with no other principal granted write,
   delete, ownership or permission-change rights. Setup and each run reject an
   unsafe ACL rather than changing Sunshine permissions automatically. Use the
   unelevated manual builder for non-default installations.

Generic PlayniteBridge-Playnite uses -Browse: games may be played sequentially; exit
Playnite to return. Individual PlayniteBridge-GUID entries use --start GUID and an owned
process marker: normal selected-game exit queues Playnite shutdown after export.
Other games, manually stopped tracking and foreign/stale markers do not trigger
automatic shutdown. Game tracking accuracy depends on the Playnite integration.

Tests: run playnite/Test-*.ps1, host/Test-Browse.ps1,
host/Test-UpdatePlayniteBridgeApps.ps1 and host/Start-PlayniteBridgeGame.ps1 -SelfTest. These use
temporary fixtures/mocks and do not launch games or alter display configuration.
Use host/Build-Apps.ps1 only with copied input for review. Actual setup still needs
normal-exit, forced-recovery, display, audio and controller verification on target
hardware. This portable version has no live acceptance claim.

To disable automatic registration remove registration-enabled and unregister
the PlayniteBridge Update Games scheduled task. Keep protected files until any task run
has finished. Preserve your Sunshine backup for restoring the previous app list.
