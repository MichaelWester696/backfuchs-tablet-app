// Waagen-Knoten für die Verwiegung (Backfuchs).
//
// Waage (RS-232) -> MAX3232-Modul (3,3 V) -> UART1 des ESP32-S2 -> WLAN.
//
// Protokoll zum Tablet (WebSocket, Port 81, reiner Text):
//   "   0.065 kg    G"   eine Zeile der Waage, unverändert (nur druckbare Zeichen)
//   "#hb <Betriebs-s> <ms seit letzter Zeile> <verworfen>"   jede Sekunde
//
// Die Auswertung der Gewichtszeilen (Einheit, Stabilität, Plausibilität) macht
// die App; der Knoten verwirft nur Zeilen mit Störbytes oder zu langen Zeilen.
//
// Einrichtung: Beim ersten Start (oder ohne Verbindung) öffnet der Knoten das
// WLAN "Backfuchs-Waage-Setup". Dort unter http://192.168.4.1 das Firmen-WLAN
// eintragen. Zurücksetzen: BOOT-Taste beim Betrieb 5 Sekunden halten.

#include <Arduino.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WebServer.h>
#include <WebSocketsServer.h>
#include <WiFi.h>

#ifndef PIN_WAAGE_RX
#define PIN_WAAGE_RX 5
#endif
#ifndef PIN_WAAGE_TX
#define PIN_WAAGE_TX 4
#endif

static const uint32_t WAAGE_BAUD = 9600;  // 8N1, wie im Waagen-Menü (PRINT)
static const char* HOSTNAME = "waage";
static const char* SETUP_SSID = "Backfuchs-Waage-Setup";
static const char* SETUP_PASSWORT = "waage-setup";
static const int PIN_BOOT = 0;

static const char SEITE_STATUS[] PROGMEM = R"HTML(<!doctype html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Waagen-Knoten</title>
<style>
body{font-family:system-ui,sans-serif;margin:16px;max-width:560px}
#w{font-size:3rem;font-weight:700;font-variant-numeric:tabular-nums}
#z{font-family:monospace;white-space:pre;background:#eee;padding:6px;border-radius:6px}
.ok{color:#1a7f37}.fehler{color:#b3261e}
</style></head><body>
<h1>Waagen-Knoten</h1>
<div id="w">-</div>
<div id="s">Verbinde ...</div>
<p>Letzte Zeile:</p><div id="z"></div>
<p id="hb"></p>
<p><a href="/setup">WLAN ändern</a></p>
<script>
const w=document.getElementById('w'),s=document.getElementById('s'),z=document.getElementById('z'),hb=document.getElementById('hb');
function verbinden(){
  const ws=new WebSocket('ws://'+location.hostname+':81/');
  ws.onopen=()=>{s.textContent='Verbunden';s.className='ok'};
  ws.onclose=()=>{s.textContent='Getrennt';s.className='fehler';setTimeout(verbinden,1500)};
  ws.onmessage=e=>{
    const t=e.data;
    if(t.startsWith('#hb')){hb.textContent=t;return}
    if(t.startsWith('#'))return;
    z.textContent=JSON.stringify(t);
    const m=t.match(/(-?\d+(?:[.,]\d+)?)\s*(kg|g)/i);
    if(m){let g=parseFloat(m[1].replace(',','.'));if(m[2].toLowerCase()==='kg')g*=1000;
      w.textContent=g.toFixed(0)+' g'+(t.includes('?')?' (unruhig)':'')}
  };
}
verbinden();
</script></body></html>)HTML";

static HardwareSerial waageSerial(1);
static Preferences prefs;
static WebServer http(80);
static WebSocketsServer ws(81);

static String gespeicherteSsid;
static String gespeichertesPasswort;
static bool setupModus = false;

// Zeilenpuffer der Waage
static char zeile[48];
static size_t zeilenLaenge = 0;
static bool zeileGestoert = false;
static char letzteZeile[48] = "";
static uint32_t letzteZeileMs = 0;
static bool hatZeile = false;
static uint32_t verworfen = 0;
static uint32_t letzterHeartbeat = 0;
static uint32_t bootGedruecktSeit = 0;

static void zeileAbschliessen() {
  bool hatZiffer = false;
  for (size_t i = 0; i < zeilenLaenge; i++) {
    if (zeile[i] >= '0' && zeile[i] <= '9') {
      hatZiffer = true;
      break;
    }
  }
  if (zeilenLaenge > 0 && !zeileGestoert && hatZiffer) {
    zeile[zeilenLaenge] = '\0';
    strlcpy(letzteZeile, zeile, sizeof(letzteZeile));
    letzteZeileMs = millis();
    hatZeile = true;
    ws.broadcastTXT(zeile);
  } else if (zeilenLaenge > 0 || zeileGestoert) {
    verworfen++;
  }
  zeilenLaenge = 0;
  zeileGestoert = false;
}

static void leseWaage() {
  while (waageSerial.available() > 0) {
    int c = waageSerial.read();
    if (c == '\n') {
      zeileAbschliessen();
    } else if (c == '\r') {
      // Zeilenende wird über LF erkannt
    } else if (c >= 0x20 && c <= 0x7E) {
      if (zeilenLaenge < sizeof(zeile) - 1) {
        zeile[zeilenLaenge++] = (char)c;
      } else {
        zeileGestoert = true;  // zu lang: keine echte Gewichtszeile
      }
    } else {
      zeileGestoert = true;  // Störbyte
    }
  }
}

static void heartbeat() {
  uint32_t jetzt = millis();
  if (jetzt - letzterHeartbeat < 1000) return;
  letzterHeartbeat = jetzt;
  char text[64];
  long alter = hatZeile ? (long)(jetzt - letzteZeileMs) : -1;
  snprintf(text, sizeof(text), "#hb %lu %ld %lu", (unsigned long)(jetzt / 1000), alter, (unsigned long)verworfen);
  ws.broadcastTXT(text);
}

static void wsEreignis(uint8_t num, WStype_t typ, uint8_t*, size_t) {
  if (typ == WStype_CONNECTED) {
    ws.sendTXT(num, "#hello waagen-knoten");
    if (hatZeile) ws.sendTXT(num, letzteZeile);
  }
}

static String htmlEscape(const String& s) {
  String r;
  for (size_t i = 0; i < s.length(); i++) {
    char c = s[i];
    if (c == '&') r += "&amp;";
    else if (c == '<') r += "&lt;";
    else if (c == '>') r += "&gt;";
    else if (c == '"') r += "&quot;";
    else r += c;
  }
  return r;
}

static void seiteSetup() {
  String netze;
  int n = WiFi.scanNetworks();
  for (int i = 0; i < n && i < 20; i++) {
    netze += "<option value=\"" + htmlEscape(WiFi.SSID(i)) + "\">";
  }
  String s;
  s += F("<!doctype html><html lang=de><head><meta charset=utf-8>"
         "<meta name=viewport content='width=device-width,initial-scale=1'>"
         "<title>WLAN einrichten</title></head><body style='font-family:system-ui;margin:16px;max-width:480px'>"
         "<h1>WLAN einrichten</h1><form method=post action=/save>"
         "<p>WLAN-Name<br><input name=ssid list=netze style='width:100%;font-size:1.1rem' value=\"");
  s += htmlEscape(gespeicherteSsid);
  s += F("\"><datalist id=netze>");
  s += netze;
  s += F("</datalist></p><p>Passwort<br><input name=pw type=password style='width:100%;font-size:1.1rem'></p>"
         "<p><button style='font-size:1.2rem;padding:8px 16px'>Speichern und neu starten</button></p></form>"
         "</body></html>");
  http.send(200, "text/html; charset=utf-8", s);
}

static void seiteSpeichern() {
  String ssid = http.arg("ssid");
  String pw = http.arg("pw");
  if (ssid.length() == 0) {
    http.send(400, "text/plain; charset=utf-8", "WLAN-Name fehlt.");
    return;
  }
  prefs.putString("ssid", ssid);
  prefs.putString("pw", pw);
  http.send(200, "text/html; charset=utf-8",
            "<!doctype html><meta charset=utf-8><body style='font-family:system-ui;margin:16px'>"
            "<h1>Gespeichert</h1><p>Der Knoten startet neu und verbindet sich mit dem WLAN.</p>");
  delay(800);
  ESP.restart();
}

static void seiteStatusJson() {
  String s = "{\"wlan\":\"";
  s += htmlEscape(WiFi.SSID());
  s += "\",\"ip\":\"" + WiFi.localIP().toString() + "\",\"rssi\":" + String(WiFi.RSSI());
  s += ",\"letzteZeileMs\":" + String(hatZeile ? (long)(millis() - letzteZeileMs) : -1L);
  s += ",\"verworfen\":" + String((unsigned long)verworfen) + "}";
  http.send(200, "application/json", s);
}

static void starteHttp() {
  if (setupModus) {
    http.on("/", HTTP_GET, []() {
      http.sendHeader("Location", "/setup");
      http.send(302);
    });
  } else {
    http.on("/", HTTP_GET, []() { http.send_P(200, "text/html; charset=utf-8", SEITE_STATUS); });
    http.on("/status", HTTP_GET, seiteStatusJson);
  }
  http.on("/setup", HTTP_GET, seiteSetup);
  http.on("/save", HTTP_POST, seiteSpeichern);
  http.onNotFound([]() {
    if (setupModus) {
      http.sendHeader("Location", "/setup");
      http.send(302);
    } else {
      http.send(404, "text/plain", "nicht gefunden");
    }
  });
  http.begin();
}

static bool verbindeWlan() {
  if (gespeicherteSsid.length() == 0) return false;
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(HOSTNAME);
  WiFi.setAutoReconnect(true);
  WiFi.begin(gespeicherteSsid.c_str(), gespeichertesPasswort.c_str());
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(250);
  }
  return WiFi.status() == WL_CONNECTED;
}

static void pruefeBootTaste() {
  if (digitalRead(PIN_BOOT) == LOW) {
    if (bootGedruecktSeit == 0) bootGedruecktSeit = millis();
    if (millis() - bootGedruecktSeit > 5000) {
      prefs.remove("ssid");
      prefs.remove("pw");
      ESP.restart();
    }
  } else {
    bootGedruecktSeit = 0;
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOOT, INPUT_PULLUP);
  waageSerial.setRxBufferSize(1024);
  waageSerial.begin(WAAGE_BAUD, SERIAL_8N1, PIN_WAAGE_RX, PIN_WAAGE_TX);

  prefs.begin("waage", false);
  gespeicherteSsid = prefs.getString("ssid", "");
  gespeichertesPasswort = prefs.getString("pw", "");

  if (!verbindeWlan()) {
    setupModus = true;
    WiFi.mode(WIFI_AP_STA);
    WiFi.softAP(SETUP_SSID, SETUP_PASSWORT);
    Serial.printf("Setup-Modus: WLAN '%s', http://192.168.4.1\n", SETUP_SSID);
  } else {
    Serial.printf("WLAN verbunden, IP %s\n", WiFi.localIP().toString().c_str());
    MDNS.begin(HOSTNAME);
    MDNS.addService("http", "tcp", 80);
  }

  starteHttp();
  ws.begin();
  ws.onEvent(wsEreignis);
}

void loop() {
  leseWaage();
  ws.loop();
  http.handleClient();
  heartbeat();
  pruefeBootTaste();
}
