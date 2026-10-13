-- KeldurnProbe
--
-- Reports what the Keldurn client actually provides, so ElvUI can be patched from facts instead of guesses.
--
--   /kprobe          run every check, then show page 1 of the report
--   /kprobe 2        show page 2 (and 3, 4, ...)
--   /kprobe events   show which game events have fired since the add-on loaded
--
-- For clean results, run it with ElvUI and !Compatibility DISABLED: !Compatibility overwrites
-- native functions, which would hide what Keldurn really has. The report warns if it is loaded.
--
-- Written to stay valid on both Lua 5.0 and 5.1: no '#', no '...', no string.match, no '%' operator.

local LINES_PER_PAGE = 12

local out = {}          -- report lines
local pages = 1

local function Say(text)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffKProbe:|r " .. text)
	end
end

local function Add(text)
	table.insert(out, text)
end

-- Joins list items with ", " and wraps lines so none exceeds the chat line limit.
local function AddList(prefix, list)
	local line = prefix
	local first = true
	for i = 1, table.getn(list) do
		local piece = list[i]
		if string.len(line) + string.len(piece) > 190 then
			Add(line)
			line = "    "
			first = true
		end
		if first then
			line = line .. piece
		else
			line = line .. ", " .. piece
		end
		first = false
	end
	Add(line)
end

-- Looks up a global by name; "string.gfind" style names are followed through tables.
local function Resolve(name)
	local obj = getfenv(0)
	local rest = name
	while rest ~= "" do
		if type(obj) ~= "table" then
			return nil
		end
		local s, e, head, tail = string.find(rest, "^([^%.]+)%.?(.*)$")
		if not head then
			return nil
		end
		obj = obj[head]
		rest = tail
	end
	return obj
end

-- Checks that every name exists (and has the expected type, if one is given).
local function Check(title, names, expected)
	local missing = {}
	local wrong = {}
	local total = table.getn(names)
	for i = 1, total do
		local name = names[i]
		local v = Resolve(name)
		if v == nil then
			table.insert(missing, name)
		elseif expected and type(v) ~= expected then
			table.insert(wrong, name .. "=" .. type(v))
		end
	end
	local bad = table.getn(missing) + table.getn(wrong)
	Add(title .. ": " .. tostring(total - bad) .. "/" .. tostring(total) .. " present")
	if table.getn(missing) > 0 then
		AddList("   MISSING: ", missing)
	end
	if table.getn(wrong) > 0 then
		AddList("   WRONG TYPE: ", wrong)
	end
end

-- Checks that an object (frame, texture, ...) has all the listed methods.
local function CheckMethods(title, obj, methods)
	if not obj then
		Add(title .. ": object could not be created")
		return
	end
	local missing = {}
	local total = table.getn(methods)
	for i = 1, total do
		local ok, v = pcall(function() return obj[methods[i]] end)
		if not ok or type(v) ~= "function" then
			table.insert(missing, methods[i])
		end
	end
	Add(title .. ": " .. tostring(total - table.getn(missing)) .. "/" .. tostring(total) .. " methods")
	if table.getn(missing) > 0 then
		AddList("   MISSING: ", missing)
	end
end

local function NewFrame(frameType)
	local ok, obj = pcall(CreateFrame, frameType, nil, UIParent)
	if ok and obj then
		return obj
	end
	Add("CreateFrame(\"" .. frameType .. "\") FAILED: " .. tostring(obj))
	return nil
end

--------------------------------------------------------------------------------
-- Live probes, started at load: how handlers are called, and which events fire
--------------------------------------------------------------------------------

local TRACKED_EVENTS = {
	"UNIT_MANA", "UNIT_POWER_UPDATE", "UNIT_POWER", "UNIT_MAXMANA", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
	"UNIT_ENERGY", "UNIT_RAGE", "UNIT_FOCUS", "UNIT_HEALTH", "UNIT_MAXHEALTH",
	"UNIT_AURA", "PLAYER_AURAS_CHANGED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
	"BAG_UPDATE", "ACTIONBAR_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_STATE", "UNIT_COMBAT",
	"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"CHAT_MSG_COMBAT_SELF_HITS", "CHAT_MSG_COMBAT_SELF_MISSES", "CHAT_MSG_SPELL_SELF_DAMAGE",
	"SPELLCAST_START", "SPELLCAST_STOP", "UPDATE_SHAPESHIFT_FORMS", "PLAYER_XP_UPDATE",
	"PLAYER_ENTERING_WORLD", "VARIABLES_LOADED", "CURSOR_UPDATE"
}

local eventCounts = {}
local eventRejected = {}
local eventFirst = nil
local updateInfo = { calls = 0 }

local probe = CreateFrame("Frame", "KeldurnProbeFrame", UIParent)

probe:SetScript("OnEvent", function(p1, p2, p3)
	local e = event
	if type(e) ~= "string" then
		e = p2
	end
	if type(e) ~= "string" then
		e = "?"
	end
	if not eventFirst then
		eventFirst = "param1=" .. type(p1) .. " param2=" .. type(p2) .. " param3=" .. type(p3)
			.. " | globals: this=" .. type(this) .. " event=" .. type(event) .. " arg1=" .. type(arg1)
	end
	eventCounts[e] = (eventCounts[e] or 0) + 1
end)

for i = 1, table.getn(TRACKED_EVENTS) do
	local name = TRACKED_EVENTS[i]
	local ok, err = pcall(probe.RegisterEvent, probe, name)
	if not ok then
		eventRejected[name] = tostring(err)
	end
end

probe:SetScript("OnUpdate", function(p1, p2)
	if updateInfo.calls < 3 then
		updateInfo.info = "param1=" .. type(p1) .. " param2=" .. type(p2)
			.. " | globals: this=" .. type(this) .. " arg1=" .. type(arg1)
		if type(p2) == "number" then
			updateInfo.elapsed = p2
		elseif type(arg1) == "number" then
			updateInfo.elapsed = arg1
		end
	end
	updateInfo.calls = updateInfo.calls + 1
	if updateInfo.calls >= 10 then
		probe:SetScript("OnUpdate", nil)
	end
end)

--------------------------------------------------------------------------------
-- The report
--------------------------------------------------------------------------------

local LUA_FUNCTIONS = {
	"string.gfind", "string.gmatch", "string.match", "string.find", "string.format", "string.gsub",
	"string.split", "string.join", "strsplit", "strjoin", "strmatch", "strfind", "strsub", "strlen",
	"select", "unpack", "table.getn", "table.setn", "table.wipe", "wipe", "table.maxn", "table.insert", "tinsert",
	"math.mod", "math.fmod", "mod", "loadstring", "getfenv", "setfenv", "getglobal", "setglobal",
	"hooksecurefunc", "securecall", "issecurevariable", "tContains", "print", "tostringall",
	"date", "time", "GetTime", "difftime", "seterrorhandler", "geterrorhandler", "debuginfo",
	"debugstack", "gcinfo", "collectgarbage"
}

local LUA_FEATURES = {
	{ "length operator #",        "return #{1,2,3}" },
	{ "modulo operator %",        "return 7 % 4" },
	{ "varargs via select",       "local function f(...) return select('#', ...) end return f(1,2)" },
	{ "legacy arg table",         "local function f(...) return arg and arg.n end return f(1,2)" },
	{ "string.match",             "return string.match('abc123', '%d+')" },
	{ "string.gmatch loop",       "local n = 0 for _ in string.gmatch('a b c', '%a') do n = n + 1 end return n" },
	{ "string.gfind loop",        "local n = 0 for _ in string.gfind('a b c', '%a') do n = n + 1 end return n" }
}

-- What !Compatibility reads at load time, plus other constants and fonts ElvUI uses
local GLOBAL_VALUES = {
	"DURABILITY_TEMPLATE", "TIME_TWELVEHOURAM", "TIME_TWELVEHOURPM", "DUNGEON_DIFFICULTY1", "NUM_BAG_FRAMES",
	"NUM_BAG_SLOTS", "NUM_CHAT_WINDOWS", "CHAT_FRAMES", "RAID_CLASS_COLORS", "CLASS_ICON_TCOORDS",
	"QuestDifficultyColors", "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE", "CLASS_SORT_ORDER",
	"MAX_CLASSES", "DAY_ONELETTER_ABBR", "HOUR_ONELETTER_ABBR", "MINUTE_ONELETTER_ABBR", "SECOND_ONELETTER_ABBR",
	"STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "DAMAGE_TEXT_FONT", "PERFORMANCEBAR_LOW_LATENCY",
	"UIDROPDOWNMENU_MAXLEVELS", "UIDROPDOWNMENU_MAXBUTTONS", "UIDROPDOWNMENU_MENU_LEVEL"
}

local API_FUNCTIONS = {
	-- read by !Compatibility at load
	"debugstack", "GetContainerItemInfo", "GetContainerItemLink", "GetContainerNumSlots", "GetInventoryItemTexture",
	"GetItemInfo", "GetShapeshiftFormInfo", "GetQuestGreenRange", "GetRealZoneText", "IsInInstance", "UnitLevel",
	"UnitBuff", "UnitDebuff",
	-- error handler and slash command support
	"GetCVar", "SetCVar", "IsAddOnLoaded", "LoadAddOn", "GetAddOnInfo", "EnableAddOn", "DisableAddOn",
	"GetNumAddOns", "GetAddOnMetadata", "GetLocale", "StaticPopup_Show", "StaticPopup_Hide",
	-- units, power and health
	"UnitPowerType", "UnitMana", "UnitManaMax", "UnitHealth", "UnitHealthMax", "UnitClass", "UnitName", "UnitIsPlayer",
	-- misc client info
	"GetNetStats", "GetFramerate", "UpdateAddOnMemoryUsage", "GetAddOnMemoryUsage", "GetMouseFocus", "GetCursorPosition",
	"GetNumRaidMembers", "GetNumPartyMembers", "GetSpellName", "GetSpellCooldown", "GetActionCooldown", "HasAction",
	"GetNumShapeshiftForms", "HasPetUI", "PetHasActionBar",
	-- Blizzard UI functions that ElvUI and Titan call or hook
	"CooldownFrame_SetTimer", "ToggleDropDownMenu", "UIDropDownMenu_Initialize", "UIDropDownMenu_AddButton",
	"CloseDropDownMenus", "FCF_DockUpdate", "FCF_UpdateCombatLogPosition", "MoneyFrame_Update", "MoneyFrame_UpdateMoney",
	"SmallMoneyFrame_OnLoad", "MoneyFrame_OnEvent", "OpenCoinPickupFrame", "ChatFrame_OnEvent", "ChatFrame_AddMessageGroup",
	"WorldStateAlwaysUpFrame_Update", "SendChatMessage"
}

local BLIZZARD_FRAMES = {
	"UIParent", "WorldFrame", "DEFAULT_CHAT_FRAME", "ChatFrame1", "ChatFrame2", "ChatFrame1EditBox", "ChatFrameMenuButton",
	"Minimap", "MinimapCluster", "MiniMapMailFrame", "MiniMapTracking", "MinimapZoneTextButton", "MinimapZoomIn", "MinimapZoomOut",
	"MiniMapWorldMapButton", "MiniMapBattlefieldFrame",
	"PlayerFrame", "TargetFrame", "PartyMemberFrame1", "PetFrame", "TargetofTargetFrame",
	"MainMenuBar", "MainMenuBarArtFrame", "ActionButton1", "BonusActionBarFrame", "BonusActionButton1",
	"MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight", "MultiBarBottomLeftButton1",
	"PetActionBarFrame", "ShapeshiftBarFrame",
	"CastingBarFrame", "CastingBarFlash", "CastingBarText", "CastingBarFrameStatusBar",
	"GroupLootFrame1", "QuestTimerFrame", "DurabilityFrame", "QuestWatchFrame", "TicketStatusFrame",
	"TemporaryEnchantFrame", "BuffFrame", "WorldStateAlwaysUpFrame", "TutorialFrameParent", "FramerateLabel",
	"CoinPickupFrame", "CoinPickupText", "DropDownList1", "DropDownList2", "DropDownList3",
	"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ContainerFrame1", "CharacterFrame", "SpellBookFrame",
	"WorldMapFrame", "FriendsFrame", "GameMenuFrame", "StaticPopup1", "MirrorTimer1", "LootFrame", "LootButton1",
	"MerchantFrame", "BankFrame", "TradeFrame", "QuestFrame", "GossipFrame", "TaxiFrame", "UIErrorsFrame",
	"ZoneTextFrame", "ScriptErrors", "ScriptErrors_Message"
}

local FRAME_METHODS = {
	"SetPoint", "ClearAllPoints", "SetAllPoints", "GetPoint", "GetNumPoints", "SetWidth", "SetHeight", "GetWidth", "GetHeight",
	"SetScale", "GetScale", "SetAlpha", "GetAlpha", "SetFrameStrata", "GetFrameStrata", "SetFrameLevel", "GetFrameLevel",
	"SetParent", "GetParent", "SetMovable", "IsMovable", "SetResizable", "StartMoving", "StopMovingOrSizing",
	"SetClampedToScreen", "SetUserPlaced", "IsUserPlaced", "EnableMouse", "EnableKeyboard", "EnableMouseWheel",
	"RegisterForDrag", "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "CreateFontString", "CreateTexture",
	"SetScript", "GetScript", "HookScript", "RegisterEvent", "UnregisterEvent", "UnregisterAllEvents", "IsEventRegistered",
	"Show", "Hide", "IsShown", "IsVisible", "GetName", "GetObjectType", "IsObjectType", "GetCenter", "GetLeft", "GetRight",
	"GetTop", "GetBottom", "SetToplevel", "Raise", "Lower", "SetID", "GetID", "SetHitRectInsets", "SetMinResize", "SetMaxResize"
}

local BUTTON_METHODS = {
	"SetNormalTexture", "SetPushedTexture", "SetHighlightTexture", "SetDisabledTexture", "GetNormalTexture",
	"GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture", "SetText", "GetText", "GetTextWidth",
	"GetFontString", "SetTextFontObject", "Enable", "Disable", "IsEnabled", "Click", "RegisterForClicks"
}

local FONTSTRING_METHODS = {
	"SetFont", "GetFont", "SetText", "GetText", "SetTextColor", "SetJustifyH", "SetJustifyV", "SetShadowColor",
	"SetShadowOffset", "GetStringWidth", "GetStringHeight", "SetWidth", "SetFontObject", "SetDrawLayer",
	"SetNonSpaceWrap", "SetSpacing", "SetAlpha"
}

local TEXTURE_METHODS = {
	"SetTexture", "GetTexture", "SetTexCoord", "SetVertexColor", "SetBlendMode", "SetDesaturated",
	"SetGradient", "SetGradientAlpha", "SetAllPoints", "SetDrawLayer", "SetAlpha"
}

local COOLDOWN_METHODS = {
	"SetSequence", "SetSequenceTime", "SetModel", "SetPosition", "SetModelScale", "SetLight", "SetCamera"
}

local MODEL_METHODS = {
	"SetSequence", "SetSequenceTime", "SetModel", "SetUnit", "SetCamera", "SetPosition", "SetFacing", "SetLight",
	"SetModelScale", "ClearModel"
}

local STATUSBAR_METHODS = {
	"SetStatusBarTexture", "GetStatusBarTexture", "SetStatusBarColor", "SetMinMaxValues", "GetMinMaxValues",
	"SetValue", "GetValue", "SetOrientation"
}

local EDITBOX_METHODS = {
	"SetText", "GetText", "SetMultiLine", "SetMaxLetters", "SetFocus", "ClearFocus", "HighlightText",
	"SetAutoFocus", "SetFontObject", "SetTextInsets", "SetNumeric", "Insert"
}

local SLIDER_METHODS = {
	"SetMinMaxValues", "SetValue", "GetValue", "SetValueStep", "SetOrientation", "SetThumbTexture"
}

local SCROLLFRAME_METHODS = {
	"SetScrollChild", "GetScrollChild", "SetHorizontalScroll", "SetVerticalScroll", "GetVerticalScroll",
	"GetVerticalScrollRange", "UpdateScrollChildRect"
}

local TOOLTIP_METHODS = {
	"SetOwner", "SetText", "AddLine", "AddDoubleLine", "SetUnit", "SetInventoryItem", "SetBagItem", "SetHyperlink",
	"SetSpell", "ClearLines", "NumLines", "SetPadding"
}

local SCRIPT_TYPES = {
	"OnShow", "OnHide", "OnEvent", "OnUpdate", "OnEnter", "OnLeave", "OnClick", "OnMouseDown", "OnMouseUp",
	"OnMouseWheel", "OnDragStart", "OnDragStop", "OnReceiveDrag", "OnValueChanged", "OnTextChanged",
	"OnEnterPressed", "OnEscapePressed", "OnEditFocusLost", "OnAnimFinished", "OnSizeChanged", "OnLoad"
}

local MANA_EVENT_NOTE = "UNIT_MANA, UNIT_POWER_UPDATE, UNIT_POWER, UNIT_MAXMANA, UNIT_MAXPOWER, UNIT_DISPLAYPOWER"

local function FirstValue(a, b, c, d)
	-- returns how many values a call produced, as text
	local n = 0
	if a ~= nil then n = 1 end
	if b ~= nil then n = 2 end
	if c ~= nil then n = 3 end
	if d ~= nil then n = 4 end
	return n
end

local function Run()
	out = {}

	local ok, d = pcall(date, "%Y-%m-%d %H:%M:%S")
	Add("KeldurnProbe 0.1  " .. (ok and d or "(no date)"))
	if IsAddOnLoaded and IsAddOnLoaded("!Compatibility") then
		Add("WARNING: !Compatibility is loaded. It overwrites natives, so 'present' may be wrong. Disable ElvUI and re-run.")
	end
	Add("_VERSION=" .. tostring(_VERSION) .. "  locale=" .. tostring(GetLocale and GetLocale()))

	-- 1. Lua functions
	Check("Lua/API functions", LUA_FUNCTIONS, "function")

	-- 2. Lua language features
	for i = 1, table.getn(LUA_FEATURES) do
		local item = LUA_FEATURES[i]
		local result
		if not loadstring then
			result = "loadstring missing"
		else
			local f, err = loadstring(item[2])
			if not f then
				result = "syntax rejected"
			else
				local ok2, value = pcall(f)
				if ok2 then
					result = "works -> " .. tostring(value)
				else
					result = "runtime error"
				end
			end
		end
		Add("Lua feature " .. item[1] .. ": " .. result)
	end

	-- 3. Constants and strings
	Check("Constants/strings", GLOBAL_VALUES, nil)
	Add("   UIDROPDOWNMENU_MAXLEVELS=" .. tostring(UIDROPDOWNMENU_MAXLEVELS)
		.. " MAXBUTTONS=" .. tostring(UIDROPDOWNMENU_MAXBUTTONS))

	-- 4. API functions
	Check("API functions", API_FUNCTIONS, "function")

	-- 5. Blizzard frames
	Check("Blizzard frames", BLIZZARD_FRAMES, "table")

	-- 6. Frame methods
	local frame = NewFrame("Frame")
	CheckMethods("Frame", frame, FRAME_METHODS)
	local ok3, fs = pcall(function() return frame:CreateFontString(nil, "ARTWORK") end)
	CheckMethods("FontString", ok3 and fs or nil, FONTSTRING_METHODS)
	local ok4, tex = pcall(function() return frame:CreateTexture(nil, "ARTWORK") end)
	CheckMethods("Texture", ok4 and tex or nil, TEXTURE_METHODS)
	CheckMethods("Button", NewFrame("Button"), BUTTON_METHODS)
	CheckMethods("Cooldown", NewFrame("Cooldown"), COOLDOWN_METHODS)
	CheckMethods("Model", NewFrame("Model"), MODEL_METHODS)
	CheckMethods("PlayerModel", NewFrame("PlayerModel"), MODEL_METHODS)
	CheckMethods("StatusBar", NewFrame("StatusBar"), STATUSBAR_METHODS)
	CheckMethods("EditBox", NewFrame("EditBox"), EDITBOX_METHODS)
	CheckMethods("Slider", NewFrame("Slider"), SLIDER_METHODS)
	CheckMethods("ScrollFrame", NewFrame("ScrollFrame"), SCROLLFRAME_METHODS)
	CheckMethods("GameTooltip (global)", GameTooltip, TOOLTIP_METHODS)

	-- 7. Script types accepted by SetScript
	if frame then
		local rejected = {}
		for i = 1, table.getn(SCRIPT_TYPES) do
			local okS = pcall(frame.SetScript, frame, SCRIPT_TYPES[i], function() end)
			if not okS then
				table.insert(rejected, SCRIPT_TYPES[i])
			end
			pcall(frame.SetScript, frame, SCRIPT_TYPES[i], nil)
		end
		Add("SetScript types: " .. tostring(table.getn(SCRIPT_TYPES) - table.getn(rejected)) .. "/"
			.. tostring(table.getn(SCRIPT_TYPES)) .. " accepted")
		if table.getn(rejected) > 0 then
			AddList("   REJECTED: ", rejected)
		end
	end

	-- 8. Handler dispatch
	Add("OnUpdate called " .. tostring(updateInfo.calls) .. "x: " .. tostring(updateInfo.info)
		.. " elapsed=" .. tostring(updateInfo.elapsed))
	Add("OnEvent first call: " .. tostring(eventFirst or "no event has fired yet"))

	-- 9. Event registration
	local rej = {}
	for name, err in pairs(eventRejected) do
		table.insert(rej, name)
	end
	if table.getn(rej) > 0 then
		AddList("Events REJECTED by RegisterEvent: ", rej)
	else
		Add("Events: all " .. tostring(table.getn(TRACKED_EVENTS)) .. " tracked names accepted by RegisterEvent")
	end
	Add("Play a bit (cast, take damage, change target), then /kprobe events. Mana events: " .. MANA_EVENT_NOTE)

	-- 10. Return values and live data
	local gc1, gc2 = nil, nil
	if gcinfo then gc1, gc2 = gcinfo() end
	Add("gcinfo returns " .. tostring(FirstValue(gc1, gc2)) .. " value(s)")
	if UnitPowerType then
		local pt1, pt2 = UnitPowerType("player")
		Add("UnitPowerType('player') -> " .. tostring(pt1) .. ", " .. tostring(pt2))
	end
	if UnitMana and UnitManaMax then
		Add("UnitMana/UnitManaMax('player') -> " .. tostring(UnitMana("player")) .. " / " .. tostring(UnitManaMax("player")))
	end
	if GetNetStats then
		local n1, n2, n3, n4 = GetNetStats()
		Add("GetNetStats returns " .. tostring(FirstValue(n1, n2, n3, n4)) .. " value(s)")
	end
	if GetAddOnMemoryUsage then
		local m1, m2, m3 = GetAddOnMemoryUsage("KeldurnProbe")
		Add("GetAddOnMemoryUsage returns " .. tostring(FirstValue(m1, m2, m3)) .. " value(s)")
	end

	pages = math.floor((table.getn(out) + LINES_PER_PAGE - 1) / LINES_PER_PAGE)
	if pages < 1 then pages = 1 end

	local okSave = pcall(function()
		KeldurnProbeDB = { report = out, when = ok and d or "?" }
	end)
	return okSave
end

local function ShowPage(page)
	if page < 1 then page = 1 end
	if page > pages then page = pages end
	Say("--- page " .. tostring(page) .. "/" .. tostring(pages) .. " (/kprobe N for other pages) ---")
	local first = (page - 1) * LINES_PER_PAGE + 1
	local last = page * LINES_PER_PAGE
	if last > table.getn(out) then last = table.getn(out) end
	for i = first, last do
		Say(out[i])
	end
end

local function ShowEvents()
	local names = {}
	for name, count in pairs(eventCounts) do
		table.insert(names, name .. "=" .. tostring(count))
	end
	table.sort(names)
	if table.getn(names) == 0 then
		Say("No tracked events have fired yet.")
		return
	end
	Say("Events fired so far (name=count):")
	local line = ""
	for i = 1, table.getn(names) do
		if string.len(line) + string.len(names[i]) > 170 then
			Say(line)
			line = ""
		end
		line = line .. names[i] .. "  "
	end
	if line ~= "" then Say(line) end
	Say("OnEvent first call: " .. tostring(eventFirst))
end

SLASH_KELDURNPROBE1 = "/kprobe"
SlashCmdList["KELDURNPROBE"] = function(msg)
	msg = msg or ""
	if msg == "events" then
		ShowEvents()
		return
	end
	local page = tonumber(msg)
	if page and table.getn(out) > 0 then
		ShowPage(page)
		return
	end
	local okRun, err = pcall(Run)
	if not okRun then
		Say("probe failed: " .. tostring(err))
		return
	end
	ShowPage(1)
end

Say("loaded. Type /kprobe")
