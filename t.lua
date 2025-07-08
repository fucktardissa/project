--[[
    Validator & Reporter Script (v25 - Pathfinding Movement)
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3" 
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
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
-- NEW PATHFINDING MOVEMENT SYSTEM
-- =============================================

local function walkToTarget(targetPosition)
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then
        warn("Pathfinding failed: Character models not found.")
        return
    end

    -- Create a path object
    local path = PathfindingService:CreatePath()
    
    -- Compute the path from current position to target
    local success, errorMessage = pcall(function()
        path:ComputeAsync(rootPart.Position, targetPosition)
    end)

    if not success or path.Status ~= Enum.PathStatus.Success then
        warn("Pathfinding failed: Could not compute a valid path. Reason: " .. tostring(errorMessage or path.Status.Name))
        -- As a fallback, try to walk directly to the target
        humanoid:MoveTo(targetPosition)
        humanoid.MoveToFinished:Wait(5) -- Wait up to 5 seconds for the fallback
        return
    end

    print("Pathfinding successful. Following waypoints...")
    local waypoints = path:GetWaypoints()

    -- Follow the computed path
    for _, waypoint in ipairs(waypoints) do
        -- Check if the waypoint is an obstacle and move to the next if it is
        if waypoint.Action == Enum.PathWaypointAction.Jump then
            humanoid.Jump = true
        end
        
        humanoid:MoveTo(waypoint.Position)
        
        -- Wait until the character reaches the waypoint or a timeout occurs
        local timeWaited = 0
        while (rootPart.Position - waypoint.Position).Magnitude > 4 and timeWaited < 5 do
            task.wait(0.1)
            timeWaited = timeWaited + 0.1
        end
        
        if timeWaited >= 5 then
            warn("Pathfinding timeout: Took too long to reach a waypoint. Stopping.")
            break
        end
    end
    print("Path following complete.")
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
        
        -- Wait for teleport to settle
        task.wait(5) 
        
        -- Use the new pathfinding movement
        walkToTarget(safeTargetPosition)
        
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
