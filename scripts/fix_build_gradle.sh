#!/bin/bash
# Fix AndroidX + compileSdk issues
set -e

cd /data/data/com/termux/files/home/NEXUS

# Ensure Flutter is available
export PATH="$PATH:$(pwd)/.fvm/default/bin"

# Pub get
flutter pub get

# Generate Android files if missing
if [ ! -f android/app/build.gradle ]; then
    echo "Error: android/app/build.gradle not found!"
    exit 1
fi

# Patch gradle.properties if needed
if [ -f android/gradle.properties ]; then
    sed -i 's/android.useAndroidX=false/android.useAndroidX=true/' android/gradle.properties
    sed -i 's/android.enableJetifier=false/android.enableJetifier=true/' android/gradle.properties
fi

echo "Build fixes applied!"
