barmonkey
===========

Barmonkey für Arduino 1.0.5 Software (incl TFT)

http://cyborgone.github.io/barmonkey/


Das Sketch für den Arduino funktioniert nur in Kombination mit einem erreichbaren Webserver der das barmonkey_ui Projekt hostet. 
Dieses beinhaltet eine Webseite incl. einer MySql-Datenbank über die die Benutzeroberfläche und die Rezeptdatenbank bereitgestellt werden.
Ebenfalls wird von dem UI-Projekt ein Interface mitgeliefert, mit dem der Arduino die Daten der MySQL-Datenbank abrufen kann. 

---------------------------------

Das Projekt ist in keiner Weise als fertiges Produkt anzusehen!
Es befindet sich in der Entwicklung und dient lediglich als Inspiration. 

Es gibt weder eine Garantie für Funktionalität, noch für Support, Updates oder sonstige Unterstützung.

Wer jedoch selber damit rum spielen möchte, darf das natürlich gerne tun.

----------------------------------


Pin-Belegung:
===========

2 - Pumpe

3 - Ventil auf/zu

4 - Binär-Switch 1

5 - Binär-Switch 2

6 - Binär-Switch 4

7 - Binär-Switch 8

A0 - Wage Signal



TFT-Pins:
===========

A1 - sclk

A2 - mosi

A3 - cs

A4 - dc

A5 - rst
