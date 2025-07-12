getgenv().AUTO_MODE_ENABLED = true
getgenv().LUCK_25X_ONLY_MODE = true

-- Configure your targets here
local RIFT_NAMES_TO_SEARCH = { "festival-rift-3", "spikey-egg"}
local MAX_FAILED_SEARCHES = 3
local SUCCESS_WEBHOOK_URL = ""

-- Services
local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local RIFT_PATH = workspace.Rendered.Rifts

-- The core search function
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
                    return riftObject
                end
            end
        end
    end
    return nil
end

-- Webhook function
local function sendWebhook(targetUrl, payload)
    pcall(function() HttpService:RequestAsync({ Url = targetUrl, Method = "POST", Headers = {["Content-Type"] = "application/json"}, Body = HttpService:JSONEncode(payload) }) end)
end

-- Server Hop function
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

print("AUTO Rift Finder Loaded. To stop, set getgenv().AUTO_MODE_ENABLED = false")

-- Global lock to prevent race conditions
getgenv().isEngagedWithRift = getgenv().isEngagedWithRift or false

-- Main Logic Loop
task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        task.wait(1)
        if getgenv().isEngagedWithRift then continue end

        local targetRift = findBestAvailableRift()
        if targetRift then
            getgenv().isEngagedWithRift = true
            
            print("FOUND TARGET: " .. targetRift.Name .. ". Sending notification and waiting for it to disappear.")
            sendWebhook(SUCCESS_WEBHOOK_URL, {content = "Found a valid rift: **" .. targetRift.Name .. "** in server: `" .. game.JobId .. "`"})
            
            -- This simple loop just waits until the rift is gone
            repeat
                task.wait(1)
            until not (targetRift and targetRift.Parent)

            print("Target " .. targetRift.Name .. " is gone. Resuming search.")
            getgenv().isEngagedWithRift = false
        else
            if not _G.failedSearchCounter then _G.failedSearchCounter = 0 end
            _G.failedSearchCounter = _G.failedSearchCounter + 1
            print("Search " .. _G.failedSearchCounter .. "/" .. MAX_FAILED_SEARCHES .. " complete. No valid rift found.")
            if _G.failedSearchCounter >= MAX_FAILED_SEARCHES then
                task.wait(10)
                simpleServerHop()
                _G.failedSearchCounter = 0
            end
        end
    end
end)
