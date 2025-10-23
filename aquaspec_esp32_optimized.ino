// ======================= AQUASPEC ESP32 + BLE UART + OLED + SUPABASE =======================
// Board: ESP32 Dev Module
// Serial: 115200
// Optimized for Flutter app integration

// ---------------- Display ----------------
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <SPI.h>
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

// ---------------- Temp Sensor ----------------
#include <OneWire.h>
#include <DallasTemperature.h>
#include <string>      // std::string
#define ONE_WIRE_BUS 4
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature sensors(&oneWire);

// ---------------- TDS / pH pins ----------------
#define tdsSensorPin 33
#define phSensorPin  32

// ---------------- SPI Wiring for OLED ----------------
#define OLED_MOSI   23
#define OLED_CLK    18
#define OLED_RESET  22
#define OLED_DC     21
#define OLED_CS     19

// ---------------- Buttons ----------------
#define UP_BUTTON     25
#define DOWN_BUTTON   26
#define SELECT_BUTTON 27
#define BACK_BUTTON   14

// Display object
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &SPI, OLED_DC, OLED_RESET, OLED_CS);

// ---------------- UI State ----------------
#include <vector>
#include <Arduino.h>

bool inMeasurementScreen = false;
bool showedConnecting = false;
bool wifiConnected = false;
bool deviceProvisioned = false;

// ---- Tank management (from Flutter app) ----
String tankNames[10];
String tankIds[10];
int tankCount = 0;
int selectedTankIndex = 0;
String currentTankName = "";
String currentTankId = "";

// Result struct + helpers
struct SensorResults { float ph; int tds; float temp; };
template<typename T>
T computeMedian(T arr[], int n) {
  for (int i = 1; i < n; i++) { T key = arr[i]; int j = i - 1; while (j >= 0 && arr[j] > key) { arr[j+1] = arr[j]; j--; } arr[j+1] = key; }
  if (n % 2 == 1) return arr[n/2];
  return (arr[n/2 - 1] + arr[n/2]) / 2.0;
}
SensorResults takeFilteredMeasurements();

// =========================== BLE (Nordic UART) ================================
#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

#define DEV_NAME "AquaSpec-Device"

// Nordic UART UUIDs
static BLEUUID SERVICE_UUID("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
static BLEUUID RX_UUID     ("6E400002-B5A3-F393-E0A9-E50E24DCCA9E"); // write (phone->ESP32)
static BLEUUID TX_UUID     ("6E400003-B5A3-F393-E0A9-E50E24DCCA9E"); // notify (ESP32->phone)

BLEServer*         pServer = nullptr;
BLECharacteristic* pTxChar = nullptr; // notify
bool deviceConnected = false;
static std::string g_rxBuf; // buffer for fragmented writes

// ---------- fwd decl ----------
void sendJsonResult(const SensorResults& r);
void doMeasurementAndMaybeNotify();
void showConnectingToBluetooth();
void showReady();
void showWifiStatus();
void startAdvertising();
void updateTankDisplay();
static void notifyLine(const char* line);
static void notifyBytes(const uint8_t* data, size_t len);

// =========================== Wi-Fi + Supabase ================================
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <Preferences.h>

Preferences prefs;

// ---- Credentials (provisioned via BLE) ----
static String WIFI_SSID  = "";
static String WIFI_PASS  = "";
static String SUPA_URL   = "";
static String SUPA_ANON  = "";
static String DEVICE_UID = "esp32-UNSET";
static String DEVICE_NAME = "";

void wifiConnect() {
  if (WiFi.status() == WL_CONNECTED) {
    wifiConnected = true;
    return;
  }
  if (WIFI_SSID.length() == 0) {
    wifiConnected = false;
    return;
  }
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID.c_str(), WIFI_PASS.c_str());
  uint32_t t0 = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - t0 < 15000) {
    delay(200);
    Serial.print(".");
  }
  
  wifiConnected = (WiFi.status() == WL_CONNECTED);
  if (wifiConnected) {
    Serial.println("\nWiFi connected!");
    Serial.println("IP address: " + WiFi.localIP().toString());
    notifyLine("WiFi connected successfully!\n");
  } else {
    Serial.println("\nWiFi connection failed!");
    notifyLine("WiFi connection failed!\n");
  }
}

// Posts one row to public.sensor_readings
bool postReadingSupabase(float temperatureF, float ph, float tds) {
  if (!wifiConnected) {
    wifiConnect();
    if (!wifiConnected) return false;
  }

  WiFiClientSecure client;
  client.setInsecure(); // NOTE: for demo; replace with proper CA / cert pinning for prod

  HTTPClient http;
  if (!http.begin(client, SUPA_URL)) return false;

  http.addHeader("Content-Type", "application/json");
  http.addHeader("apikey", SUPA_ANON);
  http.addHeader("Authorization", "Bearer " + SUPA_ANON);
  http.addHeader("Prefer", "return=minimal");

  String chosenTankId = currentTankId.length() ? currentTankId : "default";

  String body = String("{")
    + "\"tank_id\":\""   + chosenTankId + "\","
    + "\"device_uid\":\""+ DEVICE_UID   + "\","
    + "\"temperature\":" + String(temperatureF, 1) + ","
    + "\"ph\":"          + String(ph, 2)          + ","
    + "\"tds\":"         + String(tds, 0)
    + "}";

  int code = http.POST(body);
  Serial.printf("Supabase POST -> %d\n", code);
  http.end();
  
  bool success = (code >= 200 && code < 300);
  if (success) {
    notifyLine("Reading sent: T=" + String(temperatureF, 1) + " pH=" + String(ph, 2) + " TDS=" + String(tds) + "\n");
  } else {
    notifyLine("Error sending reading to cloud\n");
  }
  
  return success;
}

// =============================== BLE callbacks ================================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    Serial.println("BLE connected (client must enable notifications).");
    showReady();
  }
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
    Serial.println("BLE disconnected, advertising…");
    startAdvertising();
    showConnectingToBluetooth();
  }
};

// Handle one full command line (no CR/LF) ------------------
static void handleCommand(const std::string& cmd) {
  if (cmd == "PING") { notifyLine("PONG\n"); return; }
  if (cmd == "MEASURE") { doMeasurementAndMaybeNotify(); return; }

  // DEBUG: force-send a fake JSON without measuring
  if (cmd == "DEBUG_JSON") {
    const char* fake = "{\"tank\":\"DEBUG\",\"ph\":7.12,\"tds\":345,\"temp_c\":24.3,\"temp_f\":75.7,\"ts\":123}\n";
    Serial.printf("DEBUG: calling notify() with %u bytes\n", (unsigned)strlen(fake));
    notifyBytes((const uint8_t*)fake, strlen(fake));
    return;
  }

  // ------- Provisioning over BLE (pipe-separated) -------
  // PROVISION:SSID|PASS|DEVICE_UID|SUPABASE_URL|SUPABASE_KEY
  size_t provisionPos = cmd.find("PROVISION:");
  if (provisionPos != std::string::npos) {
    String payload = String(cmd.c_str() + provisionPos + 10);
    String parts[5]; int pi = 0, start = 0;
    while (pi < 5) {
      int bar = payload.indexOf('|', start);
      if (bar < 0) { parts[pi++] = payload.substring(start); break; }
      parts[pi++] = payload.substring(start, bar);
      start = bar + 1;
    }

    WIFI_SSID  = parts[0]; WIFI_SSID.trim();
    WIFI_PASS  = parts[1]; WIFI_PASS.trim();
    DEVICE_UID = parts[2]; DEVICE_UID.trim();
    SUPA_URL   = parts[3]; SUPA_URL.trim();
    SUPA_ANON  = parts[4]; SUPA_ANON.trim();

    // Save to preferences
    prefs.begin("aquaspec", false);
    prefs.putString("ssid", WIFI_SSID);
    prefs.putString("pass", WIFI_PASS);
    prefs.putString("duid", DEVICE_UID);
    prefs.putString("url",  SUPA_URL);
    prefs.putString("anon", SUPA_ANON);
    prefs.putBool("provisioned", true);
    prefs.end();

    deviceProvisioned = true;
    notifyLine("WiFi and Supabase credentials received. Connecting...\n");
    
    // Connect to WiFi
    wifiConnect();
    
    delay(200);
    ESP.restart();
    return;
  }

  // ------- Set tank names (from Flutter app) -------
  // SET_TANKS:name1|name2|name3
  if (cmd.rfind("SET_TANKS:", 0) == 0) {
    String payload = String(cmd.c_str() + 10);
    tankCount = 0;
    int start = 0;
    int pipePos = payload.indexOf('|');
    
    while (pipePos > 0 && tankCount < 10) {
      tankNames[tankCount] = payload.substring(start, pipePos);
      tankNames[tankCount].trim();
      tankCount++;
      start = pipePos + 1;
      pipePos = payload.indexOf('|', start);
    }
    
    // Add the last tank name
    if (start < payload.length() && tankCount < 10) {
      tankNames[tankCount] = payload.substring(start);
      tankNames[tankCount].trim();
      tankCount++;
    }
    
    notifyLine("Tank names set: " + String(tankCount) + "\n");
    updateTankDisplay();
    return;
  }

  // ------- Set tank IDs (from Flutter app) -------
  // SET_TANK_IDS:id1|id2|id3
  if (cmd.rfind("SET_TANK_IDS:", 0) == 0) {
    String payload = String(cmd.c_str() + 13);
    int count = 0;
    int start = 0;
    int pipePos = payload.indexOf('|');
    
    while (pipePos > 0 && count < 10) {
      tankIds[count] = payload.substring(start, pipePos);
      tankIds[count].trim();
      count++;
      start = pipePos + 1;
      pipePos = payload.indexOf('|', start);
    }
    
    // Add the last tank ID
    if (start < payload.length() && count < 10) {
      tankIds[count] = payload.substring(start);
      tankIds[count].trim();
      count++;
    }
    
    notifyLine("Tank IDs set: " + String(count) + "\n");
    return;
  }

  // ------- Set device name -------
  // SET_NAME:device_name
  if (cmd.rfind("SET_NAME:", 0) == 0) {
    DEVICE_NAME = String(cmd.c_str() + 9);
    DEVICE_NAME.trim();
    
    prefs.begin("aquaspec", false);
    prefs.putString("device_name", DEVICE_NAME);
    prefs.end();
    
    notifyLine("Device name set: " + DEVICE_NAME + "\n");
    return;
  }

  // ------- Select tank for measurement -------
  // SELECT_TANK:index
  if (cmd.rfind("SELECT_TANK:", 0) == 0) {
    String payload = String(cmd.c_str() + 12);
    int index = payload.toInt();
    
    if (index >= 0 && index < tankCount) {
      selectedTankIndex = index;
      currentTankName = tankNames[index];
      currentTankId = tankIds[index];
      
      prefs.begin("aquaspec", false);
      prefs.putInt("selected_tank", selectedTankIndex);
      prefs.putString("tank_name", currentTankName);
      prefs.putString("tank_id", currentTankId);
      prefs.end();
      
      notifyLine("Selected tank: " + currentTankName + "\n");
      updateTankDisplay();
    } else {
      notifyLine("ERR: Invalid tank index\n");
    }
    return;
  }

  // ------- Navigate tanks (for button control) -------
  if (cmd == "NEXT_TANK") {
    if (tankCount > 0) {
      selectedTankIndex = (selectedTankIndex + 1) % tankCount;
      currentTankName = tankNames[selectedTankIndex];
      currentTankId = tankIds[selectedTankIndex];
      updateTankDisplay();
    }
    return;
  }

  if (cmd == "PREV_TANK") {
    if (tankCount > 0) {
      selectedTankIndex = (selectedTankIndex - 1 + tankCount) % tankCount;
      currentTankName = tankNames[selectedTankIndex];
      currentTankId = tankIds[selectedTankIndex];
      updateTankDisplay();
    }
    return;
  }

  // default echo
  {
    std::string echo = "ECHO:" + cmd + "\n";
    notifyBytes((const uint8_t*)echo.data(), echo.size());
  }
}

// Buffering RX: accumulate until newline --------------------
class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* ch) override {
    std::string part = std::string(ch->getValue().c_str());
    if (part.empty()) return;

    g_rxBuf += part;

    for (;;) {
      size_t nl = g_rxBuf.find('\n');
      if (nl == std::string::npos) break;

      std::string line = g_rxBuf.substr(0, nl);
      g_rxBuf.erase(0, nl + 1);

      while (!line.empty() && (line.back()=='\r' || line.back()=='\n')) line.pop_back();
      if (line.empty()) continue;

      Serial.printf("BLE RX: %s\n", line.c_str());
      handleCommand(line);
    }
  }
};

// =============================== SETUP/LOOP ==================================
void setup() {
  Serial.begin(115200);
  delay(100);

  sensors.begin();

  // OLED
  SPI.begin(OLED_CLK, -1, OLED_MOSI, OLED_CS);
  if (!display.begin(SSD1306_SWITCHCAPVCC)) {
    Serial.println(F("SSD1306 allocation failed"));
    for(;;);
  }
  display.setRotation(3);
  pinMode(UP_BUTTON, INPUT_PULLUP);
  pinMode(DOWN_BUTTON, INPUT_PULLUP);
  pinMode(SELECT_BUTTON, INPUT_PULLUP);
  pinMode(BACK_BUTTON, INPUT_PULLUP);

  showConnectingToBluetooth();

  // BLE
  BLEDevice::init(DEV_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  BLEService* pService = pServer->createService(SERVICE_UUID);

  // TX notify
  pTxChar = pService->createCharacteristic(TX_UUID, BLECharacteristic::PROPERTY_NOTIFY);
  pTxChar->addDescriptor(new BLE2902());

  // RX write
  BLECharacteristic* pRxChar = pService->createCharacteristic(
      RX_UUID, BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR);
  pRxChar->setCallbacks(new RxCallbacks());

  pService->start();
  startAdvertising();

  Serial.println("BLE UART ready. Advertising as AquaSpec-Device");

  // Load persisted data
  prefs.begin("aquaspec", true);
  WIFI_SSID = prefs.getString("ssid", WIFI_SSID);
  WIFI_PASS = prefs.getString("pass", WIFI_PASS);
  DEVICE_UID = prefs.getString("duid", DEVICE_UID);
  SUPA_URL = prefs.getString("url", SUPA_URL);
  SUPA_ANON = prefs.getString("anon", SUPA_ANON);
  DEVICE_NAME = prefs.getString("device_name", DEVICE_NAME);
  deviceProvisioned = prefs.getBool("provisioned", false);
  selectedTankIndex = prefs.getInt("selected_tank", 0);
  currentTankName = prefs.getString("tank_name", currentTankName);
  currentTankId = prefs.getString("tank_id", currentTankId);
  prefs.end();

  // Connect to WiFi if provisioned
  if (deviceProvisioned) {
    wifiConnect();
  }
}

void startAdvertising() {
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  adv->setMinPreferred(0x06);
  adv->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("Advertising started.");
}

void loop() {
  static unsigned long lastButtonPress = 0;
  const unsigned long debounceDelay = 200;

  if (!deviceConnected && !showedConnecting) {
    showConnectingToBluetooth();
  }

  if (millis() - lastButtonPress < debounceDelay) return;

  // Button handling
  if (digitalRead(UP_BUTTON) == LOW) {
    if (tankCount > 0) {
      selectedTankIndex = (selectedTankIndex - 1 + tankCount) % tankCount;
      currentTankName = tankNames[selectedTankIndex];
      currentTankId = tankIds[selectedTankIndex];
      updateTankDisplay();
      lastButtonPress = millis();
    }
  }

  if (digitalRead(DOWN_BUTTON) == LOW) {
    if (tankCount > 0) {
      selectedTankIndex = (selectedTankIndex + 1) % tankCount;
      currentTankName = tankNames[selectedTankIndex];
      currentTankId = tankIds[selectedTankIndex];
      updateTankDisplay();
      lastButtonPress = millis();
    }
  }

  if (digitalRead(SELECT_BUTTON) == LOW) {
    if (tankCount > 0) {
      doMeasurementAndMaybeNotify();
    } else {
      // If no tanks set, show status
      showWifiStatus();
    }
    lastButtonPress = millis();
  }

  if (digitalRead(BACK_BUTTON) == LOW) {
    inMeasurementScreen = false;
    updateTankDisplay();
    lastButtonPress = millis();
  }
}

// ============================== DISPLAY HELPERS ===============================
void showConnectingToBluetooth() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(6, 20); display.print("Connecting to");
  display.setCursor(6, 32); display.print("Bluetooth...");
  display.display();
  showedConnecting = true;
}

void showReady() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(6, 20); display.print("Connected.");
  display.setCursor(6, 32); display.print("Ready.");
  display.display();
}

void showWifiStatus() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(6, 8); display.print("WiFi: ");
  display.print(wifiConnected ? "Connected" : "Disconnected");
  display.setCursor(6, 20); display.print("Provisioned: ");
  display.print(deviceProvisioned ? "Yes" : "No");
  display.setCursor(6, 32); display.print("Tanks: ");
  display.print(tankCount);
  display.display();
  delay(2000);
  updateTankDisplay();
}

void updateTankDisplay() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  
  if (tankCount == 0) {
    display.setCursor(6, 20); display.print("No tanks set");
    display.setCursor(6, 32); display.print("Use app to add");
  } else {
    display.setCursor(6, 8); display.print("Tank:");
    display.setCursor(6, 20); display.print(currentTankName);
    display.setCursor(6, 32); display.print(String(selectedTankIndex + 1) + "/" + String(tankCount));
    display.fillRect(0, 36, 128, 20, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);
    display.setCursor(18, 42); display.print("Press SELECT");
    display.setTextColor(SSD1306_WHITE);
  }
  
  display.display();
}

// ================= SENSOR MEASUREMENT FUNCTIONS =================
float measurePH() {
  int sensorValue = analogRead(phSensorPin);
  return -0.0214 * sensorValue + 16.7711; // calibration
}

int measureTDS(float TEMP) {
  int sensorValue = analogRead(tdsSensorPin);
  float voltage = sensorValue * (3.3 / 4095.0);
  float compensationCoefficient = 1.0 + 0.02 * (TEMP - 25.0);
  float compensatedVoltage = voltage / compensationCoefficient;
  float tdsValue = (133.42 * pow(compensatedVoltage, 3)
                 - 255.86 * pow(compensatedVoltage, 2)
                 + 857.39 * compensatedVoltage) * 0.5;
  tdsValue = tdsValue / 880 * 706.5;
  return (int)tdsValue;
}

float measureTemp() {
  sensors.requestTemperatures();
  float t = sensors.getTempCByIndex(0);
  if (t < -100.0f) t = 25.0f; // guard if DS18B20 not present
  return t;
}

SensorResults takeFilteredMeasurements() {
  const int NUM_SAMPLES = 20;
  float phSamples[NUM_SAMPLES];
  int   tdsSamples[NUM_SAMPLES];
  float tempSamples[NUM_SAMPLES];

  unsigned long interval = 5000 / NUM_SAMPLES; // ~250ms over ~5s

  for (int i = 0; i < NUM_SAMPLES; i++) {
    tempSamples[i] = measureTemp();
    if (i < NUM_SAMPLES - 1) delay(interval);
  }
  SensorResults results;
  results.temp = computeMedian(tempSamples, NUM_SAMPLES);

  for (int i = 0; i < NUM_SAMPLES; i++) {
    phSamples[i]  = measurePH();
    tdsSamples[i] = measureTDS(results.temp);
    if (i < NUM_SAMPLES - 1) delay(interval);
  }
  results.ph  = computeMedian(phSamples, NUM_SAMPLES);
  results.tds = computeMedian(tdsSamples, NUM_SAMPLES);
  return results;
}

// --------------------- NOTIFY HELPERS ---------------------
static void notifyBytes(const uint8_t* data, size_t len) {
  if (!deviceConnected) {
    Serial.println("notify() skipped: no BLE client connected.");
    return;
  }
  if (!pTxChar) {
    Serial.println("notify() skipped: TX characteristic not ready.");
    return;
  }
  pTxChar->setValue((uint8_t*)data, len);
  Serial.printf("notify(): attempting to send %u bytes\n", (unsigned)len);
  pTxChar->notify();
}

static void notifyLine(const char* line) {
  notifyBytes((const uint8_t*)line, strlen(line));
}

// Run the measurement, show on OLED, notify JSON, and POST to Supabase
void doMeasurementAndMaybeNotify() {
  if (tankCount == 0) {
    notifyLine("ERR: No tanks configured\n");
    return;
  }

  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0); display.print("Measuring");
  display.display();

  SensorResults r = takeFilteredMeasurements();

  float pH   = r.ph;
  int   tds  = r.tds;
  float temp = r.temp;

  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 4);   display.print("Tank: ");
  display.print(currentTankName);
  display.setCursor(0, 20);  display.print("pH: ");   display.print(pH, 2);
  display.setCursor(0, 32);  display.print("TDS: ");  display.print(tds);
  display.setCursor(0, 44);  display.print("Temp: "); display.print(temp, 1); display.print((char)247); display.print("C");
  display.display();

  // BLE notify to phone
  if (deviceConnected && pTxChar) {
    sendJsonResult(r);
  } else {
    Serial.println("Measurement done, but no notify (not connected / no TX).");
  }

  // Cloud upload (Fahrenheit to match your existing table)
  float tempF = (r.temp * 9.0f / 5.0f) + 32.0f;
  bool posted = postReadingSupabase(tempF, r.ph, r.tds);
  Serial.println(posted ? "cloud: OK" : "cloud: FAIL");

  // back to home screen
  delay(2000);
  updateTankDisplay();
}

// ========================== BLE JSON NOTIFY ==========================
void sendJsonResult(const SensorResults& r) {
  float tempF = (r.temp * 9.0f / 5.0f) + 32.0f;
  char buf[192];
  unsigned long ts = (unsigned long)(millis() / 1000);

  String nameForJson = currentTankName.length() ? currentTankName : String("UNKNOWN");

  int n = snprintf(buf, sizeof(buf),
    "{\"tank\":\"%s\",\"ph\":%.2f,\"tds\":%d,\"temp_c\":%.2f,\"temp_f\":%.2f,\"ts\":%lu}\n",
    nameForJson.c_str(), r.ph, r.tds, r.temp, tempF, ts);

  if (n < 0) { Serial.println("JSON snprintf failed."); return; }
  if ((size_t)n >= sizeof(buf)) {
    Serial.printf("JSON truncated to %u bytes\n", (unsigned)sizeof(buf));
    n = sizeof(buf) - 1; buf[n] = '\0';
  }

  Serial.printf("Notify JSON (%d bytes): %s", n, buf);
  notifyBytes((const uint8_t*)buf, (size_t)n);
}
