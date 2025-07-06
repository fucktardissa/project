--[[
    Validator & Reporter Script (v7 - Hardcoded Target with Reliable Wait)
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3" -- [*] This is now the ONLY egg the script will look for.
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

local movementConnection = nil
local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    if not humanoidRootPart or not humanoid then return end

    print("Part 2: Preparing smooth movement...")

    if movementConnection then movementConnection:Disconnect() end

    local originalGravity = workspace.Gravity
    local originalWalkSpeed = humanoid.WalkSpeed
    local originalJumpPower = humanoid.JumpPower

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
            
            print("Movement complete. Arrived at target.")
            print("Locking player in place for 3 seconds to stabilize physics...")

            workspace.Gravity = originalGravity
            
            task.wait(3)
            
            humanoid.WalkSpeed = originalWalkSpeed
            humanoid.JumpPower = originalJumpPower
            
            print("Player unlocked.")
        end
    end)
    
    while movementConnection do
        task.wait()
    end
end

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

-- [*] MODIFIED: Using WaitForChild for more reliability instead of a fixed wait time.
-- It will wait up to 15 seconds for the specific rift to load in.
local riftInstance = RIFT_PATH:WaitForChild(TARGET_EGG_NAME, 10)

-- [*] MODIFIED: The main check is now simpler. It only checks if the rift was found.
if riftInstance then
    print("Target found! Beginning two-part movement sequence.")
    local riftPosition = riftInstance.CFrame.Position -- Use CFrame.Position for models
    
    teleportToClosestPoint(math.floor(riftPosition.Y))
    
    local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
    sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
    
    task.wait(3)
    
    tweenToTarget(riftPosition)

    startAutoPressR()
    
else
    print("Target '" .. TARGET_EGG_NAME .. "' not found after 10 seconds. Sending failure report.")
    getgenv().autoPressR = false 
    local failurePayload = {content = "RIFT_SEARCH_FAILED"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
