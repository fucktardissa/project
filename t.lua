--[[
    Validator & Reporter Script (v23 - Anchoring Lock)
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3" 
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 150 -- This is now studs per second

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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

    if raycastResult and raycastResult.Instance.CanCollide then
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
-- ROBUST TWEENING SYSTEM
-- =============================================

local currentMovementTween = nil

local function cancelCurrentTween()
    if currentMovementTween then
        currentMovementTween:Cancel()
        currentMovementTween = nil
    end
end

local function resetCharacterState(humanoid, originalState)
    if humanoid and humanoid.Parent then
        humanoid.WalkSpeed = originalState.WalkSpeed
        humanoid.AutoRotate = originalState.AutoRotate
        humanoid.JumpPower = originalState.JumpPower
    end
    workspace.Gravity = originalState.Gravity
end

local function createMovementTween(humanoidRootPart, targetPos, speed)
    local distance = (humanoidRootPart.Position - targetPos).Magnitude
    local time = distance / math.max(1, speed)
    local tweenInfo = TweenInfo.new(time, Enum.EasingStyle.Linear)
    local goals = {CFrame = CFrame.new(targetPos)}
    return TweenService:Create(humanoidRootPart, tweenInfo, goals)
end

-- [*] MODIFIED: This function now includes an anchoring lock to prevent flinging.
local function performTweenMovement(humanoidRootPart, targetPosition)
    local character = humanoidRootPart.Parent
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    cancelCurrentTween()

    local originalState = {
        WalkSpeed = humanoid.WalkSpeed,
        AutoRotate = humanoid.AutoRotate,
        JumpPower = humanoid.JumpPower,
        Gravity = workspace.Gravity
    }

    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = false
    humanoid.JumpPower = 0
    workspace.Gravity = 0

    local movementTween = createMovementTween(humanoidRootPart, targetPosition, TWEEN_SPEED)
    currentMovementTween = movementTween
    movementTween:Play()

    movementTween.Completed:Wait()

    -- New anchoring lock to stabilize the character and prevent flinging
    humanoidRootPart.Anchored = true
    task.wait(0.5) -- Wait for a moment while anchored
    humanoidRootPart.Anchored = false

    -- Now it's safe to restore the character's state
    resetCharacterState(humanoid, originalState)
    currentMovementTween = nil
end

local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    print("Part 2: Preparing movement...")

    local retryAttempts = 0
    local MAX_RETRIES = 3

    while retryAttempts < MAX_RETRIES and (humanoidRootPart.Position - targetPosition).Magnitude > 5 do
        if retryAttempts > 0 then
            warn("Player is too far from target after movement. Retrying... (Attempt " .. retryAttempts .. ")")
        end
        
        performTweenMovement(humanoidRootPart, targetPosition)
        retryAttempts = retryAttempts + 1
    end
    
    if (humanoidRootPart.Position - targetPosition).Magnitude <= 5 then
        print("Movement successful. Arrived at target.")
    else
        warn("Failed to get player to target position after " .. MAX_RETRIES .. " retries.")
    end

    -- The old lock is no longer needed as the new anchoring lock is more effective.
end

-- =============================================

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

local riftInstance = RIFT_PATH:WaitForChild(TARGET_EGG_NAME, 15)

if riftInstance then
    local success, errorMessage = pcall(function()
        print("Target found! Beginning two-part movement sequence.")
        
        local riftPosition = riftInstance:GetPivot().Position
        local safeTargetPosition = findSafeLandingSpot(riftPosition)
        
        teleportToClosestPoint(math.floor(riftPosition.Y))
        
        local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
        sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
        
        task.wait(3)
        
        tweenToTarget(safeTargetPosition)
        startAutoPressR()
    end)

    if not success then
        warn("An error occurred during movement sequence: " .. tostring(errorMessage))
        getgenv().autoPressR = false 
        
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then
            resetCharacterState(hum, {WalkSpeed = 16, AutoRotate = true, JumpPower = 50, Gravity = workspace.Gravity})
            hum.Parent:FindFirstChild("HumanoidRootPart").Anchored = false
        end
        
        local failurePayload = {content = "RIFT_SEARCH_FAILED"}
        sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
    end
else
    print("Target '" .. TARGET_EGG_NAME .. "' not found after 15 seconds. Sending failure report.")
    getgenv().autoPressR = false 
    local failurePayload = {content = "RIFT_SEARCH_FAILED"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
