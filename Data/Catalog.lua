-- Forever Frame Builder
-- Catalog: hand-picked Blizzard templates that work on their own, checked against the
-- Forever UI source. setup is OnLoad code the template needs to look/behave right;
-- element names a builder element that covers the template better than the raw template.
--
-- { template, category, English note, German note, setup, element }

local _, ns = ...

ns.CatalogCategories = {
	{ key = "buttons", en = "Buttons", de = "Buttons" },
	{ key = "checks", en = "Checkboxes & radio buttons", de = "Checkboxen & Radiobuttons" },
	{ key = "inputs", en = "Input fields", de = "Eingabefelder" },
	{ key = "dropdowns", en = "Dropdowns", de = "Dropdowns" },
	{ key = "sliders", en = "Sliders", de = "Schieberegler" },
	{ key = "bars", en = "Progress bars", de = "Fortschrittsleisten" },
	{ key = "tabs", en = "Tabs & headers", de = "Reiter & Überschriften" },
	{ key = "frames", en = "Windows, borders & backgrounds", de = "Fenster, Rahmen & Hintergründe" },
	{ key = "display", en = "Text & display", de = "Text & Anzeige" },
}

ns.Catalog = {
	-- Buttons
	{ "UIPanelButtonTemplate", "buttons", "Classic red panel button.", "Klassischer roter Panel-Button.", nil, "Button" },
	{ "SharedButtonTemplate", "buttons", "Modern red three-slice button, grows with its text.", "Moderner roter Button (Three-Slice), wächst mit dem Text." },
	{ "SharedButtonSmallTemplate", "buttons", "Small modern red button.", "Kleiner moderner roter Button." },
	{ "SharedButtonLargeTemplate", "buttons", "Large modern red button.", "Großer moderner roter Button." },
	{ "SharedGoldRedButtonTemplate", "buttons", "Gold-framed red button for primary actions.", "Rot-goldener Button für Hauptaktionen." },
	{ "UIPanelGoldButtonTemplate", "buttons", "Classic gold panel button.", "Klassischer goldener Panel-Button." },
	{ "GameMenuButtonTemplate", "buttons", "Button in the style of the game menu.", "Button im Stil des Spielmenüs." },
	{ "UIMenuButtonStretchTemplate", "buttons", "Stretchable menu-style button.", "Dehnbarer Button im Menü-Stil." },
	{ "UIPanelCloseButton", "buttons", "X button; hides its parent when clicked.", "X-Button; blendet beim Klick sein Eltern-Element aus." },
	{ "UIPanelInfoButton", "buttons", "Small round (i) info button.", "Kleiner runder (i)-Info-Button." },
	{ "RefreshButtonTemplate", "buttons", "Square refresh button.", "Quadratischer Aktualisieren-Button." },
	{ "SquareIconButtonTemplate", "buttons", "Square button with an icon.", "Quadratischer Button mit Symbol.",
		"self:SetIcon(\"Interface\\\\Icons\\\\INV_Misc_Gear_01\")" },
	{ "WowStyle2IconButtonTemplate", "buttons", "Settings-style round icon button.", "Runder Symbol-Button im Einstellungs-Stil." },
	{ "MaximizeMinimizeButtonFrameTemplate", "buttons", "Maximize/minimize button pair for window corners.", "Maximieren/Minimieren-Paar für Fensterecken.",
		"self:SetOnMaximizedCallback(function() print(\"maximized\") end)\nself:SetOnMinimizedCallback(function() print(\"minimized\") end)" },

	-- Checkboxes
	{ "UICheckButtonTemplate", "checks", "Classic checkbox with a label to its right.", "Klassische Checkbox mit Beschriftung rechts.", nil, "CheckButton" },
	{ "MinimalCheckboxTemplate", "checks", "Modern small checkbox without label.", "Moderne kleine Checkbox ohne Beschriftung." },
	{ "CheckboxWithLabelTemplate", "checks", "Modern checkbox with label.", "Moderne Checkbox mit Beschriftung.",
		"self.Text:SetText(\"Option\")" },
	{ "UIRadioButtonTemplate", "checks", "Round radio button with label.", "Runder Radiobutton mit Beschriftung.",
		"self.text:SetText(\"Option\")" },

	-- Inputs
	{ "InputBoxTemplate", "inputs", "Standard single-line input.", "Einzeiliges Standard-Eingabefeld.", nil, "EditBox" },
	{ "InputBoxInstructionsTemplate", "inputs", "Input with grey placeholder text.", "Eingabefeld mit grauem Platzhaltertext.",
		"self.Instructions:SetText(\"Enter a name…\")" },
	{ "SearchBoxTemplate", "inputs", "Search field with magnifier, placeholder and clear button.", "Suchfeld mit Lupe, Platzhalter und Löschen-Button." },
	{ "LargeInputBoxTemplate", "inputs", "Taller single-line input.", "Höheres einzeiliges Eingabefeld." },
	{ "NumericInputSpinnerTemplate", "inputs", "Number field with - and + buttons.", "Zahlenfeld mit - und + Buttons.",
		"self:SetMinMaxValues(0, 100)\nself:SetValue(10)" },
	{ "InputScrollFrameTemplate", "inputs", "Multi-line input with border, scrolling and character counter.", "Mehrzeiliges Eingabefeld mit Rahmen, Scrollen und Zeichenzähler.",
		"self.EditBox:SetMaxLetters(255)\nself.EditBox:SetWidth(self:GetWidth() - 18)\nself.Instructions:SetText(\"Your text…\")" },
	{ "ScrollingEditBoxTemplate", "inputs", "Multi-line input without border (put it into an inset).", "Mehrzeiliges Eingabefeld ohne Rahmen (in ein Inset legen).",
		"self:SetDefaultText(\"Your text…\")" },
	{ "MoneyInputFrameTemplate", "inputs", "Gold / silver / copper input.", "Eingabe für Gold / Silber / Kupfer.",
		"MoneyInputFrame_SetCopper(self, 123456)" },

	-- Dropdowns (all covered by the Dropdown element)
	{ "WowStyle1DropdownTemplate", "dropdowns", "Standard dropdown; use the Dropdown element (style Standard).", "Standard-Dropdown; nutze das Element Dropdown (Stil Standard).", nil, "Dropdown" },
	{ "WowStyle2DropdownTemplate", "dropdowns", "Settings-style dropdown; use the Dropdown element.", "Dropdown im Einstellungs-Stil; nutze das Element Dropdown.", nil, "Dropdown" },
	{ "WowStyle1FilterDropdownTemplate", "dropdowns", "Filter button with a checkbox menu; use the Dropdown element.", "Filter-Button mit Checkbox-Menü; nutze das Element Dropdown.", nil, "Dropdown" },
	{ "WowStyle1ArrowDropdownTemplate", "dropdowns", "Small arrow menu button; use the Dropdown element.", "Kleiner Pfeil-Menübutton; nutze das Element Dropdown.", nil, "Dropdown" },
	{ "UIPanelIconDropdownButtonTemplate", "dropdowns", "Gear icon menu button; use the Dropdown element.", "Zahnrad-Menübutton; nutze das Element Dropdown.", nil, "Dropdown" },
	{ "UIPanelArrowDropdownButtonTemplate", "dropdowns", "Tiny arrow menu button; use the Dropdown element.", "Winziger Pfeil-Menübutton; nutze das Element Dropdown.", nil, "Dropdown" },

	-- Sliders
	{ "UISliderTemplate", "sliders", "Classic horizontal slider.", "Klassischer waagerechter Schieberegler.", nil, "Slider" },
	{ "UISliderTemplateWithLabels", "sliders", "Classic slider with title and min/max labels.", "Klassischer Regler mit Titel und Min/Max-Beschriftung.",
		"self:SetMinMaxValues(0, 100)\nself:SetValueStep(1)\nself:SetObeyStepOnDrag(true)\nself:SetValue(50)\nself.Text:SetText(\"Volume\")\nself.Low:SetText(\"0\")\nself.High:SetText(\"100\")" },
	{ "MinimalSliderTemplate", "sliders", "Modern thin slider.", "Moderner schmaler Regler.",
		"self:SetMinMaxValues(0, 100)\nself:SetValueStep(1)\nself:SetValue(50)" },
	{ "MinimalSliderWithSteppersTemplate", "sliders", "Modern slider with arrow steppers and value label (settings style).", "Moderner Regler mit Pfeilen und Wertanzeige (Einstellungs-Stil).",
		"local formatters = { [MinimalSliderWithSteppersMixin.Label.Right] = function(value) return math.floor(value) end }\nself:Init(50, 0, 100, 100, formatters)" },
	{ "SliderWithButtonsAndLabelTemplate", "sliders", "Slider with - / + buttons and a label.", "Regler mit - / + Buttons und Beschriftung.",
		"self:SetupSlider(0, 100, 50, 1, \"Volume\")" },
	{ "SliderAndEditControlTemplate", "sliders", "Slider with a number input next to it.", "Regler mit Zahlenfeld daneben.",
		"self:SetupSlider(0, 100, 50, 1, \"Value\")" },

	-- Bars
	{ "ColoredProgressBarTemplate", "bars", "Forever-style stat bar (red, green, blue, white).", "Werteleiste im Forever-Stil (rot, grün, blau, weiß).",
		"self:SetFillTextureByColorType(ColoredProgressBarMixin.ColorType.Green)\nself:SetFillPercent(0.6)\nself:SetText(\"60%\")" },

	-- Tabs & headers
	{ "PanelTabButtonTemplate", "tabs", "Classic tab below a window; use the Tabs element.", "Klassischer Reiter unter einem Fenster; nutze das Element Reiter.", nil, "Tabs" },
	{ "LargeSideTabButtonTemplate", "tabs", "Icon side tab; use the Tabs element (Side).", "Symbol-Seitenreiter; nutze das Element Reiter (Seite).", nil, "Tabs" },
	{ "MinimalTabTemplate", "tabs", "Flat settings-style tab.", "Flacher Reiter im Einstellungs-Stil.",
		"self.Text:SetText(\"General\")\nself:SetSelected(true)" },
	{ "TabSystemTemplate", "tabs", "Modern tab bar; tabs are added in code.", "Moderne Reiterleiste; Reiter werden per Code hinzugefügt.",
		"self:AddTab(\"General\")\nself:AddTab(\"Options\")\nself:SetTabSelectedCallback(function(tabID) print(\"tab\", tabID) end)\nself:SetTab(1)" },
	{ "ListHeaderVisualTemplate", "tabs", "List header with +/-; use the Collapsible section element.", "Listen-Überschrift mit +/-; nutze das Element Aufklappbarer Abschnitt.", nil, "Section" },
	{ "DialogHeaderTemplate", "tabs", "Title plate on the top edge of a dialog.", "Titelschild an der Oberkante eines Dialogs.",
		"self:Setup(\"My Dialog\")" },
	{ "CollapseButtonTemplate", "tabs", "Stand-alone +/- button.", "Einzelner +/- Button.",
		"self:UpdateCollapsedState(false)" },

	-- Windows, borders & backgrounds
	{ "ButtonFrameTemplate", "frames", "Standard window; use the Window element.", "Standardfenster; nutze das Element Fenster.", nil, "Window" },
	{ "BasicFrameTemplateWithInset", "frames", "Simple window with inset; use the Window element.", "Einfaches Fenster mit Inset; nutze das Element Fenster.", nil, "Window" },
	{ "InsetFrameTemplate", "frames", "Sunken inset area for lists and content.", "Eingelassener Bereich für Listen und Inhalte." },
	{ "TooltipBackdropTemplate", "frames", "Tooltip-style background and border.", "Hintergrund und Rahmen im Tooltip-Stil." },
	{ "TooltipBorderedFrameTemplate", "frames", "Tooltip frame with slightly transparent background.", "Tooltip-Rahmen mit leicht transparentem Hintergrund." },
	{ "DialogBorderTemplate", "frames", "Classic dialog border.", "Klassischer Dialograhmen." },
	{ "DialogBorderDarkTemplate", "frames", "Dark dialog border.", "Dunkler Dialograhmen." },
	{ "DialogBorderOpaqueTemplate", "frames", "Dialog border with opaque background.", "Dialograhmen mit deckendem Hintergrund." },
	{ "DialogBorderTranslucentTemplate", "frames", "Dialog border with translucent background.", "Dialograhmen mit durchscheinendem Hintergrund." },
	{ "ThinGoldEdgeTemplate", "frames", "Thin gold edge around an area.", "Dünne Goldkante um einen Bereich." },
	{ "TranslucentFrameTemplate", "frames", "Dark translucent panel with border.", "Dunkles durchscheinendes Panel mit Rahmen." },
	{ "FlatPanelBackgroundTemplate", "frames", "Flat modern panel background.", "Flacher moderner Panel-Hintergrund." },
	{ "ShadowOverlayTemplate", "frames", "Soft shadow in the corners of an area.", "Weicher Schatten in den Ecken eines Bereichs." },
	{ "NineSlicePanelTemplate", "frames", "Nine-slice border with any Blizzard layout.", "Nine-Slice-Rahmen mit beliebigem Blizzard-Layout.",
		"NineSliceUtil.ApplyLayoutByName(self, \"Dialog\")" },

	-- Text & display
	{ "ColorSwatchTemplate", "display", "Small color swatch.", "Kleines Farbfeld.",
		"self:SetColorRGB(1, 0.82, 0)" },
	{ "NewFeatureLabelTemplate", "display", "Glowing NEW label.", "Leuchtendes NEU-Label." },
	{ "LoadingSpinnerTemplate", "display", "Animated loading spinner.", "Animierter Lade-Kreisel." },
	{ "SpinnerTemplate", "display", "Modern animated spinner.", "Moderner animierter Kreisel." },
}

-- Returns the catalog entry for a template name, if any.
function ns.GetCatalogEntry(name)
	if not ns.CatalogIndex then
		ns.CatalogIndex = {}
		for _, entry in ipairs(ns.Catalog) do
			ns.CatalogIndex[entry[1]] = entry
		end
	end
	return ns.CatalogIndex[name]
end

function ns.CatalogNote(entry)
	return GetLocale() == "deDE" and entry[4] or entry[3]
end

function ns.CatalogCategoryName(key)
	for _, category in ipairs(ns.CatalogCategories) do
		if category.key == key then
			return GetLocale() == "deDE" and category.de or category.en
		end
	end
	return key
end
