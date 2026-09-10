-- shim.lua
-- LinoriaLib API surface over Thugsense. Consolidated final version.

local Thug = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Thugsense/Library.lua"
))()

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

getgenv().Toggles = {}
getgenv().Options = {}
local Toggles, Options = getgenv().Toggles, getgenv().Options

-- Utilities
local function copy(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = copy(v) end
    return o
end
local function fire(list, ...)
    for _, cb in ipairs(list) do pcall(cb, ...) end
end
local function resolveDefault(opts)
    local d = opts.Default
    if type(d) == "number" and opts.Values then return opts.Values[d] end
    return d
end
local function toEnum(name)
    if not name or name == "None" then return nil end
    local ok, e = pcall(function() return Enum.KeyCode[name] end)
    if ok and e then return e end
    ok, e = pcall(function() return Enum.UserInputType[name] end)
    if ok then return e end
    return nil
end

-- Keybind registry
local Keybinds = {}
local function registerKeybind(proxy) table.insert(Keybinds, proxy) end

local function matchInput(kp, input)
    local v = kp.Value
    if type(v) == "string" then
        return input.KeyCode.Name == v or input.UserInputType.Name == v
    elseif typeof(v) == "EnumItem" then
        return input.KeyCode == v or input.UserInputType == v
    end
    return false
end

UIS.InputBegan:Connect(function(input)
    if UIS:GetFocusedTextBox() then return end
    for _, kp in ipairs(Keybinds) do
        if not kp._capturing and matchInput(kp, input) then
            if kp.Mode == "Toggle" then
                kp._state = not kp._state
            elseif kp.Mode == "Hold" or kp.Mode == "Always" then
                kp._state = true
            end
            if kp._syncToggle then
                pcall(function() kp._syncToggle:SetValue(kp._state) end)
            end
            fire(kp._callbacks, kp._state)
            fire(kp._onClick)
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    for _, kp in ipairs(Keybinds) do
        if kp.Mode ~= "Hold" then continue end
        if matchInput(kp, input) then
            kp._state = false
            if kp._syncToggle then
                pcall(function() kp._syncToggle:SetValue(false) end)
            end
            fire(kp._callbacks, false)
        end
    end
end)

-- Element factories (forward-declare for recursion)
local makeColorPicker, makeKeyPicker

makeKeyPicker = function(flag, section, opts)
    opts = opts or {}
    local kp = {
        Value = opts.Default or "None",
        Mode = opts.Mode or "Toggle",
        _state = false,
        _callbacks = {},   -- fires on key press with state
        _onClick = {},     -- fires on key press, no args
        _onChanged = {},   -- fires on value change (rebind)
        _syncToggle = nil,
        _capturing = false,
        _button = nil,
    }
    if opts.Callback then table.insert(kp._callbacks, opts.Callback) end
    registerKeybind(kp)

    -- Always render a visible bind button so the user can rebind at will
    if section then
        local btn = section:Button({
            Name = "Bind: " .. tostring(kp.Value),
            Callback = function()
                if kp._capturing then return end
                kp._capturing = true
                pcall(function() btn.Elements.Text.Instance.Text = "Bind: [press key...]" end)
                task.delay(0.25, function()
                    local captured = false
                    local conn
                    conn = UIS.InputBegan:Connect(function(input)
                        if input.UserInputType == Enum.UserInputType.Keyboard then
                            kp:SetValue(input.KeyCode)
                            captured = true
                        elseif input.UserInputType == Enum.UserInputType.MouseButton1
                            or input.UserInputType == Enum.UserInputType.MouseButton2
                            or input.UserInputType == Enum.UserInputType.MouseButton3 then
                            kp:SetValue(input.UserInputType)
                            captured = true
                        end
                        if captured then
                            kp._capturing = false
                            conn:Disconnect()
                        end
                    end)
                    task.delay(5, function()
                        if not captured then
                            kp._capturing = false
                            pcall(function() conn:Disconnect() end)
                            pcall(function() btn.Elements.Text.Instance.Text = "Bind: " .. kp.Value end)
                        end
                    end)
                end)
            end,
        })
        kp._button = btn
    end

    function kp:GetState() return self._state end
    function kp:SetValue(k)
        local newVal
        if typeof(k) == "EnumItem" then newVal = k.Name
        elseif k == nil then newVal = "None"
        else newVal = tostring(k) end
        self.Value = newVal
        if kp._button then
            pcall(function() kp._button.Elements.Text.Instance.Text = "Bind: " .. newVal end)
        end
        fire(self._onChanged, newVal)
    end
    function kp:OnChanged(fn) table.insert(self._onChanged, fn) end
    function kp:OnClick(fn) table.insert(self._onClick, fn) end

    Options[flag] = kp
    return kp
end

makeColorPicker = function(flag, section, parentLabel, opts)
    opts = opts or {}
    local cp = {
        Value = opts.Default or Color3.fromRGB(255,255,255),
        _callbacks = {},
        _section = section,
    }
    local handle = parentLabel:Colorpicker({
        Name = opts.Title or flag,
        Flag = flag .. "_thug",
        Default = cp.Value,
        Callback = function(c)
            cp.Value = c
            fire(cp._callbacks, c)
        end,
    })
    function cp:SetValueRGB(c)
        self.Value = c
        pcall(function() handle:Set(c) end)
        fire(self._callbacks, c)
    end
    function cp:OnChanged(fn) table.insert(self._callbacks, fn) end
    function cp:AddColorPicker(cf, co)
        local lbl = self._section:Label({ Name = (co and co.Title) or cf, Alignment = "Left" })
        return makeColorPicker(cf, self._section, lbl, co)
    end
    function cp:AddKeyPicker(kf, ko)
        return makeKeyPicker(kf, self._section, ko)
    end
    if opts.Callback then table.insert(cp._callbacks, opts.Callback) end
    Options[flag] = cp
    return cp
end

local function makeToggle(flag, section, opts)
    opts = opts or {}
    local t = { Value = opts.Default == true, _callbacks = {} }
    local setting = false
    local handle = section:Toggle({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Default = t.Value,
        Callback = function(v)
            if setting then return end
            t.Value = v
            fire(t._callbacks, v)
        end,
    })

    function t:SetValue(v)
        v = not not v
        if self.Value == v then return end
        setting = true
        self.Value = v
        pcall(function() handle:Set(v) end)
        setting = false
        fire(self._callbacks, v)
    end
    function t:OnChanged(fn) table.insert(self._callbacks, fn) end
    function t:SetText(s)
        pcall(function() handle.Elements.Text.Instance.Text = s end)
    end
    function t:AddKeyPicker(kf, ko)
        local kp = makeKeyPicker(kf, section, ko)
        if ko and ko.SyncToggleState then kp._syncToggle = t end
        return kp
    end
    function t:AddColorPicker(cf, co)
        local lbl = section:Label({ Name = (co and co.Title) or cf, Alignment = "Left" })
        return makeColorPicker(cf, section, lbl, co)
    end

    if opts.Callback then table.insert(t._callbacks, opts.Callback) end

    -- Register BEFORE firing initial callback
    Toggles[flag] = t
    Options[flag] = t
    if opts.Default ~= nil then fire(t._callbacks, t.Value) end
    return t
end

local function makeSlider(flag, section, opts)
    opts = opts or {}
    local decimals = opts.Rounding
    if decimals == nil or decimals == 0 then decimals = 2 end

    local s = { Value = opts.Default or 0, _callbacks = {} }
    local handle = section:Slider({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Min = opts.Min or 0,
        Max = opts.Max or 100,
        Default = opts.Default or 0,
        Decimals = decimals,
        Suffix = opts.Suffix or "",
        Compact = opts.Compact or false,
        Callback = function(v)
            s.Value = v
            fire(s._callbacks, v)
        end,
    })
    function s:SetValue(v)
        self.Value = v
        pcall(function() handle:Set(v) end)
        fire(self._callbacks, v)
    end
    function s:OnChanged(fn) table.insert(self._callbacks, fn) end
    if opts.Callback then table.insert(s._callbacks, opts.Callback) end
    Options[flag] = s
    return s
end

local function makeDropdown(flag, section, opts)
    opts = opts or {}
    local values = copy(opts.Values or {})
    local d = { Value = resolveDefault(opts), _callbacks = {}, _values = values }
    local handle = section:Dropdown({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Items = values,
        Default = d.Value,
        Multi = opts.Multi or false,
        Callback = function(v)
            d.Value = v
            fire(d._callbacks, v)
        end,
    })

    if opts.SpecialType == "Player" then
        values = {}
        for _, p in ipairs(Players:GetPlayers()) do table.insert(values, p.Name) end
        d._values = values
        pcall(function() handle:Refresh(values) end)
        Players.PlayerAdded:Connect(function(p)
            table.insert(values, p.Name)
            pcall(function() handle:Refresh(values) end)
        end)
        Players.PlayerRemoving:Connect(function(p)
            for i, n in ipairs(values) do
                if n == p.Name then table.remove(values, i) break end
            end
            pcall(function() handle:Refresh(values) end)
        end)
    end

    function d:SetValue(v)
        self.Value = v
        pcall(function() handle:Set(v) end)
        fire(self._callbacks, v)
    end
    function d:SetValues(list)
        self._values = list
        pcall(function() handle:Refresh(list) end)
    end
    function d:GetValues() return self._values end
    function d:OnChanged(fn) table.insert(self._callbacks, fn) end
    if opts.Callback then table.insert(d._callbacks, opts.Callback) end
    Options[flag] = d
    return d
end

local function makeInput(flag, section, opts)
    opts = opts or {}
    local i = { Value = opts.Default or "", _callbacks = {} }
    local handle = section:Textbox({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Default = opts.Default or "",
        Placeholder = opts.Placeholder or "",
        Callback = function(v)
            i.Value = v
            fire(i._callbacks, v)
        end,
    })
    function i:SetValue(v)
        self.Value = v
        pcall(function() handle:Set(v) end)
        fire(self._callbacks, v)
    end
    function i:OnChanged(fn) table.insert(self._callbacks, fn) end
    if opts.Callback then table.insert(i._callbacks, opts.Callback) end
    Options[flag] = i
    return i
end

local function makeLabelProxy(section, text)
    local raw = section:Label({ Name = tostring(text), Alignment = "Left" })
    local proxy = {}
    function proxy:AddColorPicker(cf, co)
        return makeColorPicker(cf, section, raw, co)
    end
    function proxy:AddKeyPicker(kf, ko)
        return makeKeyPicker(kf, section, ko)
    end
    return proxy
end

local function makeGroupbox(page, side, title)
    local section = page:Section({ Name = title or "Group", Side = side })
    local gb = {}

    function gb:AddToggle(flag, opts)   return makeToggle(flag, section, opts) end
    function gb:AddSlider(flag, opts)   return makeSlider(flag, section, opts) end
    function gb:AddDropdown(flag, opts) return makeDropdown(flag, section, opts) end
    function gb:AddInput(flag, opts)    return makeInput(flag, section, opts) end

    -- Accepts AddButton({Text=..., Func=...}) AND AddButton("Name", fn)
    function gb:AddButton(a, b)
        local name, cb
        if type(a) == "table" then
            name = a.Text or "Button"
            cb = a.Func
        else
            name = a or "Button"
            cb = b
        end
        section:Button({
            Name = name,
            Callback = function() if cb then pcall(cb) end end,
        })
    end

    function gb:AddLabel(text) return makeLabelProxy(section, text) end
    function gb:AddDivider() section:Divider() end
    return gb
end

local function makeTab(page)
    local tab = {}
    function tab:AddLeftGroupbox(t)  return makeGroupbox(page, 1, t) end
    function tab:AddRightGroupbox(t) return makeGroupbox(page, 2, t) end
    function tab:AddLeftTabbox()
        local box = {}
        function box:AddTab(name) return makeGroupbox(page, 1, name) end
        return box
    end
    return tab
end

-- Watermark label finder
local _cachedWatermarkLabel = nil
local function findWatermarkLabel()
    if not Thug.Holder or not Thug.Holder.Instance then return nil end
    for _, child in ipairs(Thug.Holder.Instance:GetChildren()) do
        if child:IsA("Frame") and child.Position == UDim2.new(0, 15, 0, 15) then
            for _, sub in ipairs(child:GetChildren()) do
                if sub:IsA("TextLabel") then return sub end
            end
        end
    end
    return nil
end

-- Public Shim object
local ThugWindow, Watermark, KeybindList
local unloadCB = {}
local Shim = {}

function Shim:CreateWindow(opts)
    opts = opts or {}
    ThugWindow = Thug:Window({
        Name = opts.Title or "Menu",
        Size = UDim2.new(0, 500, 0, 600),
        FadeSpeed = 0.25,
    })
    Watermark   = Thug:Watermark(opts.Title or "Menu")
    KeybindList = Thug:KeybindList()
    Watermark:SetVisibility(false)
    KeybindList:SetVisibility(false)

    task.defer(function()
        _cachedWatermarkLabel = findWatermarkLabel()
    end)

    local api = {}
    function api:AddTab(name)
        local page = ThugWindow:Page({ Name = name, Columns = 2, Subtabs = false })
        return makeTab(page)
    end
    return api
end

function Shim:Notify(text, duration)
    Thug:Notification(tostring(text), duration or 3, Thug.Theme.Accent)
end

function Shim:SetWatermark(text)
    if not Watermark then return end
    Watermark:SetVisibility(true)
    if not _cachedWatermarkLabel or not _cachedWatermarkLabel.Parent then
        _cachedWatermarkLabel = findWatermarkLabel()
    end
    if _cachedWatermarkLabel then
        pcall(function() _cachedWatermarkLabel.Text = tostring(text) end)
    end
end

function Shim:SetWatermarkVisibility(bool)
    if Watermark then Watermark:SetVisibility(bool) end
end

function Shim:OnUnload(fn) table.insert(unloadCB, fn) end

function Shim:Unload()
    for _, fn in ipairs(unloadCB) do pcall(fn) end
    Shim.Unloaded = true
    Thug:Unload()
end

Shim.KeybindFrame = nil
Shim.ToggleKeybind = nil

getgenv().Library = Shim

-- Config manager stubs
local SaveManagerShim = {}
function SaveManagerShim:SetLibrary() end
function SaveManagerShim:SetFolder() end
function SaveManagerShim:BuildConfigSection() end
function SaveManagerShim:IgnoreThemeSettings() end
function SaveManagerShim:SetIgnoreIndexes() end
function SaveManagerShim:LoadAutoloadConfig()
    if Thug.Init then pcall(function() Thug:Init() end) end
end
getgenv().SaveManager = SaveManagerShim

local ThemeManagerShim = {}
function ThemeManagerShim:SetLibrary() end
function ThemeManagerShim:SetFolder() end
function ThemeManagerShim:ApplyToTab() end
getgenv().ThemeManager = ThemeManagerShim

-- Sync menu keybind after MenuKeybind is created
task.spawn(function()
    while not Options.MenuKeybind do task.wait(0.1) end
    local function sync()
        local v = Options.MenuKeybind.Value
        local e = toEnum(v)
        if e then Thug.MenuKeybind = e end
    end
    sync()
    Options.MenuKeybind:OnChanged(sync)
end)

-- Fallback Init
if not Thug.Init then
    function Thug:Init()
        local path = Thug.Folders.Directory .. "/autoload.json"
        if isfile(path) then
            local content = readfile(path)
            if content ~= "" then pcall(function() Thug:LoadConfig(content) end) end
        end
    end
end

-- Bootstrap Thugsense settings tab
pcall(function()
    Thug:CreateSettingsPage(ThugWindow, Watermark, KeybindList)
end)

return Shim
