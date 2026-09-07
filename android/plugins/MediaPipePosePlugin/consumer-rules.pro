# ---------------------------------------------------------------------------
# MediaPipe Pose Plugin Consumer ProGuard / R8 Rules
# ---------------------------------------------------------------------------

# Keep plugin class and Godot-exposed methods
-keep class org.godotengine.plugin.android.mediapipepose.** { *; }
-keep class * extends org.godotengine.godot.plugin.GodotPlugin { *; }
-keepclassmembers class * {
    @org.godotengine.godot.plugin.UsedByGodot <methods>;
    @org.godotengine.godot.plugin.UsedByGodot <fields>;
}

# MediaPipe Tasks Vision and Protobuf dependencies
-keep class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.solutioncore.** { *; }
-keep class com.google.mediapipe.proto.** { *; }
-keep class com.google.protobuf.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }
-keep class com.google.common.** { *; }
-dontwarn com.google.protobuf.**
-dontwarn com.google.mediapipe.**
-dontwarn javax.lang.model.**
-dontwarn com.google.common.**
