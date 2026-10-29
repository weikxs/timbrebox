import 'dart:io';

import '../design/app_strings.dart';

/// What a plugin may learn about where it runs: the `env` and `process`
/// globals of the sandbox. Nothing here identifies the user or the device.
final class PluginEnvironment {
  const PluginEnvironment({
    required this.appVersion,
    required this.os,
    required this.language,
    this.userVariables = const {},
  });

  /// The running app: its version (set at build time, `dev` otherwise), the
  /// operating system and the language the user chose.
  factory PluginEnvironment.current({
    Map<String, String> userVariables = const {},
  }) => PluginEnvironment(
    appVersion: appVersionFromBuild,
    os: Platform.operatingSystem,
    language: AppStrings.lang == AppLang.en ? 'en-US' : 'zh-CN',
    userVariables: userVariables,
  );

  /// Passed by release builds with `--dart-define=APP_VERSION=<version>`.
  static const appVersionFromBuild = String.fromEnvironment(
    'APP_VERSION',
    defaultValue: 'dev',
  );

  final String appVersion;

  /// `android`, `ios`, `macos`, `windows` or `linux`.
  final String os;

  /// A BCP 47 tag: `zh-CN` or `en-US`.
  final String language;

  /// The values the user entered for this plugin's declared variables.
  final Map<String, String> userVariables;

  Map<String, Object?> toJson() => {
    'appVersion': appVersion,
    'os': os,
    'lang': language,
    'userVariables': userVariables,
  };
}
