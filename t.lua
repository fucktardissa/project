--[[
    Validator & Reporter Script (v49 - Auto-Hatch Fallback)
    - Added AUTO_HATCH_ENABLED toggle.
    - If no rifts are found and toggle is true, script will move to a set location and auto-hatch.
    - While auto-hatching, it continues to scan for rifts and will engage immediately if one is found.
    - If auto-hatch is disabled, it will revert to server hopping after failed searches.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
getgenv().AUTO_MODE_ENABLED = true -- Set to false in your executor to stop the script
getgenv().AUTO_HATCH_ENABLED = true -- NEW: Set to true to enable the auto-hatch fallback routine

local RIFT_NAMES_TO_SEARCH = {"spikey-egg", "festival-rift-3", "festival-rift-2", "festival-rift-1"}
local MAX_FAILED_SEARCHES = 3 -- Number of times to search before server hopping (if auto-hatch is off)
local AUTO_HATCH_POSITION = Vector3.new(-123, 10, 5) -- The position for the auto-hatch fallback

local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local VERTICAL_SPEED = 300
local HORIZONTAL_SPEED = 30
local PROXIMITY_DISTANCE = 15 -- How close to be to a target to be considered "near"

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
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

local function simpleServerHop()
    print("No rifts found after " .. MAX_FAILED_SEARCHES .. " searches. Hopping to a new server...")
    pcall(function()
        TeleportService:Teleport(game.PlaceId, LocalPlayer)
    end)
end

local function isNearLocation(targetPosition)
    local character = LocalPlayer.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then return false end
    return (humanoidRootPart.Position - targetPosition).Magnitude < PROXIMITY_DISTANCE
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

local function findSafeLandingSpot(riftInstance)
    print("Finding a safe landing spot using a whitelisted raycast...")
    local islandModel = riftInstance.Parent
    if not islandModel then warn("Could not find parent model of the rift.") return nil end
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = {islandModel}
    raycastParams.IgnoreWater = true
    local originalPosition = riftInstance:GetPivot().Position
    local rayOrigin = originalPosition + Vector3.new(0, 100, 0)
    local rayDirection = Vector3.new(0, -200, 0) 
    local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)
    if rayResult and rayResult.Instance then
        return rayResult.Position + Vector3.new(0, 4, 0)
    else
        warn("Whitelist raycast failed to find the target island ground.")
        return originalPosition + Vector3.new(0, 4, 0)
    end
end

local function performMovement(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and humanoidRootPart) then error("Movement failed: Character parts not found.") end
    local originalCollisions = {}
    for _, part in ipairs(character:GetDescendants()) do if part:IsA("BasePart") then originalCollisions[part] = part.CanCollide; part.CanCollide = false; end end
    local originalPlatformStand = humanoid.PlatformStand
    humanoid.PlatformStand = true
    local startPos = humanoidRootPart.Position
    local intermediatePos = CFrame.new(startPos.X, targetPosition.Y, startPos.Z)
    local verticalTime = (startPos - intermediatePos.Position).Magnitude / VERTICAL_SPEED
    local verticalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(verticalTime, Enum.EasingStyle.Linear), {CFrame = intermediatePos})
    verticalTween:Play(); verticalTween.Completed:Wait()
    local horizontalTime = (humanoidRootPart.Position - targetPosition).Magnitude / HORIZONTAL_SPEED
    local horizontalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(horizontalTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPosition)})
    horizontalTween:Play(); horizontalTween.Completed:Wait()
    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
    humanoid.PlatformStand = originalPlatformStand
    for part, canCollide in pairs(originalCollisions) do if part and part.Parent then part.CanCollide = canCollide; end end
end

local function openRift()
    print("Attempting to open special rift...")
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
end

-- NEW FUNCTION FOR THE FALLBACK HATCHING
local function performAutoHatch()
    print("Performing auto-hatch action at base...")
    -- NOTE: You may need to change Enum.KeyCode.E to your game's hatch key
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

-- =============================================
-- MAIN EXECUTION (RESTRUCTURED)
-- =============================================
print("AUTO Script (v49 - Auto-Hatch) Loaded. To stop, set getgenv().AUTO_MODE_ENABLED = false")

local failedSearchCounter = 0
local notifiedAboutRift = {}

task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        -- STEP 1: Always scan for a priority rift first.
        local targetRiftInstance = nil
        for _, riftName in ipairs(RIFT_NAMES_TO_SEARCH) do
            local found = RIFT_PATH:FindFirstChild(riftName)
            if found then
                targetRiftInstance = found
                break -- Found the highest priority rift, stop searching.
            end
        end

        -- STEP 2: Decide what to do based on the scan result.
        
        -- PRIORITY 1: A RIFT WAS FOUND
        if targetRiftInstance then
            failedSearchCounter = 0 -- Reset counter since we found a rift
            local safeSpot = findSafeLandingSpot(targetRiftInstance)

            if safeSpot and not isNearLocation(safeSpot) then
                print("Rift "..targetRiftInstance.Name.." located. Moving to engage.")
                -- Send webhook notification only once per rift instance
                if not notifiedAboutRift[targetRiftInstance] then
                    local successPayload = {embeds = {{title = "✅ "..targetRiftInstance.Name.." FOUND!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
                    sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
                    notifiedAboutRift[targetRiftInstance] = true
                end
                teleportToClosestPoint(math.floor(safeSpot.Y))
                task.wait(5)
                performMovement(safeSpot)
            else
                -- We are already near the rift, just keep opening it.
                if not targetRiftInstance.Parent then
                    print("Rift has disappeared.")
                    notifiedAboutRift[targetRiftInstance] = nil -- Allow re-notification if it returns
                else
                    print("Already at rift "..targetRiftInstance.Name..". Continuing to open.")
                    openRift()
                end
            end
        
        -- PRIORITY 2: NO RIFT FOUND -> AUTO-HATCH FALLBACK
        elseif getgenv().AUTO_HATCH_ENABLED then
            notifiedAboutRift = {} -- Clear notifications since no rifts exist
            if not isNearLocation(AUTO_HATCH_POSITION) then
                print("No rifts found. Moving to auto-hatch position.")
                performMovement(AUTO_HATCH_POSITION)
            else
                -- We are at the hatching spot, perform the hatch action
                performAutoHatch()
            end

        -- PRIORITY 3: NO RIFT & NO AUTO-HATCH -> SERVER HOP
        else
            notifiedAboutRift = {}
            failedSearchCounter = failedSearchCounter + 1
            print("Search " .. failedSearchCounter .. "/" .. MAX_FAILED_SEARCHES .. " complete. No rift found.")
            if failedSearchCounter >= MAX_FAILED_SEARCHES then
                simpleServerHop()
                failedSearchCounter = 0 -- Reset after hopping
            end
        end
        
        task.wait(1) -- A short delay in the main loop to prevent excessive CPU usage.
    end
    print("AUTO script stopped because toggle was set to false.")
end)
