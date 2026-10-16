# Kodi Playnite Bridge

**Your PC game library, on your CoreELEC home screen.** Browse covers, launch a game on the TV, and return to Kodi when you quit. Recently played, Most played, Favourites and Installed rows come from your Playnite library.

This project grew out of getting Luna/Moonlight working on CoreELEC. The code here is a separate Kodi add-on, Playnite extension and launcher, not a fork of Luna. You do not need Luna itself, but you do need a compatible Moonlight Embedded client.

## What it does

- **Choose a game cover:** starts that game through Playnite, streams it to the TV, and returns to Kodi when the game ends.
- **Choose Open Playnite:** opens the whole library. Play multiple games, then exit Playnite to return to Kodi.
- **Keep the library current:** exports covers and play statistics from Playnite. Optional SSH sync updates Kodi, and optional Windows registration adds/removes Sunshine applications.
- **Restore your desktop:** temporarily uses only the TV display on the PC, then restores the previous monitor layout. A separate recovery process handles launcher failure.

The desktop monitor goes blank during a session. Controllers can stay connected to the PC, or optionally connect to the CoreELEC box. Xbox Bluetooth gameplay and Ugoos UR02 remote navigation were exercised in the development setup. Bluetooth vibration was confirmed through Sunshine/Moonlight with a kernel-matched xpadneo driver. The portable package does not install that driver. See the [step-by-step controller guide](CONTROLLERS.md) before enabling forwarding.

## Is this for your setup?

This is an **experimental source release for technical users**, not a one-click installer or a general Android TV add-on.

| Component | Tested setup |
| --- | --- |
| Kodi client | Ugoos AM6B, CoreELEC Amlogic-ng 21.3 |
| Gaming PC | Windows, Playnite 10.43, Sunshine 2025.924.154138 |
| Stream | 3840 × 2160 at 60 fps, HEVC 10-bit HDR, eight-channel 48 kHz PCM |
| Input | PC-connected Xbox; CoreELEC-connected Xbox Bluetooth gameplay; Xbox USB wireless adapter menu navigation; UR02 remote navigation |
| Games exercised | Stellar Blade; Ori and the Blind Forest |

The client code uses Amlogic-specific display controls and a particular 7.1 HDMI audio device. Different boxes or audio configurations need adaptation. This client does **not** deliver 4K120. Our TV remained in Dolby Vision input mode for films; games use HDR10 at 4K60.

The working private installation was tested on real equipment. The portable configuration layer in this repository has automated tests, but has **not yet been tested as a fresh installation**.

### Verification checklist

Checked items were physically verified on the development setup; unchecked items remain outstanding.

- [x] Game cover launches directly on the TV; normal game exit returns to Kodi.
- [x] Open Playnite browsing, normal exit and desktop restoration.
- [x] Full-screen 4K60 HDR picture and HDMI audio.
- [x] PC-connected Xbox gameplay and CoreELEC Bluetooth Xbox gameplay.
- [x] UR02 remote navigation in Playnite; USB wireless adapter D-pad mapping correction.
- [x] Bluetooth vibration test pulses through Sunshine/Moonlight with a kernel-matched xpadneo 0.9.7 driver.
- [ ] Actual in-game vibration and cold boot with the new driver.
- [ ] USB wireless adapter gameplay and vibration.
- [ ] Repeated reconnect/cold-boot reliability with forwarded controllers and remote.
- [ ] 1440p fullscreen/HDR changes prepared privately; not included as an automatic public default.
- [ ] Fresh installation of the portable package and other hardware/CoreELEC versions.

The [controller guide](CONTROLLERS.md) separates these results in more detail and walks through setup and rollback.

## How the pieces fit together

```text
Playnite library → exported catalogue + covers → Kodi widgets
Kodi game selection → Moonlight → Sunshine → Windows launcher → Playnite/game
Game exit → Playnite closes → display restored → stream ends → Kodi resumes
```

Sunshine is the streaming server on the PC. Moonlight is the streaming client on CoreELEC. Playnite manages the games. This project connects them and handles the handover to and from Kodi.

## Setup on CoreELEC

This guide assumes CoreELEC is already installed and boots into Kodi, with working TV audio and SSH access. The supported starting point is the tested Amlogic-ng setup above; other CoreELEC hardware or builds need backend adaptation. You also need a Windows gaming PC running Playnite and Sunshine on the same home network.

Keep backups and working SSH access to CoreELEC. First verify that ordinary Moonlight streaming from your PC works; do not debug pairing and this launcher at the same time.

### 1. Prepare the PC

Install/configure [Playnite](https://playnite.link/) and [Sunshine](https://docs.lizardbyte.dev/projects/sunshine/latest/). Add your games to Playnite and make sure they launch normally.

Windows must already detect the TV display. Configure Sunshine to capture that display. The launcher selects a Windows monitor; it does not create a virtual monitor or switch your receiver's HDMI input.

### 2. Export the Playnite library

Copy these three files from [`windows/playnite`](windows/playnite) into a new folder under your Playnite `Extensions` directory:

- `extension.yaml`
- `PlayniteBridgeCatalogue.psm1`
- `Sync-Catalogue.ps1`

Restart Playnite. Use its **Extensions → PlayniteBridge → Export PlayniteBridge catalogue** command. The extension creates a `catalogue` folder containing `catalogue.json` and `artwork`.

For automatic transfer, copy `sync-config.example.json` beside the installed extension as `sync-config.json`. Fill in your CoreELEC hostname and trusted SSH host alias. Windows OpenSSH must already connect to that device as root using a key, without a password or host-key prompt. See the [Windows instructions](windows/README.txt).

### 3. Configure the Windows launcher

Keep the `windows/host` folder together in a permanent location. Copy `settings.example.json` to `settings.json` in that folder. Set the Playnite executable path, installed extension directory and exact TV monitor identity.

To list monitor identities without changing displays, open **Windows PowerShell 5.1** in the repository's `windows` folder and run:

```powershell
. .\host\Start-PlayniteBridgeGame.ps1 -LibraryOnly
[PlayniteBridgeDisplay.Native]::Capture() | Select-Object Name, MonitorId, Primary
```

Select the TV's identity, not its friendly name. Sunshine must capture the same display. The wrapper rejects missing or ambiguous monitor identities.

### 4. Register the games with Sunshine

Start with the manual builder. Take a copy of Sunshine's `apps.json`, then run from the `windows` folder:

```powershell
.\host\Build-Apps.ps1 -SettingsPath .\host\settings.json `
  -ExistingApps .\apps-before.json -OutputPath .\apps-generated.json
```

Review the generated file, back up Sunshine's live configuration, and apply it while no stream is running. Restart Sunshine to load it. The result preserves other applications and adds `PlayniteBridge-Playnite` plus `PlayniteBridge-<game ID>` entries. The `PlayniteBridge-` prefix is reserved for this project.

Optional automatic registration is described in [windows/README.txt](windows/README.txt). It uses a protected, on-demand Windows task and supports only the default Sunshine installation. It refuses unsafe file permissions and defers while a stream is active. It does not store your Sunshine password.

### 5. Install the CoreELEC backend and Kodi add-on

Obtain and pair a compatible **Moonlight Embedded** client separately. No Moonlight binary or pairing keys are bundled here. Copy the Python files from [`coreelec`](coreelec) together into `/storage/playnite-bridge`. Put the compatible client and libraries at the paths described in the [CoreELEC instructions](coreelec/README.md).

Create a Moonlight configuration containing your PC address and confirm the client can list your Sunshine applications. Use the same PC address in both Moonlight and the launcher configuration.

Copy `kodi/plugin.program.playnitebridge` into `/storage/.kodi/addons/`, then restart Kodi or refresh local add-ons and enable **Kodi Playnite Bridge**. Alternatively, zip the `plugin.program.playnitebridge` directory and install that ZIP through Kodi's add-on installer.

Copy `kodi/launch_playnite.py` into:

```text
/storage/.kodi/userdata/addon_data/plugin.program.playnitebridge/
```

Copy `kodi/launch-config.example.json` beside it as `launch-config.json`. Replace the example address and paths. Start with `hdr4k: false`; enable it only after ordinary streaming and recovery work on your hardware.

Transfer the exported `catalogue.json` and `artwork` folder into that same add-on userdata directory, or enable the SSH sync from step 2. See [kodi/README.md](kodi/README.md) for the hook configuration.

### 6. Add the home-screen widgets

Use a Kodi skin that supports custom widgets. In its home-menu/widget editor, choose **Add-ons → Programs → Kodi Playnite Bridge**, then select a folder. Exact menu wording depends on your skin.

| Row | Plugin path |
| --- | --- |
| Recently played | `plugin://plugin.program.playnitebridge/?route=recent` |
| Most played | `plugin://plugin.program.playnitebridge/?route=mostplayed` |
| Favourites | `plugin://plugin.program.playnitebridge/?route=favourites` |
| Installed | `plugin://plugin.program.playnitebridge/?route=installed` |

Use a poster/cover layout. This repository does not overwrite your skin or home-menu configuration.

## First test and troubleshooting

For controllers, remote navigation, missing vibration and input lag, follow [CONTROLLERS.md](CONTROLLERS.md). Start with the PC-connected option if you want the fewest setup steps.

1. Close any existing Playnite instance on the PC. Stop Kodi playback.
2. Open **Kodi Playnite Bridge → Open Playnite**. Check the TV picture, sound and controller.
3. Exit Playnite normally. Confirm Kodi is visible and responsive and the desktop monitor returns.
4. Try one game cover and quit the game normally. It should return without a separate Playnite exit.
5. Only then enable 4K HDR and repeat the checks.

| Symptom | Check |
| --- | --- |
| Empty widgets | Catalogue exists in the add-on userdata folder; export/sync completed |
| New game will not launch | Its `PlayniteBridge-<ID>` application is loaded in Sunshine; a file update alone does not refresh Sunshine's in-memory list |
| Game uses the wrong screen | TV identity and Sunshine capture target match; game-specific monitor preferences may interfere |
| Controls feel delayed | Select the TV's Game picture mode for the streaming input; do not change the HDMI signal format just to do this. Then compare controller and network paths |
| Game resolution is locked | Borderless mode often follows the Windows desktop. Try the game's fullscreen mode and select 2560 × 1440 there. Lowering stream resolution alone does not necessarily lower game rendering resolution |
| No audio | The backend is calibrated for AMLAUGESOUND 7.1 PCM; check your actual device rather than assuming stereo is equivalent |
| Frozen Kodi menu over the stream | Kodi's OSD plane may still be visible; never run manual visibility recovery during an active stream |
| Black picture after exit | Inspect mode/OSD restoration; a successful process exit is not proof of visible HDMI output |

For technical recovery, the backend watches `/storage/playnite-bridge/session.stop`. Creating that file requests stream exit; remove it before launching again. This does not promise to close a still-running PC game. Avoid force-killing games with unsaved progress. Do not run display recovery commands concurrently with a new launch.

Diagnostics include `session-result.json` and `kodi-session-result.json` on CoreELEC, Playnite's log, the extension's `sync-status.txt`, and the optional registration task's `apps-update-status.json`. Keep these and all local settings out of public bug reports unless you have removed identifying data.

## Existing installations

The renamed package uses new add-on IDs, paths, extension names and Sunshine application prefixes. It is not an in-place upgrade of the initial release. Existing installations continue working without this update. To migrate, back up your settings and Sunshine apps, disable the old exporter and registration task, then install all renamed components together and reselect the new widget paths. Do not run both registration tasks or mix an old launch hook with new Sunshine entries. Keep the old installation until the replacement passes the first-test checks; remove obsolete Sunshine entries only after that.

## Tests and limits

Python tests live beside the Kodi and CoreELEC components. Windows `Test-*.ps1` scripts use mocks/temporary fixtures; they do not launch games or change monitor layouts. See the component instructions for commands.

Recovery handles normal exits and supervisor termination, but the EOF watchdog does not detect every possible live-process hang. Playnite process tracking varies between games and launchers. The automatic updater checks for an idle stream before restarting Sunshine, but that check and a new launch are not atomic. Test on your hardware before relying on unattended recovery.

## Licence and upstream projects

GPL-3.0-or-later; see [LICENSE](LICENSE). Kodi, Playnite, Sunshine, Moonlight and Luna are separate projects with their own licences. No game data, artwork, credentials or third-party executables are distributed here. The exact corresponding source/build provenance of the community Moonlight binary used during development has not been established, so that binary is deliberately excluded.
