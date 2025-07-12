getgenv().AUTO_MODE_ENABLED = true
getgenv().AUTO_HATCH_ENABLED = false
getgenv().LUCK_25X_ONLY_MODE = false
--hiihhiihihih
local RIFT_NAMES_TO_SEARCH = {"spikey-egg", "festival-rift-3", "festival-rift-2"}
local MAX_FAILED_SEARCHES = 3
local AUTO_HATCH_POSITION = Vector3.new(-123, 10, 5)

local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local VERTICAL_SPEED = 300
local HORIZONTAL_SPEED = 30
local PROXIMITY_DISTANCE = 15

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

local lastWebhookSendTime = 0
local WEBHOOK_COOLDOWN = 2

local function findBestAvailableRift()
    if not getgenv().LUCK_25X_ONLY_MODE then
        if RIFT_PATH:FindFirstChild(RIFT_NAMES_TO_SEARCH[1]) then
            return RIFT_PATH:FindFirstChild(RIFT_NAMES_TO_SEARCH[1])
        end
    end

    local allRiftsInServer = RIFT_PATH:GetChildren()
    for _, riftObject in ipairs(allRiftsInServer) do
        local has25xLuck = false
        pcall(function()
            if string.find(riftObject.Display.Icon.Luck.Text, "25") then
                has25xLuck = true
            end
        end)
        
        if has25xLuck then
            for _, targetName in ipairs(RIFT_NAMES_TO_SEARCH) do
                if riftObject.Name == targetName then
                    print("Found 25x rift '"..riftObject.Name.."' and it matches our target list.")
                    return riftObject
                end
            end
        end
    end
    return nil
end

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
    print("No valid rifts found. Using advanced server hop to find a new server...")
    pcall(function()
        local ServersURL = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local Server, Next = nil, nil
        local function ListServers(cursor)
            local Raw = game:HttpGet(ServersURL .. ((cursor and "&cursor=" .. cursor) or ""))
            return HttpService:JSONDecode(Raw)
        end
        repeat
            local Servers = ListServers(Next)
            if #Servers.data > 0 then
                Server = Servers.data[math.random(1, math.max(1, math.floor(#Servers.data / 3)))]
            end
            Next = Servers.nextPageCursor
        until Server or not Next
        
        local didTeleport = false
        if Server and Server.playing < Server.maxPlayers and Server.id ~= game.JobId then
            print("Found a suitable server with "..Server.playing.." players. Teleporting...")
            TeleportService:TeleportToPlaceInstance(game.PlaceId, Server.id, LocalPlayer)
            didTeleport = true
        else
            print("Could not find a suitable server via API, falling back to simple hop.")
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
            didTeleport = true
        end

        if didTeleport then
            print("Teleport initiated. Halting script to prevent errors in this server.")
            getgenv().AUTO_MODE_ENABLED = false
        end
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
    print("Finding a safe landing spot...")
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
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    local camera = workspace.CurrentCamera

    if not (humanoid and humanoidRootPart and camera) then
        error("Movement failed: Character parts or camera not found.")
    end

    local originalCameraType = camera.CameraType
    camera.CameraType = Enum.CameraType.Scriptable

    local cameraConnection = RunService.RenderStepped:Connect(function()
        local lookAtPosition = humanoidRootPart.Position + Vector3.new(0, 2, 0)
        local cameraPosition = lookAtPosition + Vector3.new(0, 5, 20)
        camera.CFrame = CFrame.new(cameraPosition, lookAtPosition)
    end)

    local originalCollisions = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then originalCollisions[part] = part.CanCollide; part.CanCollide = false; end
    end
    local originalPlatformStand = humanoid.PlatformStand
    humanoid.PlatformStand = true

    -- =================================================================
    -- THE FIX: Anchor the part BEFORE the tweens start.
    -- =================================================================
    humanoidRootPart.Anchored = true

    local startPos = humanoidRootPart.Position
    local intermediatePos = CFrame.new(startPos.X, targetPosition.Y, startPos.Z)

    local verticalTime = (startPos - intermediatePos.Position).Magnitude / VERTICAL_SPEED
    local verticalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(verticalTime, Enum.EasingStyle.Linear), {CFrame = intermediatePos})
    verticalTween:Play()
    verticalTween.Completed:Wait()

    local horizontalTime = (humanoidRootPart.Position - targetPosition).Magnitude / HORIZONTAL_SPEED
    local horizontalTween = TweenService:Create(humanoidRootPart, TweenInfo.new(horizontalTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPosition)})
    horizontalTween:Play()
    horizontalTween.Completed:Wait()

    cameraConnection:Disconnect()

    humanoidRootPart.Velocity = Vector3.new(0, 0, 0)
    humanoid.PlatformStand = originalPlatformStand
    for part, canCollide in pairs(originalCollisions) do
        if part and part.Parent then part.CanCollide = canCollide; end
    end
    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
    
    -- Un-anchor the part at the very end to restore normal physics.
    task.wait(0.1)
    humanoidRootPart.Anchored = false

    camera.CameraType = originalCameraType
end
local function openRift()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
end

local function performAutoHatch()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
end

print("AUTO Script (Simplified Hatcher) Loaded. To stop, set getgenv().AUTO_MODE_ENABLED = false")

local failedSearchCounter = 0
local isEngaged = false

-- =================================================================
-- PERSISTENT HATCHER (Your Idea)
-- This runs in the background, constantly trying to open rifts.
-- =================================================================
task.spawn(function()
    print("Persistent hatcher started. It will continuously try to open rifts.")
    while getgenv().AUTO_MODE_ENABLED do
        openRift()
        task.wait() -- A small wait to prevent crashing
    end
end)


-- =================================================================
-- MAIN LOGIC LOOP
-- This now only focuses on finding and moving to rifts.
-- =================================================================
task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        task.wait(1)

        if isEngaged then
            continue
        end

        local targetRiftInstance = findBestAvailableRift()

        if targetRiftInstance then
            isEngaged = true -- Lock engagement
            failedSearchCounter = 0
            
            local safeSpot = findSafeLandingSpot(targetRiftInstance)
            if safeSpot and not isNearLocation(safeSpot) then
                print("Found valid rift "..targetRiftInstance.Name..". Moving into position...")
                sendWebhook(SUCCESS_WEBHOOK_URL, {embeds = {{title = "✅ "..targetRiftInstance.Name.." FOUND!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}})
                
                teleportToClosestPoint(math.floor(safeSpot.Y))
                task.wait(5)
                performMovement(safeSpot)
            end

            print("Arrived at '"..targetRiftInstance.Name.."'. The persistent hatcher will now take over.")
            
            -- Wait here until the rift we were targeting is gone
            repeat task.wait(0.5) until not (targetRiftInstance and targetRiftInstance.Parent)
            
            print("Rift '"..targetRiftInstance.Name.."' is gone. Resuming search.")
            isEngaged = false -- Release the lock

        elseif getgenv().AUTO_HATCH_ENABLED then
            if not isNearLocation(AUTO_HATCH_POSITION) then
                isEngaged = true
                print("No valid rifts found. Moving to auto-hatch position.")
                pcall(performMovement, AUTO_HATCH_POSITION)
                isEngaged = false
            else
                performAutoHatch()
            end

        else
            failedSearchCounter = failedSearchCounter + 1
            print("Search " .. failedSearchCounter .. "/" .. MAX_FAILED_SEARCHES .. " complete. No valid rift found.")
            if failedSearchCounter >= MAX_FAILED_SEARCHES then
                print("Max failed searches reached. Waiting 10 seconds before server hopping...")
                task.wait(1)
                simpleServerHop()
                failedSearchCounter = 0
            end
        end
    end
    print("AUTO script stopped because toggle was set to false.")
end)
