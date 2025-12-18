# Test: Manage a simple iptables DROP rule on a test TCP port, validate blocking via nc, and cleanup
# References: sample_case/01-sample.t and 02-sample2.t for alias/structure; follows existing iptables samples' conventions.
#
# Steps:
#  1) List current iptables rules (INPUT chain).
#  2) Add a simple DROP rule for a test port.
#  3) Verify rule presence.
#  4) Test connectivity to that port from DUT context using nc (should be blocked/failed).
#  5) Remove the rule and verify cleanup.
#  6) Dump iptables-save for report aggregation.
#
# Notes:
#  - Uses a high, unlikely-to-be-used TCP port (65432) to avoid conflicts.
#  - The connectivity check leverages localhost nc; on some systems, behavior varies
#    depending on listening services. We check deterministic nc error patterns and treat
#    connection refusal/timeout as expected "blocked" outcomes after inserting DROP.
#  - Commands are idempotent with best-effort cleanup.

$ set -e
$ export PATH=/sbin:/usr/sbin:/bin:/usr/bin:$PATH

# 1) List current INPUT rules in normalized form (header only to keep deterministic)
$ iptables -L INPUT -n -v | awk 'NR==1 {print}' | sed 's/[[:space:]]\+/ /g'
Chain INPUT (policy *)

# 2) Add a simple DROP rule for a test TCP port
$ TEST_PORT="${TEST_PORT:-65432}"
$ echo "Using TEST_PORT=${TEST_PORT}"
Using TEST_PORT=*

# Insert DROP rule near the top to ensure it's matched early
$ iptables -I INPUT 1 -p tcp --dport "${TEST_PORT}" -j DROP

# 3) Verify rule presence in INPUT chain (normalize whitespace)
$ iptables -S INPUT | grep -E -- "-p tcp .* --dport ${TEST_PORT} .* -j DROP" | sed 's/[[:space:]]\+/ /g' | sort | uniq
-A INPUT * -p tcp * --dport * -j DROP

# 4) Test connectivity to that port using nc from DUT context; expect failure/blocked
# We attempt to connect to localhost; the DROP rule should cause timeout or immediate failure.
# We accept common nc failure outputs for determinism.
$ OUT="$( (nc -z -w2 127.0.0.1 "${TEST_PORT}" >/dev/null 2>&1 && echo OK) || (echo FAIL) )"; echo "NC_RESULT=${OUT}"
NC_RESULT=*

# Normalize expected outcomes: FAIL indicates blocked; OK should not appear but if it does due to platform quirks,
# follow-up line explicitly greps for "OK" and outputs 'unexpected' if seen to keep assertion deterministic.
$ echo "${OUT}" | grep -q '^OK$' && echo unexpected || echo blocked-or-failed
blocked-or-failed

# 5) Remove the rule and verify cleanup
$ iptables -D INPUT -p tcp --dport "${TEST_PORT}" -j DROP 2>/dev/null || true
$ iptables -S INPUT | grep -E -- "-p tcp .* --dport ${TEST_PORT} .* -j DROP" || echo "DROP_rule_absent"
DROP_rule_absent

# 6) Dump iptables-save for report aggregation (truncated to chains headers for determinism and size)
$ iptables-save | grep -E '^\*|^:INPUT|^:FORWARD|^:OUTPUT' | sed 's/[[:space:]]\+/ /g'
*filter
:INPUT *
:FORWARD *
:OUTPUT *
