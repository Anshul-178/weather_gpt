// Builds the plain-text weather context that is injected into the on-device
// LLM prompt. Mirrors the backend's build_weather_context: all values come
// from the WeatherGPT API response, never invented by the model.

import '../models/weather.dart';

String buildWeatherContext(CurrentWeather? current, List<HourlyPoint> hourly,
    List<DailyPoint> daily, String? locationName) {
  final lines = <String>[];
  final place = (locationName == null || locationName.isEmpty)
      ? 'Unknown location'
      : locationName;
  lines.add('Location: $place');

  final c = current;
  if (c != null) {
    final buffer = StringBuffer('Now: ');
    if (c.temperature != null) buffer.write('${c.temperature!.round()}°C');
    if (c.feelsLike != null) {
      buffer.write(', feels like ${c.feelsLike!.round()}°C');
    }
    if (c.condition != null && c.condition!.isNotEmpty) {
      buffer.write(', ${c.condition!}');
    }
    if (c.precipitationProbability != null) {
      buffer.write(', rain chance ${c.precipitationProbability!.round()}%');
    }
    if (c.humidity != null) buffer.write(', humidity ${c.humidity!.round()}%');
    if (c.windSpeed != null) buffer.write(', wind ${c.windSpeed!.round()} km/h');
    if (c.uvIndex != null) buffer.write(', UV ${c.uvIndex!.round()}');
    lines.add(buffer.toString());
  }

  if (hourly.isNotEmpty) {
    final window = hourly.take(12).toList();
    final parts = <String>[];
    for (final p in window) {
      final hour = p.time.hour.toString().padLeft(2, '0');
      final temp = p.temperature?.round();
      final rain = p.precipitationProbability?.round();
      final cond = p.condition;
      final bits = <String>[
        if (temp != null) '$temp°C',
        if (rain != null) 'rain $rain%',
        if (cond != null && cond.isNotEmpty) cond,
      ];
      parts.add('$hour:00: ${bits.join(', ')}');
    }
    lines.add('Next hours: ${parts.join(' | ')}');
  }

  if (daily.isNotEmpty) {
    final window = daily.take(3).toList();
    final parts = <String>[];
    for (var i = 0; i < window.length; i++) {
      final d = window[i];
      final label = i == 0
          ? 'Today'
          : i == 1
              ? 'Tomorrow'
              : _weekday(d.date);
      final bits = <String>[
        if (d.temperatureMax != null) 'high ${d.temperatureMax!.round()}°C',
        if (d.temperatureMin != null) 'low ${d.temperatureMin!.round()}°C',
        if (d.precipitationProbability != null)
          'rain ${d.precipitationProbability!.round()}%',
        if (d.condition != null && d.condition!.isNotEmpty) d.condition!,
      ];
      parts.add('$label: ${bits.join(', ')}');
    }
    lines.add('Forecast: ${parts.join(' | ')}');
  }

  return lines.join('\n');
}

String _weekday(String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return 'Day 3';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[d.weekday - 1];
}
