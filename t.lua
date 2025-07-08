--[[
    Validator & Reporter Script (v45 - Whitelist Raycast)
    - Implemented user's suggestion for a more reliable landing spot detection.
    - findSafeLandingSpot now uses a "whitelist" raycast.
    - It will ONLY detect hits on the island that the target rift is a part of, ignoring all other geometry like clouds.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local VERTICAL_SPEED = 500
local HORIZONTAL_SPEED = 35

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
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

-- THIS FUNCTION HAS BEEN COMPLETELY REBUILT WITH YOUR SUGGESTION
local function findSafeLandingSpot(riftInstance)
    print("Finding a safe landing spot using a whitelisted raycast...")
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local islandModel = riftInstance.Parent -- The model containing the rift and its island parts

    if not islandModel then
        warn("Could not find parent model of the rift.")
        return nil
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include -- Use a WHITELIST
    raycastParams.FilterDescendantsInstances = {islandModel} -- Only target parts within the island model
    raycastParams.IgnoreWater = true

    local originalPosition = riftInstance:GetPivot().Position
    local rayOrigin = originalPosition + Vector3.new(0, 100, 0)
    local rayDirection = Vector3.new(0, -200, 0) 

    local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if rayResult and rayResult.Instance then
        local groundPosition = rayResult.Position
        local finalTarget = groundPosition + Vector3.new(0, 4, 0)
        print("Safe landing spot found on target island at: " .. tostring(finalTarget))
        return finalTarget
    else
        warn("Whitelist raycast failed to find the target island ground.")
        -- Fallback to a position just above the rift's pivot as a last resort
        return originalPosition + Vector3.new(0, 4, 0)
    end
end

-- =============================================
-- MOVEMENT SYSTEM (Unchanged from v43)
-- =============================================
local function performMovement(targetPosition)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

    if not (humanoid and humanoidRootPart) then
        error("Movement failed: Character parts not found.")
    end

    local originalCollisions = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then originalCollisions[part] = part.CanCollide; part.CanCollide = false; end
    end
    local originalPlatformStand = humanoid.PlatformStand
    humanoid.PlatformStand = true

    local startPos = humanoidRootPart.Position
    local intermediatePos = CFrame.new(startPos.X, targetPosition.Y, startPos.Z)
    local verticalTime = (startPos - intermediatePos.Position).Magnitude / VERTICAL_SPEED
    local verticalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(verticalTime, Enum.EasingStyle.Linear), {CFrame = intermediatePos})
    
    verticalTween:Play()
    
    local direction = (intermediatePos.Position.Y > startPos.Y) and "UP" or "DOWN"
    local targetY = intermediatePos.Position.Y
    local connection = RunService.Heartbeat:Connect(function()
        local currentY = humanoidRootPart.Position.Y
        local conditionMet = (direction == "UP" and currentY >= targetY) or (direction == "DOWN" and currentY <= targetY)
        if conditionMet then
            verticalTween:Cancel()
        end
    end)
    
    verticalTween.Completed:Wait()
    connection:Disconnect()
    
    local horizontalTime = (humanoidRootPart.Position - targetPosition).Magnitude / HORIZONTAL_SPEED
    local horizontalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(horizontalTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPosition)})
    horizontalTween:Play()
    horizontalTween.Completed:Wait()

    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
    humanoidRootPart.Anchored = true
    humanoid.PlatformStand = originalPlatformStand
    for part, canCollide in pairs(originalCollisions) do
        if part and part.Parent then part.CanCollide = canCollide; end
    end
    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
    task.wait(0.1)
    humanoidRootPart.Anchored = false
end

-- =============================================
-- AUTO-PRESS 'R' UTILITY & MAIN EXECUTION
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

print("Validator/Reporter Script Started. Searching for: " .. TARGET_EGG_NAME)
local riftInstance = RIFT_PATH:WaitForChild(TARGET_EGG_NAME, 15)

if riftInstance then
    local success, errorMessage = pcall(function()
        print("Target found! Beginning sequence.")
        
        -- The function call is updated to pass the riftInstance
        local safeTargetPosition = findSafeLandingSpot(riftInstance)
        
        if not safeTargetPosition then
            error("Could not determine a safe landing spot on the target island.")
        end
        
        teleportToClosestPoint(math.floor(safeTargetPosition.Y))
        
        local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
        sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
        
        task.wait(5)
        
        print("Part 2: Preparing whitelisted movement...")
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
