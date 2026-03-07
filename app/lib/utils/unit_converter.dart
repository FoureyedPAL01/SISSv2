class UnitConverter {
  static String formatTemp(double celsius, String unit) {
    if (unit == 'fahrenheit') {
      return '${(celsius * 9 / 5 + 32).toStringAsFixed(1)}°F';
    }
    return '${celsius.toStringAsFixed(1)}°C';
  }

  static String formatVolume(double liters, String unit) {
    if (unit == 'gallons') {
      return '${(liters * 0.264172).toStringAsFixed(2)} gal';
    }
    return '${liters.toStringAsFixed(1)} L';
  }

  static double celsiusToFahrenheit(double celsius) {
    return celsius * 9 / 5 + 32;
  }

  static double fahrenheitToCelsius(double fahrenheit) {
    return (fahrenheit - 32) * 5 / 9;
  }

  static double litersToGallons(double liters) {
    return liters * 0.264172;
  }

  static double gallonsToLiters(double gallons) {
    return gallons / 0.264172;
  }
}
