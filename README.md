# Forever Frame Builder

Drag-&-Drop-Editor für Ingame-Frames, ähnlich einem Website-Builder. Öffnen mit `/ffb`
(oder `/framebuilder`, oder über das Addon-Kompartiment an der Minimap). `/ffb reset` setzt die Fensterposition zurück.

## Aufbau des Fensters

| Bereich | Funktion |
|---|---|
| Toolbar | Projekte, Rückgängig/Wiederholen, Raster/Einrasten, Zoom, Export, Vorschau |
| Elemente | Palette: klicken fügt zum ausgewählten Frame hinzu, ziehen legt es an die Cursorposition |
| Ebenen | Baum aller Elemente; Reihenfolge = Zeichenreihenfolge (unten = vorne) |
| Arbeitsfläche | Entspricht `UIParent` (der blaue Rahmen ist dein Bildschirm) |
| Eigenschaften | Name, Eltern-Element, Anker, Größe, Aussehen und Skripte des ausgewählten Elements |

## Bedienung

- **Verschieben:** ziehen. Shift+Ziehen bewegt die aktuelle Auswahl, auch wenn sie verdeckt ist.
- **Verschachteln:** beim Loslassen Strg halten, dann landet das Element im Frame unter dem Cursor (grün markiert).
  Alternativ im Rechtsklickmenü unter „Verschieben in“ oder in den Eigenschaften unter „Eltern-Element“.
- **Größe ändern:** an den blauen Griffen ziehen. Die gegenüberliegende Kante bleibt stehen, egal welcher Anker gesetzt ist.
- **Anker ändern:** Das Element bleibt dabei an seiner Stelle, die Offsets werden umgerechnet.
- **Ansicht:** mittlere Maustaste oder Alt+Ziehen verschiebt, das Mausrad zoomt zum Cursor.
- **Tasten:** Pfeile (Shift: ein Rasterschritt), Entf, Strg+Z/Y, Strg+C/V, Strg+D, Esc hebt die Auswahl auf.
- **Zahlenfelder:** Mausrad ändert den Wert (Shift: ×10).

## Elemente

Frame (mit Backdrop), Fenster, Reiter, aufklappbarer Abschnitt, Scrollbereich, Button, Checkbox, Eingabefeld, Dropdown, Schieberegler, Statusleiste,
Textur, Text (FontString), 3D-Modell und **Template** (jedes Blizzard-Template).

**Eltern füllen** (unter Layout) verankert ein Element an allen Kanten seines Eltern-Elements (`SetAllPoints`).
Solche Elemente werden nicht selbst verschoben: Ziehen bewegt das Eltern-Element.

### Fenster

Blizzard-Fenster-Templates mit Titel, Schließen-Button, Porträt und Button-Leiste (je nach Stil):
`ButtonFrameTemplate`, `PortraitFrameTemplate`, `BasicFrameTemplate(WithInset)`, `DefaultPanel(Flat)Template`,
`UIPanelDialogTemplate`, `SimplePanelTemplate`, `InsetFrameTemplate`, `DialogBorder(Dark)Template`.

### Reiter

Ein Reiter-Container mit `PanelTabButtonTemplate` (unten), `PanelTopTabButtonTemplate` (oben) oder
`LargeSideTabButtonTemplate` (Seite: Symbol-Reiter rechts am Rand, wie im Forever-Sammlungsfenster; die Reiter-Namen
werden dort zu Tooltips, die Symbole stehen im Feld „Symbole“, ebenfalls durch `;` getrennt).
Die Reiter-Namen stehen durch `;` getrennt in einem Feld. Jedes direkte Kind ist eine Seite (Kind 1 = Reiter 1 …);
beim Anlegen wird pro Reiter eine leere Seite erzeugt, die ihr Eltern-Element füllt. Im Editor wechselt ein Klick auf
einen Reiter die Seite, und beim Auswählen eines Elements auf einer verdeckten Seite wird deren Reiter aktiv.
Der Export enthält `E.<Name>:SelectTab(index)` und `E.<Name>.Pages`; das Skript `OnTabSelected(self, index)` wird bei jedem Wechsel aufgerufen.

### Aufklappbarer Abschnitt

Eine Listen-Überschrift (`ListHeaderVisualTemplate`) mit +/–-Button. Ihre Kinder sind der Inhalt des Abschnitts und
werden im zugeklappten Zustand ausgeblendet; beim Anlegen entsteht ein leerer Inhalts-Frame unter der Überschrift.
Im Editor klappt ein Klick auf +/– um, in der Vorschau ein Klick auf die ganze Überschrift. Export:
`E.<Name>:SetCollapsed(true/false)`, Skript `OnToggle(self, collapsed)`. Elemente unterhalb rücken beim Zuklappen
**nicht** automatisch nach oben.

### Dropdown

Deckt alle eigenständig nutzbaren Dropdowns des modernen Menüsystems ab: `WowStyle1DropdownTemplate` (Standard),
`WowStyle2DropdownTemplate` (Einstellungs-Stil), `WowStyle1FilterDropdownTemplate` (Filter-Button),
`WowStyle1ArrowDropdownTemplate`, `UIPanelIconDropdownButtonTemplate` (Zahnrad) und `UIPanelArrowDropdownButtonTemplate`.
Einträge stehen durch `;` getrennt in einem Feld (`-` = Trennlinie, `#Text` = Überschrift). Modi: Einfachauswahl (Radio),
Mehrfachauswahl (Checkboxen) oder Aktionen (Buttons). Optional mit Pfeil-Steppern links/rechts (Einfachauswahl).
Skript `OnSelect(self, index, text, checked)`; `index` zählt nur echte Einträge. Export: `SetupMenu` mit `E.<Name>.Selected`.

### Template

Erzeugt ein Widget aus einem beliebigen Blizzard-Template. Mit „…“ öffnest du eine durchsuchbare Liste aller
Templates, die der Client nach dem Login geladen hat (Widget-Typ und Standardgröße werden übernommen – auch
Größen, die ein Template erst in seinem `OnLoad` setzt). Listen-Überschriften bekommen ihren Text über `SetHeaderText`. Die Ansicht
**Empfohlen** zeigt den kuratierten Katalog (siehe `TEMPLATES.md`) nach Kategorien, mit Beschreibung und – wo nötig –
Setup-Code, der als `OnLoad` eingetragen wird. „OnLoad im Editor ausführen“ lässt diesen Code auch auf der Arbeitsfläche
laufen, damit z. B. Regler schon initialisiert aussehen. **Allgemein** zeigt alle Templates der geteilten Blizzard-Addons,
**Alle** jedes geladene Template. Unbekannte oder fehlerhafte Templates erscheinen als roter Platzhalter. Die Liste (`Data/Templates.lua`) erzeugt
`python3 Tools/build_templates.py [/pfad/zu/wow-ui-source]` aus dem UI-Source. Das Skript wertet die TOC-Dateien wie der
Forever-Client aus (Spieltyp `camelot`, `[Family]` = Mainline, `[Game]` = Camelot, Zeilen-Bedingungen, XML-`<Include>`s,
ohne Load-on-Demand- und Login-Screen-Addons).

### Scrollbereiche

Ein Scrollbereich ist ein `ScrollFrame` mit einem Inhalts-Frame (`E.<Name>.Content`) als Scroll-Child.
Elemente, die du hineinziehst, landen im Inhalt und werden an ihm verankert. Die Inhaltshöhe legst du in den
Eigenschaften fest; die Inhaltsbreite folgt der Frame-Breite, solange sie 0 ist.
Im Editor scrollt **Strg+Mausrad** über dem Bereich den Inhalt (alternativ „Scrollposition (Editor)“), damit du
auch weiter unten liegende Elemente erreichst. Elemente außerhalb des sichtbaren Ausschnitts lassen sich auf der
Arbeitsfläche nicht anklicken, wohl aber über die Ebenenliste.
Mit „Scrollleiste“ wird `ScrollFrameTemplate` samt Leiste rechts neben dem Frame exportiert, ohne Leiste ein
schlichter ScrollFrame mit Mausrad-Scrollen.

## Skripte und Vorschau

Jedes Element hat Skript-Slots (`OnLoad`, `OnClick`, `OnValueChanged` …). Im Skript ist `self` das Element,
andere Elemente erreichst du über `E.<Name>`, z. B. `E.MainFrame:Hide()`. **Vorschau** macht alles aktiv:
Buttons lassen sich klicken, Skripte laufen, verschiebbare Frames lassen sich ziehen. „Bearbeiten“ stellt den Entwurf wieder her.

## Export

- **Lua-Code:** eigenständiger Code (`CreateFrame` …), den du direkt in ein Addon kopieren kannst. Alle Elemente liegen in der Tabelle `E`.
- **Teilen-String / Import:** das komplette Projekt als String (nutzt `C_EncodingUtil`). Importierte Skripte vor der Vorschau prüfen!

Projekte werden in `ForeverFrameBuilderDB` (SavedVariables) gespeichert.

## Grenzen

- Frames können in WoW nicht zerstört werden. Der Editor verwendet sie wieder; nur Widgets, die in der Vorschau Skript-Hooks bekommen haben, werden verworfen.
- Die Strata eines Elements wird nur exportiert, auf der Arbeitsfläche aber nicht angewendet.
- 3D-Modelle ignorieren teilweise das Clipping der Arbeitsfläche.
