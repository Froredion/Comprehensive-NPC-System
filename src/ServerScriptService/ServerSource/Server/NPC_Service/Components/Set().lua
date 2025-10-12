local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Set = {}

---- Knit Services
local NPC_Service

--[[
	Manually set target for NPC
	
	@param npcModel Model - The NPC model
	@param target Model? - Target to set (nil to clear)
]]
function Set:SetTarget(npcModel, target)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData then
		npcData.CurrentTarget = target
		npcData.TargetInSight = target ~= nil
		if target then
			npcData.LastSeenTarget = tick()
		end
	end
end

--[[
	Manually set destination for NPC
	
	@param npcModel Model - The NPC model
	@param destination Vector3? - Destination to set (nil to clear)
]]
function Set:SetDestination(npcModel, destination)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if not npcData then
		return
	end

	-- Update destination in data
	npcData.Destination = destination

	-- If destination is nil, stop movement
	if not destination then
		local humanoid = npcModel:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:MoveTo(npcModel.PrimaryPart.Position) -- Stop in place
		end
		return
	end

	-- If NPC can't walk, don't try to move
	if not npcData.CanWalk then
		return
	end

	-- Actually trigger movement
	-- Use pathfinding if enabled, otherwise use simple MoveTo
	if npcData.UsePathfinding and NPC_Service.Components.PathfindingManager and npcData.Pathfinding then
		NPC_Service.Components.PathfindingManager.RunPath(npcData, destination)
	else
		-- Simple MoveTo for NPCs without pathfinding
		local humanoid = npcModel:FindFirstChild("Humanoid")
		if humanoid then
			humanoid:MoveTo(destination)
		end
	end
end

--[[
	Set NPC movement state
	
	@param npcModel Model - The NPC model
	@param state string - Movement state ("Idle", "Following", "Combat")
]]
function Set:SetMovementState(npcModel, state)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData then
		npcData.MovementState = state
	end
end

--[[
	Update NPC's custom data
	
	@param npcModel Model - The NPC model
	@param key string - Key to update
	@param value any - Value to set
]]
function Set:SetCustomData(npcModel, key, value)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData and npcData.CustomData then
		npcData.CustomData[key] = value
	end
end

--[[
	Destroy NPC and cleanup all associated data
	
	@param npcModel Model - The NPC model to destroy
]]
function Set:DestroyNPC(npcModel)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if not npcData then
		return
	end

	-- Mark as cleaned up
	npcData.CleanedUp = true

	-- Stop all threads
	for _, thread in pairs(npcData.TaskThreads) do
		if type(thread) == "thread" and coroutine.status(thread) ~= "dead" then
			pcall(function()
				task.cancel(thread)
			end)
		end
	end

	-- Disconnect all connections
	for _, connection in pairs(npcData.Connections) do
		if typeof(connection) == "RBXScriptConnection" then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end

	-- Stop pathfinding (if it was being used)
	if npcData.UsePathfinding and npcData.Pathfinding then
		pcall(function()
			npcData.Pathfinding:Stop()
			npcData.Pathfinding:Dump()
		end)
	end

	-- Cleanup sight detector visualizations
	if NPC_Service.Components.SightDetector and NPC_Service.Components.SightDetector.CleanupSightDetector then
		pcall(function()
			NPC_Service.Components.SightDetector:CleanupSightDetector(npcData)
		end)
	end

	-- Remove from registry
	NPC_Service.ActiveNPCs[npcModel] = nil

	-- Destroy model
	task.delay(5, function()
		pcall(function()
			npcModel:Destroy()
		end)
	end)
end

function Set.Start()
	-- Component start logic
end

function Set.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return Set
