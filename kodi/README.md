# Kodi library and launch hook

Install `plugin.program.playnitebridge` as a Kodi Python add-on. Its catalogue folders can be selected as skin widgets; skin/home-menu configuration is intentionally separate. The add-on reads `catalogue.json` and relative artwork from its userdata directory. The companion Playnite exporter supplies them.

Copy `launch_playnite.py` into `special://profile/addon_data/plugin.program.playnitebridge/`. Copy `launch-config.example.json` beside it as `launch-config.json`, replace the documentation-only host address and paths, and match the host to the Moonlight configuration's address. The hook passes explicit arguments to the CoreELEC backend. It selects the matching Sunshine `PlayniteBridge-<game GUID>` entry, or `PlayniteBridge-Playnite` for browsing. Those host applications must already exist.

The library UI is separate from the hardware-specific streaming backend: see `../coreelec/README.md` before enabling launch. Neither the configuration nor catalogue is bundled with personal data.

Tests: run `python -m unittest test_launch` here, and `python -m unittest test_addon test_catalogue` inside the plugin directory.
