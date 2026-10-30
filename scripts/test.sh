#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/ModuleCache"
DEVELOPER_DIR_PATH="$(xcode-select -p)"
TESTING_FRAMEWORKS="$DEVELOPER_DIR_PATH/Library/Developer/Frameworks"
TESTING_PLUGIN="$DEVELOPER_DIR_PATH/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_PLUGIN" && -d "$TESTING_FRAMEWORKS/Testing.framework" ]]; then
  swift test --disable-sandbox --disable-xctest --build-system native \
    -Xswiftc -F -Xswiftc "$TESTING_FRAMEWORKS" \
    -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN" \
    -Xlinker -rpath -Xlinker "$TESTING_FRAMEWORKS" --filter FieldWeave
else
  swift test --disable-sandbox --filter FieldWeave
fi
