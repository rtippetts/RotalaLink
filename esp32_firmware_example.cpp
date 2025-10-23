/*
 * ESP32 Aquarium Diagnostic Device - Firmware Example
 * 
 * This is a simplified example of what your ESP32 firmware should implement
 * to work with your Flutter app. This shows the communication protocol
 * and basic structure.
 */

#include <WiFi.h>
#include <BluetoothSerial.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>

// Bluetooth Serial for communication with Flutter app
BluetoothSerial SerialBT;

// WiFi credentials (received from app)
String wifiSSID = "";
String wifiPassword = "";
String deviceUID = "";

// Supabase configuration (received from app)
String supabaseUrl = "";
String supabaseKey = "";

// Sensor pins (example)
const int tempPin = A0;
const int phPin = A1;
const int tdsPin = A2;

// Tank selection (received from app)
String tankNames[10];
String tankIds[10];
int tankCount = 0;
String selectedTankId = "";

void setup() {
  Serial.begin(115200);
  
  // Initialize Bluetooth
  SerialBT.begin("AquaSpec-Device"); // Device name for BLE advertising
  Serial.println("Bluetooth device is ready to pair");
  
  // Initialize sensors
  pinMode(tempPin, INPUT);
  pinMode(phPin, INPUT);
  pinMode(tdsPin, INPUT);
  
  // Try to connect to WiFi if credentials are stored
  loadWiFiCredentials();
  if (wifiSSID.length() > 0) {
    connectToWiFi();
  }
}

void loop() {
  // Handle Bluetooth commands from Flutter app
  if (SerialBT.available()) {
    String command = SerialBT.readStringUntil('\n');
    command.trim();
    handleBluetoothCommand(command);
  }
  
  // If connected to WiFi, send sensor readings to Supabase
  if (WiFi.status() == WL_CONNECTED && selectedTankId.length() > 0) {
    sendSensorReadings();
    delay(30000); // Send readings every 30 seconds
  }
  
  delay(100);
}

void handleBluetoothCommand(String command) {
  Serial.println("Received: " + command);
  
  if (command.startsWith("PROVISION:")) {
    // Format: PROVISION:SSID|PASSWORD|DEVICE_UID|SUPABASE_URL|SUPABASE_KEY
    int firstPipe = command.indexOf('|', 10);
    int secondPipe = command.indexOf('|', firstPipe + 1);
    int thirdPipe = command.indexOf('|', secondPipe + 1);
    int fourthPipe = command.indexOf('|', thirdPipe + 1);
    
    if (firstPipe > 0 && secondPipe > 0 && thirdPipe > 0 && fourthPipe > 0) {
      wifiSSID = command.substring(10, firstPipe);
      wifiPassword = command.substring(firstPipe + 1, secondPipe);
      deviceUID = command.substring(secondPipe + 1, thirdPipe);
      supabaseUrl = command.substring(thirdPipe + 1, fourthPipe);
      supabaseKey = command.substring(fourthPipe + 1);
      
      // Save credentials
      saveWiFiCredentials();
      
      // Connect to WiFi
      connectToWiFi();
      
      // Send confirmation
      SerialBT.println("WiFi and Supabase credentials received. Connecting...");
    }
  }
  else if (command.startsWith("SET_TANKS:")) {
    // Format: SET_TANKS:name1|name2|name3
    String tankList = command.substring(10);
    parseTankNames(tankList);
    SerialBT.println("Tank names set: " + String(tankCount));
  }
  else if (command.startsWith("SET_TANK_IDS:")) {
    // Format: SET_TANK_IDS:id1|id2|id3
    String idList = command.substring(13);
    parseTankIds(idList);
    SerialBT.println("Tank IDs set: " + String(tankCount));
  }
  else if (command.startsWith("SET_NAME:")) {
    // Format: SET_NAME:device_name
    String deviceName = command.substring(9);
    SerialBT.println("Device name set: " + deviceName);
  }
  else if (command.startsWith("SELECT_TANK:")) {
    // Format: SELECT_TANK:tank_id
    selectedTankId = command.substring(12);
    SerialBT.println("Selected tank: " + selectedTankId);
  }
}

void parseTankNames(String tankList) {
  tankCount = 0;
  int start = 0;
  int pipePos = tankList.indexOf('|');
  
  while (pipePos > 0 && tankCount < 10) {
    tankNames[tankCount] = tankList.substring(start, pipePos);
    tankCount++;
    start = pipePos + 1;
    pipePos = tankList.indexOf('|', start);
  }
  
  // Add the last tank name
  if (start < tankList.length() && tankCount < 10) {
    tankNames[tankCount] = tankList.substring(start);
    tankCount++;
  }
}

void parseTankIds(String idList) {
  int count = 0;
  int start = 0;
  int pipePos = idList.indexOf('|');
  
  while (pipePos > 0 && count < 10) {
    tankIds[count] = idList.substring(start, pipePos);
    count++;
    start = pipePos + 1;
    pipePos = idList.indexOf('|', start);
  }
  
  // Add the last tank ID
  if (start < idList.length() && count < 10) {
    tankIds[count] = idList.substring(start);
    count++;
  }
}

void connectToWiFi() {
  if (wifiSSID.length() == 0) return;
  
  Serial.println("Connecting to WiFi: " + wifiSSID);
  WiFi.begin(wifiSSID.c_str(), wifiPassword.c_str());
  
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(1000);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected!");
    Serial.println("IP address: " + WiFi.localIP().toString());
    SerialBT.println("WiFi connected successfully!");
  } else {
    Serial.println("\nWiFi connection failed!");
    SerialBT.println("WiFi connection failed!");
  }
}

void sendSensorReadings() {
  // Read sensor values (this is simplified - you'll need proper calibration)
  float temperature = readTemperature();
  float ph = readPH();
  float tds = readTDS();
  
  // Create JSON payload
  DynamicJsonDocument doc(1024);
  doc["device_uid"] = deviceUID;
  doc["tank_id"] = selectedTankId;
  doc["temperature"] = temperature;
  doc["ph"] = ph;
  doc["tds"] = tds;
  doc["recorded_at"] = WiFi.getTime();
  
  String jsonString;
  serializeJson(doc, jsonString);
  
  // Send to Supabase
  HTTPClient http;
  http.begin(supabaseUrl + String("/rest/v1/sensor_readings"));
  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", supabaseKey);
  http.addHeader("Authorization", "Bearer " + supabaseKey);
  
  int httpResponseCode = http.POST(jsonString);
  
  if (httpResponseCode > 0) {
    String response = http.getString();
    Serial.println("Supabase response: " + String(httpResponseCode));
    SerialBT.println("Reading sent: T=" + String(temperature) + " pH=" + String(ph) + " TDS=" + String(tds));
  } else {
    Serial.println("Error sending to Supabase: " + String(httpResponseCode));
    SerialBT.println("Error sending reading to cloud");
  }
  
  http.end();
}

float readTemperature() {
  // Read analog value and convert to temperature
  // This is a placeholder - implement proper temperature sensor reading
  int rawValue = analogRead(tempPin);
  return 20.0 + (rawValue * 0.1); // Example conversion
}

float readPH() {
  // Read analog value and convert to pH
  // This is a placeholder - implement proper pH sensor reading
  int rawValue = analogRead(phPin);
  return 7.0 + (rawValue - 512) * 0.01; // Example conversion
}

float readTDS() {
  // Read analog value and convert to TDS
  // This is a placeholder - implement proper TDS sensor reading
  int rawValue = analogRead(tdsPin);
  return rawValue * 0.5; // Example conversion
}

void saveWiFiCredentials() {
  // Save to EEPROM or preferences
  // Implementation depends on your storage preference
  preferences.begin("credentials", false);
  preferences.putString("ssid", wifiSSID);
  preferences.putString("password", wifiPassword);
  preferences.putString("device_uid", deviceUID);
  preferences.putString("supabase_url", supabaseUrl);
  preferences.putString("supabase_key", supabaseKey);
  preferences.end();
}

void loadWiFiCredentials() {
  // Load from EEPROM or preferences
  preferences.begin("credentials", false);
  wifiSSID = preferences.getString("ssid", "");
  wifiPassword = preferences.getString("password", "");
  deviceUID = preferences.getString("device_uid", "");
  supabaseUrl = preferences.getString("supabase_url", "");
  supabaseKey = preferences.getString("supabase_key", "");
  preferences.end();
}
