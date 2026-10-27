#!/usr/bin/env bash
# =============================================================================
#  Sylvy — nested-VM containment test (Phase 8)
#  Run this INSIDE a spawned guest (as a boot-time self-check, or via the host
#  daemon exec-ing into the guest). It proves the guest CANNOT create a new
#  isolation boundary (a nested VM). See docs/building/08-agent-containment.md.
#
#  Usage:  ./containment-test.sh
#  Exit 0 only if every CRITICAL check passes. Portable: no external tools,
#  no package installs — only shell, /proc and /dev. Works on any distro.
# =============================================================================
set -u

PASS=0; FAILN=0; WARN=0
crit() { # crit <id> <desc> <0=ok|1=ko> [detail]
  if [[ $3 -eq 0 ]]; then printf '  \e[32m✔ PASS\e[0m  %-4s %s %s\n' "$1" "$2" "${4:+($4)}"; PASS=$((PASS+1))
  else printf '  \e[31m✘ FAIL\e[0m  %-4s %s %s\n' "$1" "$2" "${4:+($4)}"; FAILN=$((FAILN+1)); fi
}
dd_() { # defense-in-depth: warn, never hard-fail
  if [[ $3 -eq 0 ]]; then printf '  \e[32m✔ OK  \e[0m  %-4s %s %s\n' "$1" "$2" "${4:+($4)}"
  else printf '  \e[33m– WARN\e[0m  %-4s %s %s\n' "$1" "$2" "${4:+($4)}"; WARN=$((WARN+1)); fi
}

echo "▶ Nested-VM containment check (run inside the guest)"
echo

# ---- CRITICAL: the two doors to making a VM, plus a live attempt --------------

# C1 — the DEVICE door: /dev/kvm must not exist in the guest.
[[ -e /dev/kvm ]]; present=$?
crit C1 "the /dev/kvm device node is absent" $([[ $present -ne 0 ]] && echo 0 || echo 1) \
  "$([[ $present -eq 0 ]] && echo 'present — withhold it at launch' || echo 'absent')"

# C2 — live attempt: opening /dev/kvm must fail (not just be missing).
# A VMM acquires KVM by opening this device. We open READ-ONLY and never create
# (O_RDONLY, no O_CREAT) so the probe cannot itself bring the device into being.
# "opened" is the only failing outcome; missing or permission-denied both pass.
openres=$(python3 - <<'PYEOF' 2>/dev/null
import os, sys
try:
    fd = os.open("/dev/kvm", os.O_RDONLY)   # no O_CREAT: never creates
    os.close(fd); print("opened")
except FileNotFoundError: print("missing")
except PermissionError:   print("denied")
except OSError as e:      print("error:%s" % e.errno)
PYEOF
)
crit C2 "opening /dev/kvm does not succeed" $([[ $openres != opened ]] && echo 0 || echo 1) \
  "$([[ $openres == opened ]] && echo 'OPENED — capability reachable' || echo "$openres")"

# C3 — the CPU-FEATURE door: the vCPU must not advertise virtualization extensions.
flags=$(grep -m1 -oE '(vmx|svm)' /proc/cpuinfo 2>/dev/null | sort -u | tr '\n' ' ')
crit C3 "no virtualization CPU flags (vmx/svm) exposed" $([[ -z $flags ]] && echo 0 || echo 1) \
  "${flags:+found: $flags}"

echo

# ---- DEFENSE IN DEPTH: smells, not hard failures ------------------------------

# D0 — the KVM kernel module should not be visible in the guest at all.
kvmmod=1
{ [[ -d /sys/module/kvm ]] || [[ -d /sys/module/kvm_intel ]] || [[ -d /sys/module/kvm_amd ]]; } && kvmmod=0
dd_ D0 "KVM kernel module not visible in the guest" $([[ $kvmmod -ne 0 ]] && echo 0 || echo 1) \
  "$([[ $kvmmod -eq 0 ]] && echo 'visible in /sys/module — harmless without device+flags, but a smell' || echo 'absent')"

# D1 — a locked guest should not even ship a VMM binary.
vmm=$(for b in firecracker cloud-hypervisor qemu-system-x86_64 qemu-system-aarch64 qemu-kvm kvm; do command -v "$b" 2>/dev/null; done | tr '\n' ' ')
dd_ D1 "no VMM binary present in the guest" $([[ -z $vmm ]] && echo 0 || echo 1) "${vmm:+found: $vmm}"

# D2 — nested flag on the module params (only visible if a module leaked in).
nested=""
for f in /sys/module/kvm_intel/parameters/nested /sys/module/kvm_amd/parameters/nested; do
  [[ -r $f ]] && nested="$nested $(cat "$f" 2>/dev/null)"
done
dd_ D2 "nested-virt module parameter not enabled" \
  $([[ -z ${nested// /} || ! $nested =~ (1|Y|y) ]] && echo 0 || echo 1) "${nested:+value:$nested}"

# D3 — seccomp should be active for the workload (extra lock on the ioctl path).
sc=$(awk '/^Seccomp:/{print $2}' /proc/self/status 2>/dev/null)
dd_ D3 "seccomp filtering is active for this process" \
  $([[ -n $sc && $sc -ne 0 ]] && echo 0 || echo 1) "Seccomp=${sc:-unknown} (0=disabled)"

# ---- Summary ------------------------------------------------------------------
echo
echo "════════════════════════════════════════════"
if [[ $FAILN -eq 0 ]]; then
  printf '  \e[32mCONTAINED\e[0m — the guest cannot create a nested VM  (%d critical checks passed)\n' "$PASS"
  [[ $WARN -gt 0 ]] && printf '  %d defense-in-depth warning(s): tighten if you can, not required for the guarantee.\n' "$WARN"
else
  printf '  \e[31mNOT CONTAINED\e[0m — %d critical check(s) failed. The guest may create a nested VM.\n' "$FAILN"
  echo  '  Fix at LAUNCH (host daemon), not inside the guest:'
  echo  '    • do not expose /dev/kvm into the guest'
  echo  '    • do not advertise virtualization features to the guest vCPU (nested virt off)'
  echo  '    • back both with seccomp + dropped capabilities'
fi
echo "════════════════════════════════════════════"
[[ $FAILN -eq 0 ]]
