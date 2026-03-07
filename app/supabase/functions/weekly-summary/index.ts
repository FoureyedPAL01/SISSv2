import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(supabaseUrl, supabaseKey);

interface UserProfile {
  user_id: string;
  email: string;
  timezone: string;
  weekly_summary: boolean;
}

interface WeeklyData {
  totalWaterUsed: number;
  previousWeekTotal: number;
  dailyBreakdown: { date: string; total: number }[];
  alertsCount: number;
  devicesOnline: number;
  devicesTotal: number;
}

Deno.serve(async (req) => {
  try {
    // Get all users with weekly_summary enabled
    const { data: profiles, error: profileError } = await supabase
      .from('user_profiles')
      .select('user_id, timezone, weekly_summary')
      .eq('weekly_summary', true);

    if (profileError) {
      console.error('Error fetching profiles:', profileError);
      return new Response(JSON.stringify({ error: profileError.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    if (!profiles || profiles.length === 0) {
      return new Response(JSON.stringify({ message: 'No users with weekly summary enabled' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const results = [];

    for (const profile of profiles as UserProfile[]) {
      try {
        // Get user's email from auth.users
        const { data: userData, error: userError } = await supabase.auth.admin.getUserById(profile.user_id);
        
        if (userError || !userData.user) {
          console.error(`Error fetching user ${profile.user_id}:`, userError);
          continue;
        }

        const userEmail = userData.user.email;
        const timezone = profile.timezone || 'UTC';

        // Check if today is Monday in user's timezone
        const now = new Date();
        const userDateStr = now.toLocaleString('en-US', { timeZone: timezone });
        const userDate = new Date(userDateStr);
        
        // If it's not Monday, skip (daily cron checks every day)
        if (userDate.getDay() !== 1) {
          continue;
        }

        // Get weekly data
        const weeklyData = await getWeeklyData(profile.user_id, timezone);
        
        if (!weeklyData) {
          // No data this week - skip sending but don't error
          results.push({ userId: profile.user_id, status: 'skipped', reason: 'no_data' });
          continue;
        }

        // Send email (using Supabase's built-in or external SMTP)
        await sendWeeklyEmail(userEmail!, weeklyData, timezone);
        
        results.push({ userId: profile.user_id, status: 'sent' });
      } catch (userError) {
        console.error(`Error processing user ${profile.user_id}:`, userError);
        results.push({ userId: profile.user_id, status: 'error', error: String(userError) });
      }
    }

    return new Response(JSON.stringify({ 
      message: 'Weekly summary processing complete',
      results 
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error('Unexpected error:', error);
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});

async function getWeeklyData(userId: string, timezone: string): Promise<WeeklyData | null> {
  // Get devices for user
  const { data: devices } = await supabase
    .from('devices')
    .select('id, name, status')
    .eq('user_id', userId);

  if (!devices || devices.length === 0) {
    return null;
  }

  const deviceIds = devices.map(d => d.id);
  const devicesOnline = devices.filter(d => d.status === 'online').length;

  // Get water usage for this week and last week
  const now = new Date();
  const weekStart = new Date(now);
  weekStart.setDate(weekStart.getDate() - weekStart.getDay()); // Start of current week (Sunday)
  weekStart.setHours(0, 0, 0, 0);

  const lastWeekStart = new Date(weekStart);
  lastWeekStart.setDate(lastWeekStart.getDate() - 7);

  // Query this week's water usage
  const { data: thisWeekData } = await supabase
    .from('sensor_readings')
    .select('recorded_at, flow_litres')
    .in('device_id', deviceIds)
    .gte('recorded_at', weekStart.toISOString())
    .not('flow_litres', 'is', null);

  // Query last week's water usage
  const { data: lastWeekData } = await supabase
    .from('sensor_readings')
    .select('recorded_at, flow_litres')
    .in('device_id', deviceIds)
    .gte('recorded_at', lastWeekStart.toISOString())
    .lt('recorded_at', weekStart.toISOString())
    .not('flow_litres', 'is', null);

  // Calculate totals
  const totalWaterUsed = thisWeekData?.reduce((sum, r) => sum + (r.flow_litres || 0), 0) || 0;
  const previousWeekTotal = lastWeekData?.reduce((sum, r) => sum + (r.flow_litres || 0), 0) || 0;

  // Daily breakdown
  const dailyMap = new Map<string, number>();
  thisWeekData?.forEach(r => {
    const date = new Date(r.recorded_at).toLocaleDateString('en-US', { timeZone: timezone });
    dailyMap.set(date, (dailyMap.get(date) || 0) + (r.flow_litres || 0));
  });

  const dailyBreakdown = Array.from(dailyMap.entries()).map(([date, total]) => ({
    date,
    total: Math.round(total * 100) / 100
  }));

  // Get alerts count
  const { count: alertsCount } = await supabase
    .from('system_alerts')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', userId)
    .gte('created_at', weekStart.toISOString());

  return {
    totalWaterUsed: Math.round(totalWaterUsed * 100) / 100,
    previousWeekTotal: Math.round(previousWeekTotal * 100) / 100,
    dailyBreakdown,
    alertsCount: alertsCount || 0,
    devicesOnline,
    devicesTotal: devices.length
  };
}

async function sendWeeklyEmail(email: string, data: WeeklyData, timezone: string): Promise<void> {
  // Calculate percentage change
  let percentChange = 0;
  if (data.previousWeekTotal > 0) {
    percentChange = Math.round(((data.totalWaterUsed - data.previousWeekTotal) / data.previousWeekTotal) * 100);
  }

  const direction = percentChange > 0 ? '↑' : percentChange < 0 ? '↓' : '→';
  const changeText = data.previousWeekTotal > 0 
    ? `${direction} ${Math.abs(percentChange)}% vs last week`
    : '(no previous data for comparison)';

  // Build HTML email
  const html = `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Weekly Farm Summary</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
    <div style="background: linear-gradient(135deg, #347433 0%, #059212 100%); padding: 30px; border-radius: 12px 12px 0 0;">
      <h1 style="color: white; margin: 0; font-size: 24px;">🌱 Your Weekly Farm Summary</h1>
      <p style="color: rgba(255,255,255,0.8); margin: 10px 0 0 0;">Smart Irrigation System</p>
    </div>
    
    <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 12px 12px;">
      <!-- Water Usage Section -->
      <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="margin: 0 0 15px 0; color: #347433; font-size: 18px;">💧 Water Usage</h2>
        <div style="font-size: 32px; font-weight: bold; color: #2196F3;">
          ${data.totalWaterUsed.toFixed(1)} L
        </div>
        <p style="color: #666; margin: 5px 0 0 0; font-size: 14px;">
          ${changeText}
        </p>
        
        ${data.dailyBreakdown.length > 0 ? `
        <div style="margin-top: 15px;">
          <p style="font-size: 12px; color: #999; margin: 0 0 8px 0;">DAILY BREAKDOWN</p>
          <div style="display: flex; gap: 4px; height: 40px; align-items: flex-end;">
            ${data.dailyBreakdown.map(d => {
              const max = Math.max(...data.dailyBreakdown.map(x => x.total));
              const height = max > 0 ? (d.total / max) * 100 : 0;
              return `<div style="flex: 1; background: #2196F3; border-radius: 2px; height: ${height}%; min-height: 4px;" title="${d.date}: ${d.total.toFixed(1)}L"></div>`;
            }).join('')}
          </div>
        </div>
        ` : ''}
      </div>

      <!-- Alerts Section -->
      <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="margin: 0 0 15px 0; color: #347433; font-size: 18px;">🔔 Alerts</h2>
        <div style="font-size: 24px; font-weight: bold; color: ${data.alertsCount > 0 ? '#FF9800' : '#4CAF50'};">
          ${data.alertsCount} ${data.alertsCount === 1 ? 'alert' : 'alerts'} this week
        </div>
      </div>

      <!-- Device Status Section -->
      <div style="background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1);">
        <h2 style="margin: 0 0 15px 0; color: #347433; font-size: 18px;">📡 Device Status</h2>
        <div style="font-size: 24px; font-weight: bold; color: ${data.devicesOnline === data.devicesTotal ? '#4CAF50' : '#FF9800'};">
          ${data.devicesOnline} of ${data.devicesTotal} devices online
        </div>
        ${data.devicesOnline < data.devicesTotal ? `
        <p style="color: #FF9800; margin: 10px 0 0 0; font-size: 14px;">
          ⚠️ Some devices are offline. Check your dashboard for details.
        </p>
        ` : ''}
      </div>

      <!-- Footer -->
      <p style="text-align: center; color: #999; font-size: 12px; margin-top: 30px;">
        This is an automated weekly report from Smart Irrigation System.<br>
        <a href="#" style="color: #347433;">View Dashboard</a> | 
        <a href="#" style="color: #347433;">Unsubscribe</a>
      </p>
    </div>
  </body>
</html>
  `;

  // Send email using Supabase's internal email function or external service
  // This is a placeholder - in production, you would use Resend, SendGrid, or Supabase's SMTP
  console.log(`Sending weekly summary to ${email}:`, {
    totalWater: data.totalWaterUsed,
    alerts: data.alertsCount,
    devicesOnline: data.devicesOnline
  });

  // Example using Supabase's built-in (if configured):
  // const { error } = await supabase.functions.invoke('send-email', {
  //   body: { to: email, subject: 'Your Weekly Farm Summary', html }
  // });
}
