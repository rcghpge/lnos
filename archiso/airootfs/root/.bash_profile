cat >/root/.bash_profile <<'EOF'
# LnOS: interactive login guard
case $- in
  *i*) : ;;     # interactive -> continue
  *) return ;;  # non-interactive -> do nothing
esac

RUNFLAG="/run/lnos-firstlogin"
if [ ! -e "$RUNFLAG" ]; then
  touch "$RUNFLAG"

  # Give systemd a moment to finish user session setup
  sleep 1

  # Prefer the packaged installer
  if [ -x /usr/local/bin/LnOS-installer.sh ]; then
    /usr/local/bin/LnOS-installer.sh || echo "[LnOS] installer exited ($?)."
  # Fallback to repo path if it exists
  elif [ -x /root/LnOS/scripts/LnOS-installer.sh ]; then
    /root/LnOS/scripts/LnOS-installer.sh || echo "[LnOS] repo installer exited ($?)."
  else
    echo "[LnOS] No installer found. Dropping to shell."
  fi
fi

# Always land in a login shell after
exec /bin/bash -l
EOF

