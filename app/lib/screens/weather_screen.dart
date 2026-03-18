// lib/screens/weather_screen.dart
//
// APIs (both free, no key):
//   • Open-Meteo forecast     — https://open-meteo.com/en/docs
//   • Open-Meteo air quality  — https://open-meteo.com/en/docs/air-quality-api
//
// Reads LOCATION_LAT / LOCATION_LON from .env.
// Falls back to Mumbai (19.1014, 72.8962).
//
// Screen layout
//   1. Hero card    — big temp, condition, hi/lo, feels like
//   2. Hourly strip — next 24 h horizontal scroll
//   3. 7-day strip
//   4. Conditions grid
//        Humidity (square) │ Wind   (circle)
//        UV index (blob)   │ Precip (square)
//        AQI      (full-width gradient bar)
//
// Performance
//   • Forecast + AQI run in parallel via Future.wait().
//   • Static cache (10 min) — survives hot navigation.
//   • context.select limits rebuilds to tempUnit changes only.
//   • RepaintBoundary wraps every CustomPaint widget.
//   • Tile backgrounds are static (no weather-reactive colours).

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';
import '../theme.dart';

// ─── Endpoints ────────────────────────────────────────────────────────────────

const _kForecast = 'https://api.open-meteo.com/v1/forecast';
const _kAirQual  = 'https://air-quality-api.open-meteo.com/v1/air-quality';
const _kTimeout  = Duration(seconds: 12);

// ─── WMO weather code helpers ─────────────────────────────────────────────────

String _wmoLabel(int c) {
  if (c == 0)  return 'Clear Sky';
  if (c <= 2)  return 'Partly Cloudy';
  if (c == 3)  return 'Overcast';
  if (c <= 48) return 'Foggy';
  if (c <= 55) return 'Drizzle';
  if (c <= 65) return 'Rain';
  if (c <= 75) return 'Snow';
  if (c <= 82) return 'Rain Showers';
  if (c <= 99) return 'Thunderstorm';
  return 'Unknown';
}

PhosphorIconData _wmoIcon(int c, {bool night = false}) {
  if (c == 0) {
    return night
        ? PhosphorIcons.moon(PhosphorIconsStyle.fill)
        : PhosphorIcons.sun(PhosphorIconsStyle.fill);
  }
  if (c <= 2) {
    return night
        ? PhosphorIcons.cloudMoon(PhosphorIconsStyle.fill)
        : PhosphorIcons.cloudSun(PhosphorIconsStyle.fill);
  }
  if (c == 3) return PhosphorIcons.cloud(PhosphorIconsStyle.fill);
  if (c <= 48) return PhosphorIcons.cloudFog(PhosphorIconsStyle.fill);
  if (c <= 65) return PhosphorIcons.cloudRain(PhosphorIconsStyle.fill);
  if (c <= 75) return PhosphorIcons.snowflake(PhosphorIconsStyle.fill);
  if (c <= 82) return PhosphorIcons.cloudRain(PhosphorIconsStyle.fill);
  return PhosphorIcons.cloudLightning(PhosphorIconsStyle.fill);
}

// ─── UV ───────────────────────────────────────────────────────────────────────

String _uvLabel(double uv) {
  if (uv < 3)  return 'Low';
  if (uv < 6)  return 'Moderate';
  if (uv < 8)  return 'High';
  if (uv < 11) return 'Very High';
  return 'Extreme';
}

Color _uvColor(double uv) {
  if (uv < 3)  return const Color(0xFF3B6D11);
  if (uv < 6)  return const Color(0xFF8B6914);
  if (uv < 8)  return const Color(0xFFB45309);
  if (uv < 11) return const Color(0xFF993556);
  return const Color(0xFF534AB7);
}

// ─── AQI ──────────────────────────────────────────────────────────────────────

String _aqiLabel(int aqi) {
  if (aqi < 0)    return 'No data';
  if (aqi <= 50)  return 'Good';
  if (aqi <= 100) return 'Moderate';
  if (aqi <= 150) return 'Unhealthy for sensitive';
  if (aqi <= 200) return 'Unhealthy';
  if (aqi <= 300) return 'Very Unhealthy';
  return 'Hazardous';
}

Color _aqiColor(int aqi) {
  if (aqi < 0)    return Colors.grey;
  if (aqi <= 50)  return const Color(0xFF3B6D11);
  if (aqi <= 100) return const Color(0xFF8B6914);
  if (aqi <= 150) return const Color(0xFFB45309);
  if (aqi <= 200) return const Color(0xFF993556);
  if (aqi <= 300) return const Color(0xFF534AB7);
  return const Color(0xFF7E0023);
}

// ─── Wind ─────────────────────────────────────────────────────────────────────

String _compassLabel(int deg) {
  const d = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
  return d[((deg + 22.5) / 45).floor() % 8];
}

// ─── Time helpers ─────────────────────────────────────────────────────────────

String _dayLabel(String iso) {
  final d = DateTime.parse(iso);
  const w = ['MON','TUE','WED','THU','FRI','SAT','SUN'];
  return w[d.weekday - 1];
}

String _todayFormatted() {
  final d = DateTime.now();
  const M = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const W = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
  return '${W[d.weekday - 1]}, ${M[d.month - 1]} ${d.day}';
}

// Returns hour label like "3 PM".
String _hourLabel(DateTime dt) {
  final h    = dt.hour;
  final ampm = h >= 12 ? 'PM' : 'AM';
  final h12  = h == 0 ? 12 : (h > 12 ? h - 12 : h);
  return '$h12 $ampm';
}

// First hourly index whose time >= current hour (local).
int _nowHourIdx(List<String> times) {
  final cutoff = DateTime.now();
  final trunc  = DateTime(cutoff.year, cutoff.month, cutoff.day, cutoff.hour);
  for (int i = 0; i < times.length; i++) {
    try { if (!DateTime.parse(times[i]).isBefore(trunc)) return i; }
    catch (_) {}
  }
  return 0;
}

// True if [hour] is between sunrise and sunset (ISO strings).
bool _isDayHour(DateTime hour, String sunriseIso, String sunsetIso) {
  try {
    return hour.isAfter(DateTime.parse(sunriseIso)) &&
           hour.isBefore(DateTime.parse(sunsetIso));
  } catch (_) { return true; }
}

// Magnus formula dew-point approximation.
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

class _WeatherScreenState extends State<WeatherScreen> {
  // Static cache — survives navigation within the same app session.
  static Map<String, dynamic>? _cache;
  static DateTime?             _cacheAt;

  bool                   _loading = true;
  String?                _error;
  Map<String, dynamic>?  _data;

  static double get _lat =>
      double.tryParse(dotenv.env['LOCATION_LAT'] ?? '') ?? 19.1014;
  static double get _lon =>
      double.tryParse(dotenv.env['LOCATION_LON'] ?? '') ?? 72.8962;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Fetch ─────────────────────────────────────────────────────────────────

  Future<void> _load({bool force = false}) async {
    // Serve from cache if fresh and not a forced refresh.
    if (!force && _cache != null && _cacheAt != null &&
        DateTime.now().difference(_cacheAt!).inMinutes < 10) {
      if (mounted) setState(() { _data = _cache; _loading = false; });
      return;
    }

    if (mounted) setState(() { _loading = true; _error = null; });

    try {
      // Run both network calls concurrently.
      final results = await Future.wait([
        _callForecast(),
        _callAirQuality(),  // returns null on failure — non-critical
      ]);

      final parsed = _parse(
        results[0] as Map<String, dynamic>,
        results[1],
      );

      _cache   = parsed;
      _cacheAt = DateTime.now();
      if (mounted) setState(() { _data = parsed; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<Map<String, dynamic>> _callForecast() async {
    final uri = Uri.parse(_kForecast).replace(queryParameters: {
      'latitude':  _lat.toString(),
      'longitude': _lon.toString(),
      'current': [
        'temperature_2m', 'apparent_temperature', 'relative_humidity_2m',
        'weather_code',   'wind_speed_10m',        'wind_gusts_10m',
        'wind_direction_10m', 'is_day',
      ].join(','),
      'hourly': [
        'temperature_2m', 'weather_code', 'precipitation_probability',
      ].join(','),
      'daily': [
        'weather_code',          'temperature_2m_max',       'temperature_2m_min',
        'precipitation_probability_max', 'precipitation_sum', 'uv_index_max',
        'sunrise',               'sunset',
      ].join(','),
      'timezone':      'auto',
      'forecast_days': '7',
    });
    final r = await http.get(uri).timeout(_kTimeout);
    if (r.statusCode != 200) throw Exception('Forecast API error ${r.statusCode}');
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // Returns null on any failure so the screen still loads without AQI.
  Future<Map<String, dynamic>?> _callAirQuality() async {
    try {
      final uri = Uri.parse(_kAirQual).replace(queryParameters: {
        'latitude':       _lat.toString(),
        'longitude':      _lon.toString(),
        'current':        'us_aqi',
        'timezone':       'auto',
        'forecast_hours': '1',
      });
      final r = await http.get(uri).timeout(_kTimeout);
      if (r.statusCode != 200) return null;
      return jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) { return null; }
  }

  // ── Parse ─────────────────────────────────────────────────────────────────

  Map<String, dynamic> _parse(
    Map<String, dynamic> fc,
    Map<String, dynamic>? aq,
  ) {
    final cur    = (fc['current'] ?? {}) as Map<String, dynamic>;
    final daily  = (fc['daily']   ?? {}) as Map<String, dynamic>;
    final hourly = (fc['hourly']  ?? {}) as Map<String, dynamic>;

    // Helper — safely extract numbers with a default.
    double dbl(Map m, String k, [double def = 0.0]) =>
        (m[k] as num?)?.toDouble() ?? def;
    int    intv(Map m, String k, [int def = 0]) =>
        (m[k] as num?)?.toInt() ?? def;

    // Daily lists
    final List<String> dTimes = List<String>.from(daily['time'] ?? []);
    List<T> dList<T>(String k, T Function(num) fn) =>
        ((daily[k] ?? []) as List).map((v) => fn((v as num?) ?? 0)).toList();

    final dCodes   = dList<int>('weather_code',                  (n) => n.toInt());
    final dMax     = dList<double>('temperature_2m_max',         (n) => n.toDouble());
    final dMin     = dList<double>('temperature_2m_min',         (n) => n.toDouble());
    final dPop     = dList<int>('precipitation_probability_max', (n) => n.toInt());
    final dRain    = dList<double>('precipitation_sum',          (n) => n.toDouble());
    final dUV      = dList<double>('uv_index_max',               (n) => n.toDouble());
    final sunrises = List<String>.from(daily['sunrise'] ?? []);
    final sunsets  = List<String>.from(daily['sunset']  ?? []);

    // Hourly lists
    final hTimes = List<String>.from(hourly['time'] ?? []);
    final hTemps = ((hourly['temperature_2m'] ?? []) as List)
        .map((v) => (v as num?)?.toDouble() ?? 0.0).toList();
    final hCodes = ((hourly['weather_code'] ?? []) as List)
        .map((v) => (v as num?)?.toInt() ?? 0).toList();
    final hPrecp = ((hourly['precipitation_probability'] ?? []) as List)
        .map((v) => (v as num?)?.toInt() ?? 0).toList();

    final todayPop = dPop.isNotEmpty ? dPop[0] : 0;

    return {
      // Current conditions
      'temp':       dbl(cur, 'temperature_2m'),
      'feels':      dbl(cur, 'apparent_temperature'),
      'humidity':   intv(cur, 'relative_humidity_2m'),
      'code':       intv(cur, 'weather_code'),
      'wind_speed': dbl(cur, 'wind_speed_10m'),
      'wind_gusts': dbl(cur, 'wind_gusts_10m'),
      'wind_dir':   intv(cur, 'wind_direction_10m'),
      'is_day':     intv(cur, 'is_day', 1),
      // Today summary (index 0 of daily)
      'today_max':  dMax.isNotEmpty  ? dMax[0]     : 0.0,
      'today_min':  dMin.isNotEmpty  ? dMin[0]     : 0.0,
      'today_pop':  todayPop,
      'today_rain': dRain.isNotEmpty ? dRain[0]    : 0.0,
      'today_uv':   dUV.isNotEmpty   ? dUV[0]      : 0.0,
      'sunrise':    sunrises.isNotEmpty ? sunrises[0] : '',
      'sunset':     sunsets.isNotEmpty  ? sunsets[0]  : '',
      'will_rain':  todayPop > 50,
      // AQI — -1 means no data
      'aqi': (aq?['current']?['us_aqi'] as num?)?.toInt() ?? -1,
      // 7-day forecast
      'forecast7': List.generate(dTimes.length, (i) => <String, dynamic>{
        'date': dTimes[i],
        'code': i < dCodes.length ? dCodes[i] : 0,
        'max':  i < dMax.length   ? dMax[i]   : 0.0,
        'min':  i < dMin.length   ? dMin[i]   : 0.0,
      }),
      // Hourly arrays (raw — sliced later)
      'h_times': hTimes,
      'h_temps': hTemps,
      'h_codes': hCodes,
      'h_precp': hPrecp,
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Only rebuild when tempUnit changes — not on every sensor push.
    final tempUnit = context.select<AppStateProvider, String>((p) => p.tempUnit);

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.teal,
        onRefresh: () => _load(force: true),
        child: _buildBody(context, tempUnit),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String tempUnit) {
    final colors = Theme.of(context).colorScheme;

    // ── Loading ───────────────────────────────────────────────────────────
    if (_loading) return const Center(child: CircularProgressIndicator());

    // ── Error ─────────────────────────────────────────────────────────────
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIcons.cloudSlash(), size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: TextStyle(color: colors.error, fontFamily: 'Poppins')),
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

    // ── Unpack ────────────────────────────────────────────────────────────
    final w = _data!;

    final double temp      = (w['temp']       as num).toDouble();
    final double feels     = (w['feels']      as num).toDouble();
    final int    humidity  = (w['humidity']   as num).toInt();
    final int    code      = (w['code']       as num).toInt();
    final double windSpeed = (w['wind_speed'] as num).toDouble();
    final double windGusts = (w['wind_gusts'] as num).toDouble();
    final int    windDir   = (w['wind_dir']   as num).toInt();
    final bool   isDay     = (w['is_day']     as num).toInt() == 1;
    final double todayRain = (w['today_rain'] as num).toDouble();
    final double todayUV   = (w['today_uv']   as num).toDouble();
    final int    aqi       = (w['aqi']        as num).toInt();
    final bool   willRain  = w['will_rain']   as bool;
    final String sunrise   = w['sunrise']     as String;
    final String sunset    = w['sunset']      as String;

    final f7     = List<Map<String, dynamic>>.from(w['forecast7'] as List);
    final hTimes = List<String>.from(w['h_times'] as List);
    final hTemps = List<double>.from((w['h_temps'] as List).map((v) => (v as num).toDouble()));
    final hCodes = List<int>.from((w['h_codes']   as List).map((v) => (v as num).toInt()));
    final hPrecp = List<int>.from((w['h_precp']   as List).map((v) => (v as num).toInt()));

    final startIdx = _nowHourIdx(hTimes);

    // ── Main content ──────────────────────────────────────────────────────
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [

        // Title
        Text('Weather Forecast',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontFamily: 'Poppins', fontSize: 28)),
        const SizedBox(height: 16),

        // 1 — Hero card
        _HeroCard(
          date:      _todayFormatted(),
          temp:      UnitConverter.formatTemp(temp, tempUnit),
          maxTemp:   UnitConverter.formatTemp((w['today_max'] as num).toDouble(), tempUnit),
          minTemp:   UnitConverter.formatTemp((w['today_min'] as num).toDouble(), tempUnit),
          feels:     UnitConverter.formatTemp(feels, tempUnit),
          condition: _wmoLabel(code),
          icon:      _wmoIcon(code, night: !isDay),
          willRain:  willRain,
          colors:    colors,
        ),
        const SizedBox(height: 24),

        // 2 — Hourly strip
        _label('HOURLY FORECAST', colors),
        const SizedBox(height: 10),
        _HourlyStrip(
          times:    hTimes,
          temps:    hTemps,
          codes:    hCodes,
          precps:   hPrecp,
          start:    startIdx,
          sunrise:  sunrise,
          sunset:   sunset,
          tempUnit: tempUnit,
          colors:   colors,
        ),
        const SizedBox(height: 24),

        // 3 — 7-day strip
        _label('7-DAY FORECAST', colors),
        const SizedBox(height: 10),
        Row(
          children: List.generate(f7.length, (i) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left:  i == 0 ? 0 : 4,
                right: i == f7.length - 1 ? 0 : 4,
              ),
              child: _DayCard(
                day:     _dayLabel(f7[i]['date'] as String),
                icon:    _wmoIcon(f7[i]['code'] as int, night: false),
                max:     '${(f7[i]['max'] as double).toStringAsFixed(0)}°',
                min:     '${(f7[i]['min'] as double).toStringAsFixed(0)}°',
                today:   i == 0,
                colors:  colors,
              ),
            ),
          )),
        ),
        const SizedBox(height: 24),

        // 4 — Conditions grid
        _label('CONDITIONS', colors),
        const SizedBox(height: 10),

        // Row 1: Humidity | Wind
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _HumidityTile(
              humidity: humidity, tempC: temp, colors: colors)),
          const SizedBox(width: 12),
          Expanded(child: _WindTile(
              speed: windSpeed, gusts: windGusts, dirDeg: windDir, colors: colors)),
        ]),
        const SizedBox(height: 12),

        // Row 2: UV index (blob) | Precipitation (square)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _UVTile(uvIndex: todayUV, colors: colors)),
          const SizedBox(width: 12),
          Expanded(child: _PrecipTile(amountMm: todayRain, colors: colors)),
        ]),
        const SizedBox(height: 12),

        // Row 3: AQI full-width
        _AQITile(aqi: aqi, colors: colors),

        // Attribution (Open-Meteo requires this for the free tier)
        const SizedBox(height: 20),
        const Center(
          child: Text('Weather data by Open-Meteo.com',
              style: TextStyle(
                fontSize: 11, fontFamily: 'Poppins',
                color: Color(0x801B4332))),
        ),
      ],
    );
  }

  // Small section label builder
  static Widget _label(String text, ColorScheme colors) => Text(text,
      style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.bold,
        letterSpacing: 1.1, fontFamily: 'Poppins',
        color: colors.onSurface));
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final String date, temp, maxTemp, minTemp, feels, condition;
  final PhosphorIconData icon;
  final bool willRain;
  final ColorScheme colors;

  const _HeroCard({
    required this.date,
    required this.temp,
    required this.maxTemp,
    required this.minTemp,
    required this.feels,
    required this.condition,
    required this.icon,
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
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left block
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(date, style: TextStyle(
                        fontSize: 13, fontFamily: 'Poppins',
                        color: colors.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    Text(temp, style: TextStyle(
                        fontSize: 52, fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins', color: colors.onSurface,
                        height: 1.0)),
                    const SizedBox(height: 4),
                    Text('↑$maxTemp  ↓$minTemp', style: TextStyle(
                        fontSize: 13, fontFamily: 'Poppins',
                        color: colors.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text('Feels like $feels', style: TextStyle(
                        fontSize: 13, fontFamily: 'Poppins',
                        color: colors.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(condition, style: TextStyle(
                        fontSize: 16, fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600, color: colors.onSurface)),
                  ],
                ),
              ),
              // Right: large icon
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(icon, size: 72,
                    color: colors.primary.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
        // Rain warning bar
        if (willRain)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: colors.secondaryContainer.withValues(alpha: 0.7),
              borderRadius: const BorderRadius.only(
                bottomLeft:  Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            child: Row(children: [
              Icon(PhosphorIcons.cloudRain(PhosphorIconsStyle.fill),
                  size: 15, color: colors.onSecondaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Rain expected today — automated irrigation paused.',
                  style: TextStyle(fontSize: 12, fontFamily: 'Poppins',
                      color: colors.onSecondaryContainer),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hourly strip
// ─────────────────────────────────────────────────────────────────────────────

class _HourlyStrip extends StatelessWidget {
  final List<String> times;
  final List<double> temps;
  final List<int>    codes, precps;
  final int          start;
  final String       sunrise, sunset, tempUnit;
  final ColorScheme  colors;

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
      height: 96,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        physics: const BouncingScrollPhysics(),
        itemCount: count,
        itemBuilder: (context, i) {
          final idx  = start + i;
          final tStr = idx < times.length ? times[idx] : '';
          final tVal = idx < temps.length ? temps[idx] : 0.0;
          final cVal = idx < codes.length ? codes[idx] : 0;
          final pVal = idx < precps.length ? precps[idx] : 0;

          DateTime? dt;
          bool day = true;
          try {
            dt  = DateTime.parse(tStr);
            day = _isDayHour(dt, sunrise, sunset);
          } catch (_) {}

          final tempStr = tempUnit == 'fahrenheit'
              ? '${UnitConverter.celsiusToFahrenheit(tVal).round()}°'
              : '${tVal.round()}°';

          return _HourItem(
            label:   i == 0 ? 'Now' : (dt != null ? _hourLabel(dt) : '--'),
            icon:    _wmoIcon(cVal, night: !day),
            temp:    tempStr,
            precip:  pVal,
            colors:  colors,
          );
        },
      ),
    );
  }
}

class _HourItem extends StatelessWidget {
  final String label, temp;
  final PhosphorIconData icon;
  final int precip;
  final ColorScheme colors;

  const _HourItem({
    required this.label,
    required this.icon,
    required this.temp,
    required this.precip,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(label,
              style: TextStyle(fontSize: 10, fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold, color: colors.onSurface)),
          Icon(icon, size: 20, color: colors.primary),
          Text(temp,
              style: TextStyle(fontSize: 13, fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold, color: colors.onSurface)),
          // Rain prob — hidden when 0 to keep layout tidy.
          Text(
            precip > 0 ? '$precip%' : '',
            style: const TextStyle(
              fontSize: 10, fontFamily: 'Poppins',
              color: Color(0xFF185FA5), fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7-day day card
// ─────────────────────────────────────────────────────────────────────────────

class _DayCard extends StatelessWidget {
  final String day, max, min;
  final PhosphorIconData icon;
  final bool today;
  final ColorScheme colors;

  const _DayCard({
    required this.day,
    required this.icon,
    required this.max,
    required this.min,
    required this.today,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
      decoration: BoxDecoration(
        color: today
            ? colors.primary.withValues(alpha: 0.12)
            : colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: today
              ? colors.primary.withValues(alpha: 0.45)
              : colors.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(day,
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.bold,
                letterSpacing: 0.5, fontFamily: 'Poppins',
                color: today ? colors.primary : colors.onSurfaceVariant)),
          const SizedBox(height: 6),
          Icon(icon, size: 22,
              color: today ? colors.primary : colors.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(max, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold,
              fontFamily: 'Poppins', color: colors.onSurface)),
          Text(min, style: TextStyle(
              fontSize: 11, fontFamily: 'Poppins',
              color: colors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Condition tile shared decoration helper
// ─────────────────────────────────────────────────────────────────────────────

BoxDecoration _squareDeco(ColorScheme c) => BoxDecoration(
  color: c.surface,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: c.outline.withValues(alpha: 0.25)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Tile 1 — Humidity  (square)
// ─────────────────────────────────────────────────────────────────────────────

class _HumidityTile extends StatelessWidget {
  final int humidity;
  final double tempC;           // used for dew-point calculation
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
        child: Stack(children: [
          // Water fill background — RepaintBoundary isolates its repaints.
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WaterFillPainter(
                  fill:      humidity / 100.0,
                  fillColor: _blue.withValues(alpha: 0.10),
                  waveColor: _blue.withValues(alpha: 0.16),
                ),
              ),
            ),
          ),
          // Foreground content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TileLabel(icon: PhosphorIcons.drop(PhosphorIconsStyle.fill),
                    text: 'Humidity', color: _blue),
                const Spacer(),
                Text('$humidity%',
                    style: TextStyle(
                      fontSize: 40, fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins', color: colors.onSurface,
                      height: 1.0)),
                const SizedBox(height: 4),
                Text('Dew point  ${dew.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: 12, fontFamily: 'Poppins',
                      color: colors.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 2 — Wind  (circle with rotated inner shape)
// ─────────────────────────────────────────────────────────────────────────────

class _WindTile extends StatelessWidget {
  final double speed;
  final double gusts;
  final int dirDeg;
  final ColorScheme colors;

  static const _green = Color(0xFF2E7D32);

  const _WindTile({
    required this.speed,
    required this.gusts,
    required this.dirDeg,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Arrow pointing dynamically towards the wind direction.
    final angleRad = dirDeg * math.pi / 180.0;

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
        child: Column(
          children: [
            _TileLabel(icon: PhosphorIcons.wind(), text: 'Wind', color: _green),
            const Spacer(),
            // Dynamic inner rotated container
            Transform.rotate(
              angle: angleRad,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIcons.navigationArrow(PhosphorIconsStyle.fill),
                  size: 24, color: _green,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('${speed.toStringAsFixed(0)} km/h',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins', color: colors.onSurface,
                  height: 1.1)),
            Text(_compassLabel(dirDeg),
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins', color: colors.onSurface.withValues(alpha: 0.6))),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 3 — UV Index (blob)
// ─────────────────────────────────────────────────────────────────────────────

class _UVTile extends StatelessWidget {
  final double uvIndex;
  final ColorScheme colors;

  const _UVTile({required this.uvIndex, required this.colors});

  @override
  Widget build(BuildContext context) {
    final accent = _uvColor(uvIndex);
    final label = _uvLabel(uvIndex);

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
        child: Column(
          children: [
            _TileLabel(icon: PhosphorIcons.sun(PhosphorIconsStyle.fill), text: 'UV Index', color: accent),
            const Spacer(),
            Text(uvIndex.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins', color: colors.onSurface, height: 1.1)),
            Text(label,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins', color: accent)),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 4 — Precipitation probability (square, mm amount)
// ─────────────────────────────────────────────────────────────────────────────

class _PrecipTile extends StatelessWidget {
  final double amountMm;
  final ColorScheme colors;

  static const _blue = Color(0xFF185FA5);

  const _PrecipTile({required this.amountMm, required this.colors});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        decoration: _squareDeco(colors),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TileLabel(
              icon:  PhosphorIcons.cloudRain(PhosphorIconsStyle.fill),
              text:  'Precipitation',
              color: _blue,
            ),
            const Spacer(),
            Text('${_formatMm(amountMm)} mm',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins', color: colors.onSurface)),
            const SizedBox(height: 4),
            Text(
              amountMm > 0 ? 'Rainfall expected' : 'No rain today',
              style: TextStyle(
                fontSize: 12, fontFamily: 'Poppins',
                color: colors.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile 5 — AQI  (full-width gradient bar)
// ─────────────────────────────────────────────────────────────────────────────

class _AQITile extends StatelessWidget {
  final int aqi;
  final ColorScheme colors;

  static const _purple = Color(0xFF6B21A8);

  const _AQITile({required this.aqi, required this.colors});

  @override
  Widget build(BuildContext context) {
    final noData   = aqi < 0;
    final label    = _aqiLabel(aqi);
    final accent   = _aqiColor(aqi);
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
          // Header row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TileLabel(icon: PhosphorIcons.wind(), text: 'Air Quality Index',
                  color: _purple),
              const Spacer(),
              // Big AQI number
              Text(noData ? '--' : aqi.toString(),
                  style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins', color: colors.onSurface,
                    height: 1.0)),
            ],
          ),
          const SizedBox(height: 4),
          // Category label
          Text(label,
              style: TextStyle(
                fontSize: 13, fontFamily: 'Poppins',
                fontWeight: FontWeight.bold, color: accent)),
          const SizedBox(height: 14),
          // Gradient bar — RepaintBoundary prevents cascade repaints.
          RepaintBoundary(
            child: SizedBox(
              height: 10,
              child: CustomPaint(
                size: const Size(double.infinity, 10),
                painter: _AQIBarPainter(
                  fraction:      fraction,
                  dotColor:      colors.surface,
                  dotBorderColor: colors.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Scale labels
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Good',
                  style: TextStyle(fontSize: 10, fontFamily: 'Poppins',
                      color: Color(0xFF3B6D11))),
              Text('Moderate',
                  style: TextStyle(fontSize: 10, fontFamily: 'Poppins',
                      color: Color(0xFF8B6914))),
              Text('Unhealthy',
                  style: TextStyle(fontSize: 10, fontFamily: 'Poppins',
                      color: Color(0xFF993556))),
              Text('Hazardous',
                  style: TextStyle(fontSize: 10, fontFamily: 'Poppins',
                      color: Color(0xFF7E0023))),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared tile label row (icon + text)
// ─────────────────────────────────────────────────────────────────────────────

class _TileLabel extends StatelessWidget {
  final PhosphorIconData icon;
  final String text;
  final Color color;

  const _TileLabel({required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Flexible(
          child: Text(text,
              style: TextStyle(
                fontSize: 12, fontFamily: 'Poppins',
                fontWeight: FontWeight.bold, color: color),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CustomPainters
// ─────────────────────────────────────────────────────────────────────────────

/// Water fill — flat rect rising from the bottom with a single wavy crest.
class _WaterFillPainter extends CustomPainter {
  final double fill;         // 0.0 – 1.0
  final Color  fillColor;
  final Color  waveColor;

  const _WaterFillPainter({
    required this.fill,
    required this.fillColor,
    required this.waveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final top = size.height * (1.0 - fill);

    // Base fill
    canvas.drawRect(
      Rect.fromLTRB(0, top, size.width, size.height),
      Paint()..color = fillColor,
    );

    // Wave crest on top of the fill (three bezier bumps)
    if (top > 8 && fill > 0.05) {
      final step = size.width / 3;
      final path = Path()..moveTo(0, top);
      for (int i = 0; i < 3; i++) {
        path.quadraticBezierTo(
          (i + 0.5) * step, top - 6,
          (i + 1.0) * step, top,
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

/// AQI gradient bar with a white dot indicator.
class _AQIBarPainter extends CustomPainter {
  final double fraction;         // 0.0 – 1.0
  final Color  dotColor;
  final Color  dotBorderColor;

  static const _stops = [
    Color(0xFF00E400), // Good
    Color(0xFFFFFF00), // Moderate
    Color(0xFFFF7E00), // Unhealthy for sensitive
    Color(0xFFFF0000), // Unhealthy
    Color(0xFF8F3F97), // Very Unhealthy
    Color(0xFF7E0023), // Hazardous
  ];

  const _AQIBarPainter({
    required this.fraction,
    required this.dotColor,
    required this.dotBorderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr      = RRect.fromRectAndRadius(barRect, const Radius.circular(999));

    // Gradient bar
    final shader  = LinearGradient(colors: _stops).createShader(barRect);
    canvas.drawRRect(rr, Paint()..shader = shader);

    // Dot indicator
    final dotX = (fraction * size.width).clamp(
      size.height / 2, size.width - size.height / 2);
    final dotY = size.height / 2;
    final dotR = size.height / 2 + 2;

    canvas.drawCircle(Offset(dotX, dotY), dotR,
        Paint()..color = dotBorderColor);
    canvas.drawCircle(Offset(dotX, dotY), dotR - 2,
        Paint()..color = dotColor);
  }

  @override
  bool shouldRepaint(_AQIBarPainter o) =>
      o.fraction != fraction;
}
