# Sensor Calibration Guide

## Overview

This guide documents the sensor calibration process for RootSync ESP32 firmware. Proper calibration ensures accurate readings for soil moisture and rain detection.

---

## Issues Addressed

| Issue | Symptom | Root Cause |
|-------|---------|------------|
| Moisture reads 21% in air | Shows moisture when sensor is dry | Calibration values (4095, 1000) don't match actual sensor |
| Rain sensor always HIGH | Shows rain=1 even when dry | Logic inverted or wrong sensor type assumed |

---

## Sensor Calibration Values

### Soil Moisture Sensor (Capacitive)

The ESP32 ADC (Analog-to-Digital Converter) reads raw values from 0-4095. These need to be mapped to 0-100% moisture.

| Condition | Raw ADC Value | Expected Output |
|-----------|---------------|-----------------|
| **Dry Air** | `___` (fill in) | 0% |
| **Submerged in Water** | `___` (fill in) | 100% |

**How to calibrate:**
1. Hold sensor in dry air, note the Serial Monitor value
2. Dip sensor tip in water, note the Serial Monitor value
3. Update `config.h` with these values

### Rain Sensor (Digital)

Digital rain sensors output either HIGH (1) or LOW (0) when wet.

| Condition | Output | Sensor Type |
|-----------|--------|-------------|
| **Dry** | `___` (fill in) | - |
| **Wet (water drop)** | `___` (fill in) | - |

**Determining sensor type:**
- If DRY=1 and WET=0 → **Active LOW** (most common, set `RAIN_SENSOR_INVERT false`)
- If DRY=0 and WET=1 → **Active HIGH** (set `RAIN_SENSOR_INVERT true`)

---

## Calibration Mode

The firmware includes a calibration mode that prints raw sensor values every second.

### How to Use

1. Flash the updated firmware with `CALIBRATION_MODE = true`
2. Open Serial Monitor at **115200 baud**
3. On boot, calibration mode runs for **30 seconds**
4. Observe the raw values:

```
[CAL] ===============================================
[CAL]      SENSOR CALIBRATION MODE
[CAL] ===============================================
[CAL]
[CAL] SOIL MOISTURE:
[CAL]   Current raw value: 2850
[CAL]   1. Hold sensor in DRY AIR - note value
[CAL]   2. Dip sensor in WATER - note value
[CAL]   3. Update MOISTURE_AIR_RAW and MOISTURE_WATER_RAW in config.h
[CAL]
[CAL] RAIN SENSOR:
[CAL]   Current raw value: 1
[CAL]   1. Keep sensor DRY - note value
[CAL]   2. Drop WATER on sensor - note value
[CAL]   3. If DRY=1 & WET=0: RAIN_SENSOR_INVERT = false
[CAL]   4. If DRY=0 & WET=1: RAIN_SENSOR_INVERT = true
[CAL]
[CAL] ===============================================

[CAL] Moisture: raw=2850 (≈ 21%) | Rain: raw=1 | Time: 0s
[CAL] Moisture: raw=2847 (≈ 21%) | Rain: raw=1 | Time: 1s
[CAL] Moisture: raw=2851 (≈ 21%) | Rain: raw=0 | Time: 5s  <-- Water drop on rain sensor!
[CAL] Moisture: raw=1100 (≈100%) | Rain: raw=0 | Time: 12s <-- Moisture sensor in water!
[CAL] ===============================================
[CAL] Calibration mode complete!
[CAL] Set CALIBRATION_MODE = false in config.h
[CAL] ===============================================
```

5. Note your measured values:
   - Moisture in air: `____` (e.g., 2850)
   - Moisture in water: `____` (e.g., 1100)
   - Rain dry value: `____` (0 or 1)
   - Rain wet value: `____` (0 or 1)

6. Update `config.h` with your measured values
7. Set `CALIBRATION_MODE = false`
8. Reflash firmware

---

## Configuration (config.h)

```cpp
// -- Soil Moisture Calibration -----------------------------------------------
// Measured values - update with YOUR sensor readings from calibration mode
// These are PLACEHOLDERS - replace with your actual measured values!
#define MOISTURE_AIR_RAW    3200  // ADC reading in dry air (maps to 0%)
#define MOISTURE_WATER_RAW  1100  // ADC reading in water (maps to 100%)

// -- Rain Sensor Configuration -----------------------------------------------
// Set based on calibration:
// true  = sensor outputs HIGH when wet (Active HIGH) - rare
// false = sensor outputs LOW when wet (Active LOW) - most common (YL-38)
#define RAIN_SENSOR_INVERT  false

// -- Calibration Mode ---------------------------------------------------------
// Set to true during calibration, false for normal operation
#define CALIBRATION_MODE    true   // Set false after calibration
```

### Quick Reference: What to Set

| Your Reading | Config Value |
|--------------|--------------|
| Moisture raw in air (e.g., 2850) | `MOISTURE_AIR_RAW` |
| Moisture raw in water (e.g., 1100) | `MOISTURE_WATER_RAW` |
| Rain DRY=1, WET=0 | `RAIN_SENSOR_INVERT false` |
| Rain DRY=0, WET=1 | `RAIN_SENSOR_INVERT true` |

---

## Calibration Checklist

- [ ] Flash firmware with `CALIBRATION_MODE true`
- [ ] Open Serial Monitor at 115200 baud
- [ ] Note moisture raw value in dry air: `____`
- [ ] Note moisture raw value in water: `____`
- [ ] Drop water on rain sensor
- [ ] Note rain sensor value when dry: `____`
- [ ] Note rain sensor value when wet: `____`
- [ ] Update `config.h` with values
- [ ] Set `CALIBRATION_MODE false`
- [ ] Reflash firmware
- [ ] Verify readings are correct

---

## Troubleshooting

### Moisture Reading Too High in Air

**Symptom:** Reads >5% when held in dry air

**Cause:** `MOISTURE_AIR_RAW` is lower than actual dry reading

**Fix:** Run calibration mode, note dry air value, set `MOISTURE_AIR_RAW` to that value

**Example:** If dry air reads 2850 but `MOISTURE_AIR_RAW = 3200`, change to 2850

### Moisture Reading Doesn't Reach 100%

**Symptom:** Maxes out at 80% even in water

**Cause:** `MOISTURE_WATER_RAW` is lower than actual water reading

**Fix:** Run calibration mode, note water value, set `MOISTURE_WATER_RAW` to that value

### Rain Sensor Always Shows Rain

**Symptom:** Rain = true even when dry

**Cause:** `RAIN_SENSOR_INVERT` setting is wrong for your sensor type

**Fix:** 
1. Note rain sensor values in calibration mode (dry vs wet)
2. If DRY=1 and WET=0 → set `RAIN_SENSOR_INVERT = false`
3. If DRY=0 and WET=1 → set `RAIN_SENSOR_INVERT = true`

### Rain Sensor Never Triggers

**Symptom:** Rain = false even with water

**Cause:** Sensor wiring issue or wrong `RAIN_SENSOR_INVERT` setting

**Fix:**
1. Check sensor is powered (VCC, GND connected)
2. Check signal wire to GPIO35
3. Verify values in calibration mode

### Calibration Values Don't Make Sense

**Symptom:** Moisture value doesn't change between air and water

**Cause:** Sensor may be faulty or wrong pin configured

**Fix:**
1. Check `PIN_SOIL_MOISTURE = 34` in config.h
2. Verify sensor is connected to correct GPIO
3. Test with a different sensor if available

---

## Default Values (Pre-Calibration)

If you haven't calibrated yet, these values are reasonable defaults:

```cpp
#define MOISTURE_AIR_RAW    3200  // Approximate for most sensors
#define MOISTURE_WATER_RAW  1100  // Approximate for most sensors
#define RAIN_SENSOR_INVERT  false // Active LOW (most common)
```

---

## References

- ESP32 ADC: 12-bit (0-4095), 3.3V reference
- Capacitive moisture sensors: Higher ADC = drier
- YL-38 rain sensor module: Active LOW output
- D4184 MOSFET: For PWM pump control

---

*Last updated: 2026-03-30*
*Document version: 1.0*