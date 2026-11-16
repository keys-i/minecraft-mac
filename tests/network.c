#include <assert.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <sys/socket.h>
#include <unistd.h>

int main(void) {
  int fd = socket(AF_INET, SOCK_DGRAM, 0);
  assert(fd >= 0);
  struct sockaddr_in address = {.sin_len = sizeof(address), .sin_family = AF_INET};
  assert(bind(fd, (struct sockaddr*)&address, sizeof(address)) == 0);
  socklen_t size = sizeof(address);
  assert(getsockname(fd, (struct sockaddr*)&address, &size) == 0);
  assert(address.sin_addr.s_addr == htonl(INADDR_LOOPBACK));
  close(fd);

  fd = socket(AF_INET6, SOCK_DGRAM, 0);
  assert(fd >= 0);
  struct sockaddr_in6 six = {.sin6_len = sizeof(six), .sin6_family = AF_INET6};
  assert(bind(fd, (struct sockaddr*)&six, sizeof(six)) == 0);
  size = sizeof(six);
  assert(getsockname(fd, (struct sockaddr*)&six, &size) == 0);
  assert(IN6_IS_ADDR_LOOPBACK(&six.sin6_addr));
  close(fd);

  fd = socket(AF_INET, SOCK_DGRAM, 0);
  assert(fd >= 0);
  address.sin_addr.s_addr = htonl(0xC0000201);
  address.sin_port = 0;
  errno = 0;
  assert(bind(fd, (struct sockaddr*)&address, sizeof(address)) == -1);
  assert(errno == EACCES);
  close(fd);
  puts("Generator IPv4/IPv6 bindings stay on loopback and reject other interfaces");
}
