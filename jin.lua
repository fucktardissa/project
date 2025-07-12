getgenv().AUTO_MODE_ENABLED = true
getgenv().AUTO_HATCH_ENABLED = false
getgenv().LUCK_25X_ONLY_MODE = true

local RIFT_NAMES_TO_SEARCH = {"festival-rift-3", "spikey-egg"}
local MAX_FAILED_SEARCHES = 3
local AUTO_HATCH_POSITION = Vector3.new(-123, 10, 5)

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
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

local function performMovement(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and humanoidRootPart) then return end

    local originalCollisions = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            originalCollisions[part] = part.CanCollide
            part.CanCollide = false
        end
    end
    humanoid.PlatformStand = true
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
    
    for part, canCollide in pairs(originalCollisions) do
        if part and part.Parent then
            part.CanCollide = canCollide
        end
    end
    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
    humanoidRootPart.Anchored = false
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
        pcall(function()
            if string.find(riftObject.Display.SurfaceGui.Icon.Luck.Text, "25") then
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

print("AUTO Script (Dynamic Wait Fix) Loaded.")
getgenv().isEngagedWithRift = getgenv().isEngagedWithRift or false

task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        openRift() -- Persistent hatcher
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
            if safeSpot and not isNearLocation(safeSpot) then
                print("Found valid rift "..targetRift.Name..". Moving into position...")
                sendWebhook(SUCCESS_WEBHOOK_URL, {embeds = {{title = "✅ "..targetRift.Name.." FOUND!", color = 3066993}}})
                
                local preTeleportPosition = LocalPlayer.Character.HumanoidRootPart.Position
                teleportToClosestPoint(safeSpot.Y)
                
                print("Waiting for teleport to complete...")
                local timeout = 15
                local timeWaited = 0
                while (LocalPlayer.Character.HumanoidRootPart.Position - preTeleportPosition).Magnitude < 100 and timeWaited < timeout do
                    task.wait(0.2)
                    timeWaited = timeWaited + 0.2
                end
                
                if timeWaited >= timeout then
                    warn("Teleport took too long or failed! Movement may not work correctly.")
                else
                    print("Teleport confirmed. Proceeding with final movement.")
                end
                
                performMovement(safeSpot)
            end
            print("Arrived at '"..targetRift.Name.."'. Waiting for it to disappear.")
            repeat task.wait(0.5) until not (targetRift and targetRift.Parent)
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
