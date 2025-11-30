--[[
	ClientJumpSimulator - Physics-based jump simulation for UseClientPhysics NPCs

	Handles:
	- Gravity-based jump arc calculation
	- Ground detection via raycasting
	- Jump timeout protection
	- Integration with ClientNPCSimulator

	Uses workspace.Gravity for consistent physics behavior.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientJumpSimulator = {}

---- Configuration
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

---- Constants (from config)
local DEFAULT_JUMP_POWER
local JUMP_TIMEOUT
local GROUND_CHECK_DISTANCE

--[[
	Calculate the height offset from ground to HumanoidRootPart center
	Based on Roblox's formula: Ground + HipHeight + (RootPartHeight / 2)

	@param npcData table - NPC data containing visual model info
	@return number - Height offset from ground
]]
local function calculateHeightOffset(npcData)
	-- Use cached value if available
	if npcData.HeightOffset then
		return npcData.HeightOffset
	end

	-- Try to get values from visual model
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
	Start a jump for an NPC

	@param npcData table - NPC data
]]
function ClientJumpSimulator.StartJump(npcData)
	if npcData.IsJumping then
		return -- Already jumping
	end

	local jumpPower = npcData.Config.JumpPower or DEFAULT_JUMP_POWER

	npcData.IsJumping = true
	npcData.JumpVelocity = jumpPower
	npcData.JumpStartTime = tick()
	npcData.JumpStartPosition = npcData.Position
end

--[[
	Simulate jump physics for one frame

	@param npcData table - NPC data
	@param deltaTime number - Time since last frame
]]
function ClientJumpSimulator.SimulateJump(npcData, deltaTime)
	if not npcData.IsJumping then
		return
	end

	local gravity = workspace.Gravity
	local position = npcData.Position
	local velocity = npcData.JumpVelocity or 0

	-- Check for timeout
	local jumpTime = tick() - (npcData.JumpStartTime or tick())
	if jumpTime > JUMP_TIMEOUT then
		ClientJumpSimulator.EndJump(npcData)
		return
	end

	-- Apply gravity to velocity
	velocity = velocity - gravity * deltaTime
	npcData.JumpVelocity = velocity

	-- Calculate new position
	local newY = position.Y + velocity * deltaTime
	local newPosition = Vector3.new(position.X, newY, position.Z)

	-- Check if we're falling and near ground
	if velocity < 0 then
		local groundPos = ClientJumpSimulator.GetGroundPosition(newPosition)

		if groundPos then
			local heightOffset = calculateHeightOffset(npcData)
			local groundY = groundPos.Y + heightOffset

			if newY <= groundY then
				-- Landed
				newPosition = Vector3.new(position.X, groundY, position.Z)
				ClientJumpSimulator.EndJump(npcData)
			end
		end
	end

	npcData.Position = newPosition
end

--[[
	End a jump (landing or timeout)

	@param npcData table - NPC data
]]
function ClientJumpSimulator.EndJump(npcData)
	npcData.IsJumping = false
	npcData.JumpVelocity = 0
	npcData.JumpStartTime = nil
	npcData.JumpStartPosition = nil
end

--[[
	Check if NPC is on ground

	@param position Vector3 - Position to check
	@return boolean
]]
function ClientJumpSimulator.IsOnGround(position)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		workspace:FindFirstChild("Characters") or workspace,
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}

	-- Loop to skip non-collidable parts (max 5 iterations)
	local currentStart = position + Vector3.new(0, 0.5, 0)
	for _ = 1, 5 do
		local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -GROUND_CHECK_DISTANCE - 0.5, 0), raycastParams)

		if not rayResult then
			return false -- No hit
		end

		if rayResult.Instance.CanCollide then
			return true
		end

		-- Skip this part and continue from just below it
		raycastParams:AddToFilter(rayResult.Instance)
		currentStart = rayResult.Position + Vector3.new(0, -0.1, 0)
	end

	return false
end

--[[
	Get ground position at XZ coordinates

	@param position Vector3 - Position to check from
	@return Vector3? - Ground position or nil
]]
function ClientJumpSimulator.GetGroundPosition(position)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		workspace:FindFirstChild("Characters") or workspace,
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}

	-- Cast from slightly above current position downward
	-- This prevents detecting objects far above (like airplanes/projectiles) as ground
	local currentStart = position + Vector3.new(0, 3, 0)

	-- Loop to skip non-collidable parts (max 5 iterations)
	for _ = 1, 5 do
		local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -20, 0), raycastParams)

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
	Calculate jump trajectory to reach a target

	@param startPos Vector3 - Starting position
	@param targetPos Vector3 - Target position
	@param jumpPower number - Jump power to use
	@return table? - Jump parameters or nil if impossible
]]
function ClientJumpSimulator.CalculateJumpTrajectory(startPos, targetPos, jumpPower)
	local gravity = workspace.Gravity
	local horizontalDistance = (Vector3.new(targetPos.X, 0, targetPos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude
	local heightDifference = targetPos.Y - startPos.Y

	-- Calculate time to reach apex
	local timeToApex = jumpPower / gravity

	-- Calculate max height
	local maxHeight = (jumpPower * jumpPower) / (2 * gravity)

	-- Check if target is reachable
	if heightDifference > maxHeight then
		return nil -- Can't reach that height
	end

	-- Calculate total jump time (up + down)
	-- Using quadratic formula for landing time
	local a = 0.5 * gravity
	local b = -jumpPower
	local c = heightDifference

	local discriminant = b * b - 4 * a * c
	if discriminant < 0 then
		return nil -- No valid solution
	end

	local t1 = (-b + math.sqrt(discriminant)) / (2 * a)
	local t2 = (-b - math.sqrt(discriminant)) / (2 * a)
	local landTime = math.max(t1, t2)

	if landTime <= 0 then
		return nil
	end

	-- Calculate required horizontal speed
	local requiredSpeed = horizontalDistance / landTime

	return {
		jumpPower = jumpPower,
		horizontalSpeed = requiredSpeed,
		totalTime = landTime,
		maxHeight = maxHeight,
	}
end

--[[
	Check if a jump would clear an obstacle

	@param startPos Vector3 - Starting position
	@param obstaclePos Vector3 - Obstacle position
	@param obstacleHeight number - Obstacle height
	@param jumpPower number - Jump power
	@return boolean
]]
function ClientJumpSimulator.CanClearObstacle(startPos, obstaclePos, obstacleHeight, jumpPower)
	local gravity = workspace.Gravity

	-- Calculate height at obstacle position
	local horizontalDistance = (Vector3.new(obstaclePos.X, 0, obstaclePos.Z) - Vector3.new(startPos.X, 0, startPos.Z)).Magnitude

	-- Estimate time to reach obstacle (rough approximation)
	local approxSpeed = 16 -- Assume walking speed
	local timeToObstacle = horizontalDistance / approxSpeed

	-- Calculate height at that time
	local heightAtObstacle = jumpPower * timeToObstacle - 0.5 * gravity * timeToObstacle * timeToObstacle

	return heightAtObstacle > obstacleHeight
end

--[[
	Force end all jumps (cleanup)

	@param npcData table - NPC data
]]
function ClientJumpSimulator.ForceEndJump(npcData)
	npcData.IsJumping = false
	npcData.JumpVelocity = 0
	npcData.JumpStartTime = nil
	npcData.JumpStartPosition = nil

	-- Snap to ground if floating
	local groundPos = ClientJumpSimulator.GetGroundPosition(npcData.Position)
	if groundPos then
		local heightOffset = calculateHeightOffset(npcData)
		npcData.Position = Vector3.new(npcData.Position.X, groundPos.Y + heightOffset, npcData.Position.Z)
	end
end

function ClientJumpSimulator.Start()
	-- Component start
end

function ClientJumpSimulator.Init()
	-- Load config values
	local jumpConfig = OptimizationConfig.JumpSimulation

	DEFAULT_JUMP_POWER = jumpConfig.DEFAULT_JUMP_POWER
	JUMP_TIMEOUT = jumpConfig.JUMP_TIMEOUT
	GROUND_CHECK_DISTANCE = jumpConfig.GROUND_CHECK_DISTANCE
end

return ClientJumpSimulator
