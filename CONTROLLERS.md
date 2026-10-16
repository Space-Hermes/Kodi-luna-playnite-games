# Controllers and remote: step by step

This guide assumes you already have the bridge launching Playnite and returning to Kodi. Do not change input settings while someone is watching Kodi. Keep the ordinary remote available for recovery.

## What has actually been tested?

Checked means a person tested that behaviour on the development Ugoos AM6B/CoreELEC Amlogic-ng 21.3 installation. It does not mean every controller, firmware or CoreELEC version works.

- [x] Xbox connected directly to the Windows PC: Playnite navigation and gameplay.
- [x] Xbox connected to CoreELEC by Bluetooth: Kodi navigation and gameplay.
- [x] Xbox wireless USB adapter on CoreELEC with a locally built xow driver: stick, A/B and corrected D-pad navigation in Playnite.
- [x] Ugoos UR02 remote: navigation in Playnite after releasing Kodi's input grab.
- [x] TV Game picture mode: user reported substantially improved responsiveness.
- [x] Bluetooth vibration: three physical pulses confirmed from Windows through Sunshine and Moonlight with a kernel-matched xpadneo 0.9.7 build.
- [x] Controller power-cycle: the new driver bound automatically and vibrated on connection.
- [x] Actual in-game Bluetooth vibration in Stellar Blade; strength felt weak, with no direct-PC comparison yet.
- [x] Kodi navigation with the new driver and playback-menu access with five-second auto-hide.
- [x] Software reboot: Kodi started and xpadneo 0.9.7 loaded automatically.
- [x] Xbox reconnect and Kodi D-pad/A/B navigation after reboot, confirmed by the user.
- [ ] Full power-off cold boot.
- [ ] USB wireless adapter gameplay, all buttons and vibration.
- [ ] Full Bluetooth button-by-button and vibration acceptance test.
- [x] Recovery of a dropped Bluetooth controller by reconnecting the stream without restarting Stellar Blade; picture and gameplay confirmed by the user.
- [ ] Bluetooth disconnect/reconnect during an active stream after the hotplug fix.
- [ ] Repeated reconnect, cold boot and consecutive-session reliability with forwarded inputs.
- [ ] Remote Home key during streaming: not implemented as a return-to-Kodi shortcut.
- [ ] 1440p fullscreen/HDR: prepared privately, not yet visually verified; not included as an automatic public-launcher change.
- [ ] Fresh installation of this portable package on another machine.

## Option A: keep the Xbox connected to the PC

This is the simplest starting point if the PC is within controller range.

1. Connect the Xbox to Windows as you normally would.
2. Leave `input_device_names` empty in `launch-config.json`.
3. Start **Open Playnite** from Kodi and use the Xbox.
4. Exit Playnite normally to return to Kodi.

The stream is view-only in this mode; the PC receives the controller directly.

## Option B: connect the Xbox by Bluetooth to CoreELEC

1. Exit any game and return to Kodi. Unplug the Xbox wireless USB adapter if you used it previously.
2. Open the **CoreELEC** settings add-on and enable Bluetooth in its services settings if it is off.
3. Turn on the Xbox controller. Hold its pairing button until the Xbox light flashes quickly.
4. Open CoreELEC's **Bluetooth** page, select **Xbox Wireless Controller**, then pair/connect. The light should become steady.
5. Try the D-pad, A and B in Kodi before starting a stream.

### Paired, but Kodi ignores the buttons?

The tested Bluetooth controller was detected as **Xbox Wireless Controller, 15 buttons, 8 axes**. Kodi's bundled profile did not match it. For that exact layout, copy the included file:

`kodi/buttonmaps/Xbox_Wireless_Controller_15b_8a.xml`

into this CoreELEC folder (create missing folders):

```text
/storage/.kodi/userdata/addon_data/peripheral.joystick/resources/buttonmaps/xml/linux/
```

Use an SFTP client to copy files: connect to your CoreELEC hostname using the SSH access you set up for the main installation. Turn the controller off and on to reload it. If your device has a different name or axis/button count, use Kodi's controller configuration instead of forcing this profile. A driver update can also change the layout.

### Forward the controller into Playnite

1. Copy `coreelec/gamecontrollerdb.example.txt` beside your Moonlight executable, usually as `/storage/playnite-bridge/bin/gamecontrollerdb.txt` (remove `.example` from the filename). This small file contains only the two tested Xbox mappings. If a database already exists, back it up and merge these entries by their exact GUID rather than discarding support for other controllers. No Moonlight binary is bundled.
2. Open the add-on's `launch-config.json`. Keep the existing fields and add this field (JSON fields need commas between them):

```json
"input_device_names": ["Xbox Wireless Controller"]
```

3. Ensure the Moonlight configuration does not contain `viewonly = true`.
4. Start **Open Playnite**. Test D-pad, stick, A and B, then a familiar game.
5. Exit normally and confirm Kodi responds again.

The launcher discovers the current input event number by device name for the Kodi handoff. Do not hard-code `/dev/input/event5`: it can change when devices reconnect. With no matching connected devices, the launcher falls back to view-only; pair/connect before launching.

When forwarding is enabled, Moonlight automatically discovers local input devices and watches for reconnects. `input_device_names` selects which connected devices Kodi must release; it is not a Moonlight input allowlist. Other compatible local keyboards, mice and controllers may also be forwarded. Remove any static `input` entries from the Moonlight configuration: explicit device selection disables its automatic reconnect handling.

## Add the Ugoos remote for Playnite navigation

For the tested UR02 remote, use:

```json
"input_device_names": ["UR02", "Xbox Wireless Controller", "Xbox One Wireless Controller"]
```

Test arrows, OK and Back in Playnite. Kodi can exclusively grab the remote even when paused. The supervisor temporarily removes the selected devices from Kodi's input discovery, lets Moonlight discover inputs automatically, then re-adds the selected devices during cleanup. This is why simply adding a Moonlight input argument was not sufficient.

The remote's Home key is separate from this forwarding feature. In Kodi, use the Keymap Editor add-on to assign **Home** to the remote button if it currently does nothing. Do not overwrite your entire keymap with somebody else's file. Home is not currently a stream-exit button; exit Playnite through its menu.

## Xbox wireless USB adapter: advanced, not plug-and-play

The tested adapter required [xow](https://github.com/medusalix/xow). CoreELEC did not include a working driver for it. The development build was temporary and was not installed as a boot service. This repository does not ship xow binaries, Microsoft firmware or an unattended installer.

If you already have a working xow installation, add `Xbox One Wireless Controller` to `input_device_names`. For the tested xow SDL GUID `030000005e040000120b00000f050000`, D-pad entries must be hats: `dpup:h0.1`, `dpdown:h0.4`, `dpleft:h0.8`, `dpright:h0.2`. Back up your existing mapping before changing only the matching entry. Do not apply this USB mapping to the Bluetooth controller.

Non-expert users should start with Option A or B rather than trying to build a kernel/USB driver from this guide.

## Fix delay before changing lots of settings

1. Set the TV's picture mode for the CoreELEC input to **Game**. This improved responsiveness in the physical test. Picture mode is separate from HDMI signal format: leave your Dolby Vision/HDMI compatibility setting alone.
2. Compare the same game with the controller attached to the PC. This helps separate Bluetooth delay from video/game delay.
3. Prefer a stable wired network where possible. A fast idle ping does not prove smooth streaming under load.
4. If the GPU is struggling, reduce the game's rendering resolution or graphics quality. Borderless games can lock resolution to the Windows desktop; fullscreen may expose a resolution selector. A lower stream resolution alone does not guarantee lower game rendering resolution.

The xpadneo project documents a [Bluetooth LE timing workaround](https://github.com/atar-axis/xpadneo/blob/master/docs/TROUBLESHOOTING.md). We tested a temporary 10 ms connection interval, but have **not isolated a measurable benefit**. It is not installed automatically or presented as a proven lag fix.

## Bluetooth vibration: tested fix and limits

The tested CoreELEC 4.9 kernel bound the controller to a generic driver with no force-feedback capability. Its bundled xpadneo 0.6 did not support this controller's newer Bluetooth identity. Moonlight forwarding cannot supply a capability missing from the device driver.

We built [xpadneo v0.9.7](https://github.com/atar-axis/xpadneo/tree/v0.9.7) for CoreELEC Amlogic-ng 21.3 avdvplus R9, kernel `4.9.269`. It passed the kernel compatibility checks without force-loading. The user confirmed a Linux force-feedback pulse and three pulses sent from Windows through Sunshine and Moonlight. Reconnecting selected the new driver automatically. Its startup service is enabled. In-game effects were subsequently confirmed in Stellar Blade, although their strength felt weak and has not been compared with a direct PC connection.

The portable bridge does **not** install or bundle this kernel module. It must be built for your exact CoreELEC kernel; matching the version number alone is insufficient. Newer xpadneo releases are not a drop-in replacement for this old kernel.

With a compatible driver installed:

1. Turn the Xbox off and on. The tested driver vibrates briefly when it connects.
2. Open Playnite from Kodi and start a game with vibration enabled in its settings.
3. Test vibration, D-pad, sticks, A/B, shoulders and triggers, then exit normally.
4. Repeat after a reboot when nobody is watching Kodi.

The new driver reports **12 buttons and 9 axes**. For that exact layout, use `kodi/buttonmaps/Xbox_Wireless_Controller_12b_9a.xml` in the same Kodi buttonmap directory described above. The 15-button/8-axis profile is for the stock generic driver. Kodi navigation with the new profile was confirmed by the user. Moonlight's existing mapping for GUID `050000005e0400008e02000030110000` matches the new driver's standard Xbox layout.

Our local installation uses a startup service and the upstream reconnect rule. Keep the old configuration available for rollback; do not restart drivers or reboot during somebody else's playback.

## Undo the forwarding changes

Exit the stream normally, set `input_device_names` back to `[]`, and reconnect the controller to the PC. Remove only the custom Kodi buttonmap you added if it causes incorrect navigation. Restore your backed-up Moonlight mapping if necessary. Do not restart Kodi or Bluetooth during somebody else's playback.

## Xbox playback menu in Kodi

On the tested Arctic Zephyr Mod skin, Xbox input did not reset the idle timer used by the five-second menu auto-hide. The menu opened and immediately closed. This optional mapping keeps the auto-hide setting and routes Xbox menu actions through Kodi's timer-aware input API. The user confirmed opening and navigating the menu.

1. Copy `coreelec/xbox_kodi_action.py` to `/storage/playnite-bridge/xbox_kodi_action.py`.
2. Copy `kodi/buttonmaps/xbox-playback-keymap.xml` to `/storage/.kodi/userdata/keymaps/xbox-playback.xml`. This file belongs in **keymaps**, not the joystick buttonmap directory. If you use a different script directory, update its paths in the XML.
3. Reload keymaps with `kodi-send --action=ReloadKeymaps`, or restart Kodi when playback has stopped. If Kodi has not picked up a newly installed controller profile, reload its Joystick Support add-on as well.
4. During a movie, A opens the playback menu. Use the D-pad or left stick to navigate, A to select and B to close. Keep the skin's five-second auto-hide enabled.

This overrides the default controller profile in these two Kodi windows, so other gamepads using that profile share the mapping. It does not change Ugoos remote keys or streamed-game controls. To undo it, remove this custom keymap and reload keymaps.

## Controller connected, but the running game stops receiving input

An earlier launcher passed fixed `-input` devices to Moonlight. After a Bluetooth disconnect, CoreELEC could recreate the controller while the existing Moonlight stream no longer read it. The current supervisor omits that static selection so Moonlight can detect arriving devices.

Update `session_stream.py` in your installed backend directory after backing it up. The fix applies on the next stream launch and persists across reboot; replacing the file does not change an already-running process. Keep your configured paths and mapping database. A fresh Bluetooth dropout/reconnect during gameplay remains an acceptance check.

For an already-running game, an operator can reconnect through `kodi_session.py` with the normal host/config/app/input arguments plus `--resume-app-id <current Sunshine numeric app ID>`. Use the same app name and the ID read from that host's `serverinfo`, not a Playnite GUID. End the old client stream normally first, confirm its cleanup and Kodi audio recovery completed, and do not quit the PC game or use `--quit-app-after`. The guard refuses a different/no active app; ordinary launches still refuse a busy host. Run through Kodi so its audio handoff and recovery remain active.

During the verified recovery, the Windows desktop reverted to two monitors and the game appeared on the PC screen. Restoring the existing TV-only layout returned the game to the stream. Automatic Windows display restoration on stream reconnect is not implemented by this patch. Check the TV picture after reconnecting; this controller fix does not guarantee game-window placement.
