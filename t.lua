--[[
    Validator & Reporter Script (v29 - Pathfinding Implementation)
    - Rebuilt movement to use PathfindingService for navigating complex obstacle fields.
    - Character now follows a calculated path of waypoints to the destination.
    - Added robust error handling for when a path cannot be found.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 150 -- Studs per second

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

-- =============================================
-- UTILITY FUNCTIONS (Unchanged)
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
-- REMADE TWEENING SYSTEM (v3 - Pathfinding)
-- =============================================

-- Main movement function now using PathfindingService
local function performMovement(targetPosition)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")

    if not (humanoid and humanoidRootPart) then
        warn("Movement failed: Character parts not found.")
        return
    end

    -- 1. Create a Path object with parameters for our character
    -- These parameters tell the pathfinder the size of our character to avoid tight spaces.
    local path = PathfindingService:CreatePath({
        AgentRadius = 3,
        AgentHeight = 6,
        AgentCanJump = false
    })

    -- 2. Compute the path from our current location to the safe target position
    print("Calculating path to destination...")
    local success, err = pcall(function()
        path:ComputeAsync(humanoidRootPart.Position, targetPosition)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        warn("Could not compute a valid path to the destination. Status: " .. tostring(path.Status))
        return -- Abort movement if no path exists
    end

    print("Path calculated successfully. Following waypoints...")
    local waypoints = path:GetWaypoints()

    -- 3. Setup character state for movement
    local originalAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false
    humanoid.PlatformStand = true

    -- 4. Move the character along each waypoint in the path
    for i, waypoint in ipairs(waypoints) do
        -- We can often skip the first waypoint as it's the start position
        if i == 1 and (waypoint.Position - humanoidRootPart.Position).Magnitude < 2 then
            continue
        end

        print(string.format("Moving to waypoint %d/%d at %s", i, #waypoints, tostring(waypoint.Position)))
        
        local distance = (humanoidRootPart.Position - waypoint.Position).Magnitude
        local timeToWaypoint = distance / TWEEN_SPEED
        local tween = TweenService:Create(humanoidRootPart, TweenInfo.new(timeToWaypoint, Enum.EasingStyle.Linear), {CFrame = CFrame.new(waypoint.Position)})
        
        tween:Play()
        tween.Completed:Wait() -- Wait for each small tween to finish before starting the next
    end

    print("Final waypoint reached. Stabilizing...")

    -- 5. Stabilize and Restore State
    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
    humanoidRootPart.Anchored = true
    task.wait(0.2)
    humanoidRootPart.Anchored = false
    humanoid.PlatformStand = false
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
        
        -- First, find the exact safe coordinate to land on
        local riftPosition = riftInstance:GetPivot().Position
        local safeTargetPosition = findSafeLandingSpot(riftPosition)
        
        -- Then, teleport to the closest major area
        teleportToClosestPoint(math.floor(riftPosition.Y))
        
        local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
        sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
        
        task.wait(5) -- Wait for teleport to settle
        
        -- Finally, use pathfinding to navigate from the teleport spot to the safe landing spot
        print("Part 2: Preparing pathfinding movement...")
        performMovement(safeTargetPosition)
        print("Main sequence finished.")
        
        startAutoPressR()
    end)

    if not success then
        warn("An error occurred during main sequence: " .. tostring(errorMessage))
        getgenv().autoPressR = false
        local failurePayload = {content = "RIFT_SEARCH_FAILED_DURING_EXECUTION"}
        sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
    end
else
    print("Target '" .. TARGET_EGG_NAME .. "' not found after 15 seconds. Sending failure report.")
    getgenv().autoPressR = false
    local failurePayload = {content = "RIFT_SEARCH_FAILED_NOT_FOUND"}
    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
end

print("Validator/Reporter Script has completed its run.")
