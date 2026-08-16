#include <sys/socket.h>
#include <linux/netlink.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
int main(void){
  struct sockaddr_nl a={.nl_family=AF_NETLINK};
  int s=socket(AF_NETLINK,SOCK_RAW|SOCK_CLOEXEC,NETLINK_ROUTE);
  if(s<0){printf("socket: FAIL errno=%d (%s)\n",errno,strerror(errno));return 1;}
  printf("socket: OK fd=%d\n",s);
  if(bind(s,(struct sockaddr*)&a,sizeof(a))<0){printf("bind: FAIL errno=%d (%s)\n",errno,strerror(errno));return 2;}
  printf("bind: OK\n");
  return 0;
}
