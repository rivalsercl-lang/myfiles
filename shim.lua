-- shim.lua
-- Compatibility shim: exposes LinoriaLib API surface over Thugsense.

local Thug = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Thugsense/Library.lua"
))()

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

getgenv().Toggles = {}
getgenv().Options = {}
local Toggles, Options = getgenv().Toggles, getgenv().Options

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

local Keybinds = {}
local function registerKeybind(proxy) table.insert(Keybinds, proxy) end

UIS.InputBegan:Connect(function(input)
    if UIS:GetFocusedTextBox() then return end
    for _, kp in ipairs(Keybinds) do
        local match = false
        local v = kp.Value
        if type(v) == "string" then
            if input.KeyCode.Name == v or input.UserInputType.Name == v then match = true end
        elseif typeof(v) == "EnumItem" then
            match = (input.KeyCode == v) or (input.UserInputType == v)
        end
        if match then
            if kp.Mode == "Toggle" then kp._state = not kp._state
            elseif kp.Mode == "Hold" or kp.Mode == "Always" then kp._state = true end
            fire(kp._callbacks, kp._state)
            fire(kp._onClick)
        end
    end
end)

UIS.InputEnded:Connect(function(input)
    for _, kp in ipairs(Keybinds) do
        if kp.Mode ~= "Hold" then continue end
        local v = kp.Value
        local match = false
        if type(v) == "string" then
            if input.KeyCode.Name == v or input.UserInputType.Name == v then match = true end
        elseif typeof(v) == "EnumItem" then
            match = (input.KeyCode == v) or (input.UserInputType == v)
        end
        if match then
            kp._state = false
            fire(kp._callbacks, false)
        end
    end
end)

local function makeKeyPicker(flag, opts)
    local kp = {
        Value = opts.Default or "None",
        Mode = opts.Mode or "Toggle",
        _state = false,
        _callbacks = {},
        _onClick = {},
    }
    if opts.Callback then table.insert(kp._callbacks, opts.Callback) end
    registerKeybind(kp)

    function kp:GetState() return self._state end
    function kp:SetValue(k)
        if typeof(k) == "EnumItem" then self.Value = k.Name
        elseif k == nil then self.Value = "None"
        else self.Value = tostring(k) end
    end
    function kp:OnChanged(fn) table.insert(self._callbacks, fn) end
    function kp:OnClick(fn) table.insert(self._onClick, fn) end

    Options[flag] = kp
    return kp
end

local function makeColorPicker(flag, parentLabel, opts)
    local cp = { Value = opts.Default or Color3.fromRGB(255,255,255), _callbacks = {} }
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
    if opts.Callback then table.insert(cp._callbacks, opts.Callback) end
    Options[flag] = cp
    return cp
end

local function makeToggle(flag, section, opts)
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
    function t:AddKeyPicker(kf, ko) return makeKeyPicker(kf, ko or {}) end
    function t:AddColorPicker(cf, co)
        local lbl = section:Label({ Name = (co and co.Title) or cf, Alignment = "Left" })
        return makeColorPicker(cf, lbl, co or {})
    end

    if opts.Callback then table.insert(t._callbacks, opts.Callback) end
    if opts.Default ~= nil then fire(t._callbacks, t.Value) end

    Toggles[flag] = t
    Options[flag] = t
    return t
end

local function makeSlider(flag, section, opts)
    local s = { Value = opts.Default or 0, _callbacks = {} }
    local handle = section:Slider({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Min = opts.Min or 0,
        Max = opts.Max or 100,
        Default = opts.Default or 0,
        Decimals = opts.Rounding or 2,
        Suffix = opts.Suffix or "",
        Compact = opts.Compact or false,
        Callback = function(v) s.Value = v; fire(s._callbacks, v) end,
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
    local values = copy(opts.Values or {})
    if opts.SpecialType == "Player" then
        values = {}
        for _, p in ipairs(Players:GetPlayers()) do table.insert(values, p.Name) end
        Players.PlayerAdded:Connect(function(p) table.insert(values, p.Name) end)
        Players.PlayerRemoving:Connect(function(p)
            for i, n in ipairs(values) do if n == p.Name then table.remove(values, i) break end end
        end)
    end

    local d = { Value = resolveDefault(opts), _callbacks = {}, _values = values }
    local handle = section:Dropdown({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Items = values,
        Default = d.Value,
        Multi = opts.Multi or false,
        Callback = function(v) d.Value = v; fire(d._callbacks, v) end,
    })
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
    local i = { Value = opts.Default or "", _callbacks = {} }
    local handle = section:Textbox({
        Name = opts.Text or flag,
        Flag = flag .. "_thug",
        Default = opts.Default or "",
        Placeholder = opts.Placeholder or "",
        Callback = function(v) i.Value = v; fire(i._callbacks, v) end,
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
        return makeColorPicker(cf, raw, co or {})
    end
    return proxy
end

local function makeGroupbox(page, side, title)
    local section = page:Section({ Name = title or "Group", Side = side })
    local gb = {}
    function gb:AddToggle(flag, opts)   return makeToggle(flag, section, opts or {}) end
    function gb:AddSlider(flag, opts)   return makeSlider(flag, section, opts or {}) end
    function gb:AddDropdown(flag, opts) return makeDropdown(flag, section, opts or {}) end
    function gb:AddInput(flag, opts)    return makeInput(flag, section, opts or {}) end
    function gb:AddButton(opts)
        section:Button({
            Name = opts.Text or "Button",
            Callback = function() if opts.Func then pcall(opts.Func) end end,
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

local ThugWindow, Watermark, KeybindList
local unloadCB = {}
local Shim = {}

function Shim:CreateWindow(opts)
    ThugWindow = Thug:Window({
        Name = opts.Title or "Menu",
        Size = UDim2.new(0, 500, 0, 600),
        FadeSpeed = 0.25,
    })
    Watermark   = Thug:Watermark(opts.Title or "Menu")
    KeybindList = Thug:KeybindList()
    Watermark:SetVisibility(false)
    KeybindList:SetVisibility(false)

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
    if Watermark then
        pcall(function()
            if Watermark.Elements and Watermark.Elements.Title then
                Watermark.Elements.Title.Instance.Text = tostring(text)
            end
        end)
        Watermark:SetVisibility(true)
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

if not Thug.Init then
    function Thug:Init()
        local path = Thug.Folders.Directory .. "/autoload.json"
        if isfile(path) then
            local content = readfile(path)
            if content ~= "" then pcall(function() Thug:LoadConfig(content) end) end
        end
    end
end

pcall(function()
    Thug:CreateSettingsPage(ThugWindow, Watermark, KeybindList)
end)

return Shim
