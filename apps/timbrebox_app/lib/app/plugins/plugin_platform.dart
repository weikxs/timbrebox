import 'dart:io';

/// Whether third-party plugin code may be downloaded and run on [os] (a
/// [Platform.operatingSystem] value): the five platforms TimbreBox ships
/// for. Every plugin runs in its own sandboxed engine with a time limit (see
/// PluginRuntime and script_time_limit.dart).
bool pluginsAllowedOn(String os) =>
    const {'android', 'ios', 'macos', 'windows', 'linux'}.contains(os);

/// [pluginsAllowedOn] for the platform this runs on.
bool get pluginsAllowedHere => pluginsAllowedOn(Platform.operatingSystem);
