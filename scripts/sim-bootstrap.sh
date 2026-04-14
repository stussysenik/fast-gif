#!/usr/bin/env bash
# Creates (or reuses) a dedicated FastGIF-Dev simulator.
# Writes the UDID to scripts/.sim-udid so every downstream script
# can target the same instance.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UDID_FILE="$SCRIPT_DIR/.sim-udid"
SIM_NAME="FastGIF-Dev"
DEVICE_TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"

# Find newest iOS runtime available
RUNTIME="$(xcrun simctl list runtimes -j \
    | /usr/bin/plutil -extract runtimes json -o - - \
    | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
ios = [r for r in data if r["platform"] == "iOS" and r["isAvailable"]]
ios.sort(key=lambda r: r["version"], reverse=True)
print(ios[0]["identifier"])' 2>/dev/null || true)"

if [[ -z "$RUNTIME" ]]; then
    echo "error: no iOS runtime available" >&2
    exit 1
fi

# Reuse existing FastGIF-Dev if present
EXISTING_UDID="$(xcrun simctl list devices "$SIM_NAME" -j \
    | /usr/bin/python3 -c '
import json, sys
data = json.load(sys.stdin)
for devices in data["devices"].values():
    for d in devices:
        if d["name"] == "FastGIF-Dev":
            print(d["udid"])
            sys.exit(0)' 2>/dev/null || true)"

if [[ -n "$EXISTING_UDID" ]]; then
    UDID="$EXISTING_UDID"
    echo "reusing existing FastGIF-Dev: $UDID"
else
    UDID="$(xcrun simctl create "$SIM_NAME" "$DEVICE_TYPE" "$RUNTIME")"
    echo "created FastGIF-Dev: $UDID"
fi

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "$UDID" > "$UDID_FILE"
echo "wrote $UDID_FILE"
