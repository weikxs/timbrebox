/// Global "reduce visual effects" flag. Widgets read it at build time (like the
/// active palette) so toggling it re-renders without threading a value through
/// every constructor. The controller sets it from the persisted preference.
abstract final class AppEffects {
  static bool reduced = false;
}
