#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$MACOS_DIR/../.." && pwd)"
FIXTURE="$MACOS_DIR/Fixtures/LegacyVault"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/verity-parity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

"$ROOT_DIR/node_modules/.bin/tsx" "$ROOT_DIR/apps/server/scripts/vault-snapshot.ts" "$FIXTURE" > "$TMP/typescript.json"
swift run --package-path "$MACOS_DIR" verity-vault-snapshot "$FIXTURE" > "$TMP/swift.json"

/usr/bin/python3 -m json.tool --sort-keys "$TMP/typescript.json" > "$TMP/typescript.normalized.json"
/usr/bin/python3 -m json.tool --sort-keys "$TMP/swift.json" > "$TMP/swift.normalized.json"
diff -u "$TMP/typescript.normalized.json" "$TMP/swift.normalized.json"

/usr/bin/ditto "$FIXTURE" "$TMP/typescript-mutated"
/usr/bin/ditto "$FIXTURE" "$TMP/swift-mutated"
"$ROOT_DIR/node_modules/.bin/tsx" "$ROOT_DIR/apps/server/scripts/vault-mutate.ts" "$TMP/typescript-mutated"
swift run --package-path "$MACOS_DIR" verity-vault-snapshot --mutate "$TMP/swift-mutated" > /dev/null

for runtime in typescript swift; do
  for mutation in typescript-mutated swift-mutated; do
    if [[ "$runtime" == "typescript" ]]; then
      "$ROOT_DIR/node_modules/.bin/tsx" "$ROOT_DIR/apps/server/scripts/vault-snapshot.ts" "$TMP/$mutation" > "$TMP/$runtime-$mutation.json"
    else
      swift run --package-path "$MACOS_DIR" verity-vault-snapshot "$TMP/$mutation" > "$TMP/$runtime-$mutation.json"
    fi
    /usr/bin/python3 -m json.tool --sort-keys "$TMP/$runtime-$mutation.json" > "$TMP/$runtime-$mutation.normalized.json"
  done
done

diff -u "$TMP/typescript-typescript-mutated.normalized.json" "$TMP/swift-typescript-mutated.normalized.json"
diff -u "$TMP/typescript-swift-mutated.normalized.json" "$TMP/swift-swift-mutated.normalized.json"
diff -u "$TMP/typescript-typescript-mutated.normalized.json" "$TMP/typescript-swift-mutated.normalized.json"
echo "VERITY legacy TypeScript/Swift golden parity passed."
