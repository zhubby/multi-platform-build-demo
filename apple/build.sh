#!/usr/bin/env bash
# [INPUT]: Swift 6+、Xcode、根 VERSION 与 ARTIFACTORY_WORK_DIR。
# [OUTPUT]: 检查、共享测试或根 dist/ 的 arm64 原生开发包。
# [POS]: Apple 构建唯一入口；工程副本与 DerivedData 均置于外部工作区。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
set -euo pipefail

apple_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$apple_dir/.." && pwd)"
mode="${1:-check}"
work_root="${ARTIFACTORY_WORK_DIR:-${TMPDIR:-/tmp}/tasknotes-build}"
developer_root="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "缺少构建工具：$1" >&2; exit 1; }
}

check_xcode() {
    require xcodebuild
    require ditto
    require codesign
    if [[ ! -d "$developer_root" ]]; then
        echo "请安装完整 Xcode，并设置 DEVELOPER_DIR。" >&2
        exit 1
    fi
    export DEVELOPER_DIR="$developer_root"
    xcodebuild -license check
    xcodebuild -checkFirstLaunchStatus
    xcrun --sdk iphonesimulator --show-sdk-path
    xcrun --sdk macosx --show-sdk-path
    xcodebuild -version
}

case "$mode" in
    check)
        require swift
        require plutil
        bash -n "$apple_dir/build.sh"
        plutil -lint "$apple_dir/TaskNotes.xcodeproj/project.pbxproj" "$apple_dir/App/Info-ios.plist" "$apple_dir/App/Info-macos.plist"
        check_xcode
        ;;
    test)
        require swift
        mkdir -p "$work_root"
        test_flags=()
        # CLT 不携带 Testing.framework；只读引用已安装的 Xcode 框架。
        if ! xcrun --sdk macosx --show-sdk-platform-path >/dev/null 2>&1; then
            testing_frameworks="$developer_root/Platforms/MacOSX.platform/Developer/Library/Frameworks"
            if [[ ! -d "$testing_frameworks/Testing.framework" ]]; then
                echo "共享测试需要 Swift 6+ 与 Testing.framework。请安装 Xcode 16+。" >&2
                exit 1
            fi
            test_flags+=(--build-system native -Xswiftc -F -Xswiftc "$testing_frameworks" -Xlinker -rpath -Xlinker "$testing_frameworks")
        fi
        swift test --package-path "$apple_dir" --scratch-path "$work_root/apple-swift-tests" \
            --disable-xctest --disable-automatic-resolution "${test_flags[@]}"
        ;;
    ios|macos)
        check_xcode
        mkdir -p "$work_root" "$repo_dir/dist"
        work_dir="$(mktemp -d "$work_root/apple-$mode.XXXXXX")"
        # 构建工具只能修改副本，不能回写仓库工程或锁文件。
        ditto "$apple_dir" "$work_dir/source"
        version="$(tr -d '\r\n' < "$repo_dir/VERSION")"
        if [[ "$mode" == ios ]]; then
            scheme="TaskNotesiOS"
            destination="generic/platform=iOS Simulator"
            sdk="iphonesimulator"
            product="$work_dir/DerivedData/Build/Products/Release-iphonesimulator/TaskNotes.app"
            archive="tasknotes-ios-arm64-simulator.zip"
            sign_flags=(CODE_SIGNING_ALLOWED=NO)
        else
            scheme="TaskNotesmacOS"
            destination="generic/platform=macOS"
            sdk="macosx"
            product="$work_dir/DerivedData/Build/Products/Release/TaskNotes.app"
            archive="tasknotes-macos-arm64.zip"
            sign_flags=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
        fi
        xcodebuild -project "$work_dir/source/TaskNotes.xcodeproj" -scheme "$scheme" \
            -configuration Release -sdk "$sdk" -destination "$destination" \
            -derivedDataPath "$work_dir/DerivedData" -clonedSourcePackagesDirPath "$work_dir/packages" \
            -disableAutomaticPackageResolution -skipPackageUpdates \
            -resultBundlePath "$work_dir/build.xcresult" \
            ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MARKETING_VERSION="$version" "${sign_flags[@]}" build
        test -d "$product"
        if [[ "$mode" == macos ]]; then codesign --verify --deep --strict "$product"; fi
        ditto -c -k --sequesterRsrc --keepParent "$product" "$work_dir/$archive"
        mv "$work_dir/$archive" "$repo_dir/dist/$archive"
        echo "已生成：$repo_dir/dist/$archive"
        ;;
    *)
        echo "用法：$0 check|test|ios|macos" >&2
        exit 2
        ;;
esac
