-- Announcement listener, based on the supplied redeemer's notification discovery
-- and Codes GUI lookup. Uses existing submit handlers without changing cooldowns.
-- F6 = manually start/pause; F7 = stop and disarm automatic triggers.
-- Initially waits for a code announcement, then listens until stopped.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
for _, name in ipairs({"AnnouncementPasteUI", "LemonListenerUI"}) do
    local old = gui:FindFirstChild(name)
    if old then old:Destroy() end
end
local alive, listening, armed = true, false, true
local latestText, chosenBox
local autoRedeem = true
local spamRedeem = false
local spamWords, spamBuffer = {}, ""
local submittedCodes = {}
local sessionStartedAt = os.clock()
local lastTriggerText
local updatingCode = false
-- Normalized area circled in the supplied screenshot; scales with screen size.
local announcementRegion = {left = 0.30, right = 0.70, top = 0, bottom = 0.24}
local readCount, watchedCount = 0, 0
local previousRead, previousSource, previousReadAt = nil, nil, 0
local lastSubmitAt = -math.huge
local submitting = false
local getConnections = getconnections or (debug and debug.getconnections)
local links, watched = {}, setmetatable({}, {__mode = "k"})
local seen = setmetatable({}, {__mode = "k"})
local function bind(signal, callback)
    local c = signal:Connect(callback)
    table.insert(links, c)
    return c
end
local screen = Instance.new("ScreenGui")
screen.Name = "LemonListenerUI"
screen.ResetOnSpawn = false
screen.DisplayOrder = 1000
screen.Parent = gui
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(316, 616)
frame.Position = UDim2.new(1, -340, 0.5, -308)
frame.BackgroundColor3 = Color3.fromRGB(18, 14, 10)
frame.BorderSizePixel = 0
frame.BackgroundTransparency = 0.3
frame.Parent = screen
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 14)
local outline = Instance.new("UIStroke", frame)
outline.Color = Color3.fromRGB(255, 155, 45)
outline.Transparency = 0.35
local function card(y, height)
    local c = Instance.new("Frame", frame)
    c.Position = UDim2.fromOffset(10, y)
    c.Size = UDim2.new(1, -20, 0, height)
    c.BackgroundColor3 = Color3.fromRGB(30, 23, 17)
    c.BackgroundTransparency = 0.4
    c.BorderSizePixel = 0
    c.ZIndex = 2
    Instance.new("UICorner", c).CornerRadius = UDim.new(0, 9)
    local stroke = Instance.new("UIStroke", c)
    stroke.Color = Color3.fromRGB(100, 65, 35)
    stroke.Transparency = 0.3
    return c
end
local function label(text, y, height)
    local x = Instance.new("TextLabel")
    x.Position = UDim2.fromOffset(12, y)
    x.Size = UDim2.new(1, -24, 0, height)
    x.BackgroundTransparency = 1
    x.TextColor3 = Color3.fromRGB(255, 245, 230)
    x.Font = Enum.Font.GothamMedium
    x.TextSize = 12
    x.ZIndex = 3
    x.TextWrapped = true
    x.TextXAlignment = Enum.TextXAlignment.Left
    x.TextYAlignment = Enum.TextYAlignment.Top
    x.Text = text
    x.Parent = frame
    return x
end
local header = label("LEMON", 12, 24)
header.Position = UDim2.fromOffset(44, 12)
header.Size = UDim2.fromOffset(180, 24)
header.Size = UDim2.fromOffset(164, 24)
header.Font = Enum.Font.GothamBlack
header.TextSize = 16
header.Active = true
local avatar = Instance.new("TextLabel", frame)
avatar.Position = UDim2.fromOffset(12, 10)
avatar.Size = UDim2.fromOffset(24, 24)
avatar.BackgroundColor3 = Color3.fromRGB(48, 34, 23)
avatar.Text = "L"
avatar.Font = Enum.Font.GothamBlack
avatar.TextSize = 16
avatar.TextColor3 = Color3.fromRGB(255, 165, 55)
avatar.BackgroundTransparency = 0.25
avatar.ZIndex = 3
Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)
card(48, 96)
local top = label("Latest read: waiting... (drag here)", 58, 76)
top.Position = UDim2.fromOffset(20, 58)
top.Size = UDim2.new(1, -40, 0, 76)
top.Active = true
card(150, 56)
local status = label("Armed: waiting for 'code is', 'use code', etc.", 160, 40)
status.Position = UDim2.fromOffset(20, 160)
status.Size = UDim2.new(1, -40, 0, 40)
status.TextColor3 = Color3.fromRGB(255, 215, 0)
local target = label("Target: automatic Codes textbox", 214, 28)
target.TextColor3 = Color3.fromRGB(205, 185, 160)
card(246, 60)
local codeCaption = label("CODE", 252, 12)
codeCaption.Position = UDim2.fromOffset(20, 252)
codeCaption.Font = Enum.Font.GothamBlack
codeCaption.TextSize = 9
codeCaption.TextColor3 = Color3.fromRGB(255, 155, 45)
local codeInput = Instance.new("TextBox", frame)
codeInput.Position = UDim2.fromOffset(20, 270)
codeInput.Size = UDim2.new(1, -40, 0, 28)
codeInput.BackgroundColor3 = Color3.fromRGB(23, 17, 12)
codeInput.BackgroundTransparency = 0.25
codeInput.TextColor3 = Color3.fromRGB(255, 245, 230)
codeInput.PlaceholderColor3 = Color3.fromRGB(205, 185, 160)
codeInput.PlaceholderText = "type or capture a code..."
codeInput.Text = ""
codeInput.Font = Enum.Font.GothamBlack
codeInput.TextSize = 14
codeInput.ClearTextOnFocus = false
codeInput.ZIndex = 3
Instance.new("UICorner", codeInput).CornerRadius = UDim.new(0, 7)
local footer = label("AUTO LISTEN ON | Waiting for code phrase\nF6 manual listen | F7 stop everything", 564, 42)
footer.TextColor3 = Color3.fromRGB(205, 185, 160)
footer.TextSize = 11
local function button(text, x, color)
    local b = Instance.new("TextButton")
    b.Position = UDim2.fromOffset(x, 210)
    b.Size = UDim2.fromOffset(172, 30)
    b.BackgroundColor3 = color
    b.BackgroundTransparency = 0.25
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.Text = text
    b.ZIndex = 3
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Parent = frame
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
    local stroke = Instance.new("UIStroke", b)
    stroke.Color = Color3.fromRGB(100, 65, 35)
    bind(b.MouseEnter, function()
        TweenService:Create(stroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(255, 155, 45)}):Play()
    end)
    bind(b.MouseLeave, function()
        TweenService:Create(stroke, TweenInfo.new(0.12), {Color = Color3.fromRGB(100, 65, 35)}):Play()
    end)
    return b
end
local copyButton = button("COPY", 10, Color3.fromRGB(48, 34, 23))
local clearButton = button("CLEAR", 111, Color3.fromRGB(48, 34, 23))
local manualRedeem = button("REDEEM", 212, Color3.fromRGB(255, 155, 45))
for _, b in ipairs({copyButton, clearButton, manualRedeem}) do
    b.Position = UDim2.fromOffset(b.Position.X.Offset, 314)
    b.Size = UDim2.fromOffset(94, 33)
    b.TextSize = 12
end
local toggle = button("LISTEN [F6]", 10, Color3.fromRGB(48, 34, 23))
toggle.Position = UDim2.fromOffset(10, 358)
toggle.Size = UDim2.fromOffset(296, 32)
local stopButton = button("STOP [F7]", 10, Color3.fromRGB(175, 80, 25))
stopButton.Position = UDim2.fromOffset(10, 438)
stopButton.Size = UDim2.fromOffset(296, 34)
local redeemToggle = button("AUTO REDEEM: ON", 10, Color3.fromRGB(48, 34, 23))
redeemToggle.Position = UDim2.fromOffset(10, 398)
redeemToggle.Size = UDim2.fromOffset(296, 32)
redeemToggle.TextColor3 = Color3.fromRGB(255, 155, 45)
local spamButton = button("SPAM REDEEM: OFF", 10, Color3.fromRGB(48, 34, 23))
spamButton.Position = UDim2.fromOffset(10, 480)
spamButton.Size = UDim2.fromOffset(296, 34)
spamButton.TextColor3 = Color3.fromRGB(255, 155, 45)
local autoListenButton = button("AUTO LISTEN: ON", 10, Color3.fromRGB(48, 34, 23))
autoListenButton.Position = UDim2.fromOffset(10, 522)
autoListenButton.Size = UDim2.fromOffset(296, 32)
autoListenButton.TextColor3 = Color3.fromRGB(255, 155, 45)
local function appendWords(text, reset)
    if reset then spamWords, spamBuffer = {}, "" end
    -- Same word tokenization and concatenation as the supplied redeemer.
    -- Each queued value contains every word received so far, without spaces.
    for word in text:gmatch("[%w_]+") do
        spamBuffer = spamBuffer .. word
        table.insert(spamWords, spamBuffer)
    end
end
local function showCode(text)
    updatingCode = true
    codeInput.Text = text
    updatingCode = false
end
bind(codeInput:GetPropertyChangedSignal("Text"), function()
    if not updatingCode and spamRedeem then
        appendWords(codeInput.Text, true)
        latestText = spamBuffer ~= "" and spamBuffer or nil
    end
end)
bind(spamButton.MouseButton1Click, function()
    spamRedeem = not spamRedeem
    spamButton.Text = spamRedeem and "SPAM REDEEM: ON" or "SPAM REDEEM: OFF"
    if spamRedeem then
        listening, armed, autoRedeem = true, true, true
        sessionStartedAt = os.clock()
        submittedCodes = {}
        redeemToggle.Text = "AUTO REDEEM: ON"
        toggle.Text = "Pause [F6]"
        appendWords(codeInput.Text, true)
        latestText = spamBuffer ~= "" and spamBuffer or nil
        status.Text = #spamWords > 0 and "Adding words to one code. F7 stops."
            or "Spam ready. Waiting for text or a typed code."
    else
        latestText = codeInput.Text ~= "" and codeInput.Text or nil
        status.Text = "Spam off. Normal listening continues; F7 stops all."
    end
end)
bind(redeemToggle.MouseButton1Click, function()
    autoRedeem = not autoRedeem
    redeemToggle.Text = autoRedeem and "Auto redeem: ON" or "Auto redeem: OFF"
end)
local dragging, touch, origin, startPosition
local function beginDrag(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        touch = input.UserInputType == Enum.UserInputType.Touch and input or nil
        origin, startPosition = input.Position, frame.Position
    end
end
bind(top.InputBegan, beginDrag)
bind(header.InputBegan, beginDrag)
bind(UIS.InputChanged, function(input)
    if dragging and (input == touch or (not touch and
        input.UserInputType == Enum.UserInputType.MouseMovement)) then
        local d = input.Position - origin
        frame.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + d.X,
            startPosition.Y.Scale, startPosition.Y.Offset + d.Y)
    end
end)
bind(UIS.InputEnded, function(input)
    if input == touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging, touch = false, nil
    end
end)
bind(UIS.WindowFocusReleased, function() dragging, touch = false, nil end)
local function findBox()
    if chosenBox and chosenBox:IsDescendantOf(gui) then return chosenBox end
    local codes = gui:FindFirstChild("Codes")
    if not codes then return nil end
    local root = codes:FindFirstChild("Codes") or codes
    local main = root:FindFirstChild("Main")
    local box = main and main:FindFirstChild("TextBox")
    if box and box:IsA("TextBox") then return box end
    return codes:FindFirstChildWhichIsA("TextBox", true)
end
local function findConfirm()
    local codes = gui:FindFirstChild("Codes")
    if not codes then return nil end
    local root = codes:FindFirstChild("Codes") or codes
    local main = root:FindFirstChild("Main") or root
    local confirm = main:FindFirstChild("Confirm")
    if confirm and confirm:IsA("GuiButton") then return confirm end
    for _, object in ipairs(codes:GetDescendants()) do
        if object:IsA("GuiButton") then
            local name = object.Name:lower()
            if name:find("confirm", 1, true) or name:find("redeem", 1, true)
                or name:find("submit", 1, true) then return object end
        end
    end
end
local function fireHandlers(signal, ...)
    if not getConnections then return false end
    local ok, handlers = pcall(getConnections, signal)
    if not ok or type(handlers) ~= "table" then return false end
    local args = table.pack(...)
    local fired = false
    for _, handler in ipairs(handlers) do
        if not alive or not listening or not autoRedeem then break end
        if handler.Enabled ~= false then
            local called = pcall(function()
                handler:Fire(table.unpack(args, 1, args.n))
            end)
            fired = fired or called
        end
    end
    return fired
end
local function paste(allowSubmit)
    if not alive or not listening or not latestText then return end
    local box = findBox()
    if not box then
        status.Text = "Open Codes or select the destination textbox."
        return
    end
    local ok = pcall(function() box.Text = latestText end)
    target.Text = "Target: " .. box.Name
    if not ok then
        status.Text = "Paste failed. Select the textbox again."
        return
    end
    status.Text = "Repeating latest text. F7 stops."
    if not autoRedeem or not allowSubmit or submitting then return end
    local candidate = latestText
    if spamRedeem and submittedCodes[candidate] then return true end
    if os.clock() - lastSubmitAt < 0.2 then return end
    local codes = gui:FindFirstChild("Codes")
    if not codes or not box:IsDescendantOf(codes) then
        status.Text = "Pasted. Auto redeem requires the game's Codes textbox."
        return
    end
    if not getConnections then
        status.Text = "Pasted. Executor lacks getconnections for auto redeem."
        return
    end
    submitting = true
    lastSubmitAt = os.clock()
    if spamRedeem then submittedCodes[candidate] = true end
    local sent = false
    local safe = pcall(function()
        local confirm = findConfirm()
        if confirm then
            sent = fireHandlers(confirm.MouseButton1Click)
            if not sent then sent = fireHandlers(confirm.Activated) end
        end
        if not sent then sent = fireHandlers(box.FocusLost, true) end
    end)
    submitting = false
    if not (safe and sent) then submittedCodes[candidate] = nil end
    if alive and listening then
        status.Text = safe and sent
            and (spamRedeem and ("Spam requested: " .. latestText .. " | F7 stops")
                or "Redeem requested. Retrying every 1.5 seconds; F7 stops.")
            or "Pasted, but no usable redemption handler was found."
    end
    return safe and sent
end
local function checkRedeemSuccess(text)
    if not alive or not listening or lastSubmitAt < sessionStartedAt then return false end
    if type(text) ~= "string" then return false end
    local lower = text:gsub("<[^>]->", ""):lower()
    for _, failure in ipairs({"already", "invalid", "failed", "not redeem", "unable", "expired", "unsuccess"}) do
        if lower:find(failure, 1, true) then return false end
    end
    local success = lower:find("successfully redeemed", 1, true)
        or lower:find("redeemed successfully", 1, true)
        or lower:find("code redeemed", 1, true)
        or lower:find("successfully redeemed code", 1, true)
        or lower:find("code successfully claimed", 1, true)
    if not success then return false end
    listening, spamRedeem, armed = false, false, true
    autoListenButton.Text = "AUTO LISTEN: ON"
    latestText = nil
    spamWords, spamBuffer = {}, ""
    spamButton.Text = "SPAM REDEEM: OFF"
    toggle.Text = "Listen [F6]"
    status.Text = "Redemption success detected. Waiting for the next code phrase."
    return true
end
bind(copyButton.MouseButton1Click, function()
    local writer = setclipboard or toclipboard
    if writer then
        local ok = pcall(writer, codeInput.Text)
        status.Text = ok and "Code copied." or "Clipboard copy failed."
    else
        status.Text = "Executor does not provide clipboard access."
    end
end)
bind(clearButton.MouseButton1Click, function()
    latestText = nil
    spamWords, spamBuffer = {}, ""
    submittedCodes = {}
    sessionStartedAt = os.clock()
    showCode("")
    status.Text = "Cleared."
end)
local function redeemManual()
    if not codeInput.Text:find("%S") then
        status.Text = "Type or capture a code first."
        return
    end
    latestText = codeInput.Text
    local wasListening, wasAuto = listening, autoRedeem
    listening, autoRedeem = true, true
    paste(true)
    listening, autoRedeem = wasListening, wasAuto
end
bind(manualRedeem.MouseButton1Click, redeemManual)
bind(codeInput.FocusLost, function(enterPressed)
    if enterPressed then redeemManual() end
end)
local triggerPatterns = {
    "%f[%a]code%s+is%f[%A]",
    "%f[%a]the%s+code%s+is%f[%A]",
    "%f[%a]use%s+code%f[%A]",
    "%f[%a]use%s+the%s+code%f[%A]",
    "%f[%a]redeem%s+code%f[%A]",
    "%f[%a]redeem%s+the%s+code%f[%A]",
    "%f[%a]enter%s+code%f[%A]",
    "%f[%a]type%s+code%f[%A]",
    "%f[%a]new%s+code%f[%A]",
    "%f[%a]code%s*:",
}
local function capture(text, source)
    if not alive or not armed or type(text) ~= "string" then return end
    text = text:gsub("<[^>]->", ""):gsub("&nbsp;", " ")
    text = text:gsub("\194\160", " "):gsub("\226\128\139", "")
    if not text:find("%S") then return end
    -- Avoid processing one announcement twice through the remote and GUI paths.
    local now = os.clock()
    if text == previousRead and source ~= previousSource
        and now - previousReadAt < 0.6 then return end
    previousRead, previousSource, previousReadAt = text, source, now
    readCount = readCount + 1
    footer.Text = ("TOP BANNER | READ: %d | LABELS: %d\nF6 listen | F7 stop | Spam interval: 0.2s"):format(readCount, watchedCount)
    top.Text = "Latest read: " .. text:sub(1, 260)
    local lower = text:lower()
    local normalized = lower:gsub("%p", " ")
    local triggerEnd
    for _, pattern in ipairs(triggerPatterns) do
        local _, finish = lower:find(pattern)
        local _, normalizedFinish = normalized:find(pattern)
        if normalizedFinish and (not finish or normalizedFinish > finish) then finish = normalizedFinish end
        if finish and (not triggerEnd or finish > triggerEnd) then
            triggerEnd = finish
        end
    end
    if triggerEnd then
        if listening and lastTriggerText == text then return end
        lastTriggerText = text
        listening, spamRedeem, autoRedeem = true, true, true
        submittedCodes = {}
        sessionStartedAt = os.clock()
        spamButton.Text = "SPAM REDEEM: ON"
        redeemToggle.Text = "AUTO REDEEM: ON"
        toggle.Text = "Pause [F6]"
        -- Remove the trigger phrase and separator punctuation before pasting.
        text = text:sub(triggerEnd + 1):gsub("^[%s%p]+", ""):gsub("%s+$", "")
        latestText = nil
        spamWords, spamBuffer = {}, ""
        showCode("")
        if text == "" then
            status.Text = "Spam auto-started. Waiting for the next word..."
            return
        end
    elseif not listening then
        return
    end
    if spamRedeem then
        appendWords(text, false)
        latestText = spamBuffer ~= "" and spamBuffer or nil
        showCode(spamBuffer)
    else
        latestText = text
        showCode(text)
    end
    paste(false)
end
local function setListening(value, disarm)
    listening = value
    armed = value or not disarm
    autoListenButton.Text = armed and "AUTO LISTEN: ON" or "AUTO LISTEN: OFF"
    if value then sessionStartedAt = os.clock() end
    toggle.Text = value and "Pause [F6]" or "Listen [F6]"
    status.Text = value and "Listening for new announcements..."
        or (armed and "Auto Listen ON: waiting for a code phrase." or "Stopped. Turn Auto Listen ON to rearm.")
    if not value then
        latestText = nil
        spamRedeem = false
        spamWords, spamBuffer = {}, ""
        submittedCodes = {}
        lastTriggerText = nil
        spamButton.Text = "SPAM REDEEM: OFF"
    end
end
bind(toggle.MouseButton1Click, function() setListening(not listening) end)
bind(autoListenButton.MouseButton1Click, function() setListening(false, armed) end)
bind(stopButton.MouseButton1Click, function() setListening(false, true) end)
bind(UIS.InputBegan, function(input)
    if input.KeyCode == Enum.KeyCode.F6 then setListening(not listening)
    elseif input.KeyCode == Enum.KeyCode.F7 then setListening(false, true) end
end)
bind(UIS.TextBoxFocused, function(box)
    if not box:IsDescendantOf(screen) then
        chosenBox = box
        target.Text = "Target: " .. box.Name
    end
end)
-- Same notification-remote discovery approach as the supplied file.
local packages = RS:FindFirstChild("Packages")
local net = packages and packages:FindFirstChild("Net")
local notificationRemote
local getValues = (debug and debug.getupvalues) or getupvalues
-- Discovery must not delay the independent GUI scanner if a module yields.
task.spawn(function()
if net and getValues then
    local ok, result = pcall(function()
        local controllers = RS:FindFirstChild("Controllers")
        local module = controllers and controllers:FindFirstChild("NotificationController", true)
        if not module then return nil end
        local controller = require(module)
        if type(controller) ~= "table" or type(controller.Start) ~= "function" then return nil end
        for _, value in pairs(getValues(controller.Start)) do
            if typeof(value) == "Instance" and value.Parent == net
                and (value:IsA("RemoteEvent") or value:IsA("UnreliableRemoteEvent")) then
                return value
            end
        end
    end)
    if ok then notificationRemote = result end
end
if notificationRemote then
    if not alive then return end
    bind(notificationRemote.OnClientEvent, function(...)
        local args = table.pack(...)
        if type(args[1]) == "string" and checkRedeemSuccess(args[1]) then return end
        if type(args[1]) == "table" then
            local message = args[1].Text or args[1].text or args[1].Message or args[1].message
            if checkRedeemSuccess(message) then return end
        end
        -- The original supplied script identifies top announcements via arg 4.
        local topMessage = args[4] == "Top"
        for i = 1, args.n do
            local item = args[i]
            if type(item) == "table" then
                local position = item.Position or item.position or item.Placement or item.placement
                if type(position) == "string" and position:lower() == "top" then
                    topMessage = true
                end
            end
        end
        if not topMessage then return end
        for i = 1, args.n do
            local value = args[i]
            if type(value) == "string" then
                capture(value, "remote")
                return
            elseif type(value) == "table" then
                for _, key in ipairs({"Text", "text", "Message", "message", "Content", "content"}) do
                    if type(value[key]) == "string" then
                        capture(value[key], "remote")
                        return
                    end
                end
            end
        end
    end)
end
end)
do
    -- Always monitor GUI text, even if remote discovery picked an unused event.
    local pending = setmetatable({}, {__mode = "k"})
    local resultSeen = setmetatable({}, {__mode = "k"})
    local groupPending = {}
    local candidates = {}
    local nextDiscovery = 0
    local groupSeen = {}
    local function visible(object)
        local p = object
        while p and p ~= gui do
            if p:IsA("BillboardGui") or p:IsA("SurfaceGui") then return false end
            if p:IsA("GuiObject") and not p.Visible then return false end
            if p:IsA("ScreenGui") and not p.Enabled then return false end
            p = p.Parent
        end
        return p == gui
    end
    local function inAnnouncementRegion(object)
        local camera = workspace.CurrentCamera
        if not camera then return false end
        local viewport = camera.ViewportSize
        if viewport.X <= 0 or viewport.Y <= 0 then return false end
        local size = object.AbsoluteSize
        if size.X <= 0 or size.Y <= 0 then return false end
        local position = object.AbsolutePosition
        local root = object:FindFirstAncestorWhichIsA("ScreenGui")
        if root and not root.IgnoreGuiInset then
            local inset = GuiService:GetGuiInset()
            position = position + inset
        end
        local bounds = object.TextBounds
        local width, height = math.min(size.X, bounds.X), math.min(size.Y, bounds.Y)
        if width <= 0 or height <= 0 then return false end
        local x, y = position.X, position.Y
        if object.TextXAlignment == Enum.TextXAlignment.Center then x = x + (size.X - width) / 2
        elseif object.TextXAlignment == Enum.TextXAlignment.Right then x = x + size.X - width end
        if object.TextYAlignment == Enum.TextYAlignment.Center then y = y + (size.Y - height) / 2
        elseif object.TextYAlignment == Enum.TextYAlignment.Bottom then y = y + size.Y - height end
        local left, right = announcementRegion.left * viewport.X, announcementRegion.right * viewport.X
        local topEdge, bottom = announcementRegion.top * viewport.Y, announcementRegion.bottom * viewport.Y
        return x + width >= left and x <= right and y + height >= topEdge and y <= bottom
    end
    local function read(object)
        if not alive or not object:IsDescendantOf(gui)
            or object:IsDescendantOf(screen) then return end
        if visible(object) and resultSeen[object] ~= object.Text then
            resultSeen[object] = object.Text
            local ancestor = object
            local isResult = false
            while ancestor and ancestor ~= gui do
                local name = ancestor.Name:lower()
                if name == "codes" or name:find("notif", 1, true)
                    or name:find("toast", 1, true) then isResult = true; break end
                ancestor = ancestor.Parent
            end
            if isResult and checkRedeemSuccess(object.Text) then return end
        elseif not visible(object) then
            resultSeen[object] = nil
        end
        if not armed then return end
        if not visible(object) or not inAnnouncementRegion(object) then
            seen[object], pending[object] = nil, nil
            return
        end
        -- Exclude the redemption interface to avoid feedback from its messages.
        local codes = gui:FindFirstChild("Codes")
        if codes and object:IsDescendantOf(codes) then return end
        local text = object.Text
        if seen[object] == text then return end
        local state = pending[object]
        if not state or state.text ~= text then
            pending[object] = {text = text, at = os.clock()}
        elseif os.clock() - state.at >= 0.2 then
            seen[object], pending[object] = text, nil
            local source = "announcement:top-banner"
            capture(text, source)
        end
    end
    local function watch(object)
        if watched[object] or object:IsDescendantOf(screen) then return end
        if not (object:IsA("TextLabel") or object:IsA("TextButton")) then return end
        watched[object] = true
        watchedCount = watchedCount + 1
    end
    task.spawn(function()
        for i, object in ipairs(gui:GetDescendants()) do
            if not alive then return end
            watch(object)
            if i % 100 == 0 then task.wait() end
        end
        nextDiscovery = 0
    end)
    bind(gui.DescendantAdded, function(object)
        watch(object)
    end)
    bind(gui.DescendantRemoving, function(object)
        if watched[object] then
            watched[object], seen[object], pending[object], resultSeen[object] = nil, nil, nil, nil
            watchedCount = math.max(0, watchedCount - 1)
        end
    end)
    local function scan()
        local ordered, groups = {}, {}
        local now = os.clock()
        if now >= nextDiscovery then
            nextDiscovery = now + 0.75
            candidates = {}
            local checked = 0
            for object in pairs(watched) do
                if not alive or not armed then return end
                if object:IsDescendantOf(gui) then
                    if visible(object) and inAnnouncementRegion(object) then
                        candidates[#candidates + 1] = object
                    else
                        seen[object], pending[object] = nil, nil
                        -- Success messages may appear outside the banner.
                        if listening then read(object) end
                    end
                end
                checked = checked + 1
                if checked % 80 == 0 then task.wait() end
            end
        end
        for _, object in ipairs(candidates) do
            if object:IsDescendantOf(gui) and visible(object) and inAnnouncementRegion(object) then
                if seen[object] ~= object.Text then ordered[#ordered + 1] = object end
                if not listening then
                    local root = object:FindFirstAncestorWhichIsA("ScreenGui")
                    local row = math.floor(object.AbsolutePosition.Y / 24)
                    local rootGroups = groups[root or gui]
                    if not rootGroups then rootGroups = {}; groups[root or gui] = rootGroups end
                    rootGroups[row] = rootGroups[row] or {}
                    table.insert(rootGroups[row], object)
                end
            else
                seen[object], pending[object], resultSeen[object] = nil, nil, nil
            end
        end
        -- Some banners place each word in its own TextLabel.
        local nextGroups = {}
        local nextSeen = {}
        for root, rows in pairs(groups) do
        nextGroups[root], nextSeen[root] = {}, {}
        for row, objects in pairs(rows) do
            if #objects > 1 then
                table.sort(objects, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
                local parts = {}
                for _, object in ipairs(objects) do table.insert(parts, object.Text) end
                local joined = table.concat(parts, " "):gsub("<[^>]->", "")
                local normalized = joined:lower():gsub("%p", " ")
                local matched = false
                for _, pattern in ipairs(triggerPatterns) do
                    if normalized:find(pattern) or joined:lower():find(pattern) then matched = true; break end
                end
                if matched then
                    local state = groupPending[root] and groupPending[root][row]
                    if not state or state.text ~= joined then state = {text = joined, at = os.clock()} end
                    nextGroups[root][row] = state
                    if os.clock() - state.at >= 0.2 then
                        nextSeen[root][row] = joined
                        for _, object in ipairs(objects) do seen[object], pending[object] = object.Text, nil end
                        if not groupSeen[root] or groupSeen[root][row] ~= joined then
                            capture(joined, "announcement:split-banner")
                        end
                        break
                    end
                end
            end
        end
        end
        groupPending = nextGroups
        groupSeen = nextSeen
        table.sort(ordered, function(a, b)
            local rowA = math.floor(a.AbsolutePosition.Y / 24)
            local rowB = math.floor(b.AbsolutePosition.Y / 24)
            if rowA ~= rowB then return rowA < rowB end
            return a.AbsolutePosition.X < b.AbsolutePosition.X
        end)
        for _, object in ipairs(ordered) do read(object) end
    end
    task.spawn(function()
        while alive do
            task.wait(0.1)
            if not alive then break end
            if armed then
                local ok, err = pcall(scan)
                if not ok then status.Text = "Scanner error: " .. tostring(err):sub(1, 140) end
            end
        end
    end)
    footer.Text = ("TOP BANNER | READ: %d | LABELS: %d\nF6 listen | F7 stop | Spam interval: 0.2s"):format(readCount, watchedCount)
    status.Text = "Armed: watching the top-center announcement area."
end
bind(screen.Destroying, function()
    alive, listening, armed, dragging = false, false, false, false
    for _, c in ipairs(links) do c:Disconnect() end
    table.clear(links)
end)
task.spawn(function()
    local lastAttemptAt = -math.huge
    while alive do
        task.wait(0.1)
        if not alive then break end
        if listening and os.clock() - lastAttemptAt >= (spamRedeem and 0.2 or 1.5) then
            lastAttemptAt = os.clock()
            if spamRedeem then
                local nextCode = spamWords[1]
                if nextCode then
                    latestText = nextCode
                    local sent = paste(true)
                    if sent and spamWords[1] == nextCode then
                        table.remove(spamWords, 1)
                    end
                elseif spamBuffer ~= "" then
                    status.Text = "Each growing code submitted once. Waiting for a new word or success."
                end
            else
                paste(true)
            end
        end
    end
end)
