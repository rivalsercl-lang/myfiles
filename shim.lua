-- shim.lua
-- LinoriaLib API surface over Thugsense. Native inline keybinds, working menu key.

local Thug = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Thugsense/Library.lua"
))()

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

-- ==================== Performance: shorten tweens (no override) ====================
-- The library uses Tween.Time as the default duration for FadeItem and all
-- UI tweens. 0.3 (default) causes per-element animation lag on tab switches.
-- 0.1 keeps transitions snappy without freezing the Debounce-clear callback.
Thug.Tween.Time = 0.1

-- The library's menu check is `tostring(Input.KeyCode) == Library.MenuKeybind`,
-- so MenuKeybind must be a STRING, not an EnumItem.
Thug.MenuKeybind = "Enum.KeyCode.End"

getgenv().Toggles = {}
getgenv().Options = {}
local Toggles, Options = getgenv().Toggles, getgenv().Options

-- ==================== Utilities ====================
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
local function toEnumItem(key)
    if typeof(key) == "EnumItem" then return key end
    if type(key) ~= "string" or key == "None" or key == "" then return nil end
    local ok, e = pcall(function() return Enum.KeyCode[key] end)
    if ok and e then return e end
    ok, e = pcall(function() return Enum.UserInputType[key] end)
    if ok and e then return e end
    return nil
end
local function shortName(s)
    if not s then return nil end
    s = tostring(s)
    return s:match("KeyCode%.(.+)$") or s:match("UserInputType%.(.+)$") or s
end

-- ==================== KeyPicker proxy ====================
local function makeKeyPickerProxy(flag, opts)
    opts = opts or {}
    local defaultDisplay = "None"
    if flag == "MenuKeybind" then
        local e = toEnumItem(opts.Default) or Enum.KeyCode.End
        defaultDisplay = e.Name
    end

    local kp = {
        Value = defaultDisplay,
        Mode = opts.Mode or "Toggle",
        _state = false,
        _callbacks = {},
        _onClick = {},
        _onChanged = {},
        _syncToggle = nil,
        _ext = nil,
    }
    if opts.Callback then table.insert(kp._callbacks, opts.Callback) end

    function kp:GetState() return self._state end
    function kp:SetValue(k)
        local e = toEnumItem(k)
        if k == nil or k == "None" or k == "" then
            self.Value = "None"
        elseif e then
            self.Value = e.Name
        else
            self.Value = tostring(k)
        end
        if self._ext and e then
            pcall(function() self._ext:Set(e) end)
        end
        fire(self._onChanged, self.Value)
    end
    function kp:OnChanged(fn) table.insert(self._onChanged, fn) end
    function kp:OnClick(fn) table.insert(self._onClick, fn) end

    Options[flag] = kp
    return kp
end

local function attachNativeKeybind(handle, flag, opts, kp)
    opts = opts or {}

    local initialEnum
    if flag == "MenuKeybind" then
        initialEnum = toEnumItem(opts.Default) or Enum.KeyCode.End
    else
        initialEnum = Enum.KeyCode.Backspace  -- library "no key" sentinel
    end

    local ok, _, ext = pcall(function()
        return handle:Keybind({
            Name = opts.Text or "Bind",
            Flag = flag .. "_thug",
            Default = initialEnum,
            Mode = opts.Mode or "Toggle",
            Callback = function(toggled)
                kp._state = toggled
                if kp._syncToggle and kp.Mode == "Toggle" then
                    pcall(function() kp._syncToggle:SetValue(toggled) end)
                end
                fire(kp._callbacks, toggled)
                fire(kp._onClick)
            end,
        })
    end)

    if not ok or not ext then return end
    kp._ext = ext

    if ext.Key then
        local display = shortName(ext.Key) or kp.Value
        if display == "Backspace" then display = "None" end
        kp.Value = display
    end

    if flag == "MenuKeybind" and ext.Key then
        Thug.MenuKeybind = ext.Key
    end

    task.spawn(function()
        local lastKey = ext.Key
        local lastMode = ext.Mode
        while task.wait(0.2) do
            if not kp._ext then break end
            local k = kp._ext.Key
            local m = kp._ext.Mode
            if k and k ~= lastKey then
                lastKey = k
                local display = shortName(k) or k
                if display == "Backspace" then display = "None" end
                kp.Value = display
                if flag == "MenuKeybind" then
                    Thug.MenuKeybind = k
                end
                fire(kp._onChanged, display)
            end
            if m and m ~= lastMode then
                lastMode = m
                kp.Mode = m
            end
        end
    end)
end

-- ==================== Colorpicker proxy ====================
local makeColorPicker

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
        return makeKeyPickerProxy(kf, ko)
    end
    if opts.Callback then table.insert(cp._callbacks, opts.Callback) end
    Options[flag] = cp
    return cp
end

-- ==================== Toggle proxy ====================
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
        ko = ko or {}
        local kp = makeKeyPickerProxy(kf, ko)
        if ko.SyncToggleState then kp._syncToggle = t end
        attachNativeKeybind(handle, kf, {
            Text = ko.Text or (opts.Text or flag),
            Default = ko.Default,
            Mode = ko.Mode,
        }, kp)
        return kp
    end
    t.Keybind = t.AddKeyPicker

    function t:AddColorPicker(cf, co)
        local lbl = section:Label({ Name = (co and co.Title) or cf, Alignment = "Left" })
        return makeColorPicker(cf, section, lbl, co)
    end
    t.Colorpicker = t.AddColorPicker

    if opts.Callback then table.insert(t._callbacks, opts.Callback) end
    Toggles[flag] = t
    Options[flag] = t
    if opts.Default ~= nil then fire(t._callbacks, t.Value) end
    return t
end

-- ==================== Slider proxy ====================
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

-- ==================== Dropdown proxy ====================
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

-- ==================== Textbox proxy ====================
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

-- ==================== Label proxy ====================
local function makeLabelProxy(section, text)
    local labelObj = section:Label({ Name = tostring(text), Alignment = "Left" })
    local proxy = {}

    function proxy:AddColorPicker(cf, co)
        return makeColorPicker(cf, section, labelObj, co)
    end
    proxy.Colorpicker = proxy.AddColorPicker

    function proxy:AddKeyPicker(kf, ko)
        ko = ko or {}
        local kp = makeKeyPickerProxy(kf, ko)
        attachNativeKeybind(labelObj, kf, {
            Text = ko.Text or tostring(text),
            Default = ko.Default,
            Mode = ko.Mode,
        }, kp)
        return kp
    end
    proxy.Keybind = proxy.AddKeyPicker

    return proxy
end

-- ==================== Groupbox / Tab ====================
local function makeGroupbox(page, side, title)
    local section = page:Section({ Name = title or "Group", Side = side })
    local gb = {}

    function gb:AddToggle(flag, opts)   return makeToggle(flag, section, opts) end
    function gb:AddSlider(flag, opts)   return makeSlider(flag, section, opts) end
    function gb:AddDropdown(flag, opts) return makeDropdown(flag, section, opts) end
    function gb:AddInput(flag, opts)    return makeInput(flag, section, opts) end

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

-- ==================== Watermark ====================
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

-- ==================== Shim object ====================
local ThugWindow, Watermark, KeybindList
local unloadCB = {}
local Shim = {}

function Shim:CreateWindow(opts)
    opts = opts or {}
    ThugWindow = Thug:Window({
        Name = opts.Title or "Menu",
        Size = UDim2.new(0, 500, 0, 600),
        FadeSpeed = 0.1,
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

return Shim
