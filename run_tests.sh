#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

developer_dir="$(xcode-select -p)/Library/Developer"
if [[ -f "$developer_dir/usr/lib/lib_TestingInterop.dylib" && -d "$developer_dir/Frameworks/Testing.framework" ]]; then
    exec swift test --disable-xctest \
        -Xswiftc -F -Xswiftc "$developer_dir/Frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/Frameworks" \
        -Xlinker -rpath -Xlinker "$developer_dir/usr/lib" "$@"
fi
exec swift test "$@"
