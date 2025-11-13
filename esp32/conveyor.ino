#include <WiFi.h>
#include <HTTPClient.h>

/////////////////////
// === PINOUT ===
/////////////////////
const int LED_VERDE_PIN = 25;
const int LED_ROJO_PIN = 26;
const int BUZZER_PIN = 27;
// Motor con L293D
const int ENA = 13; // PWM
const int IN1 = 14;
const int IN2 = 12;
// HC-SR04 top (conteo y tamaño)
const int TOP_TRIG = 32;
const int TOP_ECHO = 33;
// HC-SR04 box (almacén)
const int BOX_TRIG = 4;
const int BOX_ECHO = 2;

/////////////////////
// === SETTINGS ===
/////////////////////
const char* ssid = "VERONICA2"; // <-- CAMBIA
const char* password = "veronica2"; // <-- CAMBIA
const char* SERVER_BASE = "https://iot-automatizacion-g9.onrender.com"; // <-- CAMBIA si hace falta
const char* API_KEY = "patroclo"; // <-- CAMBIA

const int TOP_DETECT_THRESHOLD_CM = 15;
const int DEBOUNCE_MS = 200;
const int BOX_FILL_THRESHOLD_CM = 8;

unsigned long lastDevicePoll = 0;
const unsigned long DEVICE_POLL_INTERVAL = 1500;

bool waiting_for_object = true;
unsigned long object_detected_at = 0;
int object_min_distance = 1000;

/////////////////////
// MOTOR
/////////////////////
void motorEncender(int velocidad = 200) {
  digitalWrite(IN1, HIGH);
  digitalWrite(IN2, LOW);
  ledcWrite(0, velocidad); // usar PWM canal 0
}
void motorApagar() {
  digitalWrite(IN1, LOW);
  digitalWrite(IN2, LOW);
  ledcWrite(0, 0);
}

/////////////////////
// SETUP
/////////////////////
void setup() {
  Serial.begin(115200);

  pinMode(LED_VERDE_PIN, OUTPUT);
  pinMode(LED_ROJO_PIN, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);

  pinMode(ENA, OUTPUT);
  pinMode(IN1, OUTPUT);
  pinMode(IN2, OUTPUT);

  pinMode(TOP_TRIG, OUTPUT);
  pinMode(TOP_ECHO, INPUT);
  pinMode(BOX_TRIG, OUTPUT);
  pinMode(BOX_ECHO, INPUT);

  // configurar PWM para ENA (canal 0)
  ledcSetup(0, 5000, 8);
  ledcAttachPin(ENA, 0);

  motorApagar();

  WiFi.begin(ssid, password);
  Serial.print("Conectando a WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nWiFi conectado: " + WiFi.localIP().toString());
}

/////////////////////
// UTIL
/////////////////////
long readUltrasonicCM(int trigPin, int echoPin) {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);
  long duration = pulseIn(echoPin, HIGH, 30000);
  long cm = duration / 29 / 2;
  if (cm == 0) return 9999;
  return cm;
}
void buzz(int ms) {
  digitalWrite(BUZZER_PIN, HIGH);
  delay(ms);
  digitalWrite(BUZZER_PIN, LOW);
}

/////////////////////
// HTTP
/////////////////////
void postObjectEvent(const char* size_cat, float length_est) {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SERVER_BASE) + "/api/object_event";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-api-key", API_KEY);
  String payload = "{\"size_cat\":\"" + String(size_cat) + "\",\"length_est\":" + String(length_est, 2) + "}";
  int code = http.POST(payload);
  Serial.printf("POST object_event -> %d\n", code);
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

void postDeviceStatePatch(bool motor_on, bool turn_led_on, bool box_full) {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SERVER_BASE) + "/api/device_state";
  http.begin(url);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("x-api-key", API_KEY);
  String payload = "{\"motor_on\": " + String(motor_on ? "true":"false") + ",\"turn_led_on\": " + String(turn_led_on ? "true":"false") + ",\"box_full\": " + String(box_full ? "true":"false") + "}";
  int code = http.POST(payload);
  Serial.printf("POST device_state -> %d\n", code);
  http.end();
}

void pollDeviceState() {
  if (WiFi.status() != WL_CONNECTED) return;
  HTTPClient http;
  String url = String(SERVER_BASE) + "/api/device_state";
  http.begin(url);
  http.addHeader("x-api-key", API_KEY);
  int code = http.GET();
  if (code == 200) {
    String res = http.getString();
    bool motor_on = res.indexOf("\"motor_on\":true") >= 0;
    bool turn_led_on = res.indexOf("\"turn_led_on\":true") >= 0;
    bool box_full = res.indexOf("\"box_full\":true") >= 0;
    digitalWrite(LED_ROJO_PIN, motor_on ? HIGH : LOW);
    digitalWrite(LED_VERDE_PIN, turn_led_on ? HIGH : LOW);
    if (motor_on && !box_full) motorEncender(200);
    else motorApagar();
    if (box_full) {
      buzz(300);
      motorApagar();
    }
    Serial.printf("Estado -> motor:%d turno:%d boxFull:%d\n", motor_on, turn_led_on, box_full);
  }
  http.end();
}

/////////////////////
// LOOP
/////////////////////
void loop() {
  unsigned long now = millis();
  if (now - lastDevicePoll >= DEVICE_POLL_INTERVAL) {
    lastDevicePoll = now;
    pollDeviceState();
  }

  long boxDist = readUltrasonicCM(BOX_TRIG, BOX_ECHO);
  if (boxDist < BOX_FILL_THRESHOLD_CM) {
    Serial.println("⚠ Caja llena: " + String(boxDist) + "cm");
    buzz(300);
    setBackendBoxFull(true);
    motorApagar();
  }

  long topDist = readUltrasonicCM(TOP_TRIG, TOP_ECHO);
  if (waiting_for_object && topDist <= TOP_DETECT_THRESHOLD_CM) {
    waiting_for_object = false;
    object_detected_at = millis();
    object_min_distance = topDist;
  } else if (!waiting_for_object && topDist > TOP_DETECT_THRESHOLD_CM + 5) {
    const int SMALL_THRESH = 6;
    const int MED_THRESH = 10;
    String cat = (object_min_distance <= SMALL_THRESH) ? "small" : (object_min_distance <= MED_THRESH) ? "medium" : "large";
    postObjectEvent(cat.c_str(), object_min_distance);
    Serial.printf("Objeto clasificado: %s (%d cm)\n", cat.c_str(), object_min_distance);
    waiting_for_object = true;
    object_min_distance = 1000;
    delay(DEBOUNCE_MS);
  }

  delay(50);
}
