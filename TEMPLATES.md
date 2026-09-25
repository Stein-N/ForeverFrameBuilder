# Template-Katalog (WoW: Forever)

Kuratierte Auswahl aus dem UI-Source, die im Frame Builder direkt nutzbar ist. Erzeugt aus `Data/Catalog.lua`.
Alle Templates werden vom Forever-Client beim Login geladen (Spieltyp *camelot*, Family *Mainline*).

Spalte **Setup**: OnLoad-Code, den der Picker automatisch einträgt (und im Editor ausführt). Spalte **Element**: Builder-Element, das das Template mit mehr Optionen abdeckt.

## Buttons

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `UIPanelButtonTemplate` | Button | Klassischer roter Panel-Button. |  | Button |
| `SharedButtonTemplate` | Button | Moderner roter Button (Three-Slice), wächst mit dem Text. |  |  |
| `SharedButtonSmallTemplate` | Button | Kleiner moderner roter Button. |  |  |
| `SharedButtonLargeTemplate` | Button | Großer moderner roter Button. |  |  |
| `SharedGoldRedButtonTemplate` | Button | Rot-goldener Button für Hauptaktionen. |  |  |
| `UIPanelGoldButtonTemplate` | Button | Klassischer goldener Panel-Button. |  |  |
| `GameMenuButtonTemplate` | Button | Button im Stil des Spielmenüs. |  |  |
| `UIMenuButtonStretchTemplate` | Button | Dehnbarer Button im Menü-Stil. |  |  |
| `UIPanelCloseButton` | Button | X-Button; blendet beim Klick sein Eltern-Element aus. |  |  |
| `UIPanelInfoButton` | Button | Kleiner runder (i)-Info-Button. |  |  |
| `RefreshButtonTemplate` | Button | Quadratischer Aktualisieren-Button. |  |  |
| `SquareIconButtonTemplate` | Button | Quadratischer Button mit Symbol. | `self:SetIcon("Interface\\Icons\\INV_Misc_Gear_01")` |  |
| `WowStyle2IconButtonTemplate` | Button | Runder Symbol-Button im Einstellungs-Stil. |  |  |
| `MaximizeMinimizeButtonFrameTemplate` | Frame | Maximieren/Minimieren-Paar für Fensterecken. | `self:SetOnMaximizedCallback(function() print("maximized") end); self:SetOnMinimizedCallback(function() print("minimized") end)` |  |

## Checkboxen & Radiobuttons

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `UICheckButtonTemplate` | CheckButton | Klassische Checkbox mit Beschriftung rechts. |  | Checkbox |
| `MinimalCheckboxTemplate` | CheckButton | Moderne kleine Checkbox ohne Beschriftung. |  |  |
| `CheckboxWithLabelTemplate` | CheckButton | Moderne Checkbox mit Beschriftung. | `self.Text:SetText("Option")` |  |
| `UIRadioButtonTemplate` | CheckButton | Runder Radiobutton mit Beschriftung. | `self.text:SetText("Option")` |  |

## Eingabefelder

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `InputBoxTemplate` | EditBox | Einzeiliges Standard-Eingabefeld. |  | Eingabefeld |
| `InputBoxInstructionsTemplate` | EditBox | Eingabefeld mit grauem Platzhaltertext. | `self.Instructions:SetText("Enter a name…")` |  |
| `SearchBoxTemplate` | EditBox | Suchfeld mit Lupe, Platzhalter und Löschen-Button. |  |  |
| `LargeInputBoxTemplate` | EditBox | Höheres einzeiliges Eingabefeld. |  |  |
| `NumericInputSpinnerTemplate` | EditBox | Zahlenfeld mit - und + Buttons. | `self:SetMinMaxValues(0, 100); self:SetValue(10)` |  |
| `InputScrollFrameTemplate` | ScrollFrame | Mehrzeiliges Eingabefeld mit Rahmen, Scrollen und Zeichenzähler. | `self.EditBox:SetMaxLetters(255); self.EditBox:SetWidth(self:GetWidth() - 18); self.Instructions:SetText("Your text…")` |  |
| `ScrollingEditBoxTemplate` | Frame | Mehrzeiliges Eingabefeld ohne Rahmen (in ein Inset legen). | `self:SetDefaultText("Your text…")` |  |
| `MoneyInputFrameTemplate` | Frame | Eingabe für Gold / Silber / Kupfer. | `MoneyInputFrame_SetCopper(self, 123456)` |  |

## Dropdowns

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `WowStyle1DropdownTemplate` | DropdownButton | Standard-Dropdown; nutze das Element Dropdown (Stil Standard). |  | Dropdown |
| `WowStyle2DropdownTemplate` | DropdownButton | Dropdown im Einstellungs-Stil; nutze das Element Dropdown. |  | Dropdown |
| `WowStyle1FilterDropdownTemplate` | DropdownButton | Filter-Button mit Checkbox-Menü; nutze das Element Dropdown. |  | Dropdown |
| `WowStyle1ArrowDropdownTemplate` | DropdownButton | Kleiner Pfeil-Menübutton; nutze das Element Dropdown. |  | Dropdown |
| `UIPanelIconDropdownButtonTemplate` | DropdownButton | Zahnrad-Menübutton; nutze das Element Dropdown. |  | Dropdown |
| `UIPanelArrowDropdownButtonTemplate` | DropdownButton | Winziger Pfeil-Menübutton; nutze das Element Dropdown. |  | Dropdown |

## Schieberegler

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `UISliderTemplate` | Slider | Klassischer waagerechter Schieberegler. |  | Schieberegler |
| `UISliderTemplateWithLabels` | Slider | Klassischer Regler mit Titel und Min/Max-Beschriftung. | `self:SetMinMaxValues(0, 100); self:SetValueStep(1); self:SetObeyStepOnDrag(true); self:SetValue(50); self.Text:SetText("Volume"); self.Low:SetText("0"); self.High:SetText("100")` |  |
| `MinimalSliderTemplate` | Slider | Moderner schmaler Regler. | `self:SetMinMaxValues(0, 100); self:SetValueStep(1); self:SetValue(50)` |  |
| `MinimalSliderWithSteppersTemplate` | Frame | Moderner Regler mit Pfeilen und Wertanzeige (Einstellungs-Stil). | `local formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = function(value) return math.floor(value) end }; self:Init(50, 0, 100, 100, formatters)` |  |
| `SliderWithButtonsAndLabelTemplate` | Frame | Regler mit - / + Buttons und Beschriftung. | `self:SetupSlider(0, 100, 50, 1, "Volume")` |  |
| `SliderAndEditControlTemplate` | Frame | Regler mit Zahlenfeld daneben. | `self:SetupSlider(0, 100, 50, 1, "Value")` |  |

## Fortschrittsleisten

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `ColoredProgressBarTemplate` | Frame | Werteleiste im Forever-Stil (rot, grün, blau, weiß). | `self:SetFillTextureByColorType(ColoredProgressBarMixin.ColorType.Green); self:SetFillPercent(0.6); self:SetText("60%")` |  |

## Reiter & Überschriften

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `PanelTabButtonTemplate` | Button | Klassischer Reiter unter einem Fenster; nutze das Element Reiter. |  | Reiter |
| `LargeSideTabButtonTemplate` | Frame | Symbol-Seitenreiter; nutze das Element Reiter (Seite). |  | Reiter |
| `MinimalTabTemplate` | Button | Flacher Reiter im Einstellungs-Stil. | `self.Text:SetText("General"); self:SetSelected(true)` |  |
| `TabSystemTemplate` | Frame | Moderne Reiterleiste; Reiter werden per Code hinzugefügt. | `self:AddTab("General"); self:AddTab("Options"); self:SetTabSelectedCallback(function(tabID) print("tab", tabID) end); self:SetTab(1)` |  |
| `ListHeaderVisualTemplate` | Button | Listen-Überschrift mit +/-; nutze das Element Aufklappbarer Abschnitt. |  | Aufklappbarer Abschnitt |
| `DialogHeaderTemplate` | Frame | Titelschild an der Oberkante eines Dialogs. | `self:Setup("My Dialog")` |  |
| `CollapseButtonTemplate` | Button | Einzelner +/- Button. | `self:UpdateCollapsedState(false)` |  |

## Fenster, Rahmen & Hintergründe

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `ButtonFrameTemplate` | Frame | Standardfenster; nutze das Element Fenster. |  | Fenster |
| `BasicFrameTemplateWithInset` | Frame | Einfaches Fenster mit Inset; nutze das Element Fenster. |  | Fenster |
| `InsetFrameTemplate` | Frame | Eingelassener Bereich für Listen und Inhalte. |  |  |
| `TooltipBackdropTemplate` | Frame | Hintergrund und Rahmen im Tooltip-Stil. |  |  |
| `TooltipBorderedFrameTemplate` | Frame | Tooltip-Rahmen mit leicht transparentem Hintergrund. |  |  |
| `DialogBorderTemplate` | Frame | Klassischer Dialograhmen. |  |  |
| `DialogBorderDarkTemplate` | Frame | Dunkler Dialograhmen. |  |  |
| `DialogBorderOpaqueTemplate` | Frame | Dialograhmen mit deckendem Hintergrund. |  |  |
| `DialogBorderTranslucentTemplate` | Frame | Dialograhmen mit durchscheinendem Hintergrund. |  |  |
| `ThinGoldEdgeTemplate` | Frame | Dünne Goldkante um einen Bereich. |  |  |
| `TranslucentFrameTemplate` | Frame | Dunkles durchscheinendes Panel mit Rahmen. |  |  |
| `FlatPanelBackgroundTemplate` | Frame | Flacher moderner Panel-Hintergrund. |  |  |
| `ShadowOverlayTemplate` | Frame | Weicher Schatten in den Ecken eines Bereichs. |  |  |
| `NineSlicePanelTemplate` | Frame | Nine-Slice-Rahmen mit beliebigem Blizzard-Layout. | `NineSliceUtil.ApplyLayoutByName(self, "Dialog")` |  |

## Text & Anzeige

| Template | Typ | Beschreibung | Setup | Element |
|---|---|---|---|---|
| `ColorSwatchTemplate` | Frame | Kleines Farbfeld. | `self:SetColorRGB(1, 0.82, 0)` |  |
| `NewFeatureLabelTemplate` | Frame | Leuchtendes NEU-Label. |  |  |
| `LoadingSpinnerTemplate` | Frame | Animierter Lade-Kreisel. |  |  |
| `SpinnerTemplate` | Frame | Moderner animierter Kreisel. |  |  |
## Bewusst nicht im Katalog

- `ScrollingFontTemplate`: sein `OnLoad` prüft `assert(self.fontName)`. Blizzard setzt `fontName` immer per `<KeyValue>` in einem abgeleiteten Template, bevor `OnLoad` läuft – allein erzeugt schlägt es fehl. Für scrollbaren Text: Element *Scrollbereich* mit einem *Text* darin.
- `DropdownWithSteppersTemplate` / `…AndLabelTemplate`: erwarten einen Kind-Frame `.Dropdown` aus einem abgeleiteten Template und werfen allein erzeugt einen Fehler. Das Element *Dropdown* hat stattdessen die Option „Pfeil-Stepper“.
- `WowStyle1ThinDropdownTemplate`, `ModelWithControlsTemplate`: existieren im Source nur für andere Flavors und werden von Forever nicht geladen.
- `UIDropDownMenuTemplate` (altes Dropdown-System): braucht `UIDropDownMenu_Initialize` und globale Namen; das moderne Menüsystem (Element *Dropdown*) ersetzt es.
- Geld-Anzeigen (`MoneyFrameTemplate`, `SmallMoneyFrameTemplate`): brauchen `MoneyFrame_SetType` und einen globalen Frame-Namen.
- Feature-spezifische Templates (Gilden, Talente, Aktionsleisten, …): hängen meist an globalen Frames und Daten ihres Addons. Sie sind im Picker unter „Alle“ zu finden, laufen aber oft nicht eigenständig.
- Allgemein: Der Generator markiert Templates, deren `OnLoad` einen Schlüssel per `assert` verlangt oder ohne Prüfung ein Kind-Element (`self.X:…`) benutzt, das weder die Vererbungskette (parentKey/KeyValue) noch das `OnLoad` selbst anlegt. Das sind derzeit 13 Basis-Templates (u. a. `ScrollingFontTemplate`, `DropdownWithSteppers*`, `ScrollBarBaseTemplate`, `Vertical/HorizontalScrollBarTemplate`). Im Picker tragen sie ein rotes **(!)** und werden als Platzhalter angelegt.
