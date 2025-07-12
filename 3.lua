getgenv().AUTO_MODE_ENABLED = true
getgenv().AUTO_HATCH_ENABLED = false
getgenv().LUCK_25X_ONLY_MODE = true

local RIFT_NAMES_TO_SEARCH = {"festival-rift-3", "spikey-egg"}
local MAX_FAILED_SEARCHES = 3
local MOVEMENT_MAX_ATTEMPTS = 3 -- Max number of times to try moving before giving up

local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local VERTICAL_SPEED = 300
local HORIZONTAL_SPEED = 30
local PROXIMITY_DISTANCE = 15

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

local function performMovement(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and humanoidRootPart) then return end

    for _, part in ipairs(character:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = false end end
    humanoid.PlatformStand = true
    humanoidRootPart.Anchored = true

    local startCFrameV = humanoidRootPart.CFrame
    local endCFrameV = CFrame.new(startCFrameV.Position.X, targetPosition.Y, startCFrameV.Position.Z)
    local durationV = (startCFrameV.Position - endCFrameV.Position).Magnitude / VERTICAL_SPEED
    local elapsedV = 0
    while elapsedV < durationV do
        local dt = RunService.Heartbeat:Wait()
        elapsedV = math.min(elapsedV + dt, durationV)
        humanoidRootPart.CFrame = startCFrameV:Lerp(endCFrameV, elapsedV / durationV)
    end
    humanoidRootPart.CFrame = endCFrameV

    local startCFrameH = humanoidRootPart.CFrame
    local endCFrameH = CFrame.new(targetPosition)
    local durationH = (startCFrameH.Position - endCFrameH.Position).Magnitude / HORIZONTAL_SPEED
    local elapsedH = 0
    while elapsedH < durationH do
        local dt = RunService.Heartbeat:Wait()
        elapsedH = math.min(elapsedH + dt, durationH)
        humanoidRootPart.CFrame = startCFrameH:Lerp(endCFrameH, elapsedH / durationH)
    end
    humanoidRootPart.CFrame = endCFrameH
end

local function restoreCharacterState()
    local character = LocalPlayer.Character
    if not character then return end
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if humanoidRootPart then humanoidRootPart.Anchored = false end
    for _, part in ipairs(character:GetDescendants()) do if part:IsA("BasePart") then part.CanCollide = true end end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end
    print("Character state restored to normal.")
end

local function findBestAvailableRift()
    if not getgenv().LUCK_25X_ONLY_MODE then
        for _, name in ipairs(RIFT_NAMES_TO_SEARCH) do
            local rift = RIFT_PATH:FindFirstChild(name)
            if rift then return rift end
        end
    end
    local allRiftsInServer = RIFT_PATH:GetChildren()
    for _, riftObject in ipairs(allRiftsInServer) do
        local has25xLuck = false
        pcall(function() if string.find(riftObject.Display.SurfaceGui.Icon.Luck.Text, "25") then has25xLuck = true end end)
        if has25xLuck then
            for _, targetName in ipairs(RIFT_NAMES_TO_SEARCH) do
                if riftObject.Name == targetName then return riftObject end
            end
        end
    end
    return nil
end

local function sendWebhook(targetUrl, payload)
    pcall(function() HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) }) end)
end

local function simpleServerHop()
    print("No valid rifts found. Hopping...")
    pcall(function()
        local servers = HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"))
        local server = servers.data and #servers.data > 0 and servers.data[math.random(1, #servers.data)]
        if server and server.playing < server.maxPlayers and server.id ~= game.JobId then
            getgenv().AUTO_MODE_ENABLED = false
            TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
        else
            getgenv().AUTO_MODE_ENABLED = false
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end
    end)
end

local function isNearLocation(targetPosition)
    local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    return root and (root.Position - targetPosition).Magnitude < PROXIMITY_DISTANCE
end

local function teleportToClosestPoint(targetHeight)
    local teleportPoints = {
        {name = "Zen", path = "Workspace.Worlds.The Overworld.Islands.Zen.Island.Portal.Spawn", height = 15970},
        {name = "The Void", path = "Workspace.Worlds.The Overworld.Islands.The Void.Island.Portal.Spawn", height = 10135},
        {name = "Twilight", path = "Workspace.Worlds.The Overworld.Islands.Twilight.Island.Portal.Spawn", height = 6855},
        {name = "Outer Space", path = "Workspace.Worlds.The Overworld.Islands.Outer Space.Island.Portal.Spawn", height = 2655}
    }
    local closestPoint
    local smallestDifference = math.huge
    for _, point in ipairs(teleportPoints) do
        local difference = math.abs(point.height - targetHeight)
        if difference < smallestDifference then
            smallestDifference = difference
            closestPoint = point
        end
    end
    if closestPoint then
        print("Teleporting to closest portal: " .. closestPoint.name)
        ReplicatedStorage.Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", closestPoint.path)
    end
end

local function findSafeLandingSpot(riftInstance)
    print("Finding a safe landing spot...")
    local islandModel = riftInstance.Parent
    if not islandModel then return nil end
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = {islandModel}
    local origin = riftInstance:GetPivot().Position + Vector3.new(0, 100, 0)
    local result = workspace:Raycast(origin, Vector3.new(0, -200, 0), raycastParams)
    return result and (result.Position + Vector3.new(0, 4, 0)) or (origin - Vector3.new(0, 96, 0))
end

local function openRift()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
end

print("AUTO Script (Retry Loop) Loaded.")
getgenv().isEngagedWithRift = getgenv().isEngagedWithRift or false

task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        openRift()
        task.wait()
    end
end)

task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        task.wait(1)
        if getgenv().isEngagedWithRift then continue end

        local targetRift = findBestAvailableRift()
        if targetRift then
            getgenv().isEngagedWithRift = true
            local safeSpot = findSafeLandingSpot(targetRift)
            local movementSuccess = false

            if safeSpot and not isNearLocation(safeSpot) then
                local attempts = 0
                repeat
                    attempts = attempts + 1
                    print(string.format("Attempting to move to rift (Attempt %d/%d)...", attempts, MOVEMENT_MAX_ATTEMPTS))
                    
                    local preTeleportPosition = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character.HumanoidRootPart.Position
                    teleportToClosestPoint(safeSpot.Y)
                    
                    if preTeleportPosition then
                        local timeout = 15; local timeWaited = 0
                        while LocalPlayer.Character and (LocalPlayer.Character.HumanoidRootPart.Position - preTeleportPosition).Magnitude < 100 and timeWaited < timeout do
                            task.wait(0.2); timeWaited = timeWaited + 0.2
                        end
                    else
                        task.wait(5)
                    end
                    
                    performMovement(safeSpot)
                    task.wait(1) -- Wait a second for anti-cheat to act
                    
                    if isNearLocation(safeSpot) then
                        print("Movement successful and position verified.")
                        movementSuccess = true
                    else
                        warn("Movement failed or was reverted. Retrying in 2 seconds...")
                        task.wait(2)
                    end
                until movementSuccess or attempts >= MOVEMENT_MAX_ATTEMPTS
            else
                movementSuccess = true -- Already near, so movement is considered successful
            end

            if movementSuccess then
                print("Arrived at '"..targetRift.Name.."'. Restoring character to hatch.")
                restoreCharacterState()
                
                print("Waiting for rift to disappear...")
                repeat task.wait(0.5) until not (targetRift and targetRift.Parent)
            else
                warn("Failed to move to rift after " .. MOVEMENT_MAX_ATTEMPTS .. " attempts. Aborting.")
            end

            print("Engagement finished. Resuming search.")
            getgenv().isEngagedWithRift = false
        else
            if not _G.failedSearchCounter then _G.failedSearchCounter = 0 end
            _G.failedSearchCounter = _G.failedSearchCounter + 1
            print("Search " .. _G.failedSearchCounter .. "/" .. MAX_FAILED_SEARCHES .. " complete.")
            if _G.failedSearchCounter >= MAX_FAILED_SEARCHES then
                task.wait(10)
                simpleServerHop()
                _G.failedSearchCounter = 0
            end
        end
    end
end)
