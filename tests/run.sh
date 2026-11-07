#!/usr/bin/env bash
#
# run.sh - unit tests for hal-posix.
#
# Covers the three `for instance` maps on `posix_hal` (Uart.send/recv,
# Gpio.read/write, Log.write), the `char *` GPIO entry (GpioName) and the
# `hal::Clock.nowMs()` -> `hal_platform_now_ms` wiring, including a negative
# link test that defines a second clock symbol on purpose.
#
# Determinism: no pipes, no /dev/null and no terminal are required. stdin is a
# temp file; stdout and stderr are temp files; everything is removed by the
# EXIT trap. If `mktemp -d` is unavailable the script aborts loudly instead of
# silently skipping a test. `ct` defaults to the 0.20.0 worktree build and can
# be overridden with CT=/path/to/ct.
#
# Usage:
#   tests/run.sh
#
# Exit status: 0 when every check passes, 1 otherwise.

set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
pkg="$(cd "$here/.." && pwd)"
repo="$(cd "$pkg/.." && pwd)"
CT="${CT:-/tmp/ct-0.20.0-worktree/ct}"
cflags='-D_POSIX_C_SOURCE=200809L -Wall -Wextra'

if [ ! -x "$CT" ]; then
    printf 'FAIL setup: ct not executable: %s\n' "$CT" >&2
    printf 'set CT=/path/to/ct and retry\n' >&2
    exit 1
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/hal-posix-tests.XXXXXX")" || {
    printf 'FAIL setup: cannot create temp directory\n' >&2
    exit 1
}
trap 'rm -rf "$tmp"' EXIT INT TERM

pass=0
fail=0

ok() {
    pass=$((pass + 1))
    printf 'ok   %s\n' "$1"
}

bad() {
    fail=$((fail + 1))
    printf 'FAIL %s: %s\n' "$1" "$2"
}

show_log() {
    printf '%s\n' '  --- build log ---'
    sed 's/^/  /' "$1"
    printf '%s\n' '  ----------------'
}

# build_ct <name> <source>  -> 0 on success, binary at $tmp/<name>/build
build_ct() {
    local name="$1" src="$2" dir="$tmp/$1"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        "$CT" build -I "$repo/hal" -I "$pkg" --cflags "$cflags" "$src" -o build
    ) >"$dir/build.log" 2>&1
    local st=$?

    if [ "$st" -ne 0 ]; then
        bad "$name" "ct build failed"
        show_log "$dir/build.log"
        return 1
    fi
    if grep -q 'warning:' "$dir/build.log"; then
        bad "$name" "compiler warning"
        show_log "$dir/build.log"
        return 1
    fi
    return 0
}

# check_stdout <name> <label> <expected-file> <run-exit> <actual-file>
check_stdout() {
    local name="$1" label="$2" want="$3" st="$4" got="$5"
    if [ "$st" -ne 0 ]; then
        bad "$name ($label)" "program exit $st"
        return
    fi
    if diff -u "$want" "$got" >"$tmp/$name/diff.log"; then
        ok "$name ($label)"
    else
        bad "$name ($label)" "output mismatch"
        sed 's/^/  /' "$tmp/$name/diff.log"
    fi
}

# ---------------------------------------------------------------- Gpio -------

if build_ct gpio "$here/t_gpio.ct"; then
    dir="$tmp/gpio"
    cat >"$dir/expected" <<'EOF'
initial=0
write_ret=0
after_set=1
other_pin=0
write_ret_zero=0
after_clear=0
neg_read=-1
neg_write=-1
hi_read=-1
hi_write=-1
pin31_write=0
pin31_read=1
EOF
    "$dir/build" >"$dir/out" 2>"$dir/err"
    check_stdout gpio "instance state and pin bounds" "$dir/expected" $? "$dir/out"
fi

# ------------------------------------------------------------ GpioName -------

if build_ct gpio_name "$here/t_gpio_name.ct"; then
    dir="$tmp/gpio_name"
    cat >"$dir/expected" <<'EOF'
init=0
write=0
read=1
via_instance=1
literal=1
literal_clear=0
literal_after_clear=0
empty=-1
bare=-1
nonnum=-1
upper=-1
high=-1
negative=-1
empty_write=-1
EOF
    "$dir/build" >"$dir/out" 2>"$dir/err"
    check_stdout gpio_name "char * entry and device-name parsing" "$dir/expected" $? "$dir/out"
fi

# errno is a libc macro that CT cannot read, so the EINVAL contract is checked
# from C against the same shim header.
dir="$tmp/gpio_name_errno"
mkdir -p "$dir"
cc -std=c99 $cflags "$here/t_gpio_name_errno.c" -o "$dir/build" >"$dir/build.log" 2>&1
if [ $? -ne 0 ]; then
    bad gpio_name_errno "cc failed"
    show_log "$dir/build.log"
elif grep -q 'warning:' "$dir/build.log"; then
    bad gpio_name_errno "compiler warning"
    show_log "$dir/build.log"
else
    printf 'errno-cases=7 ok\n' >"$dir/expected"
    "$dir/build" >"$dir/out" 2>"$dir/err"
    check_stdout gpio_name_errno "errno = EINVAL" "$dir/expected" $? "$dir/out"
fi

# ------------------------------------------------------------ Uart recv ------

if build_ct uart_recv "$here/t_uart_recv.ct"; then
    dir="$tmp/uart_recv"
    cat >"$dir/expected" <<'EOF'
zero=0
neg=-1
first=2 [ab]
second=1 [c]
eof=0
EOF
    printf 'abc' >"$dir/input.txt"
    "$dir/build" <"$dir/input.txt" >"$dir/out" 2>"$dir/err"
    check_stdout uart_recv "fd 0, chunking, EOF, length bounds" "$dir/expected" $? "$dir/out"
fi

# ------------------------------------------------------------ Uart send ------

if build_ct uart_send "$here/t_uart_send.ct"; then
    dir="$tmp/uart_send"
    printf 'PING' >"$dir/expected_out"
    printf 'a=4 b=0 c=-1\n' >"$dir/expected_err"
    "$dir/build" >"$dir/out" 2>"$dir/err"
    st=$?
    check_stdout uart_send "fd 1 content" "$dir/expected_out" "$st" "$dir/out"
    check_stdout uart_send "length bounds" "$dir/expected_err" "$st" "$dir/err"
fi

# --------------------------------------------------------- Uart fd errors ----

if build_ct uart_fd_err "$here/t_uart_fd_err.ct"; then
    dir="$tmp/uart_fd_err"
    printf 'send_err=1 recv_err=1\n' >"$dir/expected"
    "$dir/build" <&- >&- 2>"$dir/err"
    check_stdout uart_fd_err "closed fd 0 / fd 1" "$dir/expected" $? "$dir/err"
fi

# ----------------------------------------------------------------- Log -------

if build_ct log "$here/t_log.ct"; then
    dir="$tmp/log"
    printf 'a=9 b=0 c=-1\n' >"$dir/expected_out"
    printf 'log-line\n' >"$dir/expected_err"
    "$dir/build" >"$dir/out" 2>"$dir/err"
    st=$?
    check_stdout log "fd 2 content" "$dir/expected_err" "$st" "$dir/err"
    check_stdout log "length bounds" "$dir/expected_out" "$st" "$dir/out"
fi

# ------------------------------------------------------------ Log fd error ---

if build_ct log_fd_err "$here/t_log_fd_err.ct"; then
    dir="$tmp/log_fd_err"
    printf 'log_err=1\n' >"$dir/expected"
    "$dir/build" 2>&- >"$dir/out"
    check_stdout log_fd_err "closed fd 2" "$dir/expected" $? "$dir/out"
fi

# --------------------------------------------------------------- Clock -------

if build_ct clock "$here/t_clock.ct"; then
    dir="$tmp/clock"
    printf 't0=0 monotonic=1\n' >"$dir/expected"
    "$dir/build" >"$dir/out" 2>"$dir/err"
    check_stdout clock "nowMs anchoring and monotonicity" "$dir/expected" $? "$dir/out"
fi

# Duplicate symbol: PosixHal.h.ct defines hal_platform_now_ms, so a second
# definition in the test unit must fail at link time. This proves the normal
# build has exactly one definition.
name=clock_duplicate
dir="$tmp/$name"
mkdir -p "$dir"
(
    cd "$dir" || exit 1
    "$CT" build -I "$repo/hal" -I "$pkg" --cflags "$cflags" "$here/t_clock_duplicate.ct" -o build
) >"$dir/build.log" 2>&1
st=$?
if [ "$st" -eq 0 ]; then
    bad "$name" "duplicate hal_platform_now_ms linked successfully"
elif ! grep -Eq 'duplicate symbol|multiple definition' "$dir/build.log"; then
    bad "$name" "failed for a reason other than a duplicate symbol"
    show_log "$dir/build.log"
else
    ok "$name (second hal_platform_now_ms is rejected at link time)"
fi

# ------------------------------------------------------------- summary ------

printf '\npassed=%d failed=%d total=%d\n' "$pass" "$fail" "$((pass + fail))"

if [ "$fail" -ne 0 ]; then
    exit 1
fi
exit 0
