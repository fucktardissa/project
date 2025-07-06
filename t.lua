--[[
    Validator & Reporter Script (v4 - with Smooth Tween & Auto-Action)
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local MINIMUM_LUCK_MULTIPLIER = 25
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 200 -- Studs per second.

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================

-- [*] MODIFIED: Upgraded the webhook function for better reliability.
local lastWebhookSendTime = 0
local WEBHOOK_COOLDOWN = 2

local function sendWebhook(targetUrl, payload)
    local now = tick()
    if now - lastWebhookSendTime < WEBHOOK_COOLDOWN then
        warn("Webhook cooldown active. Skipping report.")
        return
    end
    if not targetUrl or not string.match(targetUrl, "discord.com/api/webhooks") then
        warn("Invalid webhook URL.")
        return
    end
    local success, result = pcall(function()
        HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) })
    end)
    if not success then
        warn("Webhook failed to send! Error: " .. tostring(result))
    else
        lastWebhookSendTime = now
        print("Webhook report sent successfully.")
    end
end

local function teleportToClosestPoint(targetHeight)
    local teleportPoints = {
        {name = "Zen", path = "Workspace.Worlds.The Overworld.Islands.Zen.Island.Portal.Spawn", height = 15970},
        {name = "The Void", path = "Workspace.Worlds.The Overworld.Islands.The Void.Island.Portal.Spawn", height = 10135},
        {name = "Twilight", path = "Workspace.Worlds.The Overworld.Islands.Twilight.Island.Portal.Spawn", height = 6855},
        {name = "Outer Space", path = "Workspace.Worlds.The Overworld.Islands.Outer Space.Island.Portal.Spawn", height = 2655}
    }
    local closestPoint = nil
    local smallestDifference = math.huge
    for _, point in ipairs(teleportPoints) do
        local difference = math.abs(point.height - targetHeight)
        if difference < smallestDifference then
            smallestDifference = difference
            closestPoint = point
        end
    end
    if closestPoint then
        print("Part 1: Teleporting to closest portal '" .. closestPoint.name .. "'...")
        local args = {"Teleport", closestPoint.path}
        ReplicatedStorage.Shared.Framework.Network.Remote.RemoteEvent:FireServer(unpack(args))
    end
end

-- [*] MODIFIED: This tweening function is now much smoother.
local movementConnection = nil
local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    if not humanoidRootPart or not humanoid then return end

    print("Part 2: Preparing smooth movement...")

    if movementConnection then movementConnection:Disconnect() end

    -- Store original state
    local originalGravity = workspace.Gravity
    local originalWalkSpeed = humanoid.WalkSpeed
    local originalJumpPower = humanoid.JumpPower

    -- Disable physics and controls for smooth flight
    workspace.Gravity = 0
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0

    local startCFrame = humanoidRootPart.CFrame
    local journeyDistance = (startCFrame.Position - targetPosition).Magnitude
    local duration = journeyDistance / TWEEN_SPEED
    local startTime = tick()

    movementConnection = RunService.RenderStepped:Connect(function()
        local now = tick()
        local alpha = math.min((now - startTime) / duration, 1)
        humanoidRootPart.CFrame = startCFrame:Lerp(CFrame.new(targetPosition), alpha)
        
        if alpha >= 1 then
            movementConnection:Disconnect()
            movementConnection = nil
            
            -- Restore original state
            workspace.Gravity = originalGravity
            humanoid.WalkSpeed = originalWalkSpeed
            humanoid.JumpPower = originalJumpPower
            
            print("Movement complete. Arrived at target.")
        end
    end)
    
    -- Wait for the connection to be disconnected (i.e., movement is finished)
    while movementConnection do
        task.wait()
    end
end

-- [+] ADDED: The auto-press 'R' function you requested.
local function startAutoPressR()
    print("Starting to auto-press 'R' key...")
    getgenv().autoPressR = true
    
    task.spawn(function()
        while getgenv().autoPressR do
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
            task.wait()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
            task.wait()
        end
    end)
end

-- =============================================
-- MAIN EXECUTION
-- =============================================
print("Validator/Reporter Script Started. Searching for: " .. TARGET_EGG_NAME)
task.wait(10)

local riftInstance = RIFT_PATH:FindFirstChild(TARGET_EGG_NAME)
local luckValue = 25

if riftInstance and riftInstance:FindFirstChild("Display") then
    local surfaceGui = riftInstance.Display:FindFirstChild("SurfaceGui")
    if surfaceGui and surfaceGui:FindFirstChild("Icon") and surfaceGui.Icon:FindFirstChild("Luck") then
        luckValue = tonumber((string.gsub(surfaceGui.Icon.Luck.Text, "[^%d%.%-]", ""))) or 0
    end
end

if riftInstance and luckValue >= MINIMUM_LUCK_MULTIPLIER then
    print("Target found! Beginning two-part movement sequence.")
    local riftPosition = riftInstance.Display.Position
    
    teleportToClosestPoint(math.floor(riftPosition.Y))
    
    local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
    sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
    
    task.wait(3)
    
    tweenToTarget(riftPosition)

    -- After arriving, start the auto-presser
    startAutoPressR()
    
else
    print("Target not found. Sending failure report.")
    -- When a search fails, ensure any previous auto-presser is stopped
    getgenv().autoPressR = false 
    local failurePayload = {content = "RIFT_SEARCH_FAILED"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
