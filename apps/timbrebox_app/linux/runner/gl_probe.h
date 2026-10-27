#ifndef RUNNER_GL_PROBE_H_
#define RUNNER_GL_PROBE_H_

#include <gtk/gtk.h>

// Returns the OpenGL renderer GDK gets for |toplevel| (e.g. "llvmpipe (LLVM
// 15.0.7, 256 bits)" when drawing on the CPU), or "" when no GL context can be
// made. Realizes |toplevel|. The caller frees the string with g_free.
gchar* gl_probe_renderer(GtkWidget* toplevel);

// Returns a copy of |arguments| with the renderer appended as
// --timbrebox-gl-renderer=<renderer>, read by the Dart side to turn visual
// effects off by default without a GPU. The caller frees it with g_strfreev.
gchar** gl_probe_append_argument(gchar** arguments, const gchar* renderer);

#endif  // RUNNER_GL_PROBE_H_
