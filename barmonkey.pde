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

int lastMem = freeMemory();

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
const int switchBinaryPin1        =  4;
const int switchBinaryPin2        =  5;
const int switchBinaryPin4        =  6;
const int switchBinaryPin8        =  7;

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

char* rawCmdAnschluss = (char*)malloc(sizeof(char)*20);
char* rawCmdMenge = (char*)malloc(sizeof(char)*20);
char* zubereitungRezeptId  = (char*)malloc(sizeof(char)*20);
const int MAX_BUFFER_LEN = 80; // max characters in page name/parameter 
char buffer[MAX_BUFFER_LEN+1]; // additional character for terminating null


EthernetServer HttpServer(80); 
EthernetClient interfaceClient;


#if defined(__SAM3X8E__)
    #undef __FlashStringHelper::F(string_literal)
    #define F(string_literal) string_literal
#endif

// Option 1: use any pins but a little slower
Adafruit_ST7735 tft = Adafruit_ST7735(cs, dc, mosi, sclk, rst);

const __FlashStringHelper * htmlHeader;
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
  // Serial initialisieren
  Serial.begin(9600);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for Leonardo only
  }
  Serial.println(F("Barmonkey v1"));
  Serial.println();
  
  // TFT initialisieren
  tft.initR(INITR_BLACKTAB);   // initialize a ST7735S chip, black tab
  tft.fillScreen(ST7735_BLACK);
  
  tft.setTextSize(2);
  tftout("Barmonkey", ST7735_GREEN, 10, 5);
  tft.setTextSize(1);

  // Netzwerk initialisieren
  Ethernet.begin(mac, ip, dns, gate, mask);
  HttpServer.begin();

  Serial.print( F("IP: ") );
  Serial.println(Ethernet.localIP());
  tftout("IP: " , ST7735_YELLOW, 15, 45);
  tft.print(Ethernet.localIP());

  tft.fillRoundRect(10, 80, 110, 17, 3, ST7735_GREEN);
  tftout("Speicher: " , ST7735_RED, 15, 85);
  tft.fillRoundRect(10, 100, 110, 17, 3, ST7735_GREEN);
  tftout("Gewicht: ", ST7735_RED, 15, 105);

  // PINs einrichten
  pinMode(switchBinaryPin1,        OUTPUT);
  pinMode(switchBinaryPin2,        OUTPUT);
  pinMode(switchBinaryPin4,        OUTPUT);
  pinMode(switchBinaryPin8,        OUTPUT);

  pinMode(switchPinVentil,   OUTPUT);
  pinMode(switchPinPressure, OUTPUT);

  pinMode(weightPin,         INPUT);

  // Waage initialisieren
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
  tftOutFreeMem();


  EthernetClient client = HttpServer.available();
  if (client) {
    
    while (client.connected()) {
      if(client.available()){
        digitalWrite(3, HIGH);
        
        Serial.println(F("Website anzeigen"));
        showWebsite(client);
        
        tftOutFreeMem();
        Serial.println(freeMemory());
        delay(100);
        client.stop();
  
        digitalWrite(3, LOW);
      }
    }
  }
  delay(100);
  // Gecachte URL-Parameter leeren
  memset(rawCmdAnschluss,0, sizeof(rawCmdAnschluss));
  memset(rawCmdMenge,0, sizeof(rawCmdMenge));
  memset(zubereitungRezeptId,0, sizeof(zubereitungRezeptId));
  
}



// ---------------------------------------
//     Webserver Hilfsmethoden
// ---------------------------------------

/**
 *  URL auswerten und entsprechende Seite aufrufen
 */
void showWebsite(EthernetClient client){
  char * HttpFrame =  readFromClient(client);
  tftOutFreeMem();
  delay(200);
  boolean pageFound = false;
  
  char *ptr = strstr(HttpFrame, "favicon.ico");
  if(ptr){
    pageFound = true;
  }
  ptr = strstr(HttpFrame, "index.html");
  if (!pageFound && ptr) {
    runIndexWebpage(client);
    pageFound = true;
  } 
  ptr = strstr(HttpFrame, "rawCmd");
  if(!pageFound && ptr){
    runRawCmdWebpage(client, HttpFrame);
    pageFound = true;
  } 
  ptr = strstr(HttpFrame, "zubereiten");
  if(!pageFound && ptr){
    runZubereitungWebpage(client);
    pageFound = true;
  } 
  tftOutFreeMem();

  delay(300);
  //ptr = strstr(HttpFrame, "/&%/&%/");   // Sonst gibts ein Speicherproblem

//  free(ptr);
  ptr=NULL;
//  free(HttpFrame);
  HttpFrame=NULL;

 if(!pageFound){
    runIndexWebpage(client);
  }
  delay(20);
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
void  runRawCmdWebpage(EthernetClient client, char* HttpFrame){
  if (atoi(rawCmdAnschluss)!=0  && atoi(rawCmdMenge)!=0 ) {
    postRawCmd(client, rawCmdAnschluss, rawCmdMenge);
    return;
  }


  showHead(client);
  
  client.println(F(  "<h4>Manuelle Schaltung</h4><br/>"
                     "<form action='/rawCmd'>"));

  client.println(F( "<b>Anschluss: </b>"
                    "<select name=\"schalte\" size=\"1\" > "
                    "  <option value=\"1\">Anschluss 1</option>"
                    "  <option value=\"2\">Anschluss 2</option>"
                    "  <option value=\"3\">Anschluss 3</option>"
                    "  <option value=\"4\">Anschluss 4</option>"
                    "  <option value=\"5\">Anschluss 5</option>"
                    "  <option value=\"6\">Anschluss 6</option>"
                    "  <option value=\"7\">Anschluss 7</option>"
                    "  <option value=\"8\">Anschluss 8</option>"
                    "  <option value=\"9\">Anschluss 9</option>"
                    "  <option value=\"10\">Anschluss 10</option>"
                    "  <option value=\"11\">Anschluss 11</option>"
                    "  <option value=\"12\">Anschluss 12</option>"
                    "  <option value=\"13\">Anschluss 13</option>"
                    "  <option value=\"14\">Anschluss 14</option>"
                    "  <option value=\"15\">Anschluss 15</option>"
                    "  <option value=\"16\">Anschluss 16</option>"
                    "</select>" ));
      
      client.println(F( "<b>Schaltdauer: </b>"
                    "<select name=\"menge\" size=\"1\" > "
                    "  <option value=\"5\">5g</option>"
                    "  <option value=\"10\">10g</option>"
                    "  <option value=\"15\">15g</option>"
                    "  <option value=\"20\">20g</option>"
                    "  <option value=\"25\">25g</option>"
                    "  <option value=\"30\">30g</option>"
                    "  <option value=\"35\">35g</option>"
                    "  <option value=\"40\">40g</option>"
                    "  <option value=\"45\">45g</option>"
                    "  <option value=\"50\">50g</option>"
                    "  <option value=\"60\">60g</option>"
                    "  <option value=\"70\">70g</option>"
                    "  <option value=\"80\">80g</option>"
                    "  <option value=\"90\">90g</option>"
                    "  <option value=\"100\">100g</option>"
                    "  <option value=\"150\">150g</option>"
                    "  <option value=\"200\">200g</option>"
                    "</select>"));
     
      client.println(F("<input type='submit' value='Abschicken'/>"
                       "</form>"));

  showFooter(client);
}


void postRawCmd(EthernetClient client, char* anschluss, char* einheiten){

  showHead(client);
  
  client.print(F(  "<h4>Schaltvorgang</h4><br/>"
                     "Es werden "));
  client.print(rawCmdMenge);  
  client.print(F(  "ml aus Anschluss "));
  client.print(rawCmdAnschluss);
  client.println(F(  " ausgegeben.<br/>"));
  zutatAbfuellen(anschluss, einheiten);

  showFooter(client);
}



/**
 * Rezept zubereiten anzeigen/durchführen
 */
void  runZubereitungWebpage(EthernetClient client){
  showHead(client);

  client.print(F("<h4>Zubereitung</h4><br/>"));

  if (atoi(zubereitungRezeptId)!=0 ) {
    Serial.print(F("REZEPT "));
    Serial.print(zubereitungRezeptId);
    Serial.println(F(" zubereiten"));
    
    rezeptZubereiten(zubereitungRezeptId);
  }

  showFooter(client);
}






// ---------------------------------------
//     Ausgabe-Hilfsmethoden
// ---------------------------------------

void showHead(EthernetClient client){
  client.println(htmlHeader);

  client.println(htmlHead);
}


void showFooter(EthernetClient client){
  client.print(F("<div  style=\"position: absolute;left: 30px; bottom: 40px; text-align:left;horizontal-align:left;\" width=200><b>Gewicht:</b> "));
  client.print(masse);
  client.println(F("g<br/>"));
  client.println(F("<b>Freier Speicher:</b> "));                              
  client.println(freeMemory()); 
  client.print(F("</div>"));
  client.print(htmlFooter);
}



void tftOutFreeMem(){
   if(lastMem != freeMemory() ){
    lastMem = freeMemory();

    tft.fillRoundRect(65, 80, 45, 17, 3, ST7735_GREEN);

    tft.setCursor(70, 85);
    tft.setTextColor(ST7735_MAGENTA);
    tft.print(freeMemory());
  }
}

void tftOutGewicht(){
  tft.fillRoundRect(65, 100, 45, 17, 3, ST7735_GREEN);

  tft.setCursor(70, 105);
  tft.setTextColor(ST7735_MAGENTA);
  tft.print(masse);
}



void tftout(char *text, uint16_t color, uint16_t x, uint16_t y) {
  tft.setCursor(x, y);
  tft.setTextColor(color);
  tft.setTextWrap(true);
  tft.print(text);
}

void tftZubereitungsOutput(char* interfaceName){
  tft.fillRoundRect(10, 120, 110, 40, 3, ST7735_GREEN);
  tftout(interfaceName, ST7735_MAGENTA, 20, 125);   
}

void tftClearZubereitungsOutput(){
  tft.fillRoundRect(0, 120, 130, 60, 3, ST7735_BLACK);
}

void tftAnschlussOutput(char* anschluss, char* menge){
  tft.fillRoundRect(10, 135, 110, 30, 3, ST7735_GREEN);
  tftout("Anschluss ", ST7735_BLUE, 15, 140);   
  tft.print(anschluss);
  tftout(menge, ST7735_BLUE, 15, 150);   
  tft.print(F("g ausgeben"));
}

void tftClearAnschlussOutput(){
  tft.fillRoundRect(10, 135, 110, 30, 3, ST7735_GREEN);
}


void initStrings(){
  htmlHeader = F("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n");
  
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
    
    htmlFooter = F( "</center>"
    "<a  style=\"position: absolute;left: 30px; bottom: 20px; \"  href=\"/\">Zur&uuml;ck zum Hauptmen&uuml;</a>"
    "<span style=\"position: absolute;right: 30px; bottom: 20px; \">Entwickelt von Daniel Scheidler und Julian Theis</span>"
    "</body></html>");
    
}



// ---------------------------------------
//     Ventilsteuerung - Hilfsmethoden
// ---------------------------------------
/**
 * 4 Pins  (switchBinaryPin1-switchBinaryPin4)
 * Somit sind Zahlen zwischen 0 und 15 gueltig.
 */
void setBinaryPins(byte value){
  String myStr;
  byte pins[] = {
    switchBinaryPin1, switchBinaryPin2, switchBinaryPin4, switchBinaryPin8  };

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
  if (atoi(anschluss)!=0  && atoi(einheiten)!=0 ) {
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

    Serial.print(F("Anschluss: "));
    Serial.print(atoi(anschluss));
    Serial.print(F(" fuer "));
    Serial.print(atoi(einheiten));
    Serial.println(F("ml geoeffnet"));

    delay(30);

    tftAnschlussOutput(anschluss, einheiten);

    // Pumpe einschalten
    digitalWrite(switchPinPressure, HIGH);
    
    while ((tmpVal-tmpCurrentWeight) < atoi(einheiten)){
      tmpVal = refreshWeight();
      delay(20);
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
    Serial.print(F("Dauer des Vorgangs: "));
    Serial.print(offTime - onTime);
    Serial.println(F("ms"));

    setBinaryPins(0);

    tftClearAnschlussOutput();

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
      Serial.print(F("GET /interface.php?command=getRezeptById&rezeptId="));
      interfaceClient.print(rezept);
      Serial.print(rezept);
      interfaceClient.println(F(" HTTP/1.1"));
      Serial.println(F(" HTTP/1.1"));
      interfaceClient.print(F("Host: "));
      Serial.print(F("Host: "));
      interfaceClient.println(pi_adress);
      Serial.println(pi_adress);
      interfaceClient.println(F("Connection: close"));
      Serial.println(F("Connection: close"));
      interfaceClient.println();
      Serial.println();

      char interfaceString[100];
      char interfaceId[11];
      char interfaceName[24];
      char interfaceZutaten[50];
      char interfacePreis[15];
      char* p_ret = readResponse();
      strcpy(interfaceString, p_ret);
      strcpy(interfaceId, strtok (interfaceString, ";"));
      strcpy(interfaceName,strtok(NULL, ";"));
      strcpy(interfaceZutaten, strtok(NULL, ";"));
      strcpy(interfacePreis, strtok(NULL, ";"));

      Serial.println(F("Zubereitung:"));

      Serial.print(F("Id: "));
      Serial.println(interfaceId);

      Serial.print(F("Name: "));
      Serial.println(interfaceName);

      Serial.print(F("Zutaten: "));
      Serial.println(interfaceZutaten);

      Serial.print(F("Preis: "));
      Serial.println(interfacePreis);
      Serial.println();
     
      char* abfuellTmp = strtok(interfaceZutaten, ",:");
      int cnt = 0;
      
      tftZubereitungsOutput(interfaceName);
      tftOutFreeMem();
      
      char anschluss[3]="0";      
      char menge[5]="0";
  
      while (abfuellTmp) {
          
          switch (cnt) {
            case 0:
              strcpy(anschluss, abfuellTmp);
              break;
            case 1:
              strcpy(menge, abfuellTmp);

              if(atoi(anschluss)>0 && atoi(menge)>0){
                 zutatAbfuellen(anschluss, menge);
              }
              
              delay(500);
              memset(anschluss,0, sizeof(anschluss));
              memset(menge,0, sizeof(menge));
              break;
          }
          abfuellTmp = strtok(NULL, ",:");
          cnt=cnt==0?1:0;

      }
      
      tftClearZubereitungsOutput();
      p_ret==NULL;
    } else {
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

  tftOutGewicht();
  
  return masse;
}





// ---------------------------------------
//     Ethernet - Hilfsmethoden
// ---------------------------------------
/**
 * Liefert die Rückgabe des Webinterfaces (PI) zurück 
 * und gibt die entsprechende Zeile auf dem Serial-Monitor aus
 */
char * readResponse(){
  unsigned long startTime = millis();

  Serial.println(F("Waiting for Server"));
  while ((!interfaceClient.available()) && ((millis() - startTime ) < 3000)){ 
    // waiting for server   
  };
  Serial.println(F("Connected to PI-Interface"));

  char* p_ret = readFromClientInterface(interfaceClient);

  Serial.println();
  Serial.println(p_ret);

  return p_ret;
}



char* readFromClientInterface(EthernetClient client){
  memset(buffer,0, sizeof(buffer)); // clear the buffer
  boolean reading = false;

  int i = 0;

  while (client.available()) {
    char c = client.read();     

    if (c == ']'){
      reading = false;
    }

    if(reading){
      *(buffer+i) = c;
      i++;  
    }

    if (c == '['){
      reading = true;
    }    
  }
  *(buffer+i)='\0';  

  return buffer;
}


char* readFromClient(EthernetClient client){
  char paramName[20];
  char paramValue[20];
  char pageName[20];
  if (client) {
    while (client.connected()) {
      if (client.available()) {
        memset(buffer,0, sizeof(buffer)); // clear the buffer

        client.find("/");
        if(byte bytesReceived = client.readBytesUntil(' ', buffer, sizeof(buffer))){ 
          buffer[bytesReceived] = '\0';

          Serial.print(F("URL: "));
          Serial.println(buffer);
          
          if(strcmp(buffer, "favicon.ico\0")){
            char* paramsTmp = strtok(buffer, " ?=&/\r\n");
            int cnt = 0;
            while (paramsTmp) {
              //Serial.print(F("Read: "));
              //Serial.println(paramsTmp);
              
              switch (cnt) {
                case 0:
                  strcpy(pageName, paramsTmp);
                  Serial.print(F("Domain: "));
                  Serial.println(buffer);
                  break;
                case 1:
                  strcpy(paramName, paramsTmp);
                  Serial.print(F("Parameter: "));
                  Serial.print(paramName);
                  break;
                case 2:
                  strcpy(paramValue, paramsTmp);
                  Serial.print(F(" = "));
                  Serial.println(paramValue);
                  pruefeURLParameter(paramName, paramValue);
                  break;
              }
              
              paramsTmp = strtok(NULL, " ?=&/\r\n");
              cnt=cnt==0?1:cnt==1?2:1;
            }
          }
    
        }
      }// end if Client available
      break;
    }// end while Client connected
  } 

  return buffer;
}


void pruefeURLParameter(char* tmpName, char* value){
  if(strcmp(tmpName, "schalte")==0 && strcmp(value, "")!=0){
    strcpy(rawCmdAnschluss, value);
    
    Serial.print(F("OK Anschluss: "));
    Serial.println(rawCmdAnschluss);    
  }
  
  if(strcmp(tmpName, "menge")==0 && strcmp(value, "")!=0){
    strcpy(rawCmdMenge, value);

    Serial.print(F("OK Menge: "));
    Serial.println(rawCmdMenge);    
  } 
    
  if(strcmp(tmpName, "RezeptId")==0 && strcmp(value, "")!=0){
    strcpy(zubereitungRezeptId, value);

    Serial.print(F("OK Rezept: "));
    Serial.println(zubereitungRezeptId);    
  } 
  
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



