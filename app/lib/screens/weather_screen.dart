import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:convert';
import 'package:lucide_icons/lucide_icons.dart';

class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _weatherData;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchWeather();
  }

  Future<void> _fetchWeather() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final backendUrl = dotenv.env['PYTHON_BACKEND_URL'] ?? 'http://localhost:8000';
      // For demo, hardcoding a fake lat/lon. In a real app, use geolocator to pass the user's location.
      final lat = 34.05;
      final lon = -118.24;
      
      final response = await http.get(Uri.parse('$backendUrl/api/weather/current?lat=$lat&lon=$lon'));

      if (response.statusCode == 200) {
        setState(() {
          _weatherData = jsonDecode(response.body);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load weather. Server returned \${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error connecting to backend: \$e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _error != null 
          ? Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _fetchWeather, child: const Text('Retry'))
              ]
            ))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text("12-Hour Forecast", style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Icon(LucideIcons.thermometerSun, size: 64, color: Colors.orange),
                        const SizedBox(height: 16),
                        Text("\${_weatherData?['current_temp']?.toStringAsFixed(1) ?? '--'}°C", style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text("Min: \${_weatherData?['temp_min']?.toStringAsFixed(1) ?? '--'}°C | Max: \${_weatherData?['temp_max']?.toStringAsFixed(1) ?? '--'}°C"),
                      ],
                    ),
                  )
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(LucideIcons.cloudRain, color: Colors.blue),
                            const SizedBox(width: 16),
                            Text("Rain Probability", style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                        Text("\${((_weatherData?['max_pop'] ?? 0) * 100).toStringAsFixed(0)}%", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                  )
                ),
                const SizedBox(height: 16),
                if (_weatherData?['will_rain_soon'] == true)
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200)
                    ),
                    child: const Row(
                      children: [
                        Icon(LucideIcons.info, color: Colors.blue),
                        SizedBox(width: 16),
                        Expanded(child: Text("High chance of rain detected. Automated pump scheduling is temporarily paused to save water.", style: TextStyle(color: Colors.blue))),
                      ],
                    ),
                  )
              ],
            )
    );
  }
}
