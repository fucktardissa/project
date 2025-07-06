--[[
    Validator & Reporter Script (with Advanced Tweening)
    - Finds a target egg and validates its luck multiplier.
    - If valid, it teleports to the closest portal.
    - Then, it uses a robust tweening system to move to the final location.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local MINIMUM_LUCK_MULTIPLIER = 25
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 50 -- Studs per second. Higher is faster.
-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts
-- IMPORTANT: Make sure you have a RemoteEvent named "NetworkOwnershipEvent" in ReplicatedStorage
local NetworkEvent = ReplicatedStorage:WaitForChild("NetworkOwnershipEvent") 

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================

-- This function sends a message to your Discord webhooks.
local function sendWebhook(targetUrl, payload)
    if not targetUrl or not string.match(targetUrl, "discord.com/api/webhooks") then
        warn("Webhook function called with an invalid or missing URL.")
        return
    end
    pcall(function()
        HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) })
    end)
end

-- This function finds the closest portal to a target height and teleports you there.
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

-- This is the new, advanced tweening function from BESTVERSION.txt
local currentTween = nil
local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    if not humanoidRootPart or not humanoid then return end

    print("Part 2: Preparing to tween to final coordinates...")

    -- Cancel any previous tween
    if currentTween then
        currentTween:Cancel()
        currentTween = nil
    end

    -- Store original player state
    local originalState = {
        WalkSpeed = humanoid.WalkSpeed,
        AutoRotate = humanoid.AutoRotate,
        JumpPower = humanoid.JumpPower,
        Gravity = workspace.Gravity
    }

    -- Prepare character for tweening
    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = false
    humanoid.JumpPower = 0
    workspace.Gravity = 0

    -- Request network ownership from the server
    NetworkEvent:FireServer("Take")

    -- Create and play the new tween
    local distance = (humanoidRootPart.Position - targetPosition).Magnitude
    local duration = distance / TWEEN_SPEED
    local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Linear)
    local goal = {CFrame = CFrame.new(targetPosition)}
    
    currentTween = TweenService:Create(humanoidRootPart, tweenInfo, goal)
    currentTween:Play()
    print("Tween initiated. Estimated travel time: " .. string.format("%.2f", duration) .. " seconds.")
    
    -- Wait for the tween to complete
    currentTween.Completed:Wait()

    -- Restore everything back to normal
    humanoid.WalkSpeed = originalState.WalkSpeed
    humanoid.AutoRotate = originalState.AutoRotate
    humanoid.JumpPower = originalState.JumpPower
    workspace.Gravity = originalState.Gravity
    
    -- Give network ownership back to the server
    NetworkEvent:FireServer("Release")
    print("Tween completed. Network ownership returned to server.")
end

-- =============================================
-- MAIN EXECUTION
-- =============================================
print("Validator/Reporter Script Started. Searching for: " .. TARGET_EGG_NAME)
task.wait(5)

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
    
    -- Step 2: Use the advanced tween to cover the final distance
    tweenToTarget(riftPosition)
else
    print("Target not found. Sending failure report.")
    local failurePayload = {content = "RIFT_SEARCH_FAILED"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
