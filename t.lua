--[[
    Validator & Reporter Script (v28 - Remade Tweening System)
    - Implemented a 3-part (Up, Across, Down) tweening method to avoid obstacles.
    - Improved post-movement stabilization to prevent character flinging.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 200 -- Studs per second (increased for efficiency with the new system)
local CLEARANCE_ALTITUDE = 150 -- Studs to ascend to avoid obstacles

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
    -- This function remains unchanged as requested.
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
        local finalTarget = groundPosition + Vector3.new(0, 3, 0) -- Standard 3-stud offset from ground
        print("Safe landing spot found at: " .. tostring(finalTarget))
        return finalTarget
    else
        warn("Raycast failed to find ground. Falling back to original target logic.")
        return originalPosition + Vector3.new(0, 5, 0)
    end
end

-- =============================================
-- REMADE TWEENING SYSTEM (v2)
-- =============================================

-- A reusable function to create, run, and wait for a single tween to complete.
local function executeTween(rootPart, targetCFrame, speed)
    local distance = (rootPart.Position - targetCFrame.Position).Magnitude
    if distance < 1 then return true end -- Skip if already there

    local travelTime = distance / speed
    local tweenInfo = TweenInfo.new(travelTime, Enum.EasingStyle.Linear)
    local tween = TweenService:Create(rootPart, tweenInfo, {CFrame = targetCFrame})
    
    tween:Play()

    -- Wait for the tween to finish with a timeout
    local startTime = tick()
    local timeout = travelTime + 5 -- Give 5 extra seconds for safety
    repeat
        task.wait()
    until tween.PlaybackState == Enum.PlaybackState.Completed or tick() - startTime > timeout

    if tween.PlaybackState ~= Enum.PlaybackState.Completed then
        warn("A tween segment failed to complete. State: " .. tostring(tween.PlaybackState))
        tween:Cancel()
        return false -- Indicate failure
    end
    
    return true -- Indicate success
end

-- The main movement function using the new 3-part tweening logic.
local function performMovement(targetPosition)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

    if not (humanoid and humanoidRootPart) then
        warn("Movement failed: Character parts not found.")
        return
    end

    -- 1. Setup and State Change
    local originalAutoRotate = humanoid.AutoRotate
    local originalPlatformStand = humanoid.PlatformStand
    humanoid.AutoRotate = false
    humanoid.PlatformStand = true -- Temporarily enables "flying" behavior, helpful for this method
    task.wait(0.1) -- Allow state to apply

    -- 2. Define Waypoints for 3-Part Movement
    local startPosition = humanoidRootPart.Position
    local ascentPoint = CFrame.new(startPosition.X, startPosition.Y + CLEARANCE_ALTITUDE, startPosition.Z)
    local traversePoint = CFrame.new(targetPosition.X, ascentPoint.Position.Y, targetPosition.Z)
    local finalDestination = CFrame.new(targetPosition)

    -- 3. Execute Movement Sequence
    print("Beginning 3-part movement...")
    
    -- Part A: Ascend
    print("Ascending to clearance altitude...")
    if not executeTween(humanoidRootPart, ascentPoint, TWEEN_SPEED) then
        warn("Failed to ascend. Aborting movement.")
    else
        -- Part B: Traverse
        print("Traversing to target coordinates...")
        if not executeTween(humanoidRootPart, traversePoint, TWEEN_SPEED) then
            warn("Failed to traverse. Aborting movement.")
        else
            -- Part C: Descend
            print("Descending to final landing spot...")
            executeTween(humanoidRootPart, finalDestination, TWEEN_SPEED * 0.75) -- Descend slightly slower
        end
    end
    
    print("Movement sequence finished. Stabilizing...")

    -- 4. Stabilize and Restore State (Crucial to prevent flinging)
    humanoidRootPart.Velocity = Vector3.new(0, 0, 0) -- Kill all momentum
    humanoidRootPart.Anchored = true
    task.wait(0.2) -- Hold position firmly
    humanoidRootPart.Anchored = false
    humanoid.PlatformStand = originalPlatformStand
    humanoid.AutoRotate = originalAutoRotate
    print("Character stabilized.")
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
            task.wait(0.1) -- Small delay between presses
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
        
        task.wait(5) -- Wait for teleport to settle
        
        print("Part 2: Preparing remade movement...")
        performMovement(safeTargetPosition)
        print("Main sequence finished.")
        
        startAutoPressR()
    end)

    if not success then
        warn("An error occurred during main sequence: " .. tostring(errorMessage))
        getgenv().autoPressR = false 
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
