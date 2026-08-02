# statusbar - a one-line CPU/RAM readout pinned to the terminal's top row.
#
# Not a tmux status line: this repo doesn't manage tmux, and herdr (the
# multiplexer actually in use day to day, see modules/herdr.nix) has no
# status-bar concept of its own. Instead this reserves row 1 with a DECSTBM
# scroll region and repaints it from a background loop, so it works in any
# pty - a herdr pane, a bare Windows Terminal tab, anything that understands
# VT100 escapes - independent of whatever's running inside it.
{ writeShellApplication, gawk, ncurses }:

writeShellApplication {
  name = "statusbar";
  runtimeInputs = [ gawk ncurses ];
  text = ''
    # CPU% is a delta over /proc/stat, not a point-in-time read: its counters
    # are cumulative since boot, so a single sample only gives an all-time
    # average. Seed prev_* with one throwaway read before the loop so the
    # first printed frame isn't that all-time-average garbage.
    read_stat() {
      read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
      idle_all=$((idle + iowait))
      total=$((user + nice + system + idle + iowait + irq + softirq + steal))
    }

    read_stat
    prev_idle=$idle_all
    prev_total=$total

    resize() {
      rows=$(tput lines)
      # Reserve row 1: the scroll region covers row 2 through the last row,
      # so ordinary shell output can never scroll over the bar.
      printf '\e[2;%dr' "$rows"
    }

    cleanup() {
      printf '\e[r'  # full-screen scroll region again
      tput cnorm
      # A caught INT/TERM/HUP doesn't terminate the script by itself - only
      # the default (untrapped) action does. Without this the trap fires,
      # tidies up the terminal, and the while loop below just keeps going.
      exit 0
    }
    trap cleanup EXIT INT TERM HUP
    trap resize WINCH
    resize

    while true; do
      read_stat
      diff_idle=$((idle_all - prev_idle))
      diff_total=$((total - prev_total))
      cpu=0
      if (( diff_total > 0 )); then
        cpu=$(( (1000 * (diff_total - diff_idle) / diff_total + 5) / 10 ))
      fi
      prev_idle=$idle_all
      prev_total=$total

      mem_total_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
      mem_avail_kb=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
      mem_used_kb=$((mem_total_kb - mem_avail_kb))
      mem_pct=$((mem_used_kb * 100 / mem_total_kb))
      mem_used_gb=$(awk -v k="$mem_used_kb" 'BEGIN { printf "%.1f", k / 1048576 }')
      mem_total_gb=$(awk -v k="$mem_total_kb" 'BEGIN { printf "%.1f", k / 1048576 }')

      bar=$(printf 'CPU %3d%%   RAM %sG/%sG (%d%%)' "$cpu" "$mem_used_gb" "$mem_total_gb" "$mem_pct")

      printf '\e7\e[1;1H\e[K%s\e8' "$bar"
      sleep 2
    done
  '';

  meta = {
    description = "One-line CPU/RAM readout pinned to the terminal's top row";
    mainProgram = "statusbar";
  };
}
