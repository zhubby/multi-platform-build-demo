#!/bin/sh
# [INPUT]: JDK 17、Android SDK 36 与固定 Gradle wrapper。
# [OUTPUT]: 检查、单元测试或根 dist 中的开发 APK。
# [POS]: Android 构建唯一公开入口；不修改源码与依赖锁。
# [PROTOCOL]: Update this header on change, then check AGENTS.md
set -eu
cd "$(dirname "$0")"
if [ -z "${JAVA_HOME:-}" ] && [ -x /usr/libexec/java_home ]; then
    JAVA_HOME=$(/usr/libexec/java_home -v 17)
    export JAVA_HOME
fi
if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
    ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
    export ANDROID_SDK_ROOT
fi
ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_HOME
java_bin="${JAVA_HOME:+$JAVA_HOME/bin/}java"
keytool_bin="${JAVA_HOME:+$JAVA_HOME/bin/}keytool"
case "${1:-check}" in
  check)
    "$java_bin" -version
    test -f "$ANDROID_SDK_ROOT/platforms/android-36/android.jar"
    test -f gradle/wrapper/gradle-wrapper.jar
    test -f app/gradle.lockfile
    ./gradlew ${GRADLE_ARGS:-} --version --no-daemon
    ;;
  test) ./gradlew ${GRADLE_ARGS:-} :app:testDebugUnitTest --no-daemon ;;
  build)
    mkdir -p app/build/signing
    rm -f app/build/signing/debug.keystore
    "$keytool_bin" -genkeypair -keystore app/build/signing/debug.keystore -storepass android -keypass android -alias androiddebugkey -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -keysize 2048 -validity 3650 >/dev/null 2>&1
    ./gradlew ${GRADLE_ARGS:-} :app:assembleDebug --no-daemon
    mkdir -p ../dist
    cp app/build/outputs/apk/debug/app-debug.apk "../dist/tasknotes-android-debug.apk"
    ;;
  *) printf '用法：%s check|test|build\n' "$0" >&2; exit 2 ;;
esac
