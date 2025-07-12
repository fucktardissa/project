getgenv().AUTO_MODE_ENABLED = true
getgenv().AUTO_HATCH_ENABLED = false
getgenv().LUCK_25X_ONLY_MODE = true

local RIFT_NAMES_TO_SEARCH = {"festival-rift-3", "spikey-egg"}
local MAX_FAILED_SEARCHES = 3
local AUTO_HATCH_POSITION = Vector3.new(-123, 10, 5)

local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local VERTICAL_SPEED = 300
local HORIZONTAL_SPEED = 30
local PROXIMITY_DISTANCE = 15
local ENGAGEMENT_COOLDOWN = 15

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local TeleportService = game:GetService("TeleportService")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

local function findBestAvailableRift()
    if not getgenv().LUCK_25X_ONLY_MODE then
        if RIFT_PATH:FindFirstChild(RIFT_NAMES_TO_SEARCH[1]) then
            return RIFT_PATH:FindFirstChild(RIFT_NAMES_TO_SEARCH[1])
        end
    end

    local allRiftsInServer = RIFT_PATH:GetChildren()
    for _, riftObject in ipairs(allRiftsInServer) do
        local has25xLuck = false
        local success, err = pcall(function()
            local luckText = riftObject.Display.SurfaceGui.Icon.Luck.Text
            if string.find(luckText, "25") then
                has25xLuck = true
            end
        end)
        
        if not success then
            warn("Luck Check FAILED for rift '"..riftObject.Name.."'. Error: " .. tostring(err))
        end

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
    pcall(function()
        HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) })
    end)
end

local function simpleServerHop()
    print("No valid rifts found. Using advanced server hop to find a new server...")
    pcall(function()
        local ServersURL = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local Server, Next = nil, nil
        local function ListServers(cursor)
            return HttpService:JSONDecode(game:HttpGet(ServersURL .. ((cursor and "&cursor=" .. cursor) or "")))
        end
        repeat
            local Servers = ListServers(Next)
            if #Servers.data > 0 then
                Server = Servers.data[math.random(1, #Servers.data)]
            end
            Next = Servers.nextPageCursor
        until Server or not Next
        
        if Server and Server.playing < Server.maxPlayers and Server.id ~= game.JobId then
            print("Found a suitable server with "..Server.playing.." players. Teleporting...")
            getgenv().AUTO_MODE_ENABLED = false
            TeleportService:TeleportToPlaceInstance(game.PlaceId, Server.id, LocalPlayer)
        else
            print("Could not find a suitable server via API, falling back to simple hop.")
            getgenv().AUTO_MODE_ENABLED = false
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end
    end)
end

local function isNearLocation(targetPosition)
    local character = LocalPlayer.Character
    local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
    return humanoidRootPart and (humanoidRootPart.Position - targetPosition).Magnitude < PROXIMITY_DISTANCE
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
        ReplicatedStorage.Shared.Framework.Network.Remote.RemoteEvent:FireServer("Teleport", closestPoint.path)
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
    return (rayResult and rayResult.Position + Vector3.new(0, 4, 0)) or (originalPosition + Vector3.new(0, 4, 0))
end

local function performMovement(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and humanoidRootPart) then return end
    local originalCollisions = {}
    for _, part in ipairs(character:GetDescendants()) do if part:IsA("BasePart") then originalCollisions[part] = part.CanCollide; part.CanCollide = false; end end
    humanoid.PlatformStand = true
    local startPos = humanoidRootPart.Position
    local intermediatePos = CFrame.new(startPos.X, targetPosition.Y, startPos.Z)
    local verticalTime = (startPos - intermediatePos.Position).Magnitude / VERTICAL_SPEED
    TweenService:Create(humanoidRootPart, TweenInfo.new(verticalTime, Enum.EasingStyle.Linear), {CFrame = intermediatePos}):Play().Completed:Wait()
    local horizontalTime = (humanoidRootPart.Position - targetPosition).Magnitude / HORIZONTAL_SPEED
    TweenService:Create(humanoidRootPart, TweenInfo.new(horizontalTime, Enum.EasingStyle.Linear), {CFrame = CFrame.new(targetPosition)}):Play().Completed:Wait()
    humanoidRootPart.Anchored = true
    for part, canCollide in pairs(originalCollisions) do if part and part.Parent then part.CanCollide = canCollide; end end
    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
    task.wait(0.1)
    humanoidRootPart.Anchored = false
end

local function openRift()
    VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
    task.wait(0.1)
    VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
end

print("AUTO Script (Final Path Fix) Loaded. To stop, set getgenv().AUTO_MODE_ENABLED = false")

getgenv().isEngagedWithRift = getgenv().isEngagedWithRift or false

task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        task.wait(1)
        if getgenv().isEngagedWithRift then continue end

        local targetRiftInstance = findBestAvailableRift()
        if targetRiftInstance then
            getgenv().isEngagedWithRift = true
            
            sendWebhook(SUCCESS_WEBHOOK_URL, {embeds = {{title = "✅ "..targetRiftInstance.Name.." FOUND!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}})
            
            local safeSpot = findSafeLandingSpot(targetRiftInstance)
            if safeSpot and not isNearLocation(safeSpot) then
                print("Moving to "..targetRiftInstance.Name.."...")
                teleportToClosestPoint(math.floor(safeSpot.Y))
                task.wait(5)
                performMovement(safeSpot)
            end

            print("Arrived at '"..targetRiftInstance.Name.."'. Beginning persistent hatch...")
            while getgenv().AUTO_MODE_ENABLED and targetRiftInstance and targetRiftInstance.Parent do
                openRift()
                task.wait() 
            end

            print("Engagement with '"..targetRiftInstance.Name.."' has ended. Cooldown...")
            task.wait(ENGAGEMENT_COOLDOWN)
            getgenv().isEngagedWithRift = false
        else
            -- Server hop logic
            if not _G.failedSearchCounter then _G.failedSearchCounter = 0 end
            _G.failedSearchCounter = _G.failedSearchCounter + 1
            print("Search " .. _G.failedSearchCounter .. "/" .. MAX_FAILED_SEARCHES .. " complete. No valid rift found.")
            if _G.failedSearchCounter >= MAX_FAILED_SEARCHES then
                print("Max failed searches reached. Waiting 10 seconds before server hopping...")
                task.wait(1)
                simpleServerHop()
                _G.failedSearchCounter = 0
            end
        end
    end
    print("AUTO script stopped.")
end)
