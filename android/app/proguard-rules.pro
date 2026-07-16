# Jitsi Meet SDK + WebRTC.
# WebRTC's native code resolves these Java classes with JNI FindClass, which R8
# can't see — so without keep rules R8 strips them and the app aborts on the
# call screen ("Check failed: !clazz.is_null() org/webrtc/WebRtcClassLoader").
-keep class org.webrtc.** { *; }
-keep class org.jitsi.** { *; }
-keep class org.jitsi.meet.** { *; }
-dontwarn org.webrtc.**
-dontwarn org.jitsi.**

# Jitsi is React-Native based; keep RN + Hermes + fbjni entry points.
-keep class com.facebook.react.** { *; }
-keep class com.facebook.hermes.** { *; }
-keep class com.facebook.jni.** { *; }
-dontwarn com.facebook.**
