local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local MovementBehavior = {}

---- Knit Services
local NPC_Service

---- Configuration
-- IDLE BEHAVIOR
local IDLE_WANDER_INTERVAL = 8
local IDLE_WANDER_RADIUS = 50

-- RANGED MODE (Archer/Long Range)
local RANGED_RUSH_DISTANCE_MIN = 2.5
local RANGED_RUSH_DISTANCE_MAX = 50
local RANGED_RUSH_DELAY = 0.25
local RANGED_STRAFE_ENABLED = true
local RANGED_STRAFE_WALK_SPEED = 5
local RANGED_STRAFE_CHECK_INTERVAL = 0.6

-- MELEE MODE (Close Combat)
local MELEE_OFFSET_MIN_BASE = 2.5 -- Minimum offset regardless of size
local MELEE_CHASE_CHECK_INTERVAL = 0.3
local MELEE_RECALCULATE_INTERVAL = 1.5

-- SHARED
local UNFOLLOW_SIGHT_DURATION = 2.5
local NO_TARGET_CHECK_INTERVAL = 1 -- How often to check when no target exists

--[[
	Find random walkable point near spawn position
	Tries up to 5 times to find a valid position
	
	@param npcData table - NPC data
	@return Vector3? - Random walkable position
]]
local function findRandomWalkablePoint(npcData)
	local spawnPos = npcData.SpawnPosition
	local maxAttempts = 5

	for attempt = 1, maxAttempts do
		local randomOffset = Vector3.new(
			math.random(-IDLE_WANDER_RADIUS, IDLE_WANDER_RADIUS),
			0,
			math.random(-IDLE_WANDER_RADIUS, IDLE_WANDER_RADIUS)
		)

		local targetPos = spawnPos + randomOffset

		-- Raycast to find ground
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {
			workspace:FindFirstChild("Characters") or workspace,
			workspace:FindFirstChild("VisualWaypoints"),
			workspace:FindFirstChild("ClientSightVisualization"),
		}

		-- Loop to skip non-collidable parts (max 5 iterations)
		local currentStart = targetPos + Vector3.new(0, 10, 0)
		for _ = 1, 5 do
			local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -100, 0), raycastParams)

			if not rayResult then
				break -- No hit, try next random point
			end

			if rayResult.Instance.CanCollide then
				return rayResult.Position
			end

			-- Skip this part and continue from just below it
			raycastParams:AddToFilter(rayResult.Instance)
			currentStart = rayResult.Position + Vector3.new(0, -0.1, 0)
		end
	end

	return nil
end

--[[
	Find rush point for ranged mode
	Avoids obstacles using raycast validation
	
	@param npcData table - NPC data
	@param distance number - Distance to rush
	@param minDist number - Minimum distance
	@param maxDist number - Maximum distance
	@return Vector3? - Rush point position
]]
local function findRushPoint(npcData, distance, minDist, maxDist)
	local target = npcData.CurrentTarget
	if not target or not target.PrimaryPart then
		return nil
	end

	local npcPos = npcData.Model.PrimaryPart.Position
	local targetPos = target.PrimaryPart.Position
	local direction = (targetPos - npcPos).Unit

	-- Calculate rush point
	local rushDistance = math.clamp(distance, minDist, maxDist)
	local rushPoint = targetPos - (direction * rushDistance)

	-- Validate with raycast (check for obstacles)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		npcData.Model,
		target,
		workspace:FindFirstChild("Characters"),
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}

	local rayResult = workspace:Raycast(npcPos, rushPoint - npcPos, raycastParams)

	if rayResult then
		-- Obstacle detected, try alternative point
		local alternativeAngle = math.rad(45)
		local alternativeDirection = CFrame.Angles(0, alternativeAngle, 0) * direction
		rushPoint = targetPos - (alternativeDirection * rushDistance)
	end

	return rushPoint
end

--[[
	Find strafe point for ranged mode
	Maintains engagement distance while circling
	
	@param npcData table - NPC data
	@param targetPosition Vector3 - Target position
	@return Vector3? - Strafe point position
]]
local function findStrafePoint(npcData, targetPosition)
	local npcPos = npcData.Model.PrimaryPart.Position
	local direction = (targetPosition - npcPos).Unit

	-- Calculate perpendicular strafe direction
	local strafeAngle = math.rad(math.random(0, 1) == 0 and 90 or -90)
	local strafeDirection = CFrame.Angles(0, strafeAngle, 0) * direction

	local strafeDistance = math.random(10, 20)
	local strafePoint = npcPos + (strafeDirection * strafeDistance)

	-- Raycast to validate
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		npcData.Model,
		workspace:FindFirstChild("Characters"),
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}

	-- Loop to skip non-collidable parts (max 5 iterations)
	local currentStart = strafePoint + Vector3.new(0, 10, 0)
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
	Calculate dynamic melee offset based on NPC's bounding box size
	Minimum offset is 3, scales up with larger NPCs
	
	@param npcData table - NPC data
	@return number - Minimum offset distance
	@return number - Maximum offset distance
]]
local function calculateMeleeOffset(npcData)
	local model = npcData.Model
	if not model or not model.PrimaryPart then
		return MELEE_OFFSET_MIN_BASE, MELEE_OFFSET_MIN_BASE + 5
	end

	-- Get bounding box size
	local boundingSize = model:GetExtentsSize()
	local maxDimension = math.max(boundingSize.X, boundingSize.Z)

	-- Calculate dynamic offset based on bounding box
	-- Min: Either 3 or the max dimension, whichever is larger
	local minOffset = math.max(MELEE_OFFSET_MIN_BASE, maxDimension)

	-- Max: Min offset plus some extra range (about 1.5x to 2x the min)
	local maxOffset = minOffset + math.max(5, maxDimension * 0.5)

	return minOffset, maxOffset
end

--[[
	Idle wandering behavior thread
	Random movement around spawn point
	
	@param npcData table - NPC data
]]
local function idleWanderThread(npcData)
	while not npcData.CleanedUp do
		local success, err = pcall(function()
			-- Only wander if enabled and no target
			if npcData.EnableIdleWander and not npcData.CurrentTarget then
				local randomPoint = findRandomWalkablePoint(npcData)
				if randomPoint then
					npcData.Model.Humanoid.WalkSpeed = npcData.WalkSpeed

					npcData.Destination = randomPoint
					npcData.MovementState = "Idle"

					-- Use pathfinding or simple MoveTo
					if npcData.UsePathfinding and NPC_Service.Components.PathfindingManager then
						NPC_Service.Components.PathfindingManager.RunPath(npcData, randomPoint)
					elseif npcData.Model:FindFirstChild("Humanoid") then
						npcData.Model.Humanoid:MoveTo(randomPoint)
					end
				end
			end

			task.wait(IDLE_WANDER_INTERVAL)
		end)

		if not success then
			warn("[MovementBehavior] Error in idleWanderThread:", err)
			task.wait(IDLE_WANDER_INTERVAL)
		end
	end
end

--[[
	Combat movement thread (mode-dependent)
	
	@param npcData table - NPC data
]]
local function combatMovementThread(npcData)
	local lastRecalculate = tick()
	local humanoid = npcData.Model:WaitForChild("Humanoid", 10)
	local originalWalkSpeed = npcData.WalkSpeed

	while not npcData.CleanedUp do
		local success, err = pcall(function()
			-- Check if we have a valid target
			if npcData.CurrentTarget and npcData.CurrentTarget.PrimaryPart then
				local targetPos = npcData.CurrentTarget.PrimaryPart.Position
				local npcPos = npcData.Model.PrimaryPart.Position
				local distance = (targetPos - npcPos).Magnitude

				-- Mode-specific behavior
				if npcData.MovementMode == "Ranged" then
					-- RANGED MODE: Rush and strafe behavior
					if RANGED_STRAFE_ENABLED and distance < RANGED_RUSH_DISTANCE_MAX then
						-- Strafe around target with reduced speed
						local strafePoint = findStrafePoint(npcData, targetPos)
						if strafePoint then
							npcData.Destination = strafePoint
							npcData.MovementState = "Combat"

							-- Apply strafe walk speed
							if humanoid then
								humanoid.WalkSpeed = RANGED_STRAFE_WALK_SPEED
							end

							if npcData.UsePathfinding and NPC_Service.Components.PathfindingManager then
								NPC_Service.Components.PathfindingManager.RunPath(npcData, strafePoint)
							elseif humanoid then
								humanoid:MoveTo(strafePoint)
							end
						end
					else
						-- Rush towards target at normal speed
						local rushPoint =
							findRushPoint(npcData, distance, RANGED_RUSH_DISTANCE_MIN, RANGED_RUSH_DISTANCE_MAX)
						if rushPoint then
							npcData.Destination = rushPoint
							npcData.MovementState = "Following"

							-- Restore original walk speed
							if humanoid then
								humanoid.WalkSpeed = originalWalkSpeed
							end

							if npcData.UsePathfinding and NPC_Service.Components.PathfindingManager then
								NPC_Service.Components.PathfindingManager.RunPath(npcData, rushPoint)
							elseif humanoid then
								humanoid:MoveTo(rushPoint)
							end
						end

						task.wait(RANGED_RUSH_DELAY)
					end

					task.wait(RANGED_STRAFE_CHECK_INTERVAL)
				elseif npcData.MovementMode == "Melee" then
					-- MELEE MODE: Direct chase with offset
					local minOffset, maxOffset = calculateMeleeOffset(npcData)

					-- Only recalculate if we're far from target or it's time to recalculate
					if distance > minOffset or (tick() - lastRecalculate >= MELEE_RECALCULATE_INTERVAL) then
						-- Calculate point directly toward target, but at offset distance
						local direction = (targetPos - npcPos).Unit
						local chasePoint = targetPos - (direction * minOffset)

						npcData.Destination = chasePoint
						npcData.MovementState = "Following"

						if npcData.UsePathfinding and NPC_Service.Components.PathfindingManager then
							NPC_Service.Components.PathfindingManager.RunPath(npcData, chasePoint)
						elseif npcData.Model:FindFirstChild("Humanoid") then
							npcData.Model.Humanoid:MoveTo(chasePoint)
						end

						lastRecalculate = tick()
					end

					task.wait(MELEE_CHASE_CHECK_INTERVAL)
				end
			else
				-- No target, check if we should unfollow
				if npcData.LastSeenTarget > 0 and (tick() - npcData.LastSeenTarget) > UNFOLLOW_SIGHT_DURATION then
					npcData.CurrentTarget = nil
					npcData.Destination = nil
					npcData.MovementState = nil

					-- Restore original walk speed when combat ends
					if humanoid then
						humanoid.WalkSpeed = originalWalkSpeed
					end
				end

				task.wait(NO_TARGET_CHECK_INTERVAL)
			end
		end)

		if not success then
			warn("[MovementBehavior] Error in combatMovementThread:", err)
			task.wait(NO_TARGET_CHECK_INTERVAL)
		end
	end
end

--[[
	Orientation update thread
	Face the target or movement direction
	
	@param npcData table - NPC data
]]
local function orientationUpdateThread(npcData)
	-- Create AlignOrientation for smooth rotation
	local hrp = npcData.Model.PrimaryPart

	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = math.huge
	alignOrientation.Responsiveness = 200
	alignOrientation.Parent = hrp

	table.insert(npcData.Connections, alignOrientation.AncestryChanged:Connect(function() end))

	while not npcData.CleanedUp do
		local success, err = pcall(function()
			local npcPos = hrp.Position
			local targetPos = nil

			if npcData.CurrentTarget and npcData.CurrentTarget.PrimaryPart then
				-- Face target
				targetPos = npcData.CurrentTarget.PrimaryPart.Position
			elseif npcData.Destination then
				-- Face destination when no target
				targetPos = npcData.Destination
			end

			if targetPos then
				-- Keep Y-axis level (prevent tilting up/down)
				local levelTargetPos = Vector3.new(targetPos.X, npcPos.Y, targetPos.Z)
				local distance = (levelTargetPos - npcPos).Magnitude

				-- Guardrail: If target is too close, use current CFrame to avoid rotation issues
				-- NPCs will flung out of the map if too close
				if distance > 0.01 then
					local direction = (levelTargetPos - npcPos).Unit
					local lookCFrame = CFrame.lookAt(npcPos, npcPos + direction)
					alignOrientation.CFrame = lookCFrame - lookCFrame.Position
				else
					-- Use current HumanoidRootPart CFrame when too close
					alignOrientation.CFrame = hrp.CFrame - hrp.CFrame.Position
				end
			end

			task.wait(0.1)
		end)

		if not success then
			warn("[MovementBehavior] Error in orientationUpdateThread:", err)
			task.wait(0.1)
		end
	end

	-- Cleanup
	alignOrientation:Destroy()
	attachment:Destroy()
end

--[[
	Setup movement behavior for NPC
	
	@param npcData table - NPC data
]]
function MovementBehavior.SetupMovementBehavior(npcData)
	-- Skip all movement setup if CanWalk is false
	if not npcData.CanWalk then
		return
	end

	-- Initialize pathfinding (only if UsePathfinding is enabled)
	if npcData.UsePathfinding and NPC_Service.Components.PathfindingManager then
		npcData.Pathfinding = NPC_Service.Components.PathfindingManager.CreatePath(npcData.Model)
	end

	-- Start behavior threads
	if npcData.EnableIdleWander then
		local idleThread = task.spawn(idleWanderThread, npcData)
		table.insert(npcData.TaskThreads, idleThread)
	end

	if npcData.EnableCombatMovement then
		local combatThread = task.spawn(combatMovementThread, npcData)
		table.insert(npcData.TaskThreads, combatThread)
	end

	local orientationThread = task.spawn(orientationUpdateThread, npcData)
	table.insert(npcData.TaskThreads, orientationThread)
end

function MovementBehavior.Start()
	-- Component start logic
end

function MovementBehavior.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return MovementBehavior
