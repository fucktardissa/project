--[[
    Validator & Reporter Script (v36 - "Slow & Steady" Two-Tween System)
    - Based on user feedback, this version avoids all instant teleports.
    - Movement is now a two-phase tween, both done in "ghost mode":
        1. A smooth vertical tween to the target's altitude.
        2. A very slow horizontal tween to the final destination.
    - This is the most careful and least aggressive approach, designed to avoid anti-cheat detection.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local VERTICAL_SPEED = 150  -- Speed for the up/down movement
local HORIZONTAL_SPEED = 35 -- VERY SLOW speed for the final approach, as requested

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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
    if now - lastWebhookSendTime < WEBHOOK_COOLDOWN then return end
    if not targetUrl or not string.match(targetUrl, "discord.com/api/webhooks") then return end
    pcall(function()
        HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) })
        lastWebhookSendTime = now
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

local function findSafeLandingSpot(originalPosition)
    print("Finding a safe landing spot using raycasting...")
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local rayOrigin = originalPosition + Vector3.new(0, 100, 0)
    local rayDirection = Vector3.new(0, -200, 0)
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {character}
    raycastParams.IgnoreWater = true
    local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if raycastResult and raycastResult.Instance and raycastResult.Instance.CanCollide then
        local groundPosition = raycastResult.Position
        local finalTarget = groundPosition + Vector3.new(0, 3, 0)
        print("Safe landing spot found at: " .. tostring(finalTarget))
        return finalTarget
    else
        warn("Raycast failed to find ground. Falling back to original target logic.")
        return originalPosition + Vector3.new(0, 5, 0)
    end
end

-- =============================================
-- "SLOW & STEADY" TWO-TWEEN MOVEMENT SYSTEM
-- =============================================
local function performMovement(targetPosition)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

    if not (humanoid and humanoidRootPart) then
        error("Movement failed: Character parts not found.")
    end

    -- 1. Engage Ghost Mode for the entire duration
    print("Engaging client-only ghost mode...")
    local originalCollisions = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            originalCollisions[part] = part.CanCollide
            part.CanCollide = false
        end
    end
    local originalPlatformStand = humanoid.PlatformStand
    humanoid.PlatformStand = true

    -- 2. Phase 1: Smoothly tween vertically to the target's height
    local startPos = humanoidRootPart.Position
    local intermediatePos = CFrame.new(startPos.X, targetPosition.Y, startPos.Z)
    
    print("Part 2a: Smoothly tweening to target altitude...")
    local verticalDistance = (startPos - intermediatePos.Position).Magnitude
    local verticalTime = verticalDistance / VERTICAL_SPEED
    local verticalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(verticalTime, Enum.EasingStyle.Linear), {CFrame = intermediatePos})
    
    verticalTween:Play()
    verticalTween.Completed:Wait()

    -- 3. Phase 2: Slowly tween horizontally to the final position
    print("Part 2b: Slowly tweening to final destination...")
    local horizontalDistance = (humanoidRootPart.Position - targetPosition).Magnitude
    local horizontalTime = horizontalDistance / HORIZONTAL_SPEED
    local horizontalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(horizontalTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPosition)})
    
    horizontalTween:Play()
    horizontalTween.Completed:Wait()

    -- 4. Disengage ghost mode and stabilize
    print("Destination reached. Cleaning up...")
    for part, canCollide in pairs(originalCollisions) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
    humanoid.PlatformStand = originalPlatformStand
    
    humanoidRootPart.Anchored = true
    task.wait(0.2)
    humanoidRootPart.Anchored = false
    print("Stabilization complete.")
end

-- =============================================
-- AUTO-PRESS 'R' UTILITY
-- =============================================
local function startAutoPressR()
    print("Starting to auto-press 'R' key...")
    getgenv().autoPressR = true
    task.spawn(function()
        while getgenv().autoPressR do
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
            task.wait()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
            task.wait(0.1)
        end
    end)
end

-- =============================================
-- MAIN EXECUTION
-- =============================================
print("Validator/Reporter Script Started. Searching for: " .. TARGET_EGG_NAME)
local riftInstance = RIFT_PATH:WaitForChild(TARGET_EGG_NAME, 15)

if riftInstance then
    local success, errorMessage = pcall(function()
        print("Target found! Beginning sequence.")
        
        local riftPosition = riftInstance:GetPivot().Position
        local safeTargetPosition = findSafeLandingSpot(riftPosition)
        
        teleportToClosestPoint(math.floor(riftPosition.Y))
        
        local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
        sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
        
        task.wait(5)
        
        print("Part 2: Preparing 'Slow & Steady' movement...")
        performMovement(safeTargetPosition)
        
        print("Movement successful. Main sequence finished.")
        startAutoPressR()
    end)

    if not success then
        warn("An error occurred during main sequence: " .. tostring(errorMessage))
        getgenv().autoPressR = false
        local failurePayload = {content = "RIFT_SEARCH_FAILED: " .. tostring(errorMessage)}
        sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
    end
else
    print("Target '" .. TARGET_EGG_NAME .. "' not found after 15 seconds. Sending failure report.")
    getgenv().autoPressR = false
    local failurePayload = {content = "RIFT_SEARCH_FAILED_NOT_FOUND"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
