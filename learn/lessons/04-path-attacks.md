# Lesson 4 — Attack techniques on the binary path

> For **F2**. Four tricks attackers use to hide where their code runs from, and how each one shows up in `/proc/<pid>/exe`.

Your defence for all four is the same single source of truth: **`/proc/<pid>/exe`**, the kernel's own record of the file it loaded (lesson 1). An attacker can lie about the name they typed; they cannot lie to the kernel about what it actually executed.

## 1. Running from a world-writable directory

`/tmp`, `/dev/shm` and `/var/tmp` are writable by everyone. An attacker who gets a foothold often drops a binary there and runs it, because they have nowhere else they can write. Legitimate software is installed to `/usr/bin`, `/usr/sbin`, `/opt`, etc. — almost never `/tmp`.

```bash
cp /usr/bin/sleep /tmp/payload && /tmp/payload 60 &
readlink /proc/$!/exe        # /tmp/payload
```

**Rule `SUSPICIOUS_PATH`:** `exe` starts with `/tmp/`, `/dev/shm/` or `/var/tmp/`.

## 2. Masquerading

Attackers name their binary after something that looks like a kernel thread (`kworker`, `kthreadd`) or a system daemon, so it blends into `ps` output. The *name* is a disguise; the *path* is not. A real `kworker` is a kernel thread with no `exe` at all; a fake one in `/tmp/.hidden/kworker` is an ordinary file.

```bash
mkdir -p /tmp/.hidden && cp /usr/bin/sleep /tmp/.hidden/kworker && /tmp/.hidden/kworker 60 &
readlink /proc/$!/exe        # /tmp/.hidden/kworker
```

Because you check the path, not the name, this is caught by the same `SUSPICIOUS_PATH` rule — that is the point of trusting `exe`.

## 3. Deleted binaries

To leave nothing for forensics, an attacker opens the binary, starts it, then deletes the file from disk. The process keeps running because the kernel holds the open file, but the directory entry is gone. The kernel marks this in `exe` by appending ` (deleted)`.

```bash
cp /usr/bin/sleep /usr/local/bin/x
python3 -c "import os; fd=os.open('/usr/local/bin/x',os.O_RDONLY); os.unlink('/usr/local/bin/x'); os.execve(fd,['x','60'],{})" &
readlink /proc/$!/exe        # /usr/local/bin/x (deleted)
```

**Rule `DELETED_BINARY`:** `exe` ends with ` (deleted)`.

## 4. Fileless execution (memfd)

The stealthiest version never touches disk at all. `memfd_create` makes an anonymous file that lives only in RAM; the attacker writes the payload into it and executes it straight from memory. There is no path to scan, no file to find — but the kernel still records the origin in `exe`, as `/memfd:...`.

```bash
python3 -c "import os; f=os.memfd_create('x'); os.write(f,open('/usr/bin/sleep','rb').read()); os.execve(f,['sleep','60'],{})" &
readlink /proc/$!/exe        # /memfd:x (deleted)
```

**Rule `MEMFD_EXEC`:** `exe` starts with `/memfd:`.

## Putting it together in F2

Once F1 gives you the `exe` string for each execution, F2 is a handful of string checks in this order:

1. starts with `/memfd:` → `MEMFD_EXEC`
2. ends with ` (deleted)` → `DELETED_BINARY` (strip the suffix to get the real path)
3. real path under `/tmp/`, `/dev/shm/`, `/var/tmp/` → `SUSPICIOUS_PATH`

Order matters: a memfd binary also shows `(deleted)`, so check `memfd` first.

## One subtlety: symlinks

An attacker might place a clean-looking symlink in `/usr/local/bin` that points into `/tmp`. `exe` already resolves to the real target, so you are fine — but if you ever compare paths yourself (for the package-provenance bonus), resolve symlinks first with `filepath.EvalSymlinks`, because `/bin` is itself a symlink to `/usr/bin` on most modern distros.

## Check yourself

- Why is checking `/proc/<pid>/exe` more reliable than checking the process name?
- Why must `MEMFD_EXEC` be tested before `DELETED_BINARY`?
- A file runs from `/home/alice/project/tool`. Should that alert? *(No — only the three world-writable roots. Beware false positives, they cost points.)*
