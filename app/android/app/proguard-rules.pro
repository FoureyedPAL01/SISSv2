# ProGuard rules for RootSync
# Keep MQTT and Supabase classes from being stripped

# HiveMQ MQTT client
-keep class com.hivemq.** { *; }

# Supabase
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**

# Firebase
-keep class com.google.firebase.** { *; }

# Conscrypt (TLS) - suppress warnings
-dontwarn org.conscrypt.**
