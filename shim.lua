-- shim.lua
-- LinoriaLib API surface over Thugsense. Inline keybinds, own menu handler.

local Thug = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/sametexe001/sametlibs/refs/heads/main/Thugsense/Library.lua"
))()

local UIS = game:GetService("UserInputService")
local Players = game:GetService("Players")

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
local function shortName(enumOrString)
    if not enumOrString then return nil end
    local s = tostring(enumOrString)
    return s:match("KeyCode%.(.+)$") or s:match("UserInputType%.(.+)$") or s
end

-- ==================== Keybind registry ====================
local Keybinds = {}
local function registerKeybind(proxy) table.insert(Keybinds, proxy) end

local function matchInput(kp, input)
    local v = kp.Value
    if v == "None" or v == nil then return false end
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
        if kp._capturing then continue end
        if matchInput(kp, input) then
            if kp.Mode == "Toggle" then
                kp._state = not kp._state
            elseif kp.Mode == "Hold" or kp.Mode == "Always" then
                kp._state = true
            end
            if kp._syncToggle and kp.Mode == "Toggle" then
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

-- ==================== Inline bind box ====================
local function createBindBox(parentInstance, kp)
    local bindBtn = Instance.new("TextButton")
    bindBtn.Name = "\0"
    bindBtn.AnchorPoint = Vector2.new(1, 0.5)
    bindBtn.Position = UDim2.new(1, -4, 0.5, 0)
    bindBtn.Size = UDim2.new(0, 26, 0, 12)
    bindBtn.BackgroundColor3 = Thug.Theme.Element
    bindBtn.BorderSizePixel = 0
    bindBtn.AutoButtonColor = false
    bindBtn.Text = ""
    bindBtn.ZIndex = 5
    bindBtn.Parent = parentInstance

    local stroke = Instance.new("UIStroke")
    stroke.Color = Thug.Theme.Outline
    stroke.Thickness = 1
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = bindBtn

    local label = Instance.new("TextLabel")
    label.Name = "\0"
    label.BackgroundTransparency = 1
    label.Size = UDim2.new(1, 0, 1, 0)
    label.FontFace = Thug.Font or Font.new("rbxasset://fonts/families/SourceSansPro.json")
    label.TextColor3 = Thug.Theme.Text
    label.TextSize = 10
    label.Text = kp.Value
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.ZIndex = 6
    label.Parent = bindBtn

    local function refresh()
        pcall(function()
            label.Text = kp.Value
            if kp._capturing then
                bindBtn.BackgroundColor3 = Thug.Theme.Accent
                label.TextColor3 = Thug.Theme.Background
            else
                bindBtn.BackgroundColor3 = Thug.Theme.Element
                label.TextColor3 = Thug.Theme.Text
            end
        end)
    end

    local function startCapture()
        if kp._capturing then return end
        kp._capturing = true
        refresh()
        local captured = false
        local conn
        conn = UIS.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Keyboard then
                kp:SetValue(input.KeyCode)
                captured = true
                conn:Disconnect()
            elseif input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.MouseButton2
                or input.UserInputType == Enum.UserInputType.MouseButton3 then
                kp:SetValue(input.UserInputType)
                captured = true
                conn:Disconnect()
            end
        end)
        task.delay(5, function()
            if not captured then pcall(function() conn:Disconnect() end) end
            kp._capturing = false
            refresh()
        end)
    end

    bindBtn.Activated:Connect(startCapture)
    bindBtn.MouseEnter:Connect(function()
        if not kp._capturing then
            bindBtn.BackgroundColor3 = Thug.Theme["Hovered Element"]
        end
    end)
    bindBtn.MouseLeave:Connect(function()
        if not kp._capturing then
            bindBtn.BackgroundColor3 = Thug.Theme.Element
        end
    end)

    kp._bindLabel = label
    kp._bindBtn = bindBtn
end

-- ==================== KeyPicker proxy ====================
local function makeKeyPickerProxy(flag, opts)
    opts = opts or {}
    local defaultVal = "None"
    if flag == "MenuKeybind" then
        defaultVal = opts.Default or "End"
    end

    local kp = {
        Value = defaultVal,
        Mode = opts.Mode or "Toggle",
        _state = false,
        _callbacks = {},
        _onClick = {},
        _onChanged = {},
        _syncToggle = nil,
        _capturing = false,
        _bindLabel = nil,
        _bindBtn = nil,
    }
    if opts.Callback then table.insert(kp._callbacks, opts.Callback) end

    function kp:GetState() return self._state end
    function kp:SetValue(k)
        local short
        if k == nil or k == "None" or k == "" then
            short = "None"
        elseif typeof(k) == "EnumItem" then
            short = shortName(k)
        else
            short = tostring(k)
        end
        self.Value = short
        if self._bindLabel then
            pcall(function() self._bindLabel.Text = short end)
        end
        fire(self._onChanged, short)
    end
    function kp:OnChanged(fn) table.insert(self._onChanged, fn) end
    function kp:OnClick(fn) table.insert(self._onClick, fn) end

    registerKeybind(kp)
    Options[flag] = kp
    return kp
end

-- ==================== Element factories ====================
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
        local toggleInstance = handle.Elements
            and handle.Elements.Toggle
            and handle.Elements.Toggle.Instance
        if toggleInstance then
            createBindBox(toggleInstance, kp)
        end
        return kp
    end
    function t:AddColorPicker(cf, co)
        local lbl = section:Label({ Name = (co and co.Title) or cf, Alignment = "Left" })
        return makeColorPicker(cf, section, lbl, co)
    end

    if opts.Callback then table.insert(t._callbacks, opts.Callback) end
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
    local labelObj = section:Label({ Name = tostring(text), Alignment = "Left" })
    local proxy = {}

    function proxy:AddColorPicker(cf, co)
        return makeColorPicker(cf, section, labelObj, co)
    end
    function proxy:AddKeyPicker(kf, ko)
        ko = ko or {}
        local kp = makeKeyPickerProxy(kf, ko)
        local labelInstance = labelObj.Elements
            and labelObj.Elements.Label
            and labelObj.Elements.Label.Instance
        if labelInstance then
            createBindBox(labelInstance, kp)
        end
        return kp
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

-- ==================== Shim ====================
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

-- ==================== Own menu keybind handler ====================
-- sametlibs' internal check is broken (compares string to EnumItem), so we
-- handle the menu toggle ourselves based on Options.MenuKeybind.Value.
task.spawn(function()
    while not Options.MenuKeybind do task.wait(0.1) end
    UIS.InputBegan:Connect(function(input)
        if UIS:GetFocusedTextBox() then return end
        if not ThugWindow then return end
        if Options.MenuKeybind._capturing then return end
        local target = Options.MenuKeybind.Value
        if not target or target == "None" then return end
        local matches = (input.KeyCode.Name == target)
                     or (input.UserInputType.Name == target)
        if matches then
            local isOpen = ThugWindow.IsOpen
            if isOpen == nil then isOpen = true end
            pcall(function() ThugWindow:SetOpen(not isOpen) end)
        end
    end)
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
