// lib/screens/weather_screen.dart

import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../utils/unit_converter.dart';
import '../theme.dart';

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

  static const double _lat = 19.1014;
  static const double _lon = 72.8962;
  static const String _apiKey = 'c0e1c1a76c203aad0e2e54276eba77cb';

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather({bool force = false}) async {
    if (!force && _cachedData != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!).inMinutes < 10) {
        if (mounted) setState(() { _weather = _cachedData; _isLoading = false; });
        return;
      }
    }

    setState(() { _isLoading = true; _error = null; });

    try {
      final currentUri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/weather'
        '?lat=$_lat&lon=$_lon'
        '&units=metric'
        '&appid=$_apiKey',
      );

      final forecastUri = Uri.parse(
        'https://api.openweathermap.org/data/2.5/forecast'
        '?lat=$_lat&lon=$_lon'
        '&units=metric'
        '&cnt=40'
        '&appid=$_apiKey',
      );

      final currentResponse = await http.get(currentUri).timeout(const Duration(seconds: 10));
      final forecastResponse = await http.get(forecastUri).timeout(const Duration(seconds: 10));

      if (currentResponse.statusCode == 200 && forecastResponse.statusCode == 200) {
        final currentData = jsonDecode(currentResponse.body) as Map<String, dynamic>;
        final forecastData = jsonDecode(forecastResponse.body) as Map<String, dynamic>;
        _cachedData = _parseResponse(currentData, forecastData);
        _lastFetchTime = DateTime.now();
        if (mounted) setState(() { _weather = _cachedData; _isLoading = false; });
      } else {
        if (mounted) setState(() {
          _error = 'Weather API returned status ${currentResponse.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = 'Could not reach weather service: $e';
        _isLoading = false;
      });
    }
  }

  Map<String, dynamic> _parseResponse(Map<String, dynamic> current, Map<String, dynamic> forecastRaw) {
    final currentWeather = (current['weather'] as List<dynamic>)[0] as Map<String, dynamic>;
    final currentCode = currentWeather['id'] as int;
    final main = current['main'] as Map<String, dynamic>;

    final list = forecastRaw['list'] as List<dynamic>;

    final Map<String, List<dynamic>> dailyData = {};
    for (final item in list) {
      final dt = item['dt'] as int;
      final date = DateTime.fromMillisecondsSinceEpoch(dt * 1000);
      final dateStr = date.toIso8601String().split('T')[0];
      dailyData.putIfAbsent(dateStr, () => []).add(item);
    }

    final dates = dailyData.keys.take(7).toList();
    final maxTemps = <double>[];
    final minTemps = <double>[];
    final rainChances = <int>[];
    final codes = <int>[];

    for (final date in dates) {
      final dayItems = dailyData[date]!;
      final temps = dayItems.map((i) => ((i['main'] as Map<String, dynamic>)['temp'] as num).toDouble()).toList();
      final pops = dayItems.map((i) => ((i['pop'] as num?) ?? 0) * 100).toList();
      final dayCodes = dayItems.map((i) => ((i['weather'] as List<dynamic>)[0])['id'] as int).toList();

      maxTemps.add(temps.reduce((a, b) => a > b ? a : b));
      minTemps.add(temps.reduce((a, b) => a < b ? a : b));
      rainChances.add(pops.reduce((a, b) => a > b ? a : b).toInt());
      codes.add(dayCodes.isNotEmpty ? dayCodes[0] : 800);
    }

    final hourlyTemps = list.take(24).map((h) => ((h['main'] as Map<String, dynamic>)['temp'] as num).toDouble()).toList();
    final hourlyRain = list.take(24).map((h) => (((h['pop'] as num?) ?? 0) * 100).toInt()).toList();
    final hourlyTimes = list.take(24).map((h) {
      final dt = h['dt'] as int;
      return DateTime.fromMillisecondsSinceEpoch(dt * 1000).toIso8601String();
    }).toList();

    return {
      'current_temp': (main['temp'] as num).toDouble(),
      'humidity':     (main['humidity'] as num).toInt(),
      'wind_speed':   ((current['wind'] as Map<String, dynamic>)?['speed'] as num?)?.toDouble() ?? 0.0,
      'precipitation': 0.0,
      'weather_code': currentCode,
      'temp_max':     maxTemps.isNotEmpty ? maxTemps[0] : 0.0,
      'temp_min':     minTemps.isNotEmpty ? minTemps[0] : 0.0,
      'max_pop':      rainChances.isNotEmpty ? rainChances[0] : 0,
      'will_rain_soon': rainChances.isNotEmpty && rainChances[0] > 50,
      'forecast': List.generate(dates.length, (i) => {
        'date': dates[i], 'max': maxTemps[i], 'min': minTemps[i],
        'rain_pct': rainChances[i], 'code': codes[i],
      }),
      'hourly_times': hourlyTimes,
      'hourly_temps': hourlyTemps,
      'hourly_rain':  hourlyRain,
    };
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  String _weatherLabel(int code) {
    if (code == 800) return 'Clear Sky';
    if (code == 801) return 'Few Clouds';
    if (code == 802) return 'Scattered Clouds';
    if (code >= 803) return 'Overcast';
    if (code >= 700) return 'Foggy';
    if (code >= 600) return 'Snowy';
    if (code >= 500) return 'Rainy';
    if (code >= 300) return 'Drizzle';
    if (code >= 200) return 'Thunderstorm';
    return 'Unknown';
  }

  PhosphorIconData _weatherIcon(int code, {bool isNight = false}) {
    if (code == 800) return isNight ? PhosphorIcons.moon(PhosphorIconsStyle.fill) : PhosphorIcons.sun(PhosphorIconsStyle.fill);
    if (code == 801 || code == 802) return isNight ? PhosphorIcons.cloudMoon(PhosphorIconsStyle.fill) : PhosphorIcons.cloudSun(PhosphorIconsStyle.fill);
    if (code >= 700) return PhosphorIcons.cloudFog(PhosphorIconsStyle.fill);
    if (code >= 600) return PhosphorIcons.snowflake(PhosphorIconsStyle.fill);
    if (code >= 500) return PhosphorIcons.cloudRain(PhosphorIconsStyle.fill);
    if (code >= 300) return PhosphorIcons.cloudRain(PhosphorIconsStyle.fill);
    if (code >= 200) return PhosphorIcons.cloudLightning(PhosphorIconsStyle.fill);
    return PhosphorIcons.cloud(PhosphorIconsStyle.fill);
  }

  bool _isNighttime() {
    final hour = DateTime.now().hour;
    return hour < 6 || hour >= 18;
  }

  String _dayLabel(String isoDate) {
    final d = DateTime.parse(isoDate);
    const days = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
    return days[d.weekday - 1];
  }

  String _todayFormatted() {
    final d = DateTime.now();
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const days   = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _hourLabel(String iso) => iso.length >= 16 ? iso.substring(11, 16) : iso;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) => Scaffold(
        body: RefreshIndicator(
          onRefresh: () => _fetchWeather(force: true),
          child: _buildBody(context, appState.tempUnit),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, String tempUnit) {
    final colors    = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>();

    if (_isLoading) return const Center(child: CircularProgressIndicator());

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
                  style: TextStyle(color: colors.error)),
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

    final w        = _weather!;
    final forecast = w['forecast'] as List<Map<String, dynamic>>;
    final hTemps   = List<double>.from(w['hourly_temps'] as List);
    final hRain    = List<int>.from(w['hourly_rain'] as List);
    final hTimes   = List<String>.from(w['hourly_times'] as List);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 36),
      children: [

        // ── Title ────────────────────────────────────────────────────────────
        Text('Weather Forecast',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontFamily: 'Poppins', fontSize: 28)),
        const SizedBox(height: 16),

        // ── Current conditions card ──────────────────────────────────────────
        _CurrentWeatherCard(
          date:         _todayFormatted(),
          tempLabel:    UnitConverter.formatTemp(w['current_temp'] as double, tempUnit),
          minLabel:     UnitConverter.formatTemp(w['temp_min'] as double, tempUnit),
          condition:    _weatherLabel(w['weather_code'] as int),
          icon:         _weatherIcon(w['weather_code'] as int, isNight: _isNighttime()),
          humidity:     w['humidity'] as int,
          windSpeed:    (w['wind_speed'] as double).toStringAsFixed(0),
          rainChance:   w['max_pop'] as int,
          colors:       colors,
        ),

        // ── Rain warning ─────────────────────────────────────────────────────
        if (w['will_rain_soon'] == true) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.onSecondaryContainer.withValues(alpha: 0.3)),
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

        // ── 7-day forecast strip ─────────────────────────────────────────────
        const SizedBox(height: 24),
        Text('7-DAY FORECAST',
            style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold,
              letterSpacing: 1.0, fontFamily: 'Poppins',
              color: colors.onSurface,
            )),
        const SizedBox(height: 12),
        Row(
          children: List.generate(forecast.length, (i) {
            final day = forecast[i];
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 5, right: i == forecast.length - 1 ? 0 : 5),
                child: _ForecastDayCard(
                  dayLabel: _dayLabel(day['date'] as String),
                  icon:     _weatherIcon(day['code'] as int, isNight: _isNighttime()),
                  maxTemp:  '${(day['max'] as double).toStringAsFixed(0)}°',
                  minTemp:  '${(day['min'] as double).toStringAsFixed(0)}°',
                  isToday:  i == 0,
                  colors:   colors,
                ),
              ),
            );
          }),
        ),

        // ── Charts row ───────────────────────────────────────────────────────
        const SizedBox(height: 24),
        LayoutBuilder(builder: (_, constraints) {
          final wide = constraints.maxWidth >= 600;
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _TempBarChart(times: hTimes, temps: hTemps, colors: colors)),
                const SizedBox(width: 12),
                Expanded(child: _RainBarChart(times: hTimes, rain: hRain, colors: colors)),
              ],
            );
          }
          return Column(children: [
            _TempBarChart(times: hTimes, temps: hTemps, colors: colors),
            const SizedBox(height: 12),
            _RainBarChart(times: hTimes, rain: hRain, colors: colors),
          ]);
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current weather hero card
// ─────────────────────────────────────────────────────────────────────────────
class _CurrentWeatherCard extends StatelessWidget {
  final String date, tempLabel, minLabel, condition, windSpeed;
  final int humidity, rainChance;
  final PhosphorIconData icon;
  final ColorScheme colors;

  const _CurrentWeatherCard({
    required this.date,          required this.tempLabel,
    required this.minLabel,      required this.condition,
    required this.icon,          required this.humidity,
    required this.windSpeed,     required this.rainChance,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          // Upper: date + big temp + icon
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date,
                    style: TextStyle(
                      fontSize: 13, fontFamily: 'Poppins',
                      color: colors.onSurfaceVariant,
                    )),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tempLabel,
                              style: TextStyle(
                                fontSize: 42, fontWeight: FontWeight.bold,
                                fontFamily: 'Poppins', color: colors.onSurface,
                              )),
                          Text('$minLabel',
                              style: TextStyle(
                                fontSize: 16, fontFamily: 'Poppins',
                                color: colors.onSurfaceVariant,
                              )),
                          const SizedBox(height: 4),
                          Text(condition,
                              style: TextStyle(
                                fontSize: 14, fontFamily: 'Poppins',
                                color: colors.onSurfaceVariant,
                              )),
                        ],
                      ),
                    ),
                    Icon(icon, size: 56,
                        color: colors.primary.withValues(alpha: 0.7)),
                  ],
                ),
              ],
            ),
          ),

          Divider(height: 1, color: colors.outline.withValues(alpha: 0.18)),

          // Bottom stats row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(
                  icon: PhosphorIcons.drop(),
                  label: 'Humidity',
                  value: '$humidity%',
                ),
                _StatChip(
                  icon: PhosphorIcons.cloudRain(),
                  label: 'Rain chance',
                  value: '$rainChance%',
                ),
                _StatChip(
                  icon: PhosphorIcons.wind(),
                  label: 'Wind speed',
                  value: '$windSpeed km/h',
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
// Compact 7-day forecast card
// ─────────────────────────────────────────────────────────────────────────────
class _ForecastDayCard extends StatelessWidget {
  final String dayLabel, maxTemp, minTemp;
  final PhosphorIconData icon;
  final bool isToday;
  final ColorScheme colors;

  const _ForecastDayCard({
    required this.dayLabel, required this.icon,
    required this.maxTemp,  required this.minTemp,
    required this.isToday,  required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.outline.withValues(alpha: 0.25),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(dayLabel,
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold,
                fontFamily: 'Poppins', letterSpacing: 0.5,
                color: isToday ? colors.primary : colors.onSurfaceVariant,
              )),
          const SizedBox(height: 8),
          Icon(icon, size: 28,
              color: isToday ? colors.primary : colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(maxTemp,
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                color: colors.onSurface,
              )),
          Text(minTemp,
              style: TextStyle(
                fontSize: 12, fontFamily: 'Poppins',
                color: colors.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Temperature line chart (next 24h)
// ─────────────────────────────────────────────────────────────────────────────
class _TempBarChart extends StatelessWidget {
  final List<String> times;
  final List<double> temps;
  final ColorScheme colors;

  const _TempBarChart({required this.times, required this.temps, required this.colors});

  @override
  Widget build(BuildContext context) {
    final minY = (temps.reduce((a, b) => a < b ? a : b) - 2).floorToDouble();
    final maxY = (temps.reduce((a, b) => a > b ? a : b) + 2).ceilToDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(PhosphorIcons.thermometer(), size: 16, color: Colors.orange),
            const SizedBox(width: 6),
            Text('Temperature (next 24h)',
                style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13,
                  fontFamily: 'Poppins', color: colors.onSurface,
                )),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: minY, maxY: maxY,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((spot) => LineTooltipItem(
                      '${spot.y.toStringAsFixed(1)}°',
                      const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Poppins'),
                    )).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 32,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}°',
                        style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant, fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i % 4 != 0 || i >= times.length) return const SizedBox.shrink();
                        return Text(
                          _hourLabel(times[i]),
                          style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant, fontFamily: 'Poppins'),
                        );
                      },
                    ),
                  ),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.outline.withValues(alpha: 0.15), strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(temps.length, (i) => FlSpot(i.toDouble(), temps[i])),
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.orange.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hourLabel(String iso) => iso.length >= 16 ? iso.substring(11, 16) : iso;
}

// ─────────────────────────────────────────────────────────────────────────────
// Rain probability line chart (next 24h)
// ─────────────────────────────────────────────────────────────────────────────
class _RainBarChart extends StatelessWidget {
  final List<String> times;
  final List<int> rain;
  final ColorScheme colors;

  const _RainBarChart({required this.times, required this.rain, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(PhosphorIcons.cloudRain(), size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Text('Rain Probability (next 24h)',
                style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13,
                  fontFamily: 'Poppins', color: colors.onSurface,
                )),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: LineChart(
              LineChartData(
                minY: 0, maxY: 100,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) => spots.map((spot) => LineTooltipItem(
                      '${spot.y.toInt()}%',
                      const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'Poppins'),
                    )).toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 36,
                      interval: 25,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}%',
                        style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant, fontFamily: 'Poppins'),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true, reservedSize: 22,
                      getTitlesWidget: (v, _) {
                        final i = v.toInt();
                        if (i % 4 != 0 || i >= times.length) return const SizedBox.shrink();
                        return Text(
                          _hourLabel(times[i]),
                          style: TextStyle(fontSize: 9, color: colors.onSurfaceVariant, fontFamily: 'Poppins'),
                        );
                      },
                    ),
                  ),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true, drawVerticalLine: false,
                  horizontalInterval: 25,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.outline.withValues(alpha: 0.15), strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(rain.length, (i) => FlSpot(i.toDouble(), rain[i].toDouble())),
                    isCurved: true,
                    color: colors.primary,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: colors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _hourLabel(String iso) => iso.length >= 16 ? iso.substring(11, 16) : iso;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat chip
// ─────────────────────────────────────────────────────────────────────────────
class _StatChip extends StatelessWidget {
  final PhosphorIconData icon;
  final String label, value;

  const _StatChip({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Icon(icon, size: 20, color: colors.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Poppins')),
        Text(label, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant, fontFamily: 'Poppins')),
      ],
    );
  }
}
