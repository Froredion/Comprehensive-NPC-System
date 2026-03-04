local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local PathfindingManager = {}

--[[
	PathfindingManager provides advanced pathfinding capabilities for NPCs.
	This component is only used when UsePathfinding is enabled in the NPC configuration.
	When disabled, NPCs will use simple Humanoid:MoveTo() instead.
]]

---- Configuration (loaded from RenderConfig)
local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.RenderConfig)

---- Utilities
local NoobPath = require(ReplicatedStorage.SharedSource.Utilities.Pathfinding.NoobPath)

---- Knit Services
local NPC_Service

--[[
	Create NoobPath instance for NPC with appropriate configuration
	
	@param npc Model - The NPC model
	@return NoobPath - Configured pathfinding instance
]]
function PathfindingManager.CreatePath(npc)
	local humanoid = npc:FindFirstChild("Humanoid")
	if not humanoid then
		warn("[PathfindingManager] NPC missing Humanoid:", npc.Name)
		return nil
	end

	-- Create NoobPath instance using Humanoid method
	local path = NoobPath.Humanoid(npc, {
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
		WaypointSpacing = 4,
		Costs = {
			Water = math.huge, -- Avoid water
		},
	})

	-- Configure path settings
	path.Timeout = true -- Enable timeout detection
	path.Speed = humanoid.WalkSpeed

	-- Show path visualizer if enabled (configured in RenderConfig)
	if RenderConfig.SHOW_PATH_VISUALIZER then
		path.Visualize = true
	else
	end

	-- Setup automatic speed synchronization when WalkSpeed changes
	-- This ensures NoobPath timeout calculations stay accurate
	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if path then
			path.Speed = humanoid.WalkSpeed
		end
	end)

	-- Setup error handling
	path.Error:Connect(function(errorType)
		PathfindingManager.HandlePathError(npc, errorType)
	end)

	-- Setup trapped detection (stuck/blocked)
	path.Trapped:Connect(function(reason)
		PathfindingManager.HandlePathBlocked(npc, reason)
	end)

	return path
end

--[[
	Handle pathfinding errors
	
	@param npc Model - The NPC model
	@param errorType string - Error type from NoobPath
]]
function PathfindingManager.HandlePathError(npc, errorType)
	local npcData = NPC_Service.ActiveNPCs[npc]
	if not npcData then
		return
	end

	if errorType == "ComputationError" then
		warn("[PathfindingManager] Computation error for NPC:", npc.Name)
		-- Clear destination and retry later
		npcData.Destination = nil
	elseif errorType == "TargetUnreachable" then
		-- Target is unreachable, clear destination
		npcData.Destination = nil
	end
end

--[[
	Handle NPC being blocked/stuck
	
	@param npc Model - The NPC model
	@param reason string - Reason for being trapped
]]
function PathfindingManager.HandlePathBlocked(npc, reason)
	local npcData = NPC_Service.ActiveNPCs[npc]
	if not npcData then
		return
	end

	local humanoid = npc:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	if reason == "ReachTimeout" then
		-- NPC took too long to reach waypoint, try jumping
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	elseif reason == "ReachFailed" then
		-- Failed to reach waypoint, clear destination
		npcData.Destination = nil
	end
end

--[[
	Run pathfinding to destination (ASYNC - non-blocking)

	Path computation runs in background thread. This prevents the main
	thread from yielding during PathfindingService computation.

	If called while a previous computation is running, the old one is cancelled
	and a new computation starts with the updated destination.

	@param npcData table - NPC instance data
	@param destination Vector3 - Target destination
]]
function PathfindingManager.RunPath(npcData, destination)
	if not npcData.Pathfinding then
		npcData.Pathfinding = PathfindingManager.CreatePath(npcData.Model)
	end

	if npcData.Pathfinding then
		-- Increment version to cancel any in-progress computation (wrap at 100)
		local newVersion = ((npcData._pathVersion or 0) % 100) + 1
		npcData._pathVersion = newVersion
		local thisVersion = newVersion

		-- Run path computation in background thread
		task.spawn(function()
			-- Safety check in case NPC was destroyed during yield
			if not npcData.Pathfinding then
				return
			end

			-- Compute the path (this is the blocking call)
			npcData.Pathfinding:Run(destination)

			-- Check if this computation was cancelled (newer one started)
			if npcData._pathVersion ~= thisVersion then
				return -- Cancelled, discard results
			end

			-- Safety check in case NPC was destroyed during computation
			if not npcData.Pathfinding then
				return
			end

			-- Reset error counters on successful path start
			if not npcData.Pathfinding.Idle and #npcData.Pathfinding.Route > 0 then
				npcData._pathErrorCount = 0
			end
		end)
	end
end

--[[
	Stop pathfinding
	
	@param npcData table - NPC instance data
]]
function PathfindingManager.StopPath(npcData)
	if npcData.Pathfinding then
		npcData.Pathfinding:Stop()
	end
end

function PathfindingManager.Start()
	-- Component start logic
end

function PathfindingManager.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return PathfindingManager
