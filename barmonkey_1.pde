/* 
 barmonkey - v1.0
 
 Arduino Sketch für barmonkey 
 Copyright (c) 2013 Daniel Scheidler All right reserved.
 
 barmonkey ist Freie Software: Sie können es unter den Bedingungen
 der GNU General Public License, wie von der Free Software Foundation,
 Version 3 der Lizenz oder (nach Ihrer Option) jeder späteren
 veröffentlichten Version, weiterverbreiten und/oder modifizieren.
 
 barmonkey wird in der Hoffnung, dass es nützlich sein wird, aber
 OHNE JEDE GEWÄHRLEISTUNG, bereitgestellt; sogar ohne die implizite
 Gewährleistung der MARKTFÄHIGKEIT oder EIGNUNG FÜR EINEN BESTIMMTEN ZWECK.
 Siehe die GNU General Public License für weitere Details.
 
 Sie sollten eine Kopie der GNU General Public License zusammen mit diesem
 Programm erhalten haben. Wenn nicht, siehe <http://www.gnu.org/licenses/>.
 */

#include <SPI.h>
#include <Ethernet.h>
#include <MemoryFree.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>

// Digital-Output Pins für Ventilauswahl 
// per Binär Wert (4 Pins = 0-15)
const byte numPins  =  4;

// Analog-Input Pin zum auslesen der Waage
const int weightPin         = A0;

#define sclk A1
#define mosi A2
#define cs   A3
#define dc   A4
#define rst  A5

// Pin zum Pumpe schalten 
const int switchPinPressure =  2;

// Pin zum Ventil schalten 
const int switchPinVentil   =  3;

// 4 Pins für Binärwert
const int switchPin1        =  4;
const int switchPin2        =  5;
const int switchPin4        =  6;
const int switchPin8        =  7;

// Variablen für Wiege-Funktion
float tara;
float faktor;
int masse = 0;
float Gewicht = 0;
float eichWert = 284.7;
float eichGewicht = 309;
int anzahlMittelung = 300; 


// Variablen für Netzwerkdienste
IPAddress pi_adress(192, 168, 1, 16);

EthernetServer HttpServer(80); 
EthernetClient interfaceClient;


#if defined(__SAM3X8E__)
    #undef __FlashStringHelper::F(string_literal)
    #define F(string_literal) string_literal
#endif

// Option 1: use any pins but a little slower
Adafruit_ST7735 tft = Adafruit_ST7735(cs, dc, mosi, sclk, rst);


const __FlashStringHelper * htmlHead;
const __FlashStringHelper * htmlFooter;

// ------------------ Reset stuff --------------------------
void(* resetFunc) (void) = 0;
unsigned long resetMillis;
boolean resetSytem = false;
// --------------- END - Reset stuff -----------------------



/**
 * SETUP
 *
 * Grundeinrichtung des Barmonkeys
 * - Serielle Ausgabe aktivieren
 * - TFT initialisieren
 * - Netzwerk initialisieren
 * - Webserver starten
 * - IN-/OUT- Pins definieren
 * - Waage initialisieren (Tara)
 */
void setup() {
  unsigned char mac[]  = {
    0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED  };
  unsigned char ip[]   = {
    192, 168, 1, 15  };
  unsigned char dns[]  = {
    192, 168, 1, 1  };
  unsigned char gate[] = {
    192, 168, 1, 1  };
  unsigned char mask[] = {
    255, 255, 255, 0  };
    
  tft.initR(INITR_BLACKTAB);   // initialize a ST7735S chip, black tab
  tft.fillScreen(ST7735_BLACK);
  
  tft.setTextSize(2);
  tftout("Barmonkey", ST7735_GREEN, 10, 5);
  tft.setTextSize(1);

  Serial.begin(9600);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for Leonardo only
  }
  Serial.println(F("Barmonkey v1"));
  Serial.println();
  Ethernet.begin(mac, ip, dns, gate, mask);
  HttpServer.begin();

  Serial.print( F("IP: ") );
  Serial.println(Ethernet.localIP());
  tftout("IP: " , ST7735_YELLOW, 15, 45);
  tft.print(Ethernet.localIP());

  tft.fillRoundRect(10, 80, 110, 17, 3, ST7735_GREEN);
  tftout("Speicher: " , ST7735_RED, 15, 85);

  // Binär-Ausgabe Pins festlegen   
  pinMode(switchPin1,        OUTPUT);
  pinMode(switchPin2,        OUTPUT);
  pinMode(switchPin4,        OUTPUT);
  pinMode(switchPin8,        OUTPUT);

  pinMode(switchPinVentil,   OUTPUT);
  pinMode(switchPinPressure, OUTPUT);

  pinMode(weightPin,         INPUT);

  doTara();
  faktor = (eichWert - tara) /  eichGewicht;  


  initStrings();
}

/**
 * LOOP
 * 
 * Standard-Loop-Methode des Arduino Sketch
 * Diese Methode wird nach dem Setup endlos wiederholt.
 *
 * - Gewicht aktualisieren
 * - Webserver: 
 *    * auf Client warten
 *      * Falls Client verbunden ist entsprechende Webseite ausgeben
 *        und Verbindung beenden.
 */
void loop() {
  float sensorValue = refreshWeight();
  Serial.print(F("Freier Speicher: "));
  Serial.println(freeMemory());     

  EthernetClient client = HttpServer.available();
  delay(300);

  if (client) {
    digitalWrite(3, HIGH);
    
    int n=0;
    while (client.connected()) {
      if(client.available()){
        Serial.println(F("Website anzeigen"));
        showWebsite(client);
        delay(200);
        client.stop();

        digitalWrite(3, LOW);
      }
    }
  }
  delay(500);

  Serial.println(freeMemory());     

  tft.fillRoundRect(65, 80, 45, 17, 3, ST7735_GREEN);

  tft.setCursor(70, 85);
  tft.setTextColor(ST7735_MAGENTA);
  tft.print(freeMemory());
}





// ---------------------------------------
//     Webserver Hilfsmethoden
// ---------------------------------------

/**
 *  URL auswerten und entsprechende Seite aufrufen
 */
void showWebsite(EthernetClient client){
  char * HttpFrame = readFromClient(client);
  boolean pageFound = false;
  Serial.println(HttpFrame);
  

  char *ptr = strstr(HttpFrame, "/favicon.ico");
  if(ptr){
    pageFound = true;
  }
  ptr = strstr(HttpFrame, "/index.html");
  if (!pageFound && ptr) {
    runIndexWebpage(client);
    pageFound = true;
  } 
  ptr = strstr(HttpFrame, "/rawCmd");
  if(!pageFound && ptr){
    runRawCmdWebpage(client);
    pageFound = true;
  } 
  ptr = strstr(HttpFrame, "/zubereiten");
  if(!pageFound && ptr){
    runZubereitungWebpage(client);
    pageFound = true;
  } 
  delay(200);

  ptr = strstr(HttpFrame, "/&%/&%/");   // Sonst gibts ein Speicherproblem

  free(ptr);
  ptr=NULL;
  free(HttpFrame);
  HttpFrame=NULL;


 if(!pageFound){
    runIndexWebpage(client);
  }
}




// ---------------------------------------
//     Webseiten
// ---------------------------------------

/**
 * Startseite anzeigen
 */
void  runIndexWebpage(EthernetClient client){
  showHead(client);

  client.print(F("<h4>Navigation</h4><br/>"
    "<a href='/rawCmd'>Manuelle Schaltung</a><br>"));

  showFooter(client);
}


/**
 * rawCmd anzeigen
 */
void  runRawCmdWebpage(EthernetClient client){
  showHead(client);

  client.print(F("<h4>Manuelle Schaltung</h4><br/>"
    "<a href='/rawCmd'>Manuelle Schaltung</a><br>"));

  showFooter(client);
}


/**
 * Rezept zubereiten anzeigen/durchführen
 */
void  runZubereitungWebpage(EthernetClient client){
  showHead(client);

  client.print(F("<h4>Zubereitung</h4><br/>"));

  showFooter(client);
}






// ---------------------------------------
//     HTML-Hilfsmethoden
// ---------------------------------------

void showHead(EthernetClient client){
  client.println(F("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"));

  client.println(htmlHead);
}


void showFooter(EthernetClient client){
  client.print(F("<div width=\"200\" height=\"18\"  style=\"position: absolute;left: 30px; bottom: 50px; \"> <b>Gewicht:</b>"));
  client.print(masse);
  client.println(F("g<br/><br/>"));
  client.println(F("Freier Speicher: "));                              
  client.println(freeMemory()); 

  client.print(htmlFooter);
}



void tftout(char *text, uint16_t color, uint16_t x, uint16_t y) {
  tft.setCursor(x, y);
  tft.setTextColor(color);
  tft.setTextWrap(true);
  tft.print(text);
}

void initStrings(){
  htmlHead = F("<html><head>"
    "<title>Barmonkey</title>"
    "<style type=\"text/css\">"
    "body{font-family:sans-serif}"
    "*{font-size:14pt}"
    "a{color:#abfb9c;}"
    "</style>"
    "</head><body text=\"white\" bgcolor=\"#494949\">"
    "<center>"
    "<hr><h2>Barmonkey</h2><hr>") ;
    
    htmlFooter = F( "</div></center>"
    "<a  style=\"position: absolute;left: 30px; bottom: 20px; \"  href=\"/\">Zur&uuml;ck zum Hauptmen&uuml;</a>"
    "<span style=\"position: absolute;right: 30px; bottom: 20px; \">Entwickelt von Daniel Scheidler und Julian Theis</span>"
    "</body></html>");
}




// ---------------------------------------
//     Ventilsteuerung - Hilfsmethoden
// ---------------------------------------
/**
 * 4 Pins  (switchPin1-switchPin4)
 * Somit sind Zahlen zwischen 0 und 15 gueltig.
 */
void setBinaryPins(byte value){
  String myStr;
  byte pins[] = {
    switchPin1, switchPin2, switchPin4, switchPin8  };

  for (byte i=0; i<numPins; i++) {
    byte state = bitRead(value, i);
    digitalWrite(pins[i], state);
  }
}



/**
 * Methode zum abfuellen einer bestimmten Menge 
 * vom uebergebenen Anschluss.
 *
 * Ablauf:
 * - waehlen des Ventils ueber die 4 Binaer-Ausgaenge
 * - Ventil oeffnen
 * - Pumpe einschalten
 * - Wenn Menge erreicht ist: Pumpe abschalten
 * - Wenn Gewicht nicht mehr ansteigt: Ventil schliessen (Nachlauf)
 */
void zutatAbfuellen(char anschluss[20], char einheiten[20]){
  // SCHALTVORGANG
  if (strlen(anschluss) && strlen(einheiten) ) {
    int onTime = millis();
    // Selektion des Ventils
    setBinaryPins(atoi(anschluss)-1);

    // Ventil oeffnen 
    digitalWrite(switchPinVentil, HIGH);      

    // Wartezeit 
    delay(10);

    // aktuelles Gewicht merken (spaeter hier auf richtiges Glas pruefen?)
    int tmpCurrentWeight = masse;

    int tmpVal = refreshWeight();
    delay(30);

    // Pumpe einschalten
    digitalWrite(switchPinPressure, HIGH);

    Serial.print(F("Anschluss: "));
    Serial.print(atoi(anschluss));
    Serial.print(F(" fuer "));
    Serial.print(atoi(einheiten));
    Serial.println(F("ml geoeffnet"));

    while ((tmpVal-tmpCurrentWeight) < atoi(einheiten)){
      tmpVal = refreshWeight();
    }

    Serial.print(F("Abschaltung bei Menge:"));
    Serial.print(tmpVal);
    Serial.println(F("g"));

    // Pumpe abschalten
    digitalWrite(switchPinPressure, LOW);   

    tmpVal = refreshWeight();
    int startmillis = millis();
    int highestVal = tmpVal;
    int stablileMessDauer = 0;

    // Warten bis nichts mehr nachlaeuft
    delay(10);
    while (stablileMessDauer < 1000){
      tmpVal = refreshWeight();

      if(highestVal < tmpVal){
        highestVal = tmpVal;
        startmillis = millis();
      }

      stablileMessDauer = millis()-startmillis;
    }

    Serial.print(F("Reell abgefuellte Menge:"));
    Serial.print(highestVal);
    Serial.println(F("g"));

    // Ventil abschalten
    digitalWrite(switchPinVentil, LOW); 
    int offTime = millis();
    Serial.println(F("Dauer des Vorgangs: "));
    Serial.println(offTime - onTime);
    Serial.println(F("ms"));

    setBinaryPins(0);

  } 
  else {
    Serial.println(F("!!! Es wurden nicht alle Parameter zum Schalten angegeben !!!"));
  }
}


/**
 *  Haupt-Methode für die Zubereitung  
 */
void rezeptZubereiten(char* rezept) {    
  // URL-Parameter parsen
  if (strlen(rezept)) {
    boolean paramError = false;

    if (interfaceClient.connect(pi_adress, 80)) {
      delay(100);
      interfaceClient.print(F("GET /interface.php?command=getRezeptById&rezeptId="));
      for (char *p = rezept; *p; p++){
        interfaceClient.print( *p ) ;
      }
//      interfaceClient.print(rezept);
      interfaceClient.println(F(" HTTP/1.1"));
      interfaceClient.print(F(" Host: "));
      interfaceClient.println(pi_adress);
      interfaceClient.println(F("Connection: close"));
      interfaceClient.println();

      char * interfaceString   = readResponse();
      char * interfaceValues   = strtok (interfaceString, ";");

      char * interfaceId       = interfaceValues;
      interfaceValues          = strtok(NULL, ";");

      char * interfaceName     = interfaceValues;
      interfaceValues          = strtok(NULL, ";");

      char * interfaceZutaten  = interfaceValues;
      interfaceValues          = strtok(NULL, ";");

      char * interfacePreis    = interfaceValues;
      interfaceValues          = strtok(NULL, ";");

      output(F("Zubereitung:"));

      outputNoNewLine(F("Id: "));
      output(interfaceId);

      outputNoNewLine(F("Name: "));
      output(interfaceName);

      outputNoNewLine(F("Zutaten: "));
      output(interfaceZutaten);

      outputNoNewLine(F("Preis: "));
      outputNoNewLine(interfacePreis);
    } 
    else {
      Serial.println(F("Verbindungsfehler bei dem Versuch das Rezept abzurufen."));
    }    

    interfaceClient.stop();  
  } 
  else {
    Serial.println(F("!!! Fehlende Parameter !!!"));     
  } 

}




// ---------------------------------------
//     Waage - Hilfsmethoden
// ---------------------------------------
/**
 * Bei der Wage den aktuellen Belastungspunkt als 0 setzen
 */
void doTara(){

  // Wage Initialisieren

  for (int i = 0; i < anzahlMittelung; i++) {  //Mittelung von tara
    tara = tara + analogRead(weightPin);
  }

  tara = tara/anzahlMittelung;
  Serial.print(F("Tara: "));
  Serial.println(tara);
}



/**
 * Ermitteln des aktuellen Gewichts
 *
 * Neben dem Rueckgabewert des aktuellen Gewichts 
 * werden die globalen Variablen "masse" und "Gewicht" aktualisiert.
 */
float refreshWeight(){
  float sensorValue = 0;
  //Mittelung des Messwertes
  for (int i = 0; i < anzahlMittelung; i++) {   
    sensorValue = sensorValue + analogRead(weightPin);
  }
  sensorValue = sensorValue/anzahlMittelung;

  Gewicht = ((sensorValue-tara)/faktor);  //Gleichung, die vorher berechnet werden muss
  masse = Gewicht; 

  return masse;
}





// ---------------------------------------
//     Ethernet - Hilfsmethoden
// ---------------------------------------
/**
 * Liest die Rückgabe des Webinterfaces aus 
 * und gibt die entsprechende Zeile auf dem Serial-Monitor aus
 */
char * readResponse(){
  unsigned long startTime = millis();

  Serial.println(F("Waiting for Server"));
  while ((!interfaceClient.available()) && ((millis() - startTime ) < 3000)){ 
    // waiting for server   
  };
  Serial.println(F("Connected to PI-Interface"));

  char *p_ret = readFromClientInterface(interfaceClient);

  Serial.println();
  Serial.println(p_ret);


  return p_ret;
}



char* readFromClientInterface(EthernetClient client){
  char *ret = (char*)malloc(sizeof(char)*11);
  boolean reading = false;
  int i = 0;

  while (client.available()) {
    char c = client.read();     

    if (c == ']'){
      reading = false;
    }

    if(reading){
      *(ret+i) = c;
      i++;  
    }

    if (c == '['){
      reading = true;
    }    
  }
  *(ret+i)='\0';  

  return ret;
}


char* readFromClient(EthernetClient client){
  char *ret = (char*)malloc(sizeof(char)*11);
  int i = 0;

  while (client.available()) {
    char c = client.read(); 
    if( c=='\n' ){
      break;
    }

    *(ret+i) = c;
    i++;  
  }

  *(ret+i)='\0';  


  return ret;
}




// ---------------------------------------
//     Allgemeine Hilfsmethoden
// ---------------------------------------
char* int2bin(unsigned int x)
{
  static char buffer[6];
  for (int i=0; i<5; i++) buffer[4-i] = '0' + ((x & (1 << i)) > 0);
  buffer[68] ='\0';
  return buffer;
}



void outputNoNewLine(const __FlashStringHelper *text){
  Serial.print(text);
  tft.print(text);
}

void output(const __FlashStringHelper *text){
  Serial.println(text);
  tft.println(text);
}

void outputNoNewLine(char *text){
  Serial.print(text);
  tft.print(text);
}

void output(char *text){
  Serial.println(text);
  tft.println(text);
}



