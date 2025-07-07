--[[
    Validator & Reporter Script (v15 - Redundant Tweening)
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3" 
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 150

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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
    if now - lastWebhookSendTime < WEBHOOK_COOLDOWN then
        warn("Webhook cooldown active. Skipping report.")
        return
    end
    if not targetUrl or not string.match(targetUrl, "discord.com/api/webhooks") then
        warn("Invalid webhook URL.")
        return
    end
    local success, result = pcall(function()
        HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) })
    end)
    if not success then
        warn("Webhook failed to send! Error: " .. tostring(result))
    else
        lastWebhookSendTime = now
        print("Webhook report sent successfully.")
    end
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

local function setPlayerCollision(canCollide)
    local character = LocalPlayer.Character
    if not character then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = canCollide
        end
    end
end

local movementConnection = nil
local function executeMovement(humanoidRootPart, targetPosition)
    if not humanoidRootPart or not humanoidRootPart.Parent then return end
    
    setPlayerCollision(false)
    
    movementConnection = RunService.Heartbeat:Connect(function()
        if not humanoidRootPart.Parent then
            movementConnection:Disconnect()
            setPlayerCollision(true)
            return
        end
        local currentPosition = humanoidRootPart.Position
        local distance = (targetPosition - currentPosition).Magnitude
        if distance < 10 then
            movementConnection:Disconnect()
            movementConnection = nil
            humanoidRootPart.Velocity = Vector3.new(0,0,0)
            return
        end
        local direction = (targetPosition - currentPosition).Unit
        humanoidRootPart.Velocity = direction * TWEEN_SPEED
    end)
    
    task.spawn(function()
        while movementConnection do
            setPlayerCollision(false)
            task.wait()
        end
    end)
    
    while movementConnection do
        task.wait()
    end
    
    setPlayerCollision(true)
end

-- [*] MODIFIED: This function now includes the retry loop you suggested.
local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    if not humanoidRootPart then return end

    print("Part 2: Preparing redundant movement...")

    local retryAttempts = 0
    local MAX_RETRIES = 3
    
    -- Loop to ensure the player arrives and stays at the target
    while retryAttempts < MAX_RETRIES and (humanoidRootPart.Position - targetPosition).Magnitude > 20 do
        if retryAttempts > 0 then
            warn("Player is too far from target after tween. Retrying... (Attempt " .. retryAttempts .. ")")
        end
        
        executeMovement(humanoidRootPart, targetPosition)
        retryAttempts = retryAttempts + 1
    end
    
    if (humanoidRootPart.Position - targetPosition).Magnitude <= 20 then
        print("Movement successful. Arrived at target.")
    else
        warn("Failed to get player to target position after " .. MAX_RETRIES .. " retries.")
    end

    print("Locking player in place for 3 seconds to stabilize physics...")
    task.wait(3)
    print("Player unlocked.")
end

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
        local safeTargetPosition = riftPosition + Vector3.new(0, 5, 0)
        
        teleportToClosestPoint(math.floor(riftPosition.Y))
        
        local successPayload = {embeds = {{title = "✅ EGG FOUND! Movement Started!", color = 3066993, thumbnail = {url = EGG_THUMBNAIL_URL}}}}
        sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
        
        task.wait(3)
        
        tweenToTarget(safeTargetPosition)
        startAutoPressR()
    end)

    if not success then
        warn("An error occurred during movement sequence: " .. tostring(errorMessage))
        getgenv().autoPressR = false 
        setPlayerCollision(true)
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
