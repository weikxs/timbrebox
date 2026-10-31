// Local media-tool supervisor. No shell, stdin commands or persistent service.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
static volatile sig_atomic_t cancelled = 0;
static void stop(int signal_number) { (void)signal_number; cancelled = 1; }

int main(int argc, char **argv) {
  char executable[PATH_MAX];
  if (!realpath(argv[0], executable)) return 126;
  char *separator = strrchr(executable, '/');
  if (!separator) return 126;
  *(separator + 1) = '\0';
  char extractor[PATH_MAX];
  int length = snprintf(extractor, sizeof(extractor),
      "%s../../../../Resources/TimbreBoxMedia/Extractor/yt-dlp", executable);
  if (length < 0 || (size_t)length >= sizeof(extractor)) return 126;
  char **arguments = calloc((size_t)argc + 1, sizeof(char *));
  if (!arguments) return 126;
  arguments[0] = extractor;
  for (int i = 1; i < argc; i++) arguments[i] = argv[i];

  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = stop;
  sigemptyset(&action.sa_mask);
  sigaction(SIGTERM, &action, NULL);
  sigaction(SIGINT, &action, NULL);
  sigaction(SIGHUP, &action, NULL);
  const pid_t parent = getppid();
  posix_spawnattr_t attributes;
  if (posix_spawnattr_init(&attributes)) { free(arguments); return 126; }
  if (posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP) ||
      posix_spawnattr_setpgroup(&attributes, 0)) {
    posix_spawnattr_destroy(&attributes); free(arguments); return 126;
  }
  pid_t child;
  int error = posix_spawn(&child, extractor, NULL, &attributes, arguments, environ);
  posix_spawnattr_destroy(&attributes);
  free(arguments);
  if (error) return 126;
  const struct timespec interval = {0, 50000000};
  int status = 0;
  for (;;) {
    pid_t result = waitpid(child, &status, WNOHANG);
    if (result == child) break;
    if (result < 0 && errno != EINTR) { kill(-child, SIGKILL); return 126; }
    if (cancelled || getppid() != parent) {
      kill(-child, SIGKILL);
      while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
      return 125;
    }
    nanosleep(&interval, NULL);
  }
  // A finished extractor must not leave a JS worker running in its group.
  kill(-child, SIGKILL);
  return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
