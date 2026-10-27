import 'dart:io';

/// Whether third-party plugin code may be downloaded and run on [os] (a
/// [Platform.operatingSystem] value). Desktop only: mobile builds never
/// fetch or execute plugin code.
bool pluginsAllowedOn(String os) =>
    const {'macos', 'windows', 'linux'}.contains(os);

/// [pluginsAllowedOn] for the platform this runs on.
bool get pluginsAllowedHere => pluginsAllowedOn(Platform.operatingSystem);
