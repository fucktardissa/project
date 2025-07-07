--[[
    Validator & Reporter Script (v14 - With Proven Tweening System)
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3" 
local SUCCESS_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local FAILURE_WEBHOOK_URL = "https://ptb.discord.com/api/webhooks/1391330776389259354/8W3Cphb1Lz_EPYiRKeqqt1FtqyhIvXPmgfRmCtjUQtX6eRO7-FuvKAVvNirx4AizKfNN"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 150 -- Studs per second.

-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

-- =============================================
-- UTILITY FUNCTIONS & STATE
-- =============================================

-- [+] ADDED: Global state controller for the tweening system from BESTVERSION.txt
local tweenController = {
    active = false,
    targetPosition = nil,
    currentTween = nil
}

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

-- [+] ADDED: Helper functions required by the new tweening system.
local function cancelCurrentTween()
    if tweenController.currentTween then
        pcall(function() tweenController.currentTween:Cancel() end)
        tweenController.currentTween = nil
    end
end

local function resetCharacterState(humanoid, originalState)
    if humanoid and humanoid.Parent then
        humanoid.WalkSpeed = originalState.WalkSpeed
        humanoid.AutoRotate = originalState.AutoRotate
        humanoid.JumpPower = originalState.JumpPower
    end
    workspace.Gravity = originalState.Gravity
    print("Player state and gravity restored.")
end

local function createMovementTween(humanoidRootPart, targetPos, speed)
    local distance = (humanoidRootPart.Position - targetPos).Magnitude
    local time = distance / math.max(1, speed)
    return TweenService:Create(
        humanoidRootPart,
        TweenInfo.new(time, Enum.EasingStyle.Linear),
        {CFrame = CFrame.new(targetPos)}
    )
end


-- [*] REPLACED: This is the new, proven tweening function from BESTVERSION.txt
local function tweenToTarget(targetPosition)
    cancelCurrentTween() -- Cancel any previous movement
    tweenController.active = true
    tweenController.targetPosition = targetPosition
    
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    local humanoid = character:WaitForChild("Humanoid")
    if not humanoidRootPart or not humanoid then tweenController.active = false; return end

    print("Part 2: Preparing smooth CFrame movement...")

    local originalState = {
        WalkSpeed = humanoid.WalkSpeed,
        AutoRotate = humanoid.AutoRotate,
        JumpPower = humanoid.JumpPower,
        Gravity = workspace.Gravity
    }

    humanoid.WalkSpeed = 0
    humanoid.AutoRotate = false
    humanoid.JumpPower = 0
    workspace.Gravity = 0
    
    -- Main movement loop
    task.spawn(function()
        while tweenController.active and humanoidRootPart and humanoidRootPart.Parent do
            local distanceToTarget = (humanoidRootPart.Position - targetPosition).Magnitude
            if distanceToTarget < 5 then
                print("Arrived at target.")
                break 
            end
            
            if not tweenController.currentTween then
                tweenController.currentTween = createMovementTween(humanoidRootPart, targetPosition, TWEEN_SPEED)
                tweenController.currentTween:Play()
            end
            
            task.wait(0.1)
        end
        
        -- Cleanup when loop ends
        cancelCurrentTween()
        resetCharacterState(humanoid, originalState)
        tweenController.active = false
    end)
    
    -- Wait for the movement to complete
    while tweenController.active do
        task.wait()
    end
    
    -- Post-arrival stabilization
    print("Locking player in place for 3 seconds...")
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
