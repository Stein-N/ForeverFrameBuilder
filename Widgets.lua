-- Forever Frame Builder
-- Widgets: small factories for the editor's own controls.

local _, ns = ...

local W = {}
ns.W = W

function W.Tooltip(frame, title, text)
	frame:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(title, 1, 1, 1)
		if text then
			GameTooltip:AddLine(text, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end)
	frame:HookScript("OnLeave", GameTooltip_Hide)
end

function W.Button(parent, text, width, onClick, tooltip)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 80, 22)
	button:SetText(text)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	if tooltip then
		W.Tooltip(button, text, tooltip)
	end
	return button
end

-- Small square button showing a texture instead of text. Textures without a
-- "-Disabled" variant are desaturated instead.
function W.IconButton(parent, texture, size, onClick, tooltip, hasDisabledTexture)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size or 22, size or 22)
	button:SetNormalTexture(texture .. "-Up")
	button:SetPushedTexture(texture .. "-Down")
	if hasDisabledTexture then
		button:SetDisabledTexture(texture .. "-Disabled")
	else
		button:SetScript("OnDisable", function(self)
			self:GetNormalTexture():SetDesaturated(true)
			self:GetNormalTexture():SetAlpha(0.4)
		end)
		button:SetScript("OnEnable", function(self)
			self:GetNormalTexture():SetDesaturated(false)
			self:GetNormalTexture():SetAlpha(1)
		end)
	end
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("OnClick", onClick)
	if tooltip then
		W.Tooltip(button, tooltip)
	end
	return button
end

function W.Check(parent, text, onClick, tooltip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	local label = check.Text or check.text
	label:SetFontObject(GameFontHighlightSmall)
	label:SetText(text)
	check:SetHitRectInsets(0, -label:GetStringWidth() - 4, 0, 0)
	check:SetScript("OnClick", function(self)
		onClick(self:GetChecked())
	end)
	check.width = 24 + label:GetStringWidth() + 6
	if tooltip then
		W.Tooltip(check, text, tooltip)
	end
	return check
end

function W.EditBox(parent, width)
	local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	box:SetAutoFocus(false)
	box:SetSize(width or 100, 20)
	box:SetFontObject(ChatFontNormal)
	return box
end

function W.Inset(parent)
	return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

function W.Label(parent, text, font)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
	label:SetText(text or "")
	return label
end

function W.Dropdown(parent, width)
	local dropdown = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
	dropdown:SetWidth(width or 120)
	return dropdown
end

-- Vertical scroll area; returns the scroll frame and its content frame.
function W.ScrollArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -4)
	scroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -22, 4)
	if scroll.ScrollBar then
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 4, -2)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 4, 2)
	end
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)
	scroll:HookScript("OnSizeChanged", function(self, width)
		content:SetWidth(width)
	end)
	return scroll, content
end

-- One-pixel outline made of four textures.
function W.Outline(frame, r, g, b, a, thickness, layer)
	thickness = thickness or 1
	local lines = {}
	for i = 1, 4 do
		local line = frame:CreateTexture(nil, layer or "OVERLAY")
		line:SetColorTexture(r, g, b, a or 1)
		lines[i] = line
	end
	lines[1]:SetPoint("TOPLEFT")
	lines[1]:SetPoint("TOPRIGHT")
	lines[1]:SetHeight(thickness)
	lines[2]:SetPoint("BOTTOMLEFT")
	lines[2]:SetPoint("BOTTOMRIGHT")
	lines[2]:SetHeight(thickness)
	lines[3]:SetPoint("TOPLEFT")
	lines[3]:SetPoint("BOTTOMLEFT")
	lines[3]:SetWidth(thickness)
	lines[4]:SetPoint("TOPRIGHT")
	lines[4]:SetPoint("BOTTOMRIGHT")
	lines[4]:SetWidth(thickness)
	frame.outline = lines
	return lines
end

function W.SetOutlineThickness(frame, thickness)
	local lines = frame.outline
	lines[1]:SetHeight(thickness)
	lines[2]:SetHeight(thickness)
	lines[3]:SetWidth(thickness)
	lines[4]:SetWidth(thickness)
end

-- Foldable category title in the style of the AddOn list: gold text, a "bag-arrow" that
-- points right while collapsed and down while expanded, and the quest title highlight.
function W.CategoryHeader(parent, onToggle)
	local header = CreateFrame("Button", nil, parent)
	header:SetHeight(22)
	local highlight = header:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	highlight:SetBlendMode("ADD")
	highlight:SetPoint("TOPLEFT", 4, 0)
	highlight:SetPoint("BOTTOMRIGHT", -4, 0)
	local arrow = header:CreateTexture(nil, "ARTWORK")
	arrow:SetAtlas("bag-arrow")
	arrow:SetSize(10, 16)
	arrow:SetPoint("LEFT", 12, 0)
	local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	header:SetScript("OnClick", function(self)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		onToggle(self)
	end)

	function header:SetTitle(text)
		title:SetText(text)
	end
	function header:SetCollapsed(collapsed)
		arrow:SetRotation(collapsed and math.pi or math.pi / 2)
	end
	-- Space kept free on the right, e.g. for a button next to the title.
	function header:SetTitleRightInset(inset)
		title:ClearAllPoints()
		title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
		title:SetPoint("RIGHT", -(inset or 8), 0)
	end
	header:SetTitleRightInset(8)
	return header
end
