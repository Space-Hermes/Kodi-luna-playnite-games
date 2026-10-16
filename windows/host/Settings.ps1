function Read-PlayniteBridgeSettings([string]$Path) {
    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in @('playnite_path','extension_directory')) {
        $value = $settings.$field
        if ($value -isnot [string] -or $value -notmatch '^[A-Za-z]:\\' -or $value -match '["\r\n]') { throw "Invalid absolute local path: $field" }
    }
    if ([IO.Path]::GetFileName($settings.playnite_path) -ne 'Playnite.FullscreenApp.exe' -or
        ![IO.File]::Exists($settings.playnite_path)) { throw 'Playnite Fullscreen executable not found' }
    if (![IO.Directory]::Exists($settings.extension_directory)) { throw 'Extension directory not found' }
    if ($settings.monitor_id -isnot [string] -or !$settings.monitor_id.StartsWith('MONITOR\') -or $settings.monitor_id -match '[\r\n]') { throw 'Expected exact Windows monitor identity' }
    return $settings
}
