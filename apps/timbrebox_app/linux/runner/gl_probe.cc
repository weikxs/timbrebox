#include "gl_probe.h"

#include <epoxy/gl.h>

gchar* gl_probe_renderer(GtkWidget* toplevel) {
  gtk_widget_realize(toplevel);
  GdkWindow* window = gtk_widget_get_window(toplevel);
  if (window == nullptr) return g_strdup("");

  g_autoptr(GError) error = nullptr;
  g_autoptr(GdkGLContext) context =
      gdk_window_create_gl_context(window, &error);
  if (context == nullptr || !gdk_gl_context_realize(context, &error)) {
    return g_strdup("");
  }
  gdk_gl_context_make_current(context);
  const GLubyte* renderer = glGetString(GL_RENDERER);
  // A context without a name is odd but not proof of a CPU renderer.
  gchar* result = g_strdup(renderer != nullptr
                               ? reinterpret_cast<const gchar*>(renderer)
                               : "unknown");
  gdk_gl_context_clear_current();
  return result;
}

gchar** gl_probe_append_argument(gchar** arguments, const gchar* renderer) {
  const guint count = arguments == nullptr ? 0 : g_strv_length(arguments);
  gchar** result = g_new0(gchar*, count + 2);
  for (guint i = 0; i < count; i++) result[i] = g_strdup(arguments[i]);
  result[count] = g_strdup_printf("--timbrebox-gl-renderer=%s", renderer);
  return result;
}
