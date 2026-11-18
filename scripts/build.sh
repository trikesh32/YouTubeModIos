#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Isrc src/Core.m tests/CoreTests.m -framework Foundation -o build/core-tests
build/core-tests
xcrun clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Isrc src/NativeMenu.m tests/NativeMenuTests.m -framework Foundation -o build/menu-tests
build/menu-tests
build/menu-tests --wrong-abi
xcrun clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -DYM_FULL=1 -Isrc src/Core.m src/FullDefaults.m tests/FullDefaultsTests.m -framework Foundation -o build/full-defaults-tests
build/full-defaults-tests
python3 scripts/build_full.py
