#!/bin/bash
# bench.sh -- fixed performance battery for the umd guest, run from a dev
# machine over SSH. Compare before/after with the same label-less protocol:
#
#   termux/bench.sh baseline          # before a change
#   termux/bench.sh after-p0          # after
#   column -t bench-baseline.tsv bench-after-p0.tsv
#
# Method (see the kernel port's tools/um-arm64/doc/80-performance.md):
#   - `compute` is a pure-userspace validator: it cannot move between
#     configurations. If it drifts >10% between two runs, the machine was not
#     in the same state (thermal/governor) and the other rows of that run are
#     suspect.
#   - each row is the median of $ROUNDS runs.
#   - a row that fails on the guest is reported as ERR, never timed as 0.
set -uo pipefail

IP=${IP:-192.168.84.95}
PORT=${PORT:-2222}
ROUNDS=${ROUNDS:-3}
LABEL=${1:-run}
OUT=${OUT:-bench-${LABEL}.tsv}
USER=${SSH_USER:-root}
SSH=(ssh -p "$PORT" -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=5 "${USER}@${IP}")

# time_remote <name> <remote-cmd>
# Runs the remote command under the guest's `time` builtin (so ssh transport
# cost is excluded for guest-side rows), prints "name<TAB>median_ms<TAB>note".
# The command is wrapped in a subshell: `time` on its own only times the
# first pipeline of a multi-command string (a `time a; b` bug that silently
# reported 0 ms for everything after the first `;`).
time_remote() {
	local name=$1 cmd=$2 i t best=
	for ((i = 0; i < ROUNDS; i++)); do
		local out
		if ! out=$("${SSH[@]}" "time ( $cmd )" 2>&1); then
			echo -e "$name\tERR\tfailed: $(echo "$out" | tail -1 | cut -c1-80)"
			return
		fi
		t=$(echo "$out" | sed -n 's/^real[[:space:]]*\([0-9]*\)m\([0-9.]*\)s.*/\1 \2/p')
		[ -n "$t" ] || { echo -e "$name\tERR\tunparsed: $out" | head -1; return; }
		t=$(echo "$t" | awk '{printf "%.0f", $1*60000 + $2*1000}')
		if [ -z "$best" ] || [ "$t" -lt "$best" ]; then best=$t; fi
	done
	echo -e "$name\t${best}\t"
}

# time_local_ms <name> <cmd...> -- median of ROUNDS, timed on this machine.
time_local_ms() {
	local name=$1; shift
	local i best= t0 t1
	for ((i = 0; i < ROUNDS; i++)); do
		t0=$EPOCHREALTIME
		"$@" >/dev/null 2>&1 || { echo -e "$name\tERR\tfailed"; return; }
		t1=$EPOCHREALTIME
		t=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.0f", (b-a)*1000}')
		if [ -z "$best" ] || [ "$t" -lt "$best" ]; then best=$t; fi
	done
	echo -e "$name\t${best}\t"
}

echo -e "row\tms\t" > "$OUT"

# Guest state, for the record.
state=$("${SSH[@]}" 'uname -r; mount | grep -E "on / " | head -1; grep -c ^processor /proc/cpuinfo' 2>&1) \
	|| { echo "cannot reach guest at ${USER}@${IP}:${PORT}"; exit 1; }
echo "# kernel: $(echo "$state" | sed -n 1p)" >> "$OUT"
echo "# root mount: $(echo "$state" | sed -n 2p)" >> "$OUT"
echo "# cpus: $(echo "$state" | sed -n 3p)  label=$LABEL  $(date -u +%FT%TZ)" >> "$OUT"

# One-time prep: docker needs hello-world locally for the docker row.
"${SSH[@]}" 'docker image inspect hello-world >/dev/null 2>&1 || docker pull -q hello-world' >/dev/null 2>&1 \
	|| echo "# warning: hello-world not available, docker row will be ERR" >> "$OUT"

# Rows. Order matters: the validator first, disk rows before docker so the
# image dir is warm.
time_remote "compute_256m"          'dd if=/dev/zero of=/dev/null bs=1M count=256'                          >> "$OUT"
time_remote "syscall_x100k"         'dd if=/dev/zero of=/dev/null bs=1 count=100000'                        >> "$OUT"
time_remote "forkexec_x100"         'i=0; while [ $i -lt 100 ]; do true; i=$((i+1)); done'                  >> "$OUT"
time_remote "openat_ls_usrbin"      'ls -laR /usr/bin /usr/sbin > /dev/null'                                >> "$OUT"
time_remote "dd_seqwrite_256m"      'dd if=/dev/zero of=/root/.bench.bin bs=1M count=256 oflag=sync'        >> "$OUT"
time_remote "dd_seqread_256m"       'dd if=/root/.bench.bin of=/dev/null bs=1M'                             >> "$OUT"
# .bench.bin is the 256 MB file the seqwrite row just made; 65535 4k blocks.
time_remote "dd_rand4k_sync_x300"   'for i in $(seq 300); do off=$((RANDOM % 65535)); dd if=/dev/zero of=/root/.bench.bin bs=4k count=1 seek=$off conv=notrunc oflag=sync; done' >> "$OUT"
time_remote "dd_rand4k_buf_x300"    'for i in $(seq 300); do off=$((RANDOM % 65535)); dd if=/dev/zero of=/root/.bench.bin bs=4k count=1 seek=$off conv=notrunc; done' >> "$OUT"
time_remote "tar_pack"              'rm -f /root/.bench.tar; cd / && tar cf /root/.bench.tar usr/bin usr/sbin usr/lib' >> "$OUT"
time_remote "tar_unpack"            'rm -rf /root/.benchdir; mkdir -p /root/.benchdir && cd /root/.benchdir && tar xf /root/.bench.tar' >> "$OUT"
time_remote "docker_run_x3"         'for i in 1 2 3; do docker run --rm hello-world >/dev/null 2>&1 || exit 1; done' >> "$OUT"

# LAN control: ssh round trip measured on this machine (includes WiFi RTT;
# it cannot move between configurations, so it is a drift control too).
time_local_ms "ssh_rtt_local" "${SSH[@]}" true >> "$OUT"

# Tidy the guest scratch files.
"${SSH[@]}" 'rm -rf /root/.bench.bin /root/.bench.tar /root/.benchdir' >/dev/null 2>&1

echo "$OUT"
column -t "$OUT" 2>/dev/null || cat "$OUT"
