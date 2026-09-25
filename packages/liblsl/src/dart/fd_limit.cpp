// Raises the process's soft open-file limit when liblsl is loaded.
//
// Every outlet, inlet and resolver holds several sockets, and the default
// soft limits (256 on macOS, 1024 on most Linux desktops) run out with a few
// dozen streams: liblsl then logs "Too many open files" and fails to create
// outlets and inlets.
//
// - A soft limit of at least kEnough is left untouched.
// - Otherwise the soft limit is raised as far as the system allows (the hard
//   limit and, on macOS, kern.maxfilesperproc), up to kTarget.
// - The hard limit is never changed and the soft limit is never lowered.
// - Failing to raise it (e.g. a sandbox or a management tool forbidding it)
//   only prints a warning to stderr; liblsl loads and works as before.
//
// Set LIBLSL_DART_NO_RLIMIT=1 to leave the limit untouched.
//
// Compiled for macOS and Linux only (see hook/build.dart). Runs while the
// library is being loaded, before liblsl's own logging is set up, hence stderr.

#include <sys/resource.h>

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#ifdef __APPLE__
#include <sys/sysctl.h>
#include <sys/syslimits.h>
#endif

namespace {

// Soft limits at or above this are high enough for LSL: leave them alone.
constexpr rlim_t kEnough = 65536;
// How far to go when raising.
constexpr rlim_t kTarget = 1048576;

void warn(rlim_t from, rlim_t to, int error) {
  std::fprintf(stderr,
               "liblsl: could not raise the open file limit from %llu to %llu "
               "(%s); continuing with %llu. Many streams may fail with \"Too "
               "many open files\"; raise it with `ulimit -n`.\n",
               static_cast<unsigned long long>(from),
               static_cast<unsigned long long>(to), std::strerror(error),
               static_cast<unsigned long long>(from));
}

__attribute__((constructor)) void liblsl_dart_raise_fd_limit() {
  const char *off = std::getenv("LIBLSL_DART_NO_RLIMIT");
  if (off != nullptr && off[0] != '\0' && off[0] != '0') return;

  struct rlimit limit;
  if (getrlimit(RLIMIT_NOFILE, &limit) != 0) return;
  const rlim_t current = limit.rlim_cur;
  if (current == RLIM_INFINITY || current >= kEnough) return;

  rlim_t target = kTarget;
  if (limit.rlim_max != RLIM_INFINITY && limit.rlim_max < target) {
    target = limit.rlim_max;
  }
#ifdef __APPLE__
  // macOS rejects a soft limit above kern.maxfilesperproc.
  int per_proc = 0;
  size_t size = sizeof(per_proc);
  if (sysctlbyname("kern.maxfilesperproc", &per_proc, &size, nullptr, 0) == 0 &&
      per_proc > 0 && static_cast<rlim_t>(per_proc) < target) {
    target = static_cast<rlim_t>(per_proc);
  }
#endif
  // Nothing more is allowed (e.g. the hard limit is the soft limit).
  if (target <= current) return;

  limit.rlim_cur = target;
  if (setrlimit(RLIMIT_NOFILE, &limit) == 0) return;
  int error = errno;
#ifdef __APPLE__
  // Older macOS versions cap the soft limit at OPEN_MAX.
  if (target > OPEN_MAX && current < OPEN_MAX) {
    limit.rlim_cur = OPEN_MAX;
    if (setrlimit(RLIMIT_NOFILE, &limit) == 0) return;
    error = errno;
  }
#endif
  warn(current, target, error);
}

}  // namespace
