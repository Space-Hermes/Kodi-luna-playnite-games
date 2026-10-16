# CoreELEC NG backend

Experimental, hardware-specific backend derived from an Amlogic Ugoos/CoreELEC NG setup. It uses Amlogic sysfs display planes, `decoder amvideo`, and the AMLAUGESOUND 7.1 HDMI device (`pcm3p`). It is not a generic Kodi/Linux launcher. By default the controller connects to the PC and Moonlight runs with `-viewonly`. Optional CoreELEC input forwarding is described in the [controller guide](../CONTROLLERS.md), including its tested limits and recovery steps.

Supply your own compatible Moonlight Embedded binary and libraries, pair it with Sunshine, and create its configuration containing `address = YOUR_PC_ADDRESS`. No binaries, pairing keys or game catalogue are included. Place these Python modules together in `/storage/playnite-bridge`, or the explicit directory in the Kodi hook configuration. The host and Moonlight config arguments are required.

The Kodi caller refuses active playback, releases HDMI audio, and launches a supervisor in its own process group. Recovery restores display state and resumes Kodi after normal client exit or supervisor death. A local `session.stop` file or SIGTERM requests exit. Remove that file before starting another session. A live but hung supervisor is not covered by the EOF watchdog.

4K60 HDR is optional and defaults off in the example hook. It changes the HDMI mode and restores it on exit. Restoration settles the mode before restoring OSD planes. The private installation returned visibly to Kodi in supervised tests; the portable configuration layer still needs a fresh installation test. Do not assume the backend works on different hardware from passing unit tests.

Run offline tests from this directory: `python -m unittest test_session test_display_restore`.

Controller forwarding now uses Moonlight automatic input discovery so devices can reconnect. See the [controller recovery instructions](../CONTROLLERS.md#controller-connected-but-the-running-game-stops-receiving-input) for its broader input scope, the guarded `--resume-app-id` recovery path, and the remaining Windows display-reconnect limitation.
