## **Features that must be implemented**

* **Automatic Soil Moisture–Based Irrigation: The system continuously monitors soil moisture and automatically turns the water pump ON or OFF based on predefined threshold values, ensuring optimal watering without manual effort.**  
* **Predictive Weather-Based Irrigation Control: Before starting irrigation, the system fetches weather forecast data using an online API. If rain is predicted, the irrigation cycle is skipped to conserve water.**  
* **IoT-Based Remote Monitoring: Users can monitor real-time soil moisture, temperature, humidity, and pump status from anywhere using a mobile application.**  
* **Manual Pump Control: The system allows the user to manually turn the pump ON or OFF through the mobile app, overriding automatic decisions when needed.**  
* **Rain Detection Safety Mechanism: A rain sensor provides a hardware-level safety mechanism to immediately stop irrigation during rainfall, even if automation is active.**  
* **Environmental Monitoring: The system measures ambient temperature and humidity to support intelligent irrigation decisions and future adaptive logic.**  
* **Smart Pump Scheduling with Thresholds: Allow dynamic thresholds for soil moisture instead of fixed values. Threshold can change based on temperature & humidity (from DHT11).**  
* **Water Usage Estimation & Logging: The system estimates the amount of water used by calculating pump runtime and displays total consumption on the IoT dashboard.**  
* **Alert / Notification Feature: Send push notifications on Blynk app: Pump ON/OFF, Soil dry alert, Rain detected / rain forecast**  
* **Crop-Specific Irrigation Profiles: User selects crop type in the app (e.g., Wheat, Rice, Tomato), and changes automatically: Soil moisture threshold, Irrigation duration, Weather sensitivity**  
* **Irrigation Efficiency Score:  The system calculates a simple score (0–100%) based on: Water used, Soil moisture improvement, Rain contribution**  
* **Fault Detection & Alert System: Detects Sensor value stuck for a long time, Pump ON but no moisture change, No WiFi data upload and alerts user.**  
* **Evapotranspiration (ET) Calculation: Calculate actual plant water needs using Penman-Monteith or the simpler Hargreaves equation.**  
* **Fertilizer Integration (Fertigation) Alert: Add a "Days Since Last Fertilized" counter in the Blynk app. Based on the water usage logs, the system can suggest when the soil nutrients might be depleted and notify the user to add liquid fertilizer.**
