# NEXUS – Android Studio Build

## Recommended toolchain
- Android Studio (current stable release)
- JDK 17
- Gradle 8.9
- Android Gradle Plugin 8.7.3
- Android SDK Platform 35
- Android SDK Build-Tools 35.0.0
- compileSdk 35 / targetSdk 35

## Build
1. Extract the ZIP.
2. Open the extracted `NEXUS` folder in Android Studio.
3. Let Gradle sync.
4. Install Android SDK Platform 35 if Android Studio asks for it.
5. Select **Build > Build APK(s)**.
6. Debug APK: `app/build/outputs/apk/debug/app-debug.apk`

## Important
The repository's GitHub Actions workflow uses the same JDK/Gradle/SDK versions.
