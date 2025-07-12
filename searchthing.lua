getgenv().AUTO_MODE_ENABLED = true
getgenv().LUCK_25X_ONLY_MODE = true

-- Configure your targets here
local RIFT_NAMES_TO_SEARCH = { "festival-rift-3", "spikey-egg"}
local MAX_FAILED_SEARCHES = 3

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

print("Rift Finder & Loader Loaded. To stop, set getgenv().AUTO_MODE_ENABLED = false")

-- Main Logic Loop
task.spawn(function()
    while getgenv().AUTO_MODE_ENABLED do
        task.wait(2) -- Check every 2 seconds

        local targetRift = findBestAvailableRift()
        if targetRift then
            -- =================================================================
            -- TARGET FOUND - EXECUTING YOUR SCRIPT
            -- =================================================================
            print("FOUND TARGET: " .. targetRift.Name .. ". Loading main script...")
            
            -- Stop this script's loops to prevent conflicts
            getgenv().AUTO_MODE_ENABLED = false

            -- Configure settings for the new script
            getgenv().boardSettings = {
                UseGoldenDice = true,
                GoldenDiceDistance = 1,
                DiceDistance = 6,
                GiantDiceDistance = 10,
            }
            getgenv().remainingItems = {} 

            -- Load and run the main script from GitHub
            -- Wrapped in a pcall to prevent errors if GitHub is down
            local success, err = pcall(function()
                loadstring(game:HttpGet("https://raw.githubusercontent.com/IdiotHub/Scripts/refs/heads/main/BGSI/main.lua"))()
            end)

            if not success then
                warn("Failed to load the main script from GitHub: " .. tostring(err))
            end
            
            -- This finder script will now go idle.
            break 
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
    print("Rift Finder script has handed over control and is now stopped.")
end)
