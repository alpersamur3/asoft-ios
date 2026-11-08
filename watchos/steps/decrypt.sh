mkdir -p "$W/os"
rm -f "$W/os/{OS}" "$W/os/{OS}.ok"
# (no "| head" here: under pipefail the writer's SIGPIPE, 141, would fail the step at random)
ipsw fw aea "$W/ipsw/{OS}.aea" -o "$W/os" 2>&1 | tail -3
ls -l "$W/os/{OS}"
: > "$W/os/{OS}.ok"
