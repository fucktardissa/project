--[[
    Validator & Reporter Script (with Reliable Webhooks & Advanced Tweening)
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

-- [*] MODIFIED: This is the new, more robust webhook function with a cooldown and error logging.
local lastWebhookSendTime = 0
local WEBHOOK_COOLDOWN = 2 -- Cooldown in seconds between sending webhooks.

local function sendWebhook(targetUrl, payload)
    local now = tick()
    if now - lastWebhookSendTime < WEBHOOK_COOLDOWN then
        warn("Webhook cooldown active. Skipping report to avoid spam.")
        return
    end

    if not targetUrl or not string.match(targetUrl, "discord.com/api/webhooks") then
        warn("Webhook function called with an invalid or missing URL.")
        return
    end

    -- Use pcall to safely make the request and capture any errors.
    local success, result = pcall(function()
        HttpService:RequestAsync({
            Url = targetUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not success then
        -- If the request failed, print the error instead of failing silently.
        warn("Webhook failed to send! Error: " .. tostring(result))
    else
        -- If successful, update the timestamp.
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
    if not humanoidRootPart then return end

    print("Part 2: Preparing to move to final coordinates...")

    if movementConnection then
        movementConnection:Disconnect()
        movementConnection = nil
    end

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
        end
    end)
end


-- =============================================
-- MAIN EXECUTION
-- =============================================
print("Validator/Reporter Script Started. Searching for: " .. TARGET_EGG_NAME)
task.wait(2)

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
else
    print("Target not found. Sending failure report.")
    local failurePayload = {content = "RIFT_SEARCH_FAILED"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
