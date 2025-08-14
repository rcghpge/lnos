#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:-.}"

say(){ printf "\n\033[1m==> %s\033[0m\n" "$*"; }

say "Scanning for autologin/getty overrides"
grep -RIn 'agetty\|autologin' "$ROOT/archiso/airootfs/etc/systemd" 2>/dev/null || echo "(none)"

say "Scanning for LnOS scripts referenced by systemd"
grep -RIn 'lnos-.*\.sh\|LnOS-installer\.sh' "$ROOT/archiso/airootfs/etc/systemd" 2>/dev/null || echo "(none)"

say "Root login dotfiles"
ls -la "$ROOT/archiso/airootfs/root" 2>/dev/null | grep -E '\.bash_profile|\.bash_login|\.profile' || echo "(none)"
grep -RIn 'lnos-.*\.sh\|LnOS-installer\.sh' "$ROOT/archiso/airootfs/root" 2>/dev/null || echo "(no references)"

say "Global shell hooks"
for f in "$ROOT/archiso/airootfs/etc/profile" \
         "$ROOT/archiso/airootfs/etc/bash.bashrc"; do
  [ -f "$f" ] && { echo "--- $f"; grep -n 'lnos-.*\.sh\|LnOS-installer\.sh' "$f" || echo "(no refs)"; }
done
[ -d "$ROOT/archiso/airootfs/etc/profile.d" ] && \
  grep -RIn 'lnos-.*\.sh\|LnOS-installer\.sh' "$ROOT/archiso/airootfs/etc/profile.d" 2>/dev/null || echo "(no profile.d refs)"

say "/etc/passwd (root shell shipped)"
if [ -f "$ROOT/archiso/airootfs/etc/passwd" ]; then
  grep -n '^root:' "$ROOT/archiso/airootfs/etc/passwd" || true
else
  echo "(no passwd in airootfs tree)"
fi

say "Executable LnOS scripts present"
find "$ROOT/archiso/airootfs/usr/local/bin" -maxdepth 1 -type f -name 'lnos-*.sh' -perm -111 -printf '%M %u:%g %p\n' 2>/dev/null || echo "(none)"

say "Possible launch points summary"
grep -RIl 'ExecStart=.*lnos-.*\.sh' "$ROOT/archiso/airootfs/etc/systemd" 2>/dev/null || echo "(no ExecStart lnos hooks)"

