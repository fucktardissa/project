--[[
    Validator & "Teleport then Tween" Script
    - This script validates if a target egg exists.
    - If found, it executes a two-part movement sequence to avoid anti-cheat detection.
    - Part 1: Uses the in-game portal system to teleport to the closest major island.
    - Part 2: Uses TweenService to smoothly move the character from the portal to the egg's final location.
]]

-- =============================================
-- CONFIGURATION (Edit These Values)
-- =============================================
local TARGET_EGG_NAME = "festival-rift-3"
local MINIMUM_LUCK_MULTIPLIER = 1
local SUCCESS_WEBHOOK_URL = "YOUR_SUCCESS_WEBHOOK_URL_HERE"
local EGG_THUMBNAIL_URL = "https://www.bgsi.gg/eggs/july4th-egg.png"
local TWEEN_SPEED = 200 -- Studs per second. Adjust if this feels too fast or too slow.


-- =============================================
-- SERVICES & REFERENCES
-- =============================================
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts


-- =============================================
-- UTILITY FUNCTIONS
-- =============================================

--- Sends a pre-formatted payload to a Discord webhook URL.
local function sendWebhook(targetUrl, payload)
    if not targetUrl or not string.find(targetUrl, "https://discord.com/api/webhooks") then
        warn("Webhook function called with an invalid or missing URL.")
        return
    end
    pcall(function()
        HttpService:RequestAsync({
            Url = targetUrl, Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = HttpService:JSONEncode(payload)
        })
    end)
end


--- Part 1: Finds the closest portal and uses the in-game teleport function.
local function teleportToClosestPoint(targetHeight)
    -- A table containing your preset teleport locations and their heights.
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
    else
        warn("Could not determine the closest teleport point.")
    end
end


--- Part 2: Smoothly tweens the character from their current position to a target position.
local function tweenToTarget(targetPosition)
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

    if not humanoidRootPart then return end

    print("Part 2: Preparing to tween to final coordinates...")
    
    local distance = (humanoidRootPart.Position - targetPosition).Magnitude
    local duration = distance / TWEEN_SPEED -- Calculate time based on distance and speed.

    -- Create the tweening properties.
    local tweenInfo = TweenInfo.new(
        duration,
        Enum.EasingStyle.Linear, -- A constant speed is best for this.
        Enum.EasingDirection.Out
    )
    
    local goal = {
        CFrame = CFrame.new(targetPosition)
    }

    -- Create and play the tween.
    local tween = TweenService:Create(humanoidRootPart, tweenInfo, goal)
    tween:Play()
    print("Tween initiated. Estimated travel time: " .. string.format("%.2f", duration) .. " seconds.")
end


-- =============================================
-- MAIN EXECUTION
-- =============================================
print("Validator Script Started. Searching for: " .. TARGET_EGG_NAME)
task.wait(10) -- Wait 10 seconds for all game assets to load.

local riftInstance = RIFT_PATH:FindFirstChild(TARGET_EGG_NAME)
local luckValue = 0

-- Check if the rift exists and get its luck value.
if riftInstance and riftInstance:FindFirstChild("Display") then
    local surfaceGui = riftInstance.Display:FindFirstChild("SurfaceGui")
    if surfaceGui and surfaceGui:FindFirstChild("Icon") and surfaceGui.Icon:FindFirstChild("Luck") then
        local numString = string.gsub(surfaceGui.Icon.Luck.Text, "[^%d%.%-]", "")
        luckValue = tonumber(numString) or 0
    end
end

-- Final check: Does the rift exist and meet our minimum luck requirement?
if riftInstance and luckValue >= MINIMUM_LUCK_MULTIPLIER then
    -- SUCCESS! The egg is here and it's valid.
    print("Target found! Beginning two-part movement sequence.")

    local riftPosition = riftInstance.Display.Position
    local riftHeight = math.floor(riftPosition.Y)

    -- 1. Execute the portal teleport first.
    teleportToClosestPoint(riftHeight)
    
    -- 2. Send the success webhook immediately so you are notified.
    local successPayload = {
        embeds = {{
            title = "✅ EGG FOUND! Movement Started!",
            description = string.format("Target `%s` located. Initiating Teleport then Tween sequence.", TARGET_EGG_NAME),
            color = 3066993, -- Green
            thumbnail = { url = EGG_THUMBNAIL_URL },
            footer = { text = "Teleport then Tween Script" }
        }}
    }
    sendWebhook(SUCCESS_WEBHOOK_URL, successPayload)
    
    -- 3. Wait for the teleport to complete, then start the tween to the final position.
    task.wait(3) -- Wait a few seconds for the character to load after the portal teleport.
    tweenToTarget(riftPosition)
    
else
    -- FAILURE: The egg was not found or did not meet the luck requirement.
    print("Target not found in this server. Script finishing.")
end

print("Validator Script has completed its run.")
