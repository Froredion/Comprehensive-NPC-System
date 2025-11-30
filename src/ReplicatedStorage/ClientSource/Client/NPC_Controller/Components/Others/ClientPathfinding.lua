--[[
	ClientPathfinding - NoobPath wrapper for client-side NPC pathfinding

	ARCHITECTURE OVERVIEW:
	----------------------
	This mirrors the server-side PathfindingManager but runs on the client
	for UseAnimationController NPCs with custom physics.

	KEY DIFFERENCES FROM SERVER:
	-----------------------------
	Server (PathfindingManager):
	- Uses NoobPath in NORMAL mode (automatic Humanoid movement)
	- NoobPath calls Humanoid:MoveTo() to move NPCs
	- Physical HumanoidRootPart exists on server
	- Roblox physics engine handles collision

	Client (ClientPathfinding):
	- Uses NoobPath in MANUAL mode (compute paths only)
	- NoobPath does NOT move the visual model
	- ClientNPCSimulator reads waypoints and updates npcData.Position
	- ClientPhysicsRenderer syncs visual model to npcData.Position
	- No physics - purely visual positioning

	HOW IT WORKS:
	-------------
	1. ClientPathfinding.CreatePath() creates NoobPath with ManualMovement=true
	2. ClientPathfinding.RunPath() starts path computation
	3. NoobPath generates waypoints but doesn't move anything
	4. ClientNPCSimulator reads current waypoint via GetWaypoint()
	5. ClientNPCSimulator updates npcData.Position toward waypoint
	6. When close enough, ClientNPCSimulator calls AdvanceWaypoint()
	7. Repeat steps 4-6 until destination reached

	VISUAL MODEL SYNC:
	------------------
	The visual model is NOT moved by pathfinding directly:
	- npcData.Position is the source of truth
	- ClientPhysicsRenderer syncs visual model CFrame to npcData.Position every RenderStepped
	- This keeps pathfinding logic separate from rendering

	BACKWARDS COMPATIBILITY:
	------------------------
	Server-side NPCs continue using PathfindingManager (normal NoobPath mode).
	This code ONLY affects client-side NPCs with UseAnimationController=true.

	Uses the same NoobPath library for consistent pathfinding behavior.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientPathfinding = {}

---- Dependencies
local NoobPath = require(ReplicatedStorage.SharedSource.Utilities.Pathfinding.NoobPath)
local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.RenderConfig)
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

--[[
	Create NoobPath instance for client-side NPC

	@param npcData table - Client-side NPC data
	@param visualModel Model - The visual NPC model with Humanoid
	@return NoobPath? - Configured pathfinding instance or nil
]]
function ClientPathfinding.CreatePath(npcData, visualModel)
	if not visualModel then
		return nil
	end

	local humanoid = visualModel:FindFirstChild("Humanoid")
	if not humanoid then
		warn("[ClientPathfinding] Visual model missing Humanoid for NPC:", npcData.ID)
		return nil
	end

	-- Get pathfinding config
	local pathConfig = OptimizationConfig.ClientPathfinding

	-- Create NoobPath instance with manual movement mode
	-- ManualMovement = true means NoobPath only computes paths, doesn't move the model
	local path = NoobPath.Humanoid(
		visualModel,
		{
			AgentRadius = pathConfig.AGENT_RADIUS,
			AgentHeight = pathConfig.AGENT_HEIGHT,
			AgentCanJump = pathConfig.AGENT_CAN_JUMP,
			WaypointSpacing = pathConfig.WAYPOINT_SPACING,
			Costs = pathConfig.TERRAIN_COSTS,
		},
		false, -- Precise (not needed for manual movement)
		true -- ManualMovement mode (only compute paths, don't auto-move)
	)

	-- Configure path settings
	path.Timeout = true -- Enable timeout detection
	path.Speed = npcData.Config.WalkSpeed or humanoid.WalkSpeed

	-- Show visualizer in debug mode
	if RenderConfig.DEBUG_MODE then
		path.Visualize = true
	end

	-- Setup automatic speed synchronization
	local speedConnection = humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if path then
			path.Speed = humanoid.WalkSpeed
		end
	end)

	-- Store connection for cleanup
	npcData.PathfindingConnections = npcData.PathfindingConnections or {}
	table.insert(npcData.PathfindingConnections, speedConnection)

	-- Setup error handling
	path.Error:Connect(function(errorType)
		ClientPathfinding.HandlePathError(npcData, errorType)
	end)

	-- Setup trapped detection (stuck/blocked)
	path.Trapped:Connect(function(reason)
		ClientPathfinding.HandlePathBlocked(npcData, visualModel, reason)
	end)

	-- Setup reached detection (destination arrived)
	path.Reached:Connect(function(waypoint, partial)
		-- In manual mode, Reached shouldn't clear destination until we confirm arrival
		-- The simulator will clear it when actually at destination
		if not npcData.Pathfinding or not npcData.Pathfinding.ManualMovement then
			npcData.Destination = nil
		end
	end)

	return path
end

--[[
	Handle pathfinding errors

	@param npcData table - NPC data
	@param errorType string - Error type from NoobPath
]]
function ClientPathfinding.HandlePathError(npcData, errorType)
	if errorType == "ComputationError" then
		-- Computation failed - clear destination after retries
		npcData._pathErrorCount = (npcData._pathErrorCount or 0) + 1
		if npcData._pathErrorCount > 3 then
			npcData.Destination = nil
			npcData._pathErrorCount = 0
		end
	elseif errorType == "TargetUnreachable" then
		-- Target unreachable - this might be a false positive due to async pathfinding
		-- Don't clear destination immediately, let rate limiting handle retries
		npcData._pathUnreachableCount = (npcData._pathUnreachableCount or 0) + 1

		-- Only clear after multiple consecutive failures
		if npcData._pathUnreachableCount > 5 then
			npcData.Destination = nil
			npcData._pathUnreachableCount = 0
		end
	elseif errorType == "AgentStuck" then
		npcData.Destination = nil
	end
end

--[[
	Handle NPC being blocked/stuck
	Client-side jump handling

	@param npcData table - NPC data
	@param visualModel Model - The visual model
	@param reason string - Reason for being blocked
]]
function ClientPathfinding.HandlePathBlocked(npcData, visualModel, reason)
	local humanoid = visualModel and visualModel:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	if reason == "ReachTimeout" then
		-- Try jumping to unstuck
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		npcData.IsJumping = true
		npcData.JumpVelocity = npcData.Config.JumpPower or 50
	elseif reason == "ReachFailed" then
		-- Clear destination and retry
		npcData.Destination = nil
	end
end

--[[
	Run pathfinding to destination

	@param npcData table - NPC data
	@param visualModel Model - The visual model
	@param destination Vector3 - Target destination
]]
function ClientPathfinding.RunPath(npcData, visualModel, destination)
	-- Respect UsePathfinding config: if false, don't use pathfinding
	local usePathfinding = npcData.Config.UsePathfinding
	if usePathfinding == nil then
		usePathfinding = true -- Default to true if not specified
	end

	if not usePathfinding then
		return -- Let SimulateMovement use fallback direct movement
	end

	-- Convert destination to ground-level coordinates (NoobPath expects Y ≈ 0)
	-- Pathfinding works on ground plane, not character height
	local groundDestination = Vector3.new(destination.X, 0, destination.Z)

	if not npcData.Pathfinding then
		npcData.Pathfinding = ClientPathfinding.CreatePath(npcData, visualModel)
	end

	if npcData.Pathfinding then
		npcData.Pathfinding:Run(groundDestination)

		-- Reset error counters on successful path start
		if not npcData.Pathfinding.Idle and #npcData.Pathfinding.Route > 0 then
			npcData._pathErrorCount = 0
			npcData._pathUnreachableCount = 0
		end

		--[[
			FIX: Manual movement mode index correction

			NoobPath:Run() calls TravelNextWaypoint() which increments Index from 1 to 2,
			skipping the first waypoint. In normal mode this is fine (Humanoid physics
			handles it), but in manual mode we need to read waypoints sequentially.

			Reset Index to 1 so GetWaypoint() returns the actual first waypoint.
			This ensures the NPC moves toward Route[1] instead of trying to reach
			Route[2] without going through Route[1] first.
		]]
		if npcData.Pathfinding.ManualMovement and not npcData.Pathfinding.Idle then
			npcData.Pathfinding.Index = 1
		end
	end
end

--[[
	Stop pathfinding

	@param npcData table - NPC data
]]
function ClientPathfinding.StopPath(npcData)
	if npcData.Pathfinding then
		pcall(function()
			npcData.Pathfinding:Stop()
		end)
	end
end

--[[
	Cleanup pathfinding for NPC

	@param npcData table - NPC data
]]
function ClientPathfinding.Cleanup(npcData)
	-- Stop pathfinding
	ClientPathfinding.StopPath(npcData)

	-- Disconnect connections
	if npcData.PathfindingConnections then
		for _, connection in pairs(npcData.PathfindingConnections) do
			if connection then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end
		npcData.PathfindingConnections = nil
	end

	-- Clear pathfinding instance
	if npcData.Pathfinding then
		pcall(function()
			npcData.Pathfinding:Dump()
		end)
		npcData.Pathfinding = nil
	end
end

--[[
	Check if pathfinding is active for NPC

	@param npcData table - NPC data
	@return boolean
]]
function ClientPathfinding.IsPathfindingActive(npcData)
	return npcData.Pathfinding ~= nil
end

function ClientPathfinding.Start()
	-- Component start
end

function ClientPathfinding.Init()
	-- Component init
end

return ClientPathfinding
