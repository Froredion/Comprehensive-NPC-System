--[[
	ClientNPCSimulator - Core simulation logic for UseClientPhysics NPCs

	ARCHITECTURE OVERVIEW:
	----------------------
	This is the BRAIN of client-side NPC simulation. It handles all movement logic,
	integrates with pathfinding, and updates npcData.Position (the source of truth).

	SIMULATION LOOP:
	----------------
	Called by ClientNPCManager every RenderStepped (~60-144 FPS):
	1. SimulateNPC() - Main entry point, determines current behavior
	2. SimulateMovement() - Move toward destination using pathfinding
	3. SimulateCombatMovement() - Chase target using pathfinding
	4. SimulateIdleWander() - Random wandering when idle
	5. SimulateJump() - Jump physics (gravity simulation)

	PATHFINDING INTEGRATION:
	-------------------------
	Uses ClientPathfinding (NoobPath in manual mode):
	- NoobPath computes waypoints but doesn't move the NPC
	- This simulator reads waypoints via GetWaypoint()
	- Manually moves npcData.Position toward current waypoint
	- Advances to next waypoint when within 2 studs (XZ distance only!)
	- Triggers jumps when waypoint.Action == Jump

	IMPORTANT: 2D DISTANCE CALCULATION
	-----------------------------------
	We calculate waypoint distance in 2D (XZ plane), NOT 3D (XYZ).
	Waypoints are at ground level (Y≈0), but NPCs have height offset (~3 studs).
	Using 3D distance would cause NPCs to never reach waypoints (always 3 studs away).
	See detailed comment in SimulateMovement() for full explanation.

	DATA FLOW:
	----------
	1. ClientNPCSimulator updates npcData.Position (this file)
	2. ClientNPCManager writes to positionValue in ReplicatedStorage
	3. ClientPhysicsRenderer reads positionValue and syncs visual model CFrame

	npcData.Position is the SINGLE SOURCE OF TRUTH for NPC position.

	FRAME TIMING:
	-------------
	- Runs on RenderStepped (primary) for smooth movement
	- Falls back to Heartbeat when player alt-tabs
	- See ClientNPCManager.Initialize() for dual-loop implementation

	COMPONENTS USED:
	----------------
	- ClientPathfinding: Provides waypoint-based pathfinding
	- ClientJumpSimulator: Handles jump physics
	- ClientMovement: Movement calculations and combat positioning
	- OptimizationConfig: Configuration values
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

	-- Setup pathfinding if available AND enabled in config
	-- Respect UsePathfinding config: if false, use simple direct movement instead
	local usePathfinding = npcData.Config.UsePathfinding
	if usePathfinding == nil then
		usePathfinding = true -- Default to true if not specified
	end

	if usePathfinding and ClientPathfinding and npcData.VisualModel then
		npcData.Pathfinding = ClientPathfinding.CreatePath(npcData, npcData.VisualModel)
	end
end

--[[
	Cleanup an NPC when simulation ends
]]
function ClientNPCSimulator.CleanupNPC(npcData)
	-- Stop and cleanup pathfinding completely
	if ClientPathfinding then
		ClientPathfinding.Cleanup(npcData)
	end

	-- Clear references
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

	-- Store position before movement for jump simulation
	local preMovementPosition = npcData.Position

	-- Determine what behavior to run (horizontal movement)
	-- This runs even during jumps to maintain horizontal velocity like real Roblox characters
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

	-- Handle jumping (applies vertical movement on top of horizontal)
	if npcData.IsJumping then
		-- Get the horizontal movement that was just applied
		local horizontalMovement = Vector3.new(
			npcData.Position.X - preMovementPosition.X,
			0,
			npcData.Position.Z - preMovementPosition.Z
		)

		-- Reset position to pre-movement, then apply jump physics with horizontal offset
		npcData.Position = preMovementPosition
		ClientNPCSimulator.SimulateJumpWithHorizontal(npcData, deltaTime, horizontalMovement)
	end

	-- Check for stuck condition
	ClientNPCSimulator.CheckStuck(npcData, deltaTime)

	-- Periodic ground check for exploit mitigation (skip during jumps)
	if not npcData.IsJumping then
		ClientNPCSimulator.PeriodicGroundCheck(npcData, deltaTime)
	end

	-- Update last position
	npcData.LastPosition = npcData.Position
end

--[[
	Simulate movement toward destination using pathfinding waypoints
]]
function ClientNPCSimulator.SimulateMovement(npcData, deltaTime)
	if not npcData.Destination then
		return
	end

	-- Use pathfinding if available
	if ClientPathfinding and npcData.VisualModel and npcData.Pathfinding then
		-- Check if we need to start/restart pathfinding
		local needsPathfinding = npcData.Pathfinding.Idle

		-- Rate limit: Prevent spamming Run() calls
		if needsPathfinding then
			local now = tick()
			local lastRunTime = npcData._lastPathRunTime or 0
			local timeSinceLastRun = now - lastRunTime

			-- Only call Run() if we haven't called it in the last 1 second
			if timeSinceLastRun > 1.0 then
				-- Set timestamp BEFORE calling RunPath to prevent race conditions
				npcData._lastPathRunTime = now
				ClientPathfinding.RunPath(npcData, npcData.VisualModel, npcData.Destination)
			else
				-- Don't proceed with waypoint movement if we're still waiting for path
				return
			end
		end

		-- Check if destination was cleared (e.g., by pathfinding error)
		if not npcData.Destination then
			return
		end

		local currentPos = npcData.Position

		-- Get current waypoint from NoobPath
		local waypoint = npcData.Pathfinding:GetWaypoint()
		if waypoint then
			local waypointPos = waypoint.Position

			--[[
				WAYPOINT DISTANCE CALCULATION - IMPORTANT!

				We calculate distance in 2D (XZ plane) instead of 3D (XYZ).

				WHY?
				-----
				Pathfinding waypoints are at ground level (Y ≈ 0), but NPCs have a height offset:
				- HipHeight (usually ~2 studs for R15)
				- + RootPart.Size.Y / 2 (usually ~1 stud)
				- = Total offset of ~3 studs above ground

				PROBLEM WITH 3D DISTANCE:
				--------------------------
				If we use 3D distance:
				  waypoint = (63.82, 0, 92.81)      ← Ground level
				  npcPos   = (63.82, 3, 92.81)      ← 3 studs above ground
				  distance = sqrt((0-3)^2) = 3      ← Always 3, even when directly above!

				The NPC would never get "close enough" (< 2 studs) to advance waypoints.

				SOLUTION - 2D DISTANCE (XZ PLANE):
				-----------------------------------
				Flatten both positions to same Y level:
				  waypointFlat = (63.82, 3, 92.81)  ← Use NPC's Y
				  npcPos       = (63.82, 3, 92.81)
				  distance     = 0                  ← Can actually reach!

				This allows NPCs to advance through waypoints based on horizontal distance only.

				DO NOT CHANGE THIS unless you also update waypoint Y positions to include height offset!
			]]
			local waypointPosFlat = Vector3.new(waypointPos.X, currentPos.Y, waypointPos.Z)
			local distanceToWaypoint = (currentPos - waypointPosFlat).Magnitude

			-- If close enough to current waypoint, advance to next (2 stud threshold)
			if distanceToWaypoint < 2 then
				local advanced = npcData.Pathfinding:AdvanceWaypoint()

				-- Check if we reached the end of the path
				if not advanced then
					-- This was the final waypoint - check if we're close enough to stop
					-- Use a smaller threshold (0.5 studs) to ensure NPC reaches destination
					if distanceToWaypoint < 0.5 then
						npcData.Destination = nil
						npcData.MovementState = "Idle"
						ClientPathfinding.StopPath(npcData)
						return
					end
					-- Otherwise, keep moving toward the final waypoint
				else
					-- Get the new waypoint after advancing
					waypoint = npcData.Pathfinding:GetWaypoint()
					waypointPos = waypoint.Position
				end
			end

			-- Move toward current waypoint
			local direction = waypointPos - currentPos
			direction = Vector3.new(direction.X, 0, direction.Z)

			if direction.Magnitude > 0.1 then
				direction = direction.Unit
				local walkSpeed = npcData.Config.WalkSpeed or 16
				local movement = direction * walkSpeed * deltaTime

				-- Update orientation to face waypoint
				npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction)

				-- Apply movement
				local newPosition = currentPos + movement
				newPosition = ClientNPCSimulator.SnapToGroundForNPC(npcData, newPosition)

				npcData.Position = newPosition
			end

			-- Check if waypoint requires jump
			if waypoint.Action == Enum.PathWaypointAction.Jump and not npcData.IsJumping then
				ClientNPCSimulator.TriggerJump(npcData)
			end
		end

		npcData.MovementState = "Moving"
	else
		-- Fallback: direct movement (no collision avoidance)
		-- This is used when UsePathfinding = false (e.g., Tower Defense waypoint following)
		local currentPos = npcData.Position
		local targetPos = npcData.Destination

		-- Calculate direction (flatten Y for ground movement)
		local direction = targetPos - currentPos
		direction = Vector3.new(direction.X, 0, direction.Z)

		local distance = direction.Magnitude

		-- Check if we've reached destination
		-- Use extremely small threshold (0.01 studs) to reach exact position
		if distance < 0.01 then
			npcData.Destination = nil
			npcData.MovementState = "Idle"
			return
		end

		-- Normalize and apply speed
		direction = direction.Unit
		local walkSpeed = npcData.Config.WalkSpeed or 16
		local movement = direction * walkSpeed * deltaTime

		-- Clamp movement to not overshoot the destination
		if movement.Magnitude > distance then
			movement = direction * distance
		end

		-- Update orientation FIRST (before movement) to face movement direction
		npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction)

		-- Apply movement
		local newPosition = currentPos + movement

		-- Ground check with proper height calculation
		newPosition = ClientNPCSimulator.SnapToGroundForNPC(npcData, newPosition)

		npcData.Position = newPosition
		npcData.MovementState = "Moving"
	end
end

--[[
	Simulate combat movement toward target using pathfinding waypoints
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

	-- Store last known position for when we lose sight
	npcData.LastKnownTargetPos = targetPos

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

	-- If within desired distance, stop pathfinding
	if distance <= desiredDistance then
		npcData.MovementState = "Combat"

		-- Stop pathfinding if active
		if ClientPathfinding then
			ClientPathfinding.StopPath(npcData)
		end

		-- Face target
		if direction.Magnitude > 0.1 then
			npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction.Unit)
		end
		return
	end

	-- Use pathfinding for combat movement if available
	if ClientPathfinding and npcData.VisualModel and npcData.Pathfinding then
		-- Calculate combat position to path toward
		local combatPosition = targetPos - direction.Unit * desiredDistance

		-- Recompute path if target moved significantly or path not active
		local recomputeThreshold = 10
		local shouldRecompute = npcData.Pathfinding.Idle
		if npcData.LastCombatTargetPos then
			local targetMoved = (npcData.LastCombatTargetPos - targetPos).Magnitude
			shouldRecompute = shouldRecompute or targetMoved > recomputeThreshold
		end

		if shouldRecompute then
			-- Prevent multiple Run() calls by rate limiting
			local now = tick()
			local lastRunTime = npcData._lastCombatPathRunTime or 0
			local timeSinceLastRun = now - lastRunTime

			if timeSinceLastRun > 0.1 then
				ClientPathfinding.RunPath(npcData, npcData.VisualModel, combatPosition)
				npcData.LastCombatTargetPos = targetPos
				npcData._lastCombatPathRunTime = now
			end
		end

		-- Get current waypoint from NoobPath
		local waypoint = npcData.Pathfinding:GetWaypoint()
		if waypoint then
			local waypointPos = waypoint.Position

			-- Calculate distance ignoring Y axis (only XZ plane)
			-- Same reasoning as SimulateMovement() - see detailed comment there
			local waypointPosFlat = Vector3.new(waypointPos.X, currentPos.Y, waypointPos.Z)
			local distanceToWaypoint = (currentPos - waypointPosFlat).Magnitude

			-- If close enough to current waypoint, advance to next
			if distanceToWaypoint < 2 then
				local advanced = npcData.Pathfinding:AdvanceWaypoint()
				if not advanced then
					-- This was the final waypoint - check if we're close enough to stop
					-- For combat, use the desired distance check instead
					if distance <= desiredDistance then
						npcData.MovementState = "Combat"
						ClientPathfinding.StopPath(npcData)
						return
					end
					-- Otherwise, keep moving toward the final waypoint
				else
					waypoint = npcData.Pathfinding:GetWaypoint()
					if waypoint then
						waypointPos = waypoint.Position
					end
				end
			end

			-- Move toward current waypoint
			local waypointDirection = waypointPos - currentPos
			waypointDirection = Vector3.new(waypointDirection.X, 0, waypointDirection.Z)

			if waypointDirection.Magnitude > 0.1 then
				waypointDirection = waypointDirection.Unit
				local walkSpeed = npcData.Config.WalkSpeed or 16
				local movement = waypointDirection * walkSpeed * deltaTime

				-- Face target while moving (not waypoint)
				if direction.Magnitude > 0.1 then
					npcData.Orientation = CFrame.lookAt(currentPos, currentPos + direction.Unit)
				end

				-- Apply movement
				local newPosition = currentPos + movement
				newPosition = ClientNPCSimulator.SnapToGroundForNPC(npcData, newPosition)

				npcData.Position = newPosition
			end

			-- Check if waypoint requires jump
			if waypoint.Action == Enum.PathWaypointAction.Jump and not npcData.IsJumping then
				ClientNPCSimulator.TriggerJump(npcData)
			end
		end

		npcData.MovementState = "CombatMoving"
	else
		-- Fallback: direct movement (no collision avoidance)
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
end

--[[
	Simulate idle wandering behavior with pathfinding
]]
function ClientNPCSimulator.SimulateIdleWander(npcData, deltaTime)
	-- IMPORTANT: Don't pick new destination if already moving to one
	-- This prevents path restarting mid-route (causes "blinking")
	if npcData.Destination then
		return
	end

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

	-- Set destination (will trigger pathfinding in SimulateMovement)
	npcData.Destination = destination
	npcData.LastWanderTime = now

	-- Start pathfinding immediately if available
	if ClientPathfinding and npcData.VisualModel then
		ClientPathfinding.RunPath(npcData, npcData.VisualModel, destination)
	end
end

--[[
	Simulate jump physics (vertical only - legacy function)
]]
function ClientNPCSimulator.SimulateJump(npcData, deltaTime)
	ClientNPCSimulator.SimulateJumpWithHorizontal(npcData, deltaTime, Vector3.zero)
end

--[[
	Simulate jump physics with horizontal movement
	This allows NPCs to maintain horizontal velocity while jumping, like real Roblox characters

	@param npcData table - NPC data
	@param deltaTime number - Time since last frame
	@param horizontalMovement Vector3 - Horizontal movement to apply (X, 0, Z)
]]
function ClientNPCSimulator.SimulateJumpWithHorizontal(npcData, deltaTime, horizontalMovement)
	if not npcData.IsJumping then
		return
	end

	local gravity = workspace.Gravity
	local position = npcData.Position
	local velocity = npcData.JumpVelocity or 0

	-- Initialize jump velocity if not set
	if velocity == 0 and npcData.JumpStartTime == nil then
		local jumpPower = npcData.Config.JumpPower or 50
		velocity = jumpPower
		npcData.JumpVelocity = velocity
		npcData.JumpStartTime = tick()
	end

	-- Check for timeout (3 second max jump duration)
	local jumpTime = tick() - (npcData.JumpStartTime or tick())
	if jumpTime > 3.0 then
		ClientNPCSimulator.EndJump(npcData)
		return
	end

	-- Apply gravity to vertical velocity
	velocity = velocity - gravity * deltaTime
	npcData.JumpVelocity = velocity

	-- Calculate new position with both vertical and horizontal movement
	local newX = position.X + horizontalMovement.X
	local newY = position.Y + velocity * deltaTime
	local newZ = position.Z + horizontalMovement.Z
	local newPosition = Vector3.new(newX, newY, newZ)

	-- Check if we're falling and near ground
	if velocity < 0 then
		local groundPos = ClientNPCSimulator.GetGroundPosition(newPosition)

		if groundPos then
			local heightOffset = npcData.HeightOffset or calculateHeightOffset(npcData)
			local groundY = groundPos.Y + heightOffset

			if newY <= groundY then
				-- Landed - snap to ground
				newPosition = Vector3.new(newX, groundY, newZ)
				ClientNPCSimulator.EndJump(npcData)
			end
		end
	end

	npcData.Position = newPosition
end

--[[
	End a jump (landing or timeout)
]]
function ClientNPCSimulator.EndJump(npcData)
	npcData.IsJumping = false
	npcData.JumpVelocity = 0
	npcData.JumpStartTime = nil
end

--[[
	Check if NPC is stuck and handle unstuck behavior
]]
function ClientNPCSimulator.CheckStuck(npcData, deltaTime)
	-- Don't check for stuck while jumping - vertical movement shouldn't trigger stuck detection
	if npcData.IsJumping then
		npcData.StuckTime = 0
		return
	end

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
	-- Try jumping to get unstuck
	if not npcData.IsJumping then
		npcData.IsJumping = true
		npcData.JumpVelocity = npcData.Config.JumpPower or 50
	end

	-- Note: We don't clear destination anymore - the stuck detection is already
	-- disabled while jumping (CheckStuck returns early), so this shouldn't fire
	-- while jumping. If NPC is truly stuck on ground, the jump should unstuck it.
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
	raycastParams.FilterDescendantsInstances = {
		workspace:FindFirstChild("Characters") or workspace,
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}

	-- Loop to skip non-collidable parts (max 5 iterations)
	local currentStart = position + Vector3.new(0, 1, 0)
	for _ = 1, 5 do
		local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -100, 0), raycastParams)

		if not rayResult then
			break -- No hit
		end

		if rayResult.Instance.CanCollide then
			return rayResult.Position
		end

		-- Skip this part and continue from just below it
		raycastParams:AddToFilter(rayResult.Instance)
		currentStart = rayResult.Position + Vector3.new(0, -0.1, 0)
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
