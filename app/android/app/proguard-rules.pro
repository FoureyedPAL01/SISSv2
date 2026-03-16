# ProGuard rules for SISS v2
# Keep MQTT and Supabase classes from being stripped

# HiveMQ MQTT client
-keep class com.hivemq.** { *; }

# Supabase
-keep class io.supabase.** { *; }

# Conscrypt (TLS) - suppress warnings
-dontwarn org.conscrypt.**
