// lib/screens/weather_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  static Map<String, dynamic>? _cachedData;
  static DateTime? _lastFetchTime;

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _weather;

  // ── Location config ────────────────────────────────────────────────────────
  static const double _lat = 19.097092385037833;
  static const double _lon = 72.89634431557758;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather({bool force = false}) async {
    if (!force && _cachedData != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!).inMinutes < 10) {
        if (mounted) {
          setState(() {
            _weather = _cachedData;
            _isLoading = false;
          });
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_lat'
        '&longitude=$_lon'
        '&current=temperature_2m,relative_humidity_2m,'
        'precipitation,weather_code,wind_speed_10m'
        '&daily=temperature_2m_max,temperature_2m_min,'
        'precipitation_probability_max,weather_code'
        '&timezone=auto'
        '&forecast_days=7',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _cachedData = _parseResponse(data);
        _lastFetchTime = DateTime.now();
        if (mounted) {
          setState(() {
            _weather = _cachedData;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Weather API returned status ${response.statusCode}';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not reach weather service: $e';
          _isLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _parseResponse(Map<String, dynamic> raw) {
    final current = raw['current'] as Map<String, dynamic>;
    final daily = raw['daily'] as Map<String, dynamic>;

    final maxTemps = List<double>.from(
      (daily['temperature_2m_max'] as List).map((v) => (v as num).toDouble()),
    );
    final minTemps = List<double>.from(
      (daily['temperature_2m_min'] as List).map((v) => (v as num).toDouble()),
    );
    final rainChances = List<int>.from(
      (daily['precipitation_probability_max'] as List).map(
        (v) => (v as num).toInt(),
      ),
    );
    final dates = List<String>.from(daily['time'] as List);
    final codes = List<int>.from(
      (daily['weather_code'] as List).map((v) => (v as num).toInt()),
    );

    final willRainSoon = rainChances.isNotEmpty && rainChances[0] > 50;

    return {
      'current_temp': (current['temperature_2m'] as num).toDouble(),
      'humidity': (current['relative_humidity_2m'] as num).toInt(),
      'wind_speed': (current['wind_speed_10m'] as num).toDouble(),
      'precipitation': (current['precipitation'] as num).toDouble(),
      'weather_code': (current['weather_code'] as num).toInt(),
      'temp_max': maxTemps.isNotEmpty ? maxTemps[0] : 0.0,
      'temp_min': minTemps.isNotEmpty ? minTemps[0] : 0.0,
      'max_pop': rainChances.isNotEmpty ? rainChances[0] : 0,
      'will_rain_soon': willRainSoon,
      'forecast': List.generate(
        dates.length,
        (i) => {
          'date': dates[i],
          'max': maxTemps[i],
          'min': minTemps[i],
          'rain_pct': rainChances[i],
          'code': codes[i],
        },
      ),
    };
  }

  // WMO weather code → human-readable label
  String _weatherLabel(int code) {
    if (code == 0) return 'Clear Sky';
    if (code <= 3) return 'Partly Cloudy';
    if (code <= 49) return 'Foggy';
    if (code <= 67) return 'Rainy';
    if (code <= 77) return 'Snowy';
    if (code <= 82) return 'Rain Showers';
    if (code <= 99) return 'Thunderstorm';
    return 'Unknown';
  }

  // WMO code → icon
  PhosphorIconData _weatherIcon(int code) {
    if (code == 0) return PhosphorIcons.sun();
    if (code <= 3) return PhosphorIcons.cloud();
    if (code <= 49) return PhosphorIcons.cloudFog();
    if (code <= 82) return PhosphorIcons.cloudRain();
    if (code <= 99) return PhosphorIcons.cloudLightning();
    return PhosphorIcons.cloud();
  }

  String _dayLabel(String isoDate) {
    final d = DateTime.parse(isoDate);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[d.weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final tempUnit = appState.tempUnit;
        return Scaffold(
          body: RefreshIndicator(
            onRefresh: () => _fetchWeather(force: true),
            child: _buildBody(context, tempUnit),
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, String tempUnit) {
    final colors = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(PhosphorIcons.cloudSlash(), size: 48, color: colors.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.error),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _fetchWeather(force: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final w = _weather!;
    final forecast = w['forecast'] as List<Map<String, dynamic>>;

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // ── Current conditions card ──────────────────────────────────────────
        Text(
          'Weather Forecast',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontFamily: 'Bungee',
            fontSize: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Lat: $_lat  •  Lon: $_lon',
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 16),

        Card(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              children: [
                Icon(
                  _weatherIcon(w['weather_code'] as int),
                  size: 56,
                  color: colors.tertiary,
                ),
                const SizedBox(height: 8),
                Text(
                  _weatherLabel(w['weather_code'] as int),
                  style: TextStyle(
                    fontSize: 16,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                // Large current temperature
                Text(
                  UnitConverter.formatTemp(
                    w['current_temp'] as double,
                    tempUnit,
                  ),
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'High ${UnitConverter.formatTemp(w['temp_max'] as double, tempUnit).replaceAll('°C', '°').replaceAll('°F', '°')}  '
                  'Low ${UnitConverter.formatTemp(w['temp_min'] as double, tempUnit).replaceAll('°C', '°').replaceAll('°F', '°')}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // Stats row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatChip(
                      icon: PhosphorIcons.drop(),
                      label: 'Humidity',
                      value: '${w['humidity']}%',
                    ),
                    _StatChip(
                      icon: PhosphorIcons.wind(),
                      label: 'Wind',
                      value:
                          '${(w['wind_speed'] as double).toStringAsFixed(0)} km/h',
                    ),
                    _StatChip(
                      icon: PhosphorIcons.cloudRain(),
                      label: 'Rain chance',
                      value: '${w['max_pop']}%',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── Rain warning banner ──────────────────────────────────────────────
        if (w['will_rain_soon'] == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.secondary),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.info(), color: colors.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Rain expected today. Automated irrigation is paused to save water.',
                    style: TextStyle(color: colors.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── 7-day forecast list ──────────────────────────────────────────────
        const SizedBox(height: 24),
        Text(
          '7-Day Forecast',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontFamily: 'Bungee', fontSize: 20),
        ),
        const SizedBox(height: 12),

        ...forecast.map(
          (day) => Card(
            color: colors.surface,
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                _weatherIcon(day['code'] as int),
                color: colors.primary,
              ),
              title: Text(_dayLabel(day['date'] as String)),
              subtitle: Text(_weatherLabel(day['code'] as int)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(day['max'] as double).toStringAsFixed(0)}° / '
                    '${(day['min'] as double).toStringAsFixed(0)}°',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '🌧 ${day['rain_pct']}%',
                    style: TextStyle(fontSize: 11, color: colors.primary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Small reusable stat chip used in the current conditions card
class _StatChip extends StatelessWidget {
  final PhosphorIconData icon;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 20, color: colors.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}
