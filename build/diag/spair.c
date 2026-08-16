#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
	int sp[2];
	pid_t pid;
	int st;

	if (argc < 2) {
		fprintf(stderr, "usage: spair cmd...\n");
		return 2;
	}
	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sp)) {
		perror("socketpair");
		return 1;
	}
	pid = fork();
	if (pid < 0) {
		perror("fork");
		return 1;
	}
	if (pid == 0) {
		close(sp[1]);
		if (dup2(sp[0], 3) != 3)
			_exit(126);
		if (sp[0] > 2)
			close(sp[0]);
		execv(argv[1], &argv[1]);
		perror("execv");
		_exit(127);
	}
	close(sp[0]);
	if (waitpid(pid, &st, 0) < 0)
		perror("waitpid");
	if (WIFEXITED(st))
		fprintf(stderr, "EXIT=%d\n", WEXITSTATUS(st));
	else if (WIFSIGNALED(st))
		fprintf(stderr, "SIGNALED=%d\n", WTERMSIG(st));
	return 0;
}
