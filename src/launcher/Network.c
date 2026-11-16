#include <errno.h>
#include <crt_externs.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>

// The isolated generator never needs a listener reachable from another machine
static int local_bind(int socket, const struct sockaddr* address, socklen_t size) {
  int generator = 0;
  char** arguments = *_NSGetArgv();
  for (int i = 0; i < *_NSGetArgc(); ++i) {
    const char* file = strrchr(arguments[i], '/');
    file = file ? file + 1 : arguments[i];
    const char* windows = strrchr(file, '\\');
    file = windows ? windows + 1 : file;
    if (strcmp(file, "bedrock_server.exe") == 0) generator = 1;
  }
  if (!generator) return bind(socket, address, size);
  struct sockaddr_storage storage;
  if (address && size <= sizeof(storage) && size >= sizeof(struct sockaddr)) {
    memcpy(&storage, address, size);
    if (address->sa_family == AF_INET && size >= sizeof(struct sockaddr_in)) {
      struct sockaddr_in* local = (struct sockaddr_in*)&storage;
      if (local->sin_addr.s_addr == htonl(INADDR_ANY)) {
        local->sin_addr.s_addr = htonl(INADDR_LOOPBACK);
      } else if ((ntohl(local->sin_addr.s_addr) >> 24) != 127) {
        errno = EACCES;
        return -1;
      }
      return bind(socket, (const struct sockaddr*)local, size);
    }
    if (address->sa_family == AF_INET6 && size >= sizeof(struct sockaddr_in6)) {
      struct sockaddr_in6* local = (struct sockaddr_in6*)&storage;
      if (IN6_IS_ADDR_UNSPECIFIED(&local->sin6_addr)) {
        local->sin6_addr = in6addr_loopback;
      } else if (!IN6_IS_ADDR_LOOPBACK(&local->sin6_addr)) {
        errno = EACCES;
        return -1;
      }
      return bind(socket, (const struct sockaddr*)local, size);
    }
  }
  return bind(socket, address, size);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct {
  const void* replacement;
  const void* original;
} binding = {(const void*)local_bind, (const void*)bind};
