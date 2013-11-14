#include <SPI.h>
#include <Ethernet.h>

// Digital-Output Pins für Ventilauswahl 
// per Binär Wert (4 Pins = 0-15)
const byte numPins  =  4;

// Analog-Input Pin zum auslesen der Waage
#define weightPin          A0;

// Pin zum Pumpe schalten 
#define switchPinPressure   2;

// Pin zum Ventil schalten 
#define switchPinVentil     3;

// 4 Pins für Binärwert
#define switchPin1          4;
#define switchPin2          5;
#define switchPin4          6;
#define switchPin8          7;

// Variablen für Wiege-Funktion
float tara;
float faktor;
int masse = 0;
float Gewicht = 0;
float eichWert = 284.7;
float eichGewicht = 309;
int anzahlMittelung = 300; // um so höher um so präzieser (jedoch langsamer)

IPAddress pi_adress(192, 168, 1, 16);

char HttpFrame[256];           // General buffer for Http Params
EthernetServer HttpServer(80);   // HTTP is used to send IR commands
EthernetClient interfaceClient;


// ------------------ Reset stuff --------------------------
void(* resetFunc) (void) = 0;
unsigned long resetMillis;
boolean resetSytem = false;
// --------------- END - Reset stuff -----------------------

 
void setup() {
  unsigned char mac[]  = {0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED};
  unsigned char ip[]   = {192, 168, 1, 15};
  unsigned char dns[]  = {192, 168, 1, 1};
  unsigned char gate[] = {192, 168, 1, 1};
  unsigned char mask[] = {255, 255, 255, 0};

  Serial.begin(9600);
  while (!Serial) {
    ; // wait for serial port to connect. Needed for Leonardo only
  }

  Ethernet.begin(mac, ip, dns, gate, mask);
  HttpServer.begin();

  Serial.print( F("IP: ") );
  Serial.println(Ethernet.localIP());


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
}
 


void loop() {
   // Gewicht aktualisieren
  float sensorValue = refreshWeight();
  delay(200);

  EthernetClient client = HttpServer.available();
  if (client) {
     char *ptr=HttpFrame;
     int n=0;

     while (client.connected() && client.available()) {
       if (n++<sizeof(HttpFrame))
         *ptr++=client.read();
       else
         client.flush(); 
     }
     *ptr=0;
  
    if (n>0) {
      parseUrlParams();
    }
  }
}





// ---------------------------------------
//     Webserver/Seiten Hilfsmethoden
// ---------------------------------------
/**
 *  URL auswerten und entsprechende Seite aufrufen
 */
void parseUrlParams(){
  char *ptr = strstr(HttpFrame, "/index.html");
  if (ptr) {
     runIndexWebpage();
     return;
  } 

  ptr = strstr(HttpFrame, "/info.html");
  if(ptr){
    runInfoWebpage();
    return;
  } 

  // Wenn keine gültige Seite gefunden wurde,
  // Startseite aufrufen  
  runIndexWebpage();
}




/**
 * Webseite - Startseite anzeigen
 */
void  runIndexWebpage(){
  client.println(HtmlHeader);
  client.println(F("Index-Website"));
  client.stop();
}

/**
 * Webseite - Infoseite anzeigen
 */
void runInfoWebpage(){
  client.println(HtmlHeader);
  client.println(F("Info-Website"));
  client.stop();
}



/**
 * Webseite - Rezept zubereiten anzeigen
 */
void  runZubereitungWebpage(){
  client.println(HtmlHeader);
  client.println(F("Zubereitung-Website"));
  client.println();

  // URL-Parameter auswerten
  char* ptr=strstr(HttpFrame, "rezeptId=");
  if (ptr) {
    client.print(F("Rezept Nr: "));
    client.println(ptr);

    rezeptZubereiten(ptr);
  }

  client.stop();
}









/**
 *  Haupt-Methode für die Zubereitung  
 */
void rezeptZubereiten(char* rezept) {    
    URLPARAM_RESULT rc;

    // URL-Parameter parsen
    if (strlen(rezept)) {
      boolean paramError = false;

      if (interfaceClient.connect(pi_adress, 80)) {
        Serial.println("PI-Interface connected... ");

        interfaceClient.print("GET /interface.php?command=getRezeptById&rezeptId=");
        interfaceClient.print(rezept);
        interfaceClient.println(" HTTP/1.1");        
        interfaceClient.print(" Host: ");        
        interfaceClient.println(pi_adress);        
        interfaceClient.println("Connection: close");
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

        Serial.print("Id: ");
        Serial.println(interfaceId);

        Serial.print("Name: ");
        Serial.println(interfaceName);

        Serial.print("Zutaten: ");
        Serial.println(interfaceZutaten);

        Serial.print("Preis: ");
        Serial.println(interfacePreis);

      } else {
        Serial.println("connection failed");
      }    
  
      interfaceClient.stop();  
    } else {
      Serial.println("!!! Fehlende Parameter !!!");     
    } 
 
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
  byte pins[] = {switchPin1, switchPin2, switchPin4, switchPin8};

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
      
      Serial.print("Anschluss: ");
      Serial.print(atoi(anschluss));
      Serial.print(" fuer ");
      Serial.print(atoi(einheiten));
      Serial.println("ml geoeffnet");
     
      while ((tmpVal-tmpCurrentWeight) < atoi(einheiten)){
        tmpVal = refreshWeight();
      }
     
      Serial.print("Abschaltung bei Menge:");
      Serial.print(tmpVal);
      Serial.println("g");
      
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

      Serial.print("Reell abgefuellte Menge:");
      Serial.print(highestVal);
      Serial.println("g");
      

      // Ventil abschalten
      digitalWrite(switchPinVentil, LOW); 
      int offTime = millis();
      Serial.println("Dauer des Vorgangs: ");
      Serial.println(offTime - onTime);
      Serial.println("ms");
      
      setBinaryPins(0);

    } else {
      Serial.println("!!! Es wurden nicht alle Parameter zum Schalten angegeben !!!");
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
    tara = tara + analogRead(ANALOG_INPUT_PIN);
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
    sensorValue = sensorValue + analogRead(ANALOG_INPUT_PIN);
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
  boolean reading = false;
  char *p_ret = (char*)malloc(sizeof(char)*11);
  int i = 0;

  unsigned long startTime = millis();

  Serial.println(F("Waiting for Server"));
  while ((!interfaceClient.available()) && ((millis() - startTime ) < 3000)){ 
    // waiting for server   
  };
  Serial.println(F("Connected to PI-Interface"));

  while (interfaceClient.available()) {
    char c = interfaceClient.read(); 
    Serial.print(c);
    
    if (c == ']'){
      reading = false;
    }
    
    if(reading){
      *(p_ret+i) = c;
      i++;  
   }
    
    if (c == '['){
      reading = true;
    }    
    
  }

  *(p_ret+i)='\0';  

  Serial.println();
  Serial.print(F(">"));
  Serial.print(p_ret);
  Serial.println(F("<"));
  
  return p_ret;
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







// ---------------------------------------
//   Strings (im Flash-Speicher abgelegt)
// ---------------------------------------
const __FlashStringHelper *HtmlHeader=F("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n");

const __FlashStringHelper *HtmlHead1 =F("<html><head>"
                                        "<title>Barmonkey</title>"
                                        "<style type=\"text/css\">"
                                        "body{font-family:sans-serif}"
                                        "h1{font-size:25pt;}"
                                        "p{font-size:20pt;}"
                                        "*{font-size:pt}"
                                        "a{color:#abfb9c;}"
                                        "</style>"
                                        "</head><body text=\"white\" bgcolor=\"#494949\">");
                
const __FlashStringHelper *htmlHead2 = F("<center>"
                                         "<hr><h2>Barmonkey</h2><hr>"
                                         "<span style=\"position: absolute;right: 30px; bottom: 20px; \">Developed by Daniel Scheidler</span>");

const __FlashStringHelper *htmlBackTail = F("<br/><a  href=\"javascript:history.back()\">Zur&uumlck!</a><br/><br/>");

const __FlashStringHelper *htmlFooter1 = F("<br/><a  style=\"position: absolute;left: 30px; bottom: 20px; \"  href=\"/\">Zur&uuml;ck zum Hauptmen&uuml;</a><br/><br/>"
                                          "<div width=\"200\" height=\"18\"  style=\"position: absolute;left: 30px; bottom: 50px; \"> <b>Gewicht:</b>");
    
const __FlashStringHelper *htmlFooter2 =  F("g</div></center>");

const __FlashStringHelper *htmlTail =    F("</body></html>");
    
const __FlashStringHelper *htmlTail2 =     F("</center></body></html>");  

const __FlashStringHelper *htmlParamError = F("<br><font color=\"red\">Die gültigen Parameter lauten <b>schalte</b> und <b>menge</b></font><br>"
                                             "<br><br><b>Beispiel um den Anschluss 4 für eine Sekunde ein zu schalten:</b><br>"
                                             "<br><i>http://arduino_url/rawCmd?schalte=4&menge=10</i>");

const __FlashStringHelper *trtd180 = F("<tr><td width=\"400\" align=\"right\">");

const __FlashStringHelper *tdtd = F("</td><td><input maxlength=\"10\" type=\"password\" name=\"");

const __FlashStringHelper *tdtr = F("\"/></td></tr>");

const __FlashStringHelper *submit =  F("</tbody></table><br/>"
                                       "<input type='submit' value='Abschicken'/></form>");

const __FlashStringHelper *posttable = F("method='post'>"
                                       "<table cellpadding=\"2\" border=\"1\" rules=\"rows\" frame=\"box\" bordercolor=\"white\" width=\"500\">"
                                       "<thead><b>");


const __FlashStringHelper *htmlAnschlussCombo = F("<b>Anschluss: </b>"
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
                                                  "</select>");

const __FlashStringHelper *htmlMengeCombo = F("<b>Menge: </b>"
                                              "<select name=\"menge\" size=\"1\" > "
                                              "  <option value=\"5\">5 ml</option>"
                                              "  <option value=\"10\">10 ml</option>"
                                              "  <option value=\"15\">15 ml</option>"
                                              "  <option value=\"20\">20 ml</option>"
                                              "  <option value=\"25\">25 ml</option>"
                                              "  <option value=\"30\">30 ml</option>"
                                              "  <option value=\"35\">35 ml</option>"
                                              "  <option value=\"40\">40 ml</option>"
                                              "  <option value=\"45\">45 ml</option>"
                                              "  <option value=\"50\">50 ml</option>"
                                              "  <option value=\"60\">60 ml</option>"
                                              "  <option value=\"70\">70 ml</option>"
                                              "  <option value=\"80\">80 ml</option>"
                                              "  <option value=\"90\">90 ml</option>"
                                              "  <option value=\"100\">100 ml</option>"
                                              "</select>");

