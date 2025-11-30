--[[
	PlayerCollisionHandler - Handles player character collision group assignment

	Monitors Players service for new players and applies collision groups to their
	characters on spawn and respawn.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PlayerCollisionHandler = {}

---- Knit Services
local CollisionService

---- Player connections
local PlayerConnections = {} -- [player] = {connections}

--[[
	Handle player character added
	
	@param player Player - The player instance
	@param character Model - The character model
]]
local function onCharacterAdded(player, character)
	-- Wait for character to fully load
	local hrp = character:WaitForChild("HumanoidRootPart", 10)
	if not hrp then
		warn("[PlayerCollisionHandler] Character missing HumanoidRootPart for:", player.Name)
		return
	end
	
	-- Apply player collision group
	if CollisionService and CollisionService.Components.CharacterCollisionHandler then
		CollisionService.Components.CharacterCollisionHandler:ApplyCollisionGroup(character, "Players")
		print(string.format("[PlayerCollisionHandler] Applied 'Players' collision group to %s", player.Name))
	end
end

--[[
	Handle player added
	
	@param player Player - The player instance
]]
local function onPlayerAdded(player)
	-- Create connections table for this player
	if not PlayerConnections[player] then
		PlayerConnections[player] = {}
	end
	
	-- Connect to CharacterAdded for all future spawns/respawns
	local characterConnection = player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	table.insert(PlayerConnections[player], characterConnection)
	
	-- Apply to current character if it exists
	if player.Character then
		local character = player.Character
		if character:FindFirstChild("HumanoidRootPart") then
			onCharacterAdded(player, character)
		else
			-- Wait for character to load
			task.spawn(function()
				character:WaitForChild("HumanoidRootPart", 10)
				onCharacterAdded(player, character)
			end)
		end
	end
end

--[[
	Handle player removing
	
	@param player Player - The player instance
]]
local function onPlayerRemoving(player)
	-- Cleanup connections
	local connections = PlayerConnections[player]
	if connections then
		for _, connection in ipairs(connections) do
			if typeof(connection) == "RBXScriptConnection" then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end
		PlayerConnections[player] = nil
	end
end

--[[
	Initialize player collision monitoring
	Called during CollisionService:KnitStart()
]]
function PlayerCollisionHandler:Initialize()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(onPlayerAdded, player)
	end
	
	-- Connect to player events
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	
	print("[PlayerCollisionHandler] Initialized - monitoring player characters for collision group assignment")
end

function PlayerCollisionHandler.Start()
	-- Component start logic
end

function PlayerCollisionHandler.Init()
	CollisionService = Knit.GetService("CollisionService")
end

return PlayerCollisionHandler
