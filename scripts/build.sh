#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcrun clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Isrc src/Core.m tests/CoreTests.m -framework Foundation -o build/core-tests
build/core-tests
xcrun clang -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Isrc src/NativeMenu.m tests/NativeMenuTests.m -framework Foundation -o build/menu-tests
build/menu-tests
build/menu-tests --wrong-abi
sdk_path="${IOS_SDK_PATH:-$(xcrun --sdk iphoneos --show-sdk-path)}"
xcrun clang -target arm64-apple-ios17.0 -isysroot "$sdk_path" -dynamiclib -fobjc-arc -fblocks -O2 -Wall -Wextra -Werror -Wno-unused-parameter -Isrc src/Core.m src/NativeMenu.m src/Settings.m -framework Foundation -framework UIKit -framework AVFAudio -install_name @rpath/YouTubeMod.dylib -o build/YouTubeMod.dylib
codesign --force --sign - --timestamp=none build/YouTubeMod.dylib
codesign --verify --strict build/YouTubeMod.dylib
