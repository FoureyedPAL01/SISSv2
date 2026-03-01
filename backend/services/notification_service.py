from database import supabase

def trigger_push_notification(user_id: str, title: str, body: str, data: dict = None):
    """
    Triggers a push notification to the Flutter app.
    In a real implementation, this function would call Firebase Cloud Messaging (FCM)
    or send a POST request to a Supabase Edge Function that handles FCM.

    Example Edge Function payload:
    """
    payload = {
        "user_id": user_id,
        "notification": {
            "title": title,
            "body": body,
        },
        "data": data or {}
    }
    
    print(f"--> PUSH NOTIFICATION DISPATCHED to {user_id}: {title} | {body}")
    
    # Example Edge function call:
    # try:
    #     supabase.functions.invoke("send-notification", invoke_options={"body": payload})
    # except Exception as e:
    #     print(f"Failed to trigger notification edge function: {e}")
    
    return True
