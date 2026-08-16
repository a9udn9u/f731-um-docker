#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <sched.h>

static int copy_self(int outfd)
{
	char buf[65536];
	ssize_t n;
	int in = open("/proc/self/exe", O_RDONLY);

	if (in < 0) return -1;
	while ((n = read(in, buf, sizeof(buf))) > 0)
		if (write(outfd, buf, n) != n) return -1;
	close(in);
	return 0;
}

static void child_ok(const char *tag)
{
	printf("PROBE_%s_OK pid=%d\n", tag, getpid());
	_exit(0);
}

int main(int argc, char **argv)
{
	if (argc > 1) {
		child_ok(argv[1]);
		return 0;
	}

	/* 1. exec of a regular file the app wrote itself */
	{
		char path[512];
		int fd;
		snprintf(path, sizeof(path), "%s/umdprobe-copy", getenv("PWD") ? getenv("PWD") : ".");
		fd = open(path, O_CREAT | O_TRUNC | O_WRONLY, 0755);
		if (fd < 0 || copy_self(fd) < 0) {
			printf("PROBE_EXEC_FILE_WRITE_FAIL: %s\n", strerror(errno));
		} else {
			close(fd);
			pid_t p = fork();
			if (p == 0) {
				execl(path, "x", "FILE", NULL);
				printf("PROBE_EXEC_FILE_EXEC_FAIL: %s\n", strerror(errno));
				_exit(1);
			}
			int st;
			waitpid(p, &st, 0);
			if (WIFEXITED(st) && WEXITSTATUS(st) == 0)
				printf("PROBE_EXEC_FILE_OK\n");
			else
				printf("PROBE_EXEC_FILE_CHILD_FAIL: %d\n", st);
		}
		unlink(path);
	}

	/* 2. memfd exec */
	{
		int fd = syscall(SYS_memfd_create, "umdprobe", 0);
		if (fd < 0) {
			printf("PROBE_MEMFD_CREATE_FAIL: %s\n", strerror(errno));
		} else if (copy_self(fd) < 0) {
			printf("PROBE_MEMFD_WRITE_FAIL: %s\n", strerror(errno));
		} else {
			pid_t p = fork();
			if (p == 0) {
				char fdp[16];
				snprintf(fdp, sizeof(fdp), "%d", fd);
				/* fexecve via /proc/self/fd works around execve-at on some kernels */
				char proc[64];
				snprintf(proc, sizeof(proc), "/proc/self/fd/%d", fd);
				execv(proc, (char *[]){"x", "MEMFD", NULL});
				execl(proc, "x", "MEMFD", NULL);
				printf("PROBE_MEMFD_EXEC_FAIL: %s\n", strerror(errno));
				_exit(1);
			}
			int st;
			waitpid(p, &st, 0);
			if (WIFEXITED(st) && WEXITSTATUS(st) == 0)
				printf("PROBE_MEMFD_OK\n");
			else
				printf("PROBE_MEMFD_CHILD_FAIL: %d\n", st);
		}
	}

	/* 3. userns unshare */
	{
		if (unshare(CLONE_NEWUSER) == 0)
			printf("PROBE_USERSNS_OK\n");
		else
			printf("PROBE_USERSNS_FAIL: %s\n", strerror(errno));
	}

	return 0;
}