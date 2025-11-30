--[[
	ClientPhysicsSync - Server-side position synchronization for UseAnimationController

	Handles:
	- Receiving position updates from simulating clients
	- Broadcasting updates to nearby clients only (distance-based)
	- Tracking NPC ownership
	- Handling client disconnection

	IMPORTANT: No position validation is performed to prevent ping-related false positives.
	This is an intentional design decision - see Main.md for details.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ClientPhysicsSync = {}

---- Knit Services
local NPC_Service

---- Configuration
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

---- State
local NPCOwnership = {} -- [npcID] = Player
local LastUpdateTimes = {} -- [npcID] = tick()
local NPCPositions = {} -- [npcID] = Vector3

---- Constants
local OWNERSHIP_TIMEOUT = 3.0 -- seconds before NPC is considered orphaned
local TIMEOUT_CHECK_INTERVAL = 5.0 -- how often to check for timeouts

--[[
	Called when a new client-physics NPC is spawned
]]
function ClientPhysicsSync.OnNPCSpawned(npcID, npcData)
	NPCPositions[npcID] = npcData.Position
	-- NPC starts unclaimed - will be picked up by nearby clients
end

--[[
	Called when a client-physics NPC is removed
]]
function ClientPhysicsSync.OnNPCRemoved(npcID)
	NPCOwnership[npcID] = nil
	LastUpdateTimes[npcID] = nil
	NPCPositions[npcID] = nil
end

--[[
	Handle position update from client

	@param fromPlayer Player - The player sending the update
	@param npcID string - The NPC ID
	@param newPosition Vector3 - New position
	@param newOrientation CFrame? - New orientation (optional)
]]
function ClientPhysicsSync.HandlePositionUpdate(fromPlayer, npcID, newPosition, newOrientation)
	-- Validate NPC exists
	local ActiveNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not ActiveNPCsFolder then
		return
	end

	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end

	-- Check if this player owns the NPC (or if unclaimed, auto-assign)
	local currentOwner = NPCOwnership[npcID]
	if currentOwner and currentOwner ~= fromPlayer then
		-- Another player owns this NPC, ignore update
		return
	end

	if not currentOwner then
		-- Auto-assign ownership on first update
		NPCOwnership[npcID] = fromPlayer
	end

	-- REMOVED: Position validation (caused false positives from ping/latency)
	-- We accept all position updates to ensure smooth gameplay for high-ping users

	-- Apply soft bounds check if enabled
	if OptimizationConfig.ExploitMitigation.SOFT_BOUNDS_ENABLED then
		newPosition = ClientPhysicsSync.SoftBoundsCheck(npcID, newPosition)
	end

	-- Debug: print position update receipt
	if not npcFolder:GetAttribute("_lastServerUpdatePrint") or tick() - npcFolder:GetAttribute("_lastServerUpdatePrint") > 3 then
		print(string.format("[TD_SERVER_RECV] NPC %s: Received position from %s: %s", npcID, fromPlayer.Name, tostring(newPosition)))
		npcFolder:SetAttribute("_lastServerUpdatePrint", tick())
	end

	-- Update position in ReplicatedStorage
	local positionValue = npcFolder:FindFirstChild("Position")
	if positionValue then
		positionValue.Value = newPosition
	end

	-- Update orientation if provided
	if newOrientation then
		local orientationValue = npcFolder:FindFirstChild("Orientation")
		if orientationValue then
			orientationValue.Value = newOrientation
		end
	end

	-- Track position and update time
	NPCPositions[npcID] = newPosition
	LastUpdateTimes[npcID] = tick()

	-- CRITICAL FIX: Update NPC data in service registry
	-- The server-side Tower Defense test reads from this data!
	if NPC_Service and NPC_Service.ActiveClientPhysicsNPCs then
		local npcData = NPC_Service.ActiveClientPhysicsNPCs[npcID]
		if npcData then
			npcData.Position = newPosition
			if newOrientation then
				npcData.Orientation = newOrientation
			end
		end
	end

	-- Broadcast to nearby clients ONLY
	ClientPhysicsSync.BroadcastToNearbyClients(npcID, newPosition, newOrientation, fromPlayer)
end

--[[
	Soft bounds check - clamps position instead of rejecting

	@param npcID string - The NPC ID
	@param reportedPosition Vector3 - The reported position
	@return Vector3 - Corrected position (clamped if needed)
]]
function ClientPhysicsSync.SoftBoundsCheck(npcID, reportedPosition)
	local ActiveNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not ActiveNPCsFolder then
		return reportedPosition
	end

	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return reportedPosition
	end

	local configValue = npcFolder:FindFirstChild("Config")
	if not configValue then
		return reportedPosition
	end

	local success, config = pcall(function()
		return game:GetService("HttpService"):JSONDecode(configValue.Value)
	end)

	if not success or not config then
		return reportedPosition
	end

	local spawnPos = Vector3.new(
		config.SpawnPosition and config.SpawnPosition.X or 0,
		config.SpawnPosition and config.SpawnPosition.Y or 0,
		config.SpawnPosition and config.SpawnPosition.Z or 0
	)
	local maxWanderRadius = config.MaxWanderRadius or OptimizationConfig.ExploitMitigation.DEFAULT_MAX_WANDER_RADIUS

	-- Check if NPC is outside expected area
	local distance = (Vector3.new(reportedPosition.X, 0, reportedPosition.Z) - Vector3.new(spawnPos.X, 0, spawnPos.Z)).Magnitude
	if distance > maxWanderRadius then
		-- Clamp to boundary instead of rejecting
		local direction = (Vector3.new(reportedPosition.X, 0, reportedPosition.Z) - Vector3.new(spawnPos.X, 0, spawnPos.Z)).Unit
		local clampedXZ = Vector3.new(spawnPos.X, 0, spawnPos.Z) + direction * maxWanderRadius
		return Vector3.new(clampedXZ.X, reportedPosition.Y, clampedXZ.Z)
	end

	return reportedPosition
end

--[[
	Broadcast position update only to clients within BROADCAST_DISTANCE
	This is the KEY optimization - reduces network traffic by 70-90%

	@param npcID string - The NPC ID
	@param position Vector3 - The position
	@param orientation CFrame? - The orientation
	@param excludePlayer Player? - Player to exclude from broadcast (the sender)
]]
function ClientPhysicsSync.BroadcastToNearbyClients(npcID, position, orientation, excludePlayer)
	local broadcastDistance = OptimizationConfig.ClientSimulation.BROADCAST_DISTANCE

	for _, player in pairs(Players:GetPlayers()) do
		-- Skip the sender (they already have the latest position)
		if player == excludePlayer then
			continue
		end

		local character = player.Character
		if character and character.PrimaryPart then
			local playerPosition = character.PrimaryPart.Position
			local distance = (playerPosition - position).Magnitude

			-- Only send update if player is within broadcast distance
			if distance <= broadcastDistance then
				-- Fire to specific client via Knit signal
				NPC_Service.Client.NPCPositionUpdated:Fire(player, npcID, position, orientation)
			end
		end
	end
end

--[[
	Claim ownership of an NPC

	@param player Player - The player claiming
	@param npcID string - The NPC ID
	@return boolean - Whether claim was successful
]]
function ClientPhysicsSync.ClaimNPC(player, npcID)
	-- Check if NPC exists
	local ActiveNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not ActiveNPCsFolder or not ActiveNPCsFolder:FindFirstChild(npcID) then
		return false
	end

	-- Check if already owned
	local currentOwner = NPCOwnership[npcID]
	if currentOwner and currentOwner ~= player then
		return false
	end

	-- Check ownership limit
	local ownedCount = 0
	for _, owner in pairs(NPCOwnership) do
		if owner == player then
			ownedCount = ownedCount + 1
		end
	end

	if ownedCount >= OptimizationConfig.ClientSimulation.MAX_SIMULATED_PER_CLIENT then
		return false
	end

	-- Assign ownership
	NPCOwnership[npcID] = player
	LastUpdateTimes[npcID] = tick()

	-- Notify fallback simulator
	if NPC_Service.Components.ServerFallbackSimulator then
		NPC_Service.Components.ServerFallbackSimulator.MarkClaimed(npcID)
	end

	return true
end

--[[
	Release ownership of an NPC

	@param player Player - The player releasing
	@param npcID string - The NPC ID
]]
function ClientPhysicsSync.ReleaseNPC(player, npcID)
	if NPCOwnership[npcID] == player then
		NPCOwnership[npcID] = nil
		LastUpdateTimes[npcID] = nil

		-- Notify fallback simulator
		if NPC_Service.Components.ServerFallbackSimulator then
			NPC_Service.Components.ServerFallbackSimulator.MarkUnclaimed(npcID)
		end

		-- Broadcast that this NPC needs a new owner
		ClientPhysicsSync.BroadcastOrphanedNPCs({ npcID })
	end
end

--[[
	Handle player disconnection

	@param player Player - The player who left
]]
function ClientPhysicsSync.HandlePlayerLeft(player)
	local orphanedNPCs = {}

	-- Find all NPCs owned by this player
	for npcID, owner in pairs(NPCOwnership) do
		if owner == player then
			NPCOwnership[npcID] = nil
			LastUpdateTimes[npcID] = nil
			table.insert(orphanedNPCs, npcID)

			-- Notify fallback simulator
			if NPC_Service.Components.ServerFallbackSimulator then
				NPC_Service.Components.ServerFallbackSimulator.MarkUnclaimed(npcID)
			end
		end
	end

	-- Broadcast orphaned NPCs to all remaining clients
	if #orphanedNPCs > 0 then
		ClientPhysicsSync.BroadcastOrphanedNPCs(orphanedNPCs)
	end
end

--[[
	Broadcast orphaned NPCs to all clients

	@param npcIDs {string} - List of orphaned NPC IDs
]]
function ClientPhysicsSync.BroadcastOrphanedNPCs(npcIDs)
	local ActiveNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not ActiveNPCsFolder then
		return
	end

	-- Get positions for distance-based claiming
	local npcPositions = {}
	for _, npcID in ipairs(npcIDs) do
		local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
		if npcFolder then
			local positionValue = npcFolder:FindFirstChild("Position")
			if positionValue then
				npcPositions[npcID] = positionValue.Value
			end
		end
	end

	-- Fire to all clients
	NPC_Service.Client.NPCsOrphaned:FireAll(npcPositions)
end

--[[
	Check for timed-out NPCs (client crashed without disconnecting)
]]
function ClientPhysicsSync.CheckForTimeouts()
	local now = tick()
	local orphanedNPCs = {}

	for npcID, lastUpdate in pairs(LastUpdateTimes) do
		if now - lastUpdate > OWNERSHIP_TIMEOUT then
			-- NPC hasn't received updates - owner likely crashed
			local owner = NPCOwnership[npcID]
			NPCOwnership[npcID] = nil
			LastUpdateTimes[npcID] = nil
			table.insert(orphanedNPCs, npcID)

			-- Notify fallback simulator
			if NPC_Service.Components.ServerFallbackSimulator then
				NPC_Service.Components.ServerFallbackSimulator.MarkUnclaimed(npcID)
			end
		end
	end

	if #orphanedNPCs > 0 then
		ClientPhysicsSync.BroadcastOrphanedNPCs(orphanedNPCs)
	end
end

--[[
	Start the timeout checker loop
]]
function ClientPhysicsSync.StartTimeoutChecker()
	task.spawn(function()
		while true do
			task.wait(TIMEOUT_CHECK_INTERVAL)
			ClientPhysicsSync.CheckForTimeouts()
		end
	end)
end

--[[
	Get current owner of an NPC

	@param npcID string - The NPC ID
	@return Player? - The owning player or nil
]]
function ClientPhysicsSync.GetOwner(npcID)
	return NPCOwnership[npcID]
end

--[[
	Check if an NPC is claimed

	@param npcID string - The NPC ID
	@return boolean
]]
function ClientPhysicsSync.IsClaimed(npcID)
	return NPCOwnership[npcID] ~= nil
end

function ClientPhysicsSync.Start()
	-- Start timeout checker
	ClientPhysicsSync.StartTimeoutChecker()
end

function ClientPhysicsSync.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return ClientPhysicsSync
