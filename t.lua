--[[
    Validator & Reporter Script (Client-Only CFrame Movement)
    - This version does NOT require server access or any RemoteEvents.
    - It uses a manual CFrame loop for smooth movement.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local MINIMUM_LUCK_MULTIPLIER = 25
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 50 -- Studs per second.

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================
local function sendWebhook(targetUrl, payload)
    if not targetUrl or not string.match(targetUrl, "discord.com/api/webhooks") then
        warn("Webhook function called with an invalid or missing URL.")
        return
    end
    pcall(function()
        HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) })
    end)
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

-- [*] MODIFIED: This is the new tweening function using manual CFrame control.
local movementConnection = nil
local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    if not humanoidRootPart or not humanoid then return end

    print("Part 2: Preparing to move to final coordinates...")

    -- Cancel any previous movement loop
    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end

    local startCFrame = humanoidRootPart.CFrame
    local journeyDistance = (startCFrame.Position - targetPosition).Magnitude
    local duration = journeyDistance / TWEEN_SPEED
    local startTime = tick()

    -- This loop runs every frame to move the character
    movementConnection = RunService.RenderStepped:Connect(function()
        local now = tick()
        local alpha = math.min((now - startTime) / duration, 1) -- Progress from 0.0 to 1.0

        -- Lerp (linearly interpolate) the CFrame for smooth movement
        humanoidRootPart.CFrame = startCFrame:Lerp(CFrame.new(targetPosition), alpha)

        -- Check if we have arrived
        if alpha >= 1 then
            movementConnection:Disconnect()
            movementConnection = nil
            print("Movement complete. Arrived at target.")
        end
    end)
end


-- =============================================
-- MAIN EXECUTION
-- =============================================
print("Validator/Reporter Script Started. Searching for: " .. TARGET_EGG_NAME)
task.wait(1)

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
    
    -- Step 1: Teleport to the closest portal
    teleportToClosestPoint(math.floor(riftPosition.Y))
    
    local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
    sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
    
    -- Wait for the teleport to finish
    task.wait(3)
    
    -- Step 2: Use the manual CFrame movement to cover the final distance
    tweenToTarget(riftPosition)
else
    print("Target not found. Sending failure report.")
    local failurePayload = {content = "RIFT_SEARCH_FAILED"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
