# ProGuard rules for NEXUS
# Add project specific ProGuard rules here

# Keep Flutter platform channel handlers
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# Keep webview_flutter classes
-keep class io.flutter.plugins.webviewflutter.** { *; }

# Keep Kotlin reflections
-keep class kotlin.reflect.** { *; }

# Keep generic signatures
-keepattributes Signature, InnerClasses, EnclosingMethod, EnclosingClass
-keepattributes RuntimeVisibleAnnotations, RuntimeVisibleAnnotationDefaults
