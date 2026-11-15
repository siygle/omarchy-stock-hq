# Marketplace #14295: remaining 0.5.1 review items

Base commit: `462cbf2a73742506632cca0a67417a744fee4091`.

## Export temporary-path replacement

Export now stages inside a newly created 0700 directory on the destination
filesystem. The helper enters that directory, then checks the actual `.` inode's
UID and mode before creating a payload. All payload checks and writes use a
relative path in that pinned cwd. A different UID can rename the directory entry
in a non-sticky shared parent, but cannot replace files inside the verified
private directory or redirect the helper's cwd.

Publication renames the same 0600 payload inode into `../<destination>`. Using the
pinned cwd's parent rather than reopening an absolute destination directory also
keeps publication on the same filesystem: changing an absolute parent path must
not cause `mv` to fall back to copying private bytes into a foreign file on a
different filesystem. Existing foreign/symlink destinations still select a fresh
name. Mode/ownership failures still fail closed.

Regression tests include two real UIDs (root as exporter, nobody as attacker) in
a Linux container:

- Replace staging after the final payload-mode check, before the shell opens the
  payload for writing. The replacement's attacker-owned 0666 payload receives no
  bytes; the published file stays 0600 and is unreadable by nobody.
- Replace staging before `cd`. The cwd ownership check rejects the replacement
  before any payload file is created.

The controlled interleaving uses command shims; this is not a timing-dependent
stress test. The two-UID cases skip explicitly outside a root Linux environment
with `runuser`. Concurrent changes to the shared directory can still deny export
or make its reported pathname stale; confidentiality is the guarantee here, not
availability against someone able to rename/remove entries in that directory.

## Direct-process destruction

Quickshell now owns a waiting shell, which launches `timeout` as an independent
child. Normal TERM/HUP/INT is forwarded to the timeout monitor. SIGKILL of the
direct owner cannot kill the independent monitor, so it retains the batch's
60-second deadline and two-second TERM-to-KILL escalation.

This deliberately does **not** promise immediate cancellation on destructor
SIGKILL: descendants may continue until the original deadline plus kill grace.
It implements the reviewer's alternative of retaining an independent enforcing
supervisor. fd 3 preserves stdin explicitly when starting the asynchronous child;
POSIX shells otherwise replace an asynchronous command's stdin with `/dev/null`.

Regression tests kill only the direct owner with SIGKILL and check both a real
hanging curl and a TERM-resistant workload. They shorten the real supervisor's
deadline to two seconds, verify it survives owner death, and verify all recorded
batch descendants (including head/sleep, not just marker-bearing commands) cease
running after the deadline/grace. Unreaped container zombies are distinguished
from running processes. No actual Quickshell teardown was run.

## Validation

Executed in a Debian 12 Linux amd64 Docker container on a macOS host:

- Node v20.20.2
- curl 7.88.1
- Qt/qmllint/qmltestrunner 6.4.2

```sh
node --test test/*.test.js
# 103 passed, 0 failed, 0 skipped

QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner \
  -input test/tst_textinput_lifecycle.qml -o -,txt
# 5 lifecycle tests passed; 7 including init/cleanup

git diff --check
```

The Node suite includes real-curl response bounds, export permissions, qmllint
against the existing stubs, literal-label rendering and offscreen screenshots.
This is not validation on Omarchy, Quickshell 0.3.2 or Qt 6.12; repeat there before
claiming target-runtime validation or requesting marketplace approval.
