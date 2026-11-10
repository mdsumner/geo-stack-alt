# Shared helpers for arms. Source me.
OUT=/out
printf 'step\tseconds\texit\n' > "$OUT/steps.tsv"

# step <name> <command...>: run, log to $OUT/<name>.log, record wall time and exit code.
step() {
  local name=$1; shift
  local t0 t1 rc
  t0=$(date +%s.%N)
  ( "$@" ) > "$OUT/$name.log" 2>&1
  rc=$?
  t1=$(date +%s.%N)
  printf '%s\t%.1f\t%d\n' "$name" "$(awk "BEGIN{print $t1-$t0}")" "$rc" >> "$OUT/steps.tsv"
  return 0
}

finish() {
  chown -R "${HOST_UID:-0}:${HOST_GID:-0}" "$OUT"
}
trap finish EXIT
