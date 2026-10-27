part of 'app_controller.dart';

/// Appearance: built-in themes and an optional custom skin image.
extension AppControllerAppearance on AppController {
  void _appearanceChanged() {
    _appearance.value = (_themeId, _skinImagePath);
    _notify();
  }

  Future<void> _restoreAppearance() async {
    final store = _appearanceStore;
    if (store == null) return;
    final themeId = await store.loadThemeId();
    final skin = await store.loadSkin();
    if (themeId != null) _themeId = themeId;
    _skinImagePath = skin?.path;
    _appearanceChanged();
  }

  /// Selects a built-in theme and drops any custom skin image.
  Future<void> selectTheme(String id) async {
    _themeId = id;
    _skinImagePath = null;
    _appearanceChanged();
    await _appearanceStore?.saveThemeId(id);
    await _appearanceStore?.clearSkin();
  }

  /// Copies [sourcePath] into app storage and applies it as a custom skin.
  Future<void> setSkinFromFile(String sourcePath) async {
    final store = _appearanceStore;
    if (store == null) return;
    final file = await store.saveSkin(sourcePath);
    _skinImagePath = file.path;
    _appearanceChanged();
  }
}
