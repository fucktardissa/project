--[[
    Validator & Reporter Script (v48 - Search Priority)
    - Reordered the RIFT_NAMES_TO_SEARCH list to prioritize rifts in the order 3, 2, then 1 as requested.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
getgenv().AUTO_MODE_ENABLED = true -- Set to false in your executor to stop the script

-- ** THIS LINE HAS BEEN UPDATED WITH THE NEW PRIORITY **
local RIFT_NAMES_TO_SEARCH = {"festival-rift-3", "festival-rift-2", "festival-rift-1"}

local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local VERTICAL_SPEED = 300
local HORIZONTAL_SPEED = 30

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

local function findSafeLandingSpot(riftInstance)
    print("Finding a safe landing spot using a whitelisted raycast...")
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local islandModel = riftInstance.Parent

    if not islandModel then
        warn("Could not find parent model of the rift.")
        return nil
    end

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Include
    raycastParams.FilterDescendantsInstances = {islandModel}
    raycastParams.IgnoreWater = true

    local originalPosition = riftInstance:GetPivot().Position
    local rayOrigin = originalPosition + Vector3.new(0, 100, 0)
    local rayDirection = Vector3.new(0, -200, 0) 

    local rayResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    if rayResult and rayResult.Instance then
        local groundPosition = rayResult.Position
        local finalTarget = groundPosition + Vector3.new(0, 4, 0)
        return finalTarget
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
    humanoidRootPart.Anchored = true
    humanoid.PlatformStand = originalPlatformStand
    for part, canCollide in pairs(originalCollisions) do
        if part and part.Parent then part.CanCollide = canCollide; end
    end
    humanoid:ChangeState(Enum.HumanoidStateType.Landed)
    task.wait(0.1)
    humanoidRootPart.Anchored = false
    
    camera.CameraType = originalCameraType
end

local function openRift()
    print("Attempting to open rift by pressing 'R'...")
    local pressDuration = 3 
    local startTime = tick()
    while tick() - startTime < pressDuration do
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.R, false, game)
        task.wait()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.R, false, game)
        task.wait(0.1)
    end
    print("Finished opening rift.")
end

-- =============================================
-- MAIN EXECUTION (AUTO MODE)
-- =============================================
print("AUTO Rift Script v48 Loaded. To stop, set getgenv().AUTO_MODE_ENABLED = false")

task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        local riftFoundAndProcessed = false
        
        for _, riftName in ipairs(RIFT_NAMES_TO_SEARCH) do
            local riftInstance = RIFT_PATH:FindFirstChild(riftName)
            
            if riftInstance then
                print("Target found: " .. riftName)
                
                local success, errorMessage = pcall(function()
                    local safeTargetPosition = findSafeLandingSpot(riftInstance)
                    if not safeTargetPosition then
                        error("Could not determine a safe landing spot for " .. riftName)
                    end
                    
                    teleportToClosestPoint(math.floor(safeTargetPosition.Y))
                    local successPayload = {embeds = {{title = "✅ "..riftName.." FOUND!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
                    sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
                    
                    task.wait(5)
                    
                    print("Preparing polished movement...")
                    performMovement(safeTargetPosition)
                    
                    print("Movement successful. Opening rift...")
                    openRift()
                end)

                if success then
                    print("Successfully processed " .. riftName .. ". Cooling down before next search.")
                    riftFoundAndProcessed = true
                    break
                else
                    warn("An error occurred while processing " .. riftName .. ": " .. tostring(errorMessage))
                    local failurePayload = {content = "RIFT_PROCESS_FAILED: " .. tostring(errorMessage)}
                    sendWebhook(FAILURE_WEBHOOK_URL, failurePayload)
                end
            end
        end
        
        if riftFoundAndProcessed then
            task.wait(10)
        else
            task.wait(1)
        end
    end
    print("AUTO Rift script stopped because toggle was set to false.")
end)
