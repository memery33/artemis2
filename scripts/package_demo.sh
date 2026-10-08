#!/bin/sh
# Build a self-contained offline demo zip. The archive is not committed.
# Usage: scripts/package_demo.sh [output.zip]
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
out=${1:-"$root/dist/artemis2-demo.zip"}
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
dest="$stage/artemis2-demo"
mkdir -p "$dest/data"

cp "$root/demo/index.html" "$root/demo/app.js" "$root/demo/logic.js" \
  "$root/demo/style.css" "$root/demo/grain.png" "$dest/"
cp -R "$root/demo/data/." "$dest/data/"

cat > "$dest/Start Demo.command" << 'EOF'
#!/bin/sh
cd "$(CDPATH= cd -- "$(dirname "$0")" && pwd)" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is not installed. Install the Xcode Command Line Tools (xcode-select --install), then try again."
  exit 1
fi
port=8765
while ! python3 -c "import socket,sys; s=socket.socket();
try:
    s.bind(('127.0.0.1', $port))
except OSError:
    sys.exit(1)
finally:
    s.close()"
do
  port=$((port + 1))
  if [ "$port" -gt 8865 ]; then
    echo "No free port between 8765 and 8865."
    exit 1
  fi
done
echo "Close this window to stop the demo."
python3 -m http.server "$port" --bind 127.0.0.1 &
server=$!
sleep 0.4
open "http://127.0.0.1:${port}/"
wait "$server"
EOF
chmod +x "$dest/Start Demo.command"

cat > "$dest/README.txt" << 'EOF'
Artemis II — Orion window

Double-click "Start Demo.command". The Terminal window stays open while the demo runs. Close that window to stop it.

Or, from this folder:

    cd artemis2-demo && python3 -m http.server 8765

Then open http://127.0.0.1:8765

The page starts on a black screen. Click or press any key there so the browser will play the crew audio. Press F for full screen.

Photos and recordings: NASA ID …, Credit: NASA/Artemis II Crew. NASA media are generally not copyrighted in the United States. Acknowledge NASA. This is an independent project, not a NASA product, and NASA does not endorse it.
EOF

mkdir -p "$(dirname "$out")"
rm -f "$out"
(cd "$stage" && zip -r "$out" artemis2-demo)
echo "$out"
