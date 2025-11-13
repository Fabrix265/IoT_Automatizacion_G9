// conveyor.ino
#include <WiFi.h>
#include <HTTPClient.h>

/////////////////////
// === PINOUT ===
/////////////////////
const int LED_VERDE_PIN = 25;
const int LED_ROJO_PIN  = 26;
const int BUZZER_PIN    = 27;

const int MOTOR1_RELAY_PIN = 14; // relé motor cinta
const int MOTOR2_RELAY_PIN = 12; // opcional

// HC-SR04 top (conteo y tamaño)
const int TOP_TRIG = 32;
const int TOP_ECHO = 33;

// HC-SR04 box (almacen)
const int BOX_TRIG = 4;
const int BOX_ECHO = 2;

/////////////////////
// === SETTINGS ===
/////////////////////
const char* ssid = "VERONICA2";           // <-- CAMBIAR
const char* password = "veronica2";       // <-- CAMBIAR

const char* SERVER_BASE = "http://192.168.1.141:5000/api/update"; // <-- ### CAMBIAR SEGUN DESPLIEGUE/NGROK DEMAS ###
const char* API_KEY = "patroclo";               // <-- CAMBIAR

// object detection params
const int TOP_DETECT_THRESHOLD_CM = 15; // si la distancia es menor a esto detecta objeto encima del sensor
const int DEBOUNCE_MS = 200;            // anti-rebotes para detección de objetos

// box fill threshold
const int BOX_FILL_THRESHOLD_CM = 8;    // si distancia de caja < esto => llena (ajustar segun caja)

unsigned long lastDevicePoll = 0;
const unsigned long DEVICE_POLL_INTERVAL = 1500; // ms

// object detection state
bool waiting_for_object = true;
unsigned long object_detected_at = 0;
int object_min_distance = 1000; // track min distance during presence

void setup() {
  Serial.begin(115200);
  pinMode(LED_VERDE_PIN, OUTPUT);
  pinMode(LED_ROJO_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(MOTOR1_RELAY_PIN, OUTPUT);
  pinMode(MOTOR2_RELAY_PIN, OUTPUT);

  // relés off (LOW or HIGH depending module)
  digitalWrite(MOTOR1_RELAY_PIN, LOW);
  digitalWrite(MOTOR2_RELAY_PIN, LOW);

  pinMode(TOP_TRIG, OUTPUT);
  pinMode(TOP_ECHO, INPUT);
  pinMode(BOX_TRIG, OUTPUT);
  pinMode(BOX_ECHO, INPUT);

  WiFi.begin(ssid, password);
  Serial.print("Conectando a WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWiFi conectado: " + WiFi.localIP().toString());
}

/////////////////
// UTIL
/////////////////
long readUltrasonicCM(int trigPin, int echoPin) {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);
  long duration = pulseIn(echoPin, HIGH, 30000); // timeout 30ms
  long cm = duration / 29 / 2;
  if (cm == 0) return 9999; // timeout -> no reading
  return cm;
}

void buzz(int ms) { digitalWrite(BUZZER_PIN, HIGH); delay(ms); digitalWrite(BUZZER_PIN, LOW); }

/////////////////
// POST helper
/////////////////
void postObjectEvent(const char* size_cat, float length_est) {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SERVER_BASE) + "/api/object_event";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-api-key", API_KEY);
  String payload = "{\"size_cat\":\"" + String(size_cat) + "\",\"length_est\":" + String(length_est, 2) + "}";
  int code = http.POST(payload);
  if (code > 0) {
    String res = http.getString();
    Serial.printf("POST object_event %d: %s\n", code, res.c_str());
  } else {
    Serial.printf("Error POST object_event: %s\n", http.errorToString(code).c_str());
  }
  http.end();
}

void setBackendBoxFull(bool state) {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SERVER_BASE) + "/api/device_state";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-api-key", API_KEY);
  String payload = "{\"box_full\": " + String(state ? "true" : "false") + "}";
  int code = http.POST(payload);
  Serial.printf("POST box_full %d\n", code);
  http.end();
}

/////////////////
// Poll backend for motor/turn led/box status
/////////////////
void pollDeviceState() {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SERVER_BASE) + "/api/device_state";
  http.begin(url);
  int code = http.GET();
  if (code == 200) {
    String res = http.getString();
    bool motor_on = res.indexOf("\"motor_on\":true") >= 0;
    bool turn_led_on = res.indexOf("\"turn_led_on\":true") >= 0;
    bool box_full = res.indexOf("\"box_full\":true") >= 0;
    // control outputs
    digitalWrite(MOTOR1_RELAY_PIN, motor_on ? HIGH : LOW);
    digitalWrite(MOTOR2_RELAY_PIN, motor_on ? HIGH : LOW);
    digitalWrite(LED_ROJO_PIN, motor_on ? HIGH : LOW);
    digitalWrite(LED_VERDE_PIN, turn_led_on ? HIGH : LOW);
    if (box_full) {
      // backend says box full: ensure motor off
      digitalWrite(MOTOR1_RELAY_PIN, LOW);
      digitalWrite(MOTOR2_RELAY_PIN, LOW);
      digitalWrite(LED_ROJO_PIN, LOW);
    }
    Serial.printf("Polled device state - motor:%d turnLed:%d boxFull:%d\n", motor_on, turn_led_on, box_full);
  } else {
    Serial.printf("Error polling device state: %d\n", code);
  }
  http.end();
}

/////////////////
// MAIN LOOP
/////////////////
unsigned long lastLoop = 0;
void loop() {
  unsigned long now = millis();

  // Poll backend for commands
  if (now - lastDevicePoll >= DEVICE_POLL_INTERVAL) {
    lastDevicePoll = now;
    pollDeviceState();
  }

  // measure box level
  long boxDist = readUltrasonicCM(BOX_TRIG, BOX_ECHO);
  if (boxDist < BOX_FILL_THRESHOLD_CM) {
    Serial.println("Caja cerca de llenarse: " + String(boxDist) + "cm");
    // Sound buzzer and notify backend and stop motor
    buzz(200);
    setBackendBoxFull(true);
    // also, ensure motor is turned off locally
    digitalWrite(MOTOR1_RELAY_PIN, LOW);
    digitalWrite(MOTOR2_RELAY_PIN, LOW);
    digitalWrite(LED_ROJO_PIN, LOW);
  } else {
    // clear box_full in backend if previously set and now clear
    // (could poll backend to check, but we do simple set false when becomes clear)
    // optional: setBackendBoxFull(false);
  }

  // Top sensor detection: detect presence of object (distance below threshold)
  long topDist = readUltrasonicCM(TOP_TRIG, TOP_ECHO);
  // Serial.printf("topDist=%ld\n", topDist);
  if (waiting_for_object) {
    if (topDist <= TOP_DETECT_THRESHOLD_CM) {
      // object has entered
      waiting_for_object = false;
      object_detected_at = millis();
      object_min_distance = topDist;
      Serial.println("Objeto detectado - empezando monitoreo");
      delay(DEBOUNCE_MS); // small debounce
    }
  } else {
    // currently object present: track min distance while it's present
    if (topDist < object_min_distance) object_min_distance = topDist;
    if (topDist > TOP_DETECT_THRESHOLD_CM + 5) {
      // object has cleared sensor -> count and classify
      unsigned long duration_ms = millis() - object_detected_at;
      Serial.printf("Objeto pasado. MinDist=%d cm, dur=%lu ms\n", object_min_distance, duration_ms);
      // classify by min distance (SMALL/MEDIUM/LARGE). Ajustar thresholds por calibración:
      const int SMALL_THRESH = 6;  // cm <=6 => small
      const int MED_THRESH   = 10; // <=10 => medium
      String cat = "small";
      if (object_min_distance <= SMALL_THRESH) cat = "small";
      else if (object_min_distance <= MED_THRESH) cat = "medium";
      else cat = "large";
      // send event to backend
      postObjectEvent(cat.c_str(), object_min_distance);

      // reset state
      waiting_for_object = true;
      object_min_distance = 1000;
      delay(DEBOUNCE_MS);
    }
  }

  // short loop delay
  delay(50);
}
