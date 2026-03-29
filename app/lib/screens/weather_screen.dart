// lib/screens/weather_screen.dart
//
// APIs (both free, no key):
//   • Open-Meteo forecast     — https://open-meteo.com/en/docs
//   • Open-Meteo air quality  — https://open-meteo.com/en/docs/air-quality-api
//
// All units (temperature, wind, precipitation) are read from AppStateProvider
// and applied at render time — no hardcoded unit strings anywhere.

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';
import '../theme.dart';
import '../widgets/double_back_press_wrapper.dart';

// ─── Dashed Border Painter ─────────────────────────────────────────────────────
class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;

  const DashedBorder({
    super.key,
    required this.child,
    required this.color,
    this.strokeWidth = 1.5,
    this.dashWidth = 6,
    this.dashSpace = 4,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        strokeWidth: strokeWidth,
        dashWidth: dashWidth,
        dashSpace: dashSpace,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;
  final double borderRadius;

  _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashWidth,
    required this.dashSpace,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius),
    );

    final path = Path()..addRRect(rrect);
    final dashPath = Path();

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        dashPath.addPath(
          metric.extractPath(distance, distance + dashWidth),
          Offset.zero,
        );
        distance += dashWidth + dashSpace;
      }
    }

    canvas.drawPath(dashPath, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Endpoints ────────────────────────────────────────────────────────────────

const _kForecast = 'https://api.open-meteo.com/v1/forecast';
const _kAirQual = 'https://air-quality-api.open-meteo.com/v1/air-quality';
const _kTimeout = Duration(seconds: 12);

// ─── WMO weather code helpers ─────────────────────────────────────────────────

String _wmoLabel(int c) {
  if (c == 0) return 'Clear Sky';
  if (c <= 2) return 'Partly Cloudy';
  if (c == 3) return 'Overcast';
  if (c <= 48) return 'Foggy';
  if (c <= 55) return 'Drizzle';
  if (c <= 65) return 'Rain';
  if (c <= 75) return 'Snow';
  if (c <= 82) return 'Rain Showers';
  if (c <= 99) return 'Thunderstorm';
  return 'Unknown';
}

String _wmoSvg(int c, {bool night = false}) {
  const folder = 'light';
  const prefix = 'assets/set-6';
  if (c == 0) return '$prefix/$folder/${night ? 'clear_night' : 'sunny'}.svg';
  if (c <= 2) {
    return '$prefix/$folder/${night ? 'mostly_cloudy_night' : 'mostly_sunny'}.svg';
  }
  if (c == 3) return '$prefix/$folder/cloudy.svg';
  if (c <= 48) return '$prefix/$folder/windy.svg';
  if (c <= 55) return '$prefix/$folder/drizzle.svg';
  if (c <= 65) return '$prefix/$folder/heavy_rain.svg';
  if (c <= 75) return '$prefix/$folder/icy.svg';
  if (c <= 82) return '$prefix/$folder/sleet_hail.svg';
  return '$prefix/$folder/strong_thunderstorms.svg';
}

// ─── UV ───────────────────────────────────────────────────────────────────────

String _uvLabel(double uv) {
  if (uv < 3) return 'Low';
  if (uv < 6) return 'Moderate';
  if (uv < 8) return 'High';
  if (uv < 11) return 'Very High';
  return 'Extreme';
}

Color _uvColor(double uv) {
  if (uv < 3) return const Color(0xFF3B6D11);
  if (uv < 6) return const Color(0xFF8B6914);
  if (uv < 8) return const Color(0xFFB45309);
  if (uv < 11) return const Color(0xFF993556);
  return const Color(0xFF534AB7);
}

// ─── AQI ──────────────────────────────────────────────────────────────────────

String _aqiLabel(int aqi) {
  if (aqi < 0) return 'No data';
  if (aqi <= 50) return 'Good';
  if (aqi <= 100) return 'Moderate';
  if (aqi <= 150) return 'Unhealthy for sensitive';
  if (aqi <= 200) return 'Unhealthy';
  if (aqi <= 300) return 'Very Unhealthy';
  return 'Hazardous';
}

Color _aqiColor(int aqi) {
  if (aqi < 0) return Colors.grey;
  if (aqi <= 50) return const Color(0xFF3B6D11);
  if (aqi <= 100) return const Color(0xFF8B6914);
  if (aqi <= 150) return const Color(0xFFB45309);
  if (aqi <= 200) return const Color(0xFF993556);
  if (aqi <= 300) return const Color(0xFF534AB7);
  return const Color(0xFF7E0023);
}

// ─── Wind unit conversion (Open-Meteo returns km/h by default) ───────────────

/// Converts km/h to the user's preferred wind unit.
String _formatWindKmh(double kmh, String unit) {
  switch (unit) {
    case 'mph':
      return '${(kmh * 0.621371).toStringAsFixed(0)} mph';
    case 'm/s':
      return '${(kmh / 3.6).toStringAsFixed(1)} m/s';
    case 'knots':
      return '${(kmh * 0.539957).toStringAsFixed(0)} kn';
    default: // 'km/h'
      return '${kmh.toStringAsFixed(0)} km/h';
  }
}

// ─── Precipitation unit conversion (Open-Meteo returns mm) ───────────────────

/// Converts mm to the user's preferred precipitation unit.
String _formatPrecipMm(double mm, String unit) {
  if (unit == 'in') return '${(mm / 25.4).toStringAsFixed(2)} in';
  return '${_formatMm(mm)} mm';
}

// ─── Wind direction ───────────────────────────────────────────────────────────

String _compassLabel(int deg) {
  const d = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return d[((deg + 22.5) / 45).floor() % 8];
}

// ─── Time helpers ─────────────────────────────────────────────────────────────

String _dayLabel(String iso) {
  final d = DateTime.parse(iso);
  const w = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  return w[d.weekday - 1];
}

String _todayFormatted() {
  final d = DateTime.now();
  const M = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  const W = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return '${W[d.weekday - 1]}, ${M[d.month - 1]} ${d.day}';
}

String _hourLabel(DateTime dt) {
  final h = dt.hour;
  final ampm = h >= 12 ? 'PM' : 'AM';
  final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '$h12 $ampm';
}

int _nowHourIdx(List<String> times) {
  final now = DateTime.now();
  final cutoff = DateTime(now.year, now.month, now.day, now.hour);
  for (int i = 0; i < times.length; i++) {
    try {
      if (!DateTime.parse(times[i]).isBefore(cutoff)) return i;
    } catch (_) {}
  }
  return 0;
}

double _dewPoint(double tempC, double rh) {
  const a = 17.27, b = 237.7;
  final alpha = a * tempC / (b + tempC) + math.log(rh / 100.0);
  return b * alpha / (a - alpha);
}

String _formatMm(double mm) {
  final text = mm >= 10 ? mm.toStringAsFixed(0) : mm.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

// ─────────────────────────────────────────────────────────────────────────────
// WeatherScreen
// ─────────────────────────────────────────────────────────────────────────────

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});
  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheAt;

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool force = false}) async {
    if (!force &&
        _cache != null &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!).inMinutes < 10) {
      if (mounted) {
        setState(() {
          _data = _cache;
          _loading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final results = await Future.wait([_callForecast(), _callAirQuality()]);

      final parsed = _parse(results[0] as Map<String, dynamic>, results[1]);

      _cache = parsed;
      _cacheAt = DateTime.now();
      if (mounted) {
        setState(() {
          _data = parsed;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _callForecast() async {
    final provider = context.read<AppStateProvider>();
    final lat = provider.locationLat;
    final lon = provider.locationLon;
    final uri = Uri.parse(_kForecast).replace(
      queryParameters: {
        'latitude': lat,
        'longitude': lon,
        'current': [
          'temperature_2m', 'apparent_temperature', 'relative_humidity_2m',
          'weather_code', 'wind_speed_10m', 'wind_gusts_10m',
          'wind_direction_10m', 'is_day',
          'uv_index', // real-time UV — separate from uv_index_max (daily peak)
        ].join(','),
        'hourly': [
          'temperature_2m',
          'weather_code',
          'precipitation_probability',
        ].join(','),
        'daily': [
          'weather_code',
          'temperature_2m_max',
          'temperature_2m_min',
          'precipitation_probability_max',
          'precipitation_sum',
          'uv_index_max',
          'sunrise',
          'sunset',
        ].join(','),
        'timezone': 'auto',
        'forecast_days': '7',
      },
    );
    final r = await http.get(uri).timeout(_kTimeout);
    if (r.statusCode != 200) {
      throw Exception('Forecast API error ${r.statusCode}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> _callAirQuality() async {
    try {
      final provider = context.read<AppStateProvider>();
      final lat = provider.locationLat;
      final lon = provider.locationLon;
      final uri = Uri.parse(_kAirQual).replace(
        queryParameters: {
          'latitude': lat,
          'longitude': lon,
          'current': 'us_aqi',
          'timezone': 'auto',
          'forecast_hours': '1',
        },
      );
      final r = await http.get(uri).timeout(_kTimeout);
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Parse ─────────────────────────────────────────────────────────────────
  // All raw values stored in SI/base units (°C, km/h, mm).
  // Unit conversion happens at render time using user preferences.

  Map<String, dynamic> _parse(
    Map<String, dynamic> fc,
    Map<String, dynamic>? aq,
  ) {
    final cur = (fc['current'] ?? {}) as Map<String, dynamic>;
    final daily = (fc['daily'] ?? {}) as Map<String, dynamic>;
    final hourly = (fc['hourly'] ?? {}) as Map<String, dynamic>;

    double dbl(Map m, String k, [double def = 0.0]) =>
        (m[k] as num?)?.toDouble() ?? def;
    int intv(Map m, String k, [int def = 0]) => (m[k] as num?)?.toInt() ?? def;

    final List<String> dTimes = List<String>.from(daily['time'] ?? []);
    List<T> dList<T>(String k, T Function(num) fn) =>
        ((daily[k] ?? []) as List).map((v) => fn((v as num?) ?? 0)).toList();

    final dCodes = dList<int>('weather_code', (n) => n.toInt());
    final dMax = dList<double>('temperature_2m_max', (n) => n.toDouble());
    final dMin = dList<double>('temperature_2m_min', (n) => n.toDouble());
    final dPop = dList<int>('precipitation_probability_max', (n) => n.toInt());
    final dRain = dList<double>('precipitation_sum', (n) => n.toDouble());
    final dUV = dList<double>('uv_index_max', (n) => n.toDouble());
    final sunrises = List<String>.from(daily['sunrise'] ?? []);
    final sunsets = List<String>.from(daily['sunset'] ?? []);

    final hTimes = List<String>.from(hourly['time'] ?? []);
    final hTemps = ((hourly['temperature_2m'] ?? []) as List)
        .map((v) => (v as num?)?.toDouble() ?? 0.0)
        .toList();
    final hCodes = ((hourly['weather_code'] ?? []) as List)
        .map((v) => (v as num?)?.toInt() ?? 0)
        .toList();
    final hPrecp = ((hourly['precipitation_probability'] ?? []) as List)
        .map((v) => (v as num?)?.toInt() ?? 0)
        .toList();

    final todayPop = dPop.isNotEmpty ? dPop[0] : 0;

    return {
      'temp': dbl(cur, 'temperature_2m'), // °C
      'feels': dbl(cur, 'apparent_temperature'), // °C
      'humidity': intv(cur, 'relative_humidity_2m'),
      'code': intv(cur, 'weather_code'),
      'wind_speed': dbl(cur, 'wind_speed_10m'), // km/h
      'wind_gusts': dbl(cur, 'wind_gusts_10m'), // km/h
      'wind_dir': intv(cur, 'wind_direction_10m'),
      'is_day': intv(cur, 'is_day', 1),
      'today_max': dMax.isNotEmpty ? dMax[0] : 0.0, // °C
      'today_min': dMin.isNotEmpty ? dMin[0] : 0.0, // °C
      'today_pop': todayPop,
      'today_rain': dRain.isNotEmpty ? dRain[0] : 0.0, // mm
      // Use real-time uv_index from current block.
      // Fall back to uv_index_max (daily peak) only if current is unavailable.
      'uv_current': dbl(cur, 'uv_index', -1),
      'today_uv': dUV.isNotEmpty
          ? dUV[0]
          : 0.0, // daily peak (kept for reference)
      'sunrise': sunrises.isNotEmpty ? sunrises[0] : '',
      'sunset': sunsets.isNotEmpty ? sunsets[0] : '',
      'will_rain': todayPop > 50,
      'aqi': (aq?['current']?['us_aqi'] as num?)?.toInt() ?? -1,
      'forecast7': List.generate(
        dTimes.length,
        (i) => <String, dynamic>{
          'date': dTimes[i],
          'code': i < dCodes.length ? dCodes[i] : 0,
          'max': i < dMax.length ? dMax[i] : 0.0, // °C
          'min': i < dMin.length ? dMin[i] : 0.0, // °C
          'pop': i < dPop.length ? dPop[i] : 0,
        },
      ),
      'h_times': hTimes,
      'h_temps': hTemps, // °C
      'h_codes': hCodes,
      'h_precp': hPrecp,
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = Theme.of(context).colorScheme;
    // Rebuild only when one of these three unit prefs changes.
    final tempUnit = context.select<AppStateProvider, String>(
      (p) => p.tempUnit,
    );
    final windUnit = context.select<AppStateProvider, String>(
      (p) => p.windUnit,
    );
    final precipUnit = context.select<AppStateProvider, String>(
      (p) => p.precipitationUnit,
    );

    return DoubleBackPressWrapper(
      child: Scaffold(
        backgroundColor: colors.surfaceContainerHighest,
        body: RefreshIndicator(
          color: AppTheme.teal,
          onRefresh: () => _load(force: true),
          child: _buildBody(context, tempUnit, windUnit, precipUnit),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    String tempUnit,
    String windUnit,
    String precipUnit,
  ) {
    final colors = Theme.of(context).colorScheme;

    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error, fontFamily: 'Poppins'),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _load(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final w = _data!;

    final double temp = (w['temp'] as num).toDouble();
    final double feels = (w['feels'] as num).toDouble();
    final int humidity = (w['humidity'] as num).toInt();
    final int code = (w['code'] as num).toInt();
    final double windSpeed = (w['wind_speed'] as num).toDouble(); // km/h
    final double windGusts = (w['wind_gusts'] as num).toDouble(); // km/h
    final int windDir = (w['wind_dir'] as num).toInt();
    final bool isDay = (w['is_day'] as num).toInt() == 1;
    final double todayRain = (w['today_rain'] as num).toDouble(); // mm
    // Real-time UV from current block; fall back to daily peak if -1.
    final double uvCurrent = (w['uv_current'] as num).toDouble();
    final double uvDayMax = (w['today_uv'] as num).toDouble();
    final double todayUV = uvCurrent >= 0 ? uvCurrent : uvDayMax;
    final int aqi = (w['aqi'] as num).toInt();
    final bool willRain = w['will_rain'] as bool;
    final String sunrise = w['sunrise'] as String;
    final String sunset = w['sunset'] as String;

    final f7 = List<Map<String, dynamic>>.from(w['forecast7'] as List);
    final hTimes = List<String>.from(w['h_times'] as List);
    final hTemps = List<double>.from(
      (w['h_temps'] as List).map((v) => (v as num).toDouble()),
    );
    final hCodes = List<int>.from(
      (w['h_codes'] as List).map((v) => (v as num).toInt()),
    );
    final hPrecp = List<int>.from(
      (w['h_precp'] as List).map((v) => (v as num).toInt()),
    );

    final startIdx = _nowHourIdx(hTimes);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [
        // 1 — Hero card
        _HeroCard(
          date: _todayFormatted(),
          temp: UnitConverter.formatTemp(temp, tempUnit),
          maxTemp: UnitConverter.formatTemp(
            (w['today_max'] as num).toDouble(),
            tempUnit,
          ),
          minTemp: UnitConverter.formatTemp(
            (w['today_min'] as num).toDouble(),
            tempUnit,
          ),
          feels: UnitConverter.formatTemp(feels, tempUnit),
          condition: _wmoLabel(code),
          code: code,
          isDay: isDay,
          willRain: willRain,
          colors: colors,
        ),
        const SizedBox(height: 24),

        // 2 — Hourly strip
        _HourlyStrip(
          times: hTimes,
          temps: hTemps, // °C — converted inside the widget
          codes: hCodes,
          precps: hPrecp,
          start: startIdx,
          sunrise: sunrise,
          sunset: sunset,
          tempUnit: tempUnit,
          colors: colors,
        ),
        const SizedBox(height: 24),

        // 3 — Daily forecast
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('DAILY FORECAST', colors),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: f7.length,
                  itemBuilder: (context, i) {
                    final f = f7[i];
                    final dateStr = f['date'] as String;
                    final dt = DateTime.parse(dateStr);
                    final isToday = i == 0;

                    final dayStr = isToday
                        ? 'Today'
                        : _dayLabel(dateStr).substring(0, 3);
                    final dateFormatted =
                        '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 72,
                        child: _DayCard(
                          day: dayStr,
                          date: dateFormatted,
                          code: f['code'] as int,
                          max: UnitConverter.formatTemp(
                            f['max'] as double,
                            tempUnit,
                          ),
                          min: UnitConverter.formatTemp(
                            f['min'] as double,
                            tempUnit,
                          ),
                          pop: f['pop'] as int,
                          today: isToday,
                          colors: colors,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // 4 — Conditions grid
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _HumidityTile(
                humidity: humidity,
                tempC: temp,
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _WindTile(
                speedKmh: windSpeed,
                gustsKmh: windGusts,
                dirDeg: windDir,
                windUnit: windUnit, // from provider
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _UVTile(
                uvNow: todayUV,
                uvDayMax: uvDayMax,
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PrecipTile(
                amountMm: todayRain,
                precipUnit: precipUnit, // from provider
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        _AQITile(aqi: aqi, colors: colors),
      ],
    );
  }

  static Widget _label(String text, ColorScheme colors) => Text(
    text,
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.bold,
      letterSpacing: 1.1,
      fontFamily: 'Poppins',
      color: colors.onSurface,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String date, temp, maxTemp, minTemp, feels, condition;
  final int code;
  final bool isDay;
  final bool willRain;
  final ColorScheme colors;

  const _HeroCard({
    required this.date,
    required this.temp,
    required this.maxTemp,
    required this.minTemp,
    required this.feels,
    required this.condition,
    required this.code,
    required this.isDay,
    required this.willRain,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Poppins',
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        temp,
                        style: TextStyle(
                          fontSize: 52,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                          color: colors.onSurface,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '↑$maxTemp  ↓$minTemp',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Poppins',
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Feels like $feels',
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'Poppins',
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        condition,
                        style: TextStyle(
                          fontSize: 16,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SvgPicture.asset(
                    _wmoSvg(code, night: !isDay),
                    width: 120,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
          if (willRain)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.water_drop,
                    size: 15,
                    color: colors.onSecondaryContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Rain expected today — automated irrigation paused.',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Poppins',
                        color: colors.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hourly strip
// ─────────────────────────────────────────────────────────────────────────────

class _HourlyStrip extends StatelessWidget {
  final List<String> times;
  final List<double> temps; // °C
  final List<int> codes, precps;
  final int start;
  final String sunrise, sunset, tempUnit;
  final ColorScheme colors;

  const _HourlyStrip({
    required this.times,
    required this.temps,
    required this.codes,
    required this.precps,
    required this.start,
    required this.sunrise,
    required this.sunset,
    required this.tempUnit,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final count = (times.length - start).clamp(0, 24);

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'HOURLY FORECAST',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              fontFamily: 'Poppins',
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              physics: const BouncingScrollPhysics(),
              itemCount: count,
              itemBuilder: (context, i) {
                final idx = start + i;
                final tStr = idx < times.length ? times[idx] : '';
                final tVal = idx < temps.length ? temps[idx] : 0.0; // °C
                final cVal = idx < codes.length ? codes[idx] : 0;
                final pVal = idx < precps.length ? precps[idx] : 0;

                DateTime? dt;
                try {
                  dt = DateTime.parse(tStr);
                } catch (_) {}

                // Convert °C to user's preferred temperature unit.
                final tempStr = tempUnit == 'fahrenheit'
                    ? '${UnitConverter.celsiusToFahrenheit(tVal).round()}°'
                    : '${tVal.round()}°';

                return _HourItem(
                  label: i == 0 ? 'Now' : (dt != null ? _hourLabel(dt) : '--'),
                  code: cVal,
                  temp: tempStr,
                  precip: pVal,
                  colors: colors,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HourItem extends StatelessWidget {
  final String label, temp;
  final int code;
  final int precip;
  final ColorScheme colors;

  const _HourItem({
    required this.label,
    required this.code,
    required this.temp,
    required this.precip,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = colors.surfaceContainerHighest.withValues(alpha: 0.35);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Container(
        width: 52,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            SvgPicture.asset(_wmoSvg(code), width: 24, height: 24),
            Text(
              temp,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Manrope',
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
            ),
            Text(
              precip > 0 ? '$precip%' : '',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'Manrope',
                color: colors.tertiary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7-day day card
// ─────────────────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final String day, date, max, min;
  final int code, pop;
  final bool today;
  final ColorScheme colors;

  const _DayCard({
    required this.day,
    required this.date,
    required this.code,
    required this.pop,
    required this.max,
    required this.min,
    required this.today,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = colors.surfaceContainerHighest.withValues(alpha: 0.35);
    final borderColor = today
        ? const Color(0xFF1B1C1A)
        : colors.outline.withValues(alpha: 0.25);
    final borderWidth = today ? 2.5 : 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            max,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              fontFamily: 'Manrope',
              color: colors.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            min,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'Manrope',
              color: colors.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 4),
          SvgPicture.asset(_wmoSvg(code), width: 28, height: 28),
          const SizedBox(height: 4),

          Text(
            '$pop%',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'Manrope',
              color: Color(0xFF3B6D11),
            ),
          ),

          const SizedBox(height: 4),
          Text(
            day,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              fontFamily: 'Manrope',
              color: colors.onSurface,
            ),
          ),
          Text(
            date,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'Manrope',
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared tile decoration
// ─────────────────────────────────────────────────────────────────────────────

BoxDecoration _squareDeco(ColorScheme c) => BoxDecoration(
  color: c.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: c.outline.withValues(alpha: 0.25)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Tile 1 — Humidity
// ─────────────────────────────────────────────────────────────────────────────

class _HumidityTile extends StatelessWidget {
  final int humidity;
  final double tempC;
  final ColorScheme colors;
  static const _blue = Color(0xFF185FA5);

  const _HumidityTile({
    required this.humidity,
    required this.tempC,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final dew = _dewPoint(tempC, humidity.toDouble());

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: _squareDeco(colors),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _WaterFillPainter(
                    fill: humidity / 100.0,
                    fillColor: _blue.withValues(alpha: 0.10),
                    waveColor: _blue.withValues(alpha: 0.16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$humidity%',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: colors.onSurface,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Dew point  ${dew.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      color: colors.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
// Tile 2 — Wind (converted from km/h using windUnit)
// ─────────────────────────────────────────────────────────────────────────────

class _WindTile extends StatelessWidget {
  final double speedKmh; // raw km/h from Open-Meteo
  final double gustsKmh; // raw km/h from Open-Meteo
  final int dirDeg;
  final String windUnit; // 'km/h' | 'mph' | 'm/s' | 'knots'
  final ColorScheme colors;
  static const _green = Color(0xFF2E7D32);

  const _WindTile({
    required this.speedKmh,
    required this.gustsKmh,
    required this.dirDeg,
    required this.windUnit,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            // Background image (static, reduced opacity)
            Positioned.fill(
              child: ClipOval(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.white.withValues(alpha: 0.85),
                    BlendMode.srcOver,
                  ),
                  child: Transform.scale(
                    scale: 1.4,
                    child: Image.asset(
                      'assets/icon/compass2.jpg',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
            // Foreground content
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Center(
                  child: Text(
                    'Wind',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: _green,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Speed converted to user's preferred unit.
                Center(
                  child: Text(
                    _formatWindKmh(speedKmh, windUnit),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: colors.onSurface,
                      height: 1.1,
                    ),
                  ),
                ),
                // Gusts also converted.
                Center(
                  child: Text(
                    'Gusts ${_formatWindKmh(gustsKmh, windUnit)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Poppins',
                      color: colors.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    _compassLabel(dirDeg),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 3 — UV Index
// ─────────────────────────────────────────────────────────────────────────────

class _UVTile extends StatelessWidget {
  final double uvNow; // real-time UV from current block
  final double uvDayMax; // daily peak from uv_index_max
  final ColorScheme colors;

  const _UVTile({
    required this.uvNow,
    required this.uvDayMax,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _uvColor(uvNow);
    final label = _uvLabel(uvNow);

    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
        ),
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.all(14),
        child: Stack(
          children: [
            // Background image (static, reduced opacity)
            Positioned.fill(
              child: ClipOval(
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.white.withValues(alpha: 0.45),
                    BlendMode.srcOver,
                  ),
                  child: Transform.scale(
                    scale: 1.4,
                    child: Image.asset(
                      'assets/icon/UV.jpg',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),
            ),
            // Foreground content
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Center(
                  child: Text(
                    'UV Index',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                // Real-time current UV value
                Center(
                  child: Text(
                    uvNow.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: colors.onSurface,
                      height: 1.1,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Daily peak for context
                Center(
                  child: Text(
                    'Peak ${uvDayMax.toStringAsFixed(1)} today',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Poppins',
                      color: colors.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 4 — Precipitation (converted from mm using precipUnit)
// ─────────────────────────────────────────────────────────────────────────────

class _PrecipTile extends StatelessWidget {
  final double amountMm; // raw mm from Open-Meteo
  final String precipUnit; // 'mm' | 'in'
  final ColorScheme colors;
  static const _blue = Color(0xFF185FA5);

  const _PrecipTile({
    required this.amountMm,
    required this.precipUnit,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: _squareDeco(colors),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _TileLabel(
              icon: Icons.water_drop,
              text: 'Precipitation',
              color: _blue,
            ),
            const Spacer(),
            // Amount converted from mm to user's preferred unit.
            Text(
              _formatPrecipMm(amountMm, precipUnit),
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              amountMm > 0 ? 'Rainfall expected' : 'No rain today',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'Poppins',
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 5 — AQI
// ─────────────────────────────────────────────────────────────────────────────

class _AQITile extends StatelessWidget {
  final int aqi;
  final ColorScheme colors;
  static const _purple = Color(0xFF6B21A8);

  const _AQITile({required this.aqi, required this.colors});

  @override
  Widget build(BuildContext context) {
    final noData = aqi < 0;
    final label = _aqiLabel(aqi);
    final accent = _aqiColor(aqi);
    final fraction = noData ? 0.0 : (aqi.clamp(0, 500) / 500.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TileLabel(
                icon: Icons.masks,
                text: 'Air Quality Index',
                color: _purple,
              ),
              const Spacer(),
              Text(
                noData ? '--' : aqi.toString(),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: colors.onSurface,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 14),
          RepaintBoundary(
            child: SizedBox(
              height: 10,
              child: CustomPaint(
                size: const Size(double.infinity, 10),
                painter: _AQIBarPainter(
                  fraction: fraction,
                  dotColor: colors.surface,
                  dotBorderColor: colors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Good',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Poppins',
                  color: Color(0xFF3B6D11),
                ),
              ),
              Text(
                'Moderate',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Poppins',
                  color: Color(0xFF8B6914),
                ),
              ),
              Text(
                'Unhealthy',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Poppins',
                  color: Color(0xFF993556),
                ),
              ),
              Text(
                'Hazardous',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Poppins',
                  color: Color(0xFF7E0023),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared tile label
// ─────────────────────────────────────────────────────────────────────────────

class _TileLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _TileLabel({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainters
// ─────────────────────────────────────────────────────────────────────────────

class _WaterFillPainter extends CustomPainter {
  final double fill;
  final Color fillColor;
  final Color waveColor;

  const _WaterFillPainter({
    required this.fill,
    required this.fillColor,
    required this.waveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * (1.0 - fill);
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, size.height),
      Paint()..color = fillColor,
    );
    if (top > 8 && fill > 0.05) {
      final step = size.width / 3;
      final path = Path()..moveTo(0, top);
      for (int i = 0; i < 3; i++) {
        path.quadraticBezierTo(
          (i + 0.5) * step,
          top - 6,
          (i + 1.0) * step,
          top,
        );
      }
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = waveColor);
    }
  }

  @override
  bool shouldRepaint(_WaterFillPainter o) =>
      o.fill != fill || o.fillColor != fillColor;
}

class _AQIBarPainter extends CustomPainter {
  final double fraction;
  final Color dotColor;
  final Color dotBorderColor;

  static const _stops = [
    Color(0xFF00E400),
    Color(0xFFFFFF00),
    Color(0xFFFF7E00),
    Color(0xFFFF0000),
    Color(0xFF8F3F97),
    Color(0xFF7E0023),
  ];

  const _AQIBarPainter({
    required this.fraction,
    required this.dotColor,
    required this.dotBorderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(barRect, const Radius.circular(999));
    canvas.drawRRect(
      rr,
      Paint()..shader = LinearGradient(colors: _stops).createShader(barRect),
    );

    final dotX = (fraction * size.width).clamp(
      size.height / 2,
      size.width - size.height / 2,
    );
    final dotY = size.height / 2;
    final dotR = size.height / 2 + 2;
    canvas.drawCircle(
      Offset(dotX, dotY),
      dotR,
      Paint()..color = dotBorderColor,
    );
    canvas.drawCircle(Offset(dotX, dotY), dotR - 2, Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_AQIBarPainter o) => o.fraction != fraction;
}
