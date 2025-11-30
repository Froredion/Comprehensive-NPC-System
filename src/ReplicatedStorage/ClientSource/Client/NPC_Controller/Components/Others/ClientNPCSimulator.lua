--[[
	ClientNPCSimulator - Core simulation logic for UseAnimationController NPCs

	Handles:
	- Movement simulation (walking toward destinations)
	- Idle wandering behavior
	- Combat movement (if target exists)
	- Integration with ClientPathfinding and ClientJumpSimulator

	This runs the actual simulation logic each Heartbeat.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ClientNPCSimulator = {}

---- Dependencies (loaded in Init)
local ClientPathfinding
local ClientJumpSimulator
local ClientMovement
local OptimizationConfig

---- Constants
local STUCK_THRESHOLD = 0.5 -- studs - if moved less than this, considered stuck
local STUCK_TIME_THRESHOLD = 2.0 -- seconds before triggering unstuck behavior
local WANDER_COOLDOWN = 3.0 -- seconds between wander attempts
local WANDER_RADIUS_MIN = 10
local WANDER_RADIUS_MAX = 30

--[[
	Calculate the height offset from ground to HumanoidRootPart center
	Based on Roblox's formula: Ground + HipHeight + (RootPartHeight / 2)

	@param npcData table - NPC data containing visual model info
	@return number - Height offset from ground
]]
local function calculateHeightOffset(npcData)
	-- Try to get values from visual model first
	if npcData.VisualModel then
		local humanoid = npcData.VisualModel:FindFirstChildOfClass("Humanoid")
		local rootPart = npcData.VisualModel:FindFirstChild("HumanoidRootPart")

		if humanoid and rootPart then
			local hipHeight = humanoid.HipHeight
			local rootPartHalfHeight = rootPart.Size.Y / 2
			return hipHeight + rootPartHalfHeight
		end
	end

	-- Fallback: use config values or defaults
	-- Default HipHeight for R15 is around 2, RootPart height is around 2
	local hipHeight = npcData.HipHeight or 2
	local rootPartHalfHeight = npcData.RootPartHalfHeight or 1

	return hipHeight + rootPartHalfHeight
end

--[[
	Initialize an NPC for simulation
]]
function ClientNPCSimulator.InitializeNPC(npcData)
	-- Initialize movement state
	npcData.LastPosition = npcData.Position
	npcData.StuckTime = 0
	npcData.LastWanderTime = 0

	-- Cache height offset values from visual model when available
	if npcData.VisualModel then
		local humanoid = npcData.VisualModel:FindFirstChildOfClass("Humanoid")
		local rootPart = npcData.VisualModel:FindFirstChild("HumanoidRootPart")

		if humanoid and rootPart then
			npcData.HipHeight = humanoid.HipHeight
			npcData.RootPartHalfHeight = rootPart.Size.Y / 2
			npcData.HeightOffset = npcData.HipHeight + npcData.RootPartHalfHeight
		end
	end

	-- Setup pathfinding if available
	if ClientPathfinding and npcData.VisualModel then
		npcData.Pathfinding = ClientPathfinding.CreatePath(npcData, npcData.VisualModel)
	end
end

--[[
	Cleanup an NPC when simulation ends
]]
function ClientNPCSimulator.CleanupNPC(npcData)
	-- Stop pathfinding
	if ClientPathfinding and npcData.Pathfinding then
		ClientPathfinding.StopPath(npcData)
	end

	-- Clear references
	npcData.Pathfinding = nil
	npcData.VisualModel = nil
end

--[[
	Main simulation step for an NPC
]]
function ClientNPCSimulator.SimulateNPC(npcData, deltaTime)
	if not npcData.IsAlive then
		return
	end

	-- Skip all movement if CanWalk is false
	if npcData.Config.CanWalk == false then
		return
	end

	-- Handle jumping first
	if npcData.IsJumping then
		ClientNPCSimulator.SimulateJump(npcData, deltaTime)
		return
	end

	-- Determine what behavior to run
	if npcData.CurrentTarget and npcData.Config.EnableCombatMovement then
		-- Combat movement
		ClientNPCSimulator.SimulateCombatMovement(npcData, deltaTime)
	elseif npcData.Destination then
		-- Moving to destination
		ClientNPCSimulator.SimulateMovement(npcData, deltaTime)
	elseif npcData.Config.EnableIdleWander then
		-- Idle wandering
		ClientNPCSimulator.SimulateIdleWander(npcData, deltaTime)
	end

	-- Check for stuck condition
	ClientNPCSimulator.CheckStuck(npcData, deltaTime)

	-- Periodic ground check for exploit mitigation
	ClientNPCSimulator.PeriodicGroundCheck(npcData, deltaTime)

	-- Update last position
	npcData.LastPosition = npcData.Position
end

--[[
	Simulate movement toward destination
]]
function ClientNPCSimulator.SimulateMovement(npcData, deltaTime)
	if not npcData.Destination then
		return
	end

	local currentPos = npcData.Position
	local targetPos = npcData.Destination

	-- Calculate direction (flatten Y for ground movement)
	local direction = targetPos - currentPos
	direction = Vector3.new(direction.X, 0, direction.Z)

	local distance = direction.Magnitude

	-- Check if we've reached destination
	if distance < 2 then
		npcData.Destination = nil
		npcData.MovementState = "Idle"
		return
	end

	-- Normalize and apply speed
	direction = direction.Unit
	local walkSpeed = npcData.Config.WalkSpeed or 16
	local movement = direction * walkSpeed * deltaTime

	-- Update orientation FIRST (before movement) to face movement direction
	npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction)

	-- Apply movement
	local newPosition = currentPos + movement

	-- Ground check with proper height calculation
	newPosition = ClientNPCSimulator.SnapToGroundForNPC(npcData, newPosition)

	npcData.Position = newPosition
	npcData.MovementState = "Moving"
end

--[[
	Simulate combat movement toward target
]]
function ClientNPCSimulator.SimulateCombatMovement(npcData, deltaTime)
	local target = npcData.CurrentTarget
	if not target or not target.Parent then
		npcData.CurrentTarget = nil
		return
	end

	local targetPart = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
	if not targetPart then
		return
	end

	local currentPos = npcData.Position
	local targetPos = targetPart.Position

	-- Calculate desired distance based on movement mode
	local desiredDistance = 0
	if npcData.Config.MovementMode == "Melee" then
		desiredDistance = npcData.Config.MeleeOffsetRange or 5
	else
		-- Ranged: stay at sight range edge
		desiredDistance = (npcData.Config.SightRange or 200) * 0.7
	end

	local direction = targetPos - currentPos
	direction = Vector3.new(direction.X, 0, direction.Z)
	local distance = direction.Magnitude

	-- If within desired distance, stop
	if distance <= desiredDistance then
		npcData.MovementState = "Combat"
		-- Face target
		if direction.Magnitude > 0.1 then
			npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction.Unit)
		end
		return
	end

	-- Move toward target
	direction = direction.Unit
	local walkSpeed = npcData.Config.WalkSpeed or 16
	local movement = direction * walkSpeed * deltaTime

	-- Update orientation FIRST (before movement) to face movement direction
	npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction)

	local newPosition = currentPos + movement
	newPosition = ClientNPCSimulator.SnapToGroundForNPC(npcData, newPosition)

	npcData.Position = newPosition
	npcData.MovementState = "CombatMoving"
end

--[[
	Simulate idle wandering behavior
]]
function ClientNPCSimulator.SimulateIdleWander(npcData, deltaTime)
	local now = tick()

	-- Check cooldown
	if now - npcData.LastWanderTime < WANDER_COOLDOWN then
		return
	end

	-- Random chance to wander
	if math.random() > 0.3 then -- 30% chance each cooldown cycle
		npcData.LastWanderTime = now
		return
	end

	-- Pick random destination within wander radius
	local spawnPos = Vector3.new(
		npcData.Config.SpawnPosition and npcData.Config.SpawnPosition.X or npcData.Position.X,
		npcData.Config.SpawnPosition and npcData.Config.SpawnPosition.Y or npcData.Position.Y,
		npcData.Config.SpawnPosition and npcData.Config.SpawnPosition.Z or npcData.Position.Z
	)

	local wanderRadius = math.random(WANDER_RADIUS_MIN, WANDER_RADIUS_MAX)
	local angle = math.random() * math.pi * 2

	local offsetX = math.cos(angle) * wanderRadius
	local offsetZ = math.sin(angle) * wanderRadius

	local destination = spawnPos + Vector3.new(offsetX, 0, offsetZ)

	-- Ground check for destination (use NPC's height offset)
	destination = ClientNPCSimulator.SnapToGroundForNPC(npcData, destination)

	npcData.Destination = destination
	npcData.LastWanderTime = now
end

--[[
	Simulate jump physics
]]
function ClientNPCSimulator.SimulateJump(npcData, deltaTime)
	if ClientJumpSimulator then
		ClientJumpSimulator.SimulateJump(npcData, deltaTime)
	else
		-- Fallback: simple jump simulation
		local gravity = workspace.Gravity
		local jumpPower = npcData.Config.JumpPower or 50

		if not npcData.JumpVelocity then
			npcData.JumpVelocity = jumpPower
		end

		-- Apply gravity
		npcData.JumpVelocity = npcData.JumpVelocity - gravity * deltaTime

		-- Update position
		local newY = npcData.Position.Y + npcData.JumpVelocity * deltaTime
		npcData.Position = Vector3.new(npcData.Position.X, newY, npcData.Position.Z)

		-- Check if landed
		local groundPos = ClientNPCSimulator.GetGroundPosition(npcData.Position)
		if groundPos then
			local heightOffset = npcData.HeightOffset or calculateHeightOffset(npcData)
			local landingY = groundPos.Y + heightOffset

			if npcData.Position.Y <= landingY and npcData.JumpVelocity < 0 then
				npcData.Position = Vector3.new(npcData.Position.X, landingY, npcData.Position.Z)
				npcData.IsJumping = false
				npcData.JumpVelocity = 0
			end
		end
	end
end

--[[
	Check if NPC is stuck and handle unstuck behavior
]]
function ClientNPCSimulator.CheckStuck(npcData, deltaTime)
	local movement = (npcData.Position - npcData.LastPosition).Magnitude

	if movement < STUCK_THRESHOLD and npcData.MovementState ~= "Idle" then
		npcData.StuckTime = (npcData.StuckTime or 0) + deltaTime

		if npcData.StuckTime >= STUCK_TIME_THRESHOLD then
			-- Try to unstuck
			ClientNPCSimulator.TryUnstuck(npcData)
			npcData.StuckTime = 0
		end
	else
		npcData.StuckTime = 0
	end
end

--[[
	Try to unstuck an NPC
]]
function ClientNPCSimulator.TryUnstuck(npcData)
	-- Try jumping
	if not npcData.IsJumping then
		npcData.IsJumping = true
		npcData.JumpVelocity = npcData.Config.JumpPower or 50
	end

	-- Clear destination to pick a new one
	npcData.Destination = nil
end

--[[
	Periodic ground check for exploit mitigation
]]
function ClientNPCSimulator.PeriodicGroundCheck(npcData, deltaTime)
	npcData.GroundCheckAccumulator = (npcData.GroundCheckAccumulator or 0) + deltaTime

	local checkInterval = OptimizationConfig and OptimizationConfig.ExploitMitigation.GROUND_CHECK_INTERVAL or 2.0

	if npcData.GroundCheckAccumulator >= checkInterval then
		npcData.GroundCheckAccumulator = 0

		local groundPos = ClientNPCSimulator.GetGroundPosition(npcData.Position)
		if groundPos then
			local heightOffset = calculateHeightOffset(npcData)
			local expectedY = groundPos.Y + heightOffset
			local heightDiff = math.abs(npcData.Position.Y - expectedY)
			local tolerance = OptimizationConfig and OptimizationConfig.ExploitMitigation.GROUND_SNAP_TOLERANCE or 10

			if heightDiff > tolerance then
				-- Snap to ground with proper height offset
				npcData.Position = Vector3.new(npcData.Position.X, expectedY, npcData.Position.Z)
			end
		end
	end
end

--[[
	Snap position to ground level with proper height calculation
	Uses HipHeight + (RootPartHeight / 2) formula

	@param position Vector3 - Current position
	@param npcData table? - NPC data for height calculation (optional)
	@return Vector3 - Position snapped to ground
]]
function ClientNPCSimulator.SnapToGround(position, npcData)
	local groundPos = ClientNPCSimulator.GetGroundPosition(position)
	if groundPos then
		local heightOffset
		if npcData then
			heightOffset = calculateHeightOffset(npcData)
		else
			-- Fallback: use default R15 values (HipHeight ~2 + RootPartHalfHeight ~1)
			heightOffset = 3
		end
		return Vector3.new(position.X, groundPos.Y + heightOffset, position.Z)
	end
	return position
end

--[[
	Snap position to ground for a specific NPC (uses cached height values)

	@param npcData table - NPC data
	@param position Vector3 - Position to snap
	@return Vector3 - Position snapped to ground
]]
function ClientNPCSimulator.SnapToGroundForNPC(npcData, position)
	local groundPos = ClientNPCSimulator.GetGroundPosition(position)
	if groundPos then
		local heightOffset = npcData.HeightOffset or calculateHeightOffset(npcData)
		return Vector3.new(position.X, groundPos.Y + heightOffset, position.Z)
	end
	return position
end

--[[
	Get ground position at given XZ coordinates
]]
function ClientNPCSimulator.GetGroundPosition(position)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { workspace:FindFirstChild("Characters") or workspace }

	local startPos = position
	local rayResult = workspace:Raycast(startPos, Vector3.new(0, -20, 0), raycastParams)

	if rayResult then
		return rayResult.Position
	end

	return nil
end

--[[
	Trigger a jump for an NPC
]]
function ClientNPCSimulator.TriggerJump(npcData)
	if not npcData.IsJumping then
		npcData.IsJumping = true
		npcData.JumpVelocity = npcData.Config.JumpPower or 50
	end
end

--[[
	Set destination for an NPC
]]
function ClientNPCSimulator.SetDestination(npcData, destination)
	npcData.Destination = destination
end

--[[
	Set target for an NPC
]]
function ClientNPCSimulator.SetTarget(npcData, target)
	npcData.CurrentTarget = target
end

function ClientNPCSimulator.Start()
	-- Component start
end

function ClientNPCSimulator.Init()
	-- Load dependencies
	OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

	-- Load other components (they may not exist yet)
	local componentsFolder = script.Parent

	task.spawn(function()
		local pathfindingModule = componentsFolder:FindFirstChild("ClientPathfinding")
		if pathfindingModule then
			ClientPathfinding = require(pathfindingModule)
		end

		local jumpModule = componentsFolder:FindFirstChild("ClientJumpSimulator")
		if jumpModule then
			ClientJumpSimulator = require(jumpModule)
		end

		local movementModule = componentsFolder:FindFirstChild("ClientMovement")
		if movementModule then
			ClientMovement = require(movementModule)
		end
	end)
end

return ClientNPCSimulator
