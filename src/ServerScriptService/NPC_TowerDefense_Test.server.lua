-- ============================================================================
-- TOWER DEFENSE ENEMY WAVE SYSTEM
-- ============================================================================
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Knit to initialize
local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

-- if true then
-- 	return
-- end

local NPC_Service = Knit.GetService("NPC_Service")

print("\n" .. string.rep("=", 50))
print("🏰 TOWER DEFENSE ENEMY WAVE SYSTEM")
print(string.rep("=", 50) .. "\n")

-- Get references to map elements
local TowerDefenseMap = Workspace:FindFirstChild("TowerDefense_Map")
if not TowerDefenseMap then
	warn("❌ TowerDefense_Map not found in Workspace!")
	warn("Expected path: Workspace.TowerDefense_Map")
	return
end

-- Get walkpoints
local Enemy_WalkPoints = TowerDefenseMap:FindFirstChild("Enemy_WalkPoints")
if not Enemy_WalkPoints then
	warn("❌ Enemy_WalkPoints folder not found!")
	warn("Expected path: Workspace.TowerDefense_Map.Enemy_WalkPoints")
	return
end

-- Collect all walkpoints in order
local walkpoints = {}
for i = 1, 10 do
	local waypoint = Enemy_WalkPoints:FindFirstChild(tostring(i))
	if waypoint then
		table.insert(walkpoints, waypoint)
	else
		warn("⚠️ Walkpoint " .. i .. " not found!")
	end
end

if #walkpoints < 10 then
	warn("❌ Not all walkpoints found! Expected 10, found " .. #walkpoints)
	return
end

print("✅ Found all " .. #walkpoints .. " walkpoints")

-- Get Base and make it non-collidable with enemies
local Base = TowerDefenseMap:FindFirstChild("Base")
if Base then
	-- Make all parts in Base non-collidable
	local function setCanCollideRecursive(instance)
		if instance:IsA("BasePart") then
			instance.CanCollide = false
		end
		for _, child in pairs(instance:GetChildren()) do
			setCanCollideRecursive(child)
		end
	end

	if Base:IsA("BasePart") then
		Base.CanCollide = false
	elseif Base:IsA("Model") then
		setCanCollideRecursive(Base)
	end
else
	warn("⚠️ Base not found at Workspace.TowerDefense_Map.Base")
end

-- Get Enemy rig
local enemyRig = ReplicatedStorage:FindFirstChild("Assets")
	and ReplicatedStorage.Assets:FindFirstChild("NPCs")
	and ReplicatedStorage.Assets.NPCs:FindFirstChild("Characters")
	and ReplicatedStorage.Assets.NPCs.Characters:FindFirstChild("Enemy")

if not enemyRig then
	warn("❌ Enemy rig not found at: ReplicatedStorage.Assets.NPCs.Characters.Enemy")
	return
end

-- Enemy spawn configuration
local MAX_ACTIVE_ENEMIES = 3
local SPAWN_INTERVAL = 1 -- seconds
local activeEnemies = {}
local enemyCounter = 0

-- Function to spawn a new wave enemy
local function spawnWaveEnemy()
	enemyCounter = enemyCounter + 1
	local enemyId = enemyCounter

	-- Spawn at first waypoint
	local randomAngle = math.random(0, 360)
	local rotation = CFrame.Angles(0, 0, 0)

	local enemy = NPC_Service:SpawnNPC({
		Name = "TowerDefense_Enemy_" .. enemyId,
		SpawnerPart = walkpoints[1], -- Use SpawnerPart to auto-disable CanCollide/CanQuery/CanTouch
		Rotation = rotation,
		ModelPath = enemyRig,

		-- Stats
		MaxHealth = 100,
		WalkSpeed = 16,
		JumpPower = 50,

		-- Behavior - disable automatic behaviors for controlled movement
		SightRange = 0, -- Disable detection
		SightMode = "Omnidirectional",
		MovementMode = "Ranged",
		UsePathfinding = false, -- Use simple MoveTo for waypoint following
		CanWalk = true,
		EnableIdleWander = false, -- Disable wandering
		EnableCombatMovement = false, -- Disable combat movement

		-- Client Rendering Data
		ClientRenderData = {
			Scale = 0.4, -- 0.4 scale as requested
			CustomColor = Color3.fromRGB(255, 80, 80), -- Red tint for enemies
			Transparency = 0,
		},

		-- -- Custom Game Data
		-- CustomData = {
		-- 	Faction = "Enemy",
		-- 	EnemyType = "TowerDefenseWave",
		-- 	ExperienceReward = 100,
		-- 	LootTableID = "TowerDefense_Enemy",
		-- 	Level = 1,
		-- },
	})

	if not enemy then
		warn("❌ Failed to spawn tower defense enemy!")
		return nil
	end

	-- Add to active enemies table
	activeEnemies[enemyId] = enemy

	return enemy, enemyId
end

-- Function to move enemy through waypoints (supports both traditional and client-physics NPCs)
local function moveEnemyThroughWaypoints(enemy, enemyId)
	local isClientPhysicsNPC = typeof(enemy) == "string"

	local currentWaypointIndex = 1

	-- Helper to check if NPC is still valid
	local function isNPCValid()
		if isClientPhysicsNPC then
			local npcData = NPC_Service:GetClientPhysicsNPCData(enemy)
			return npcData ~= nil and npcData.IsAlive
		else
			return enemy and enemy.Parent
		end
	end

	-- Helper to get NPC position
	local function getNPCPosition()
		if isClientPhysicsNPC then
			local npcData = NPC_Service:GetClientPhysicsNPCData(enemy)
			if npcData and npcData.Position then
				return npcData.Position
			end
			return nil
		else
			local rootPart = enemy:FindFirstChild("HumanoidRootPart")
			return rootPart and rootPart.Position
		end
	end

	-- Start moving through waypoints
	local function moveToNextWaypoint()
		if not isNPCValid() then
			activeEnemies[enemyId] = nil
			return
		end

		if currentWaypointIndex > #walkpoints then
			-- Reached the end (waypoint 10)
			-- Destroy current enemy
			NPC_Service:DestroyNPC(enemy)
			activeEnemies[enemyId] = nil
			return
		end

		local waypoint = walkpoints[currentWaypointIndex]
		local waypointPos = waypoint.Position

		-- Set destination using NPC_Service (works for both NPC types)
		NPC_Service:SetDestination(enemy, waypointPos)

		if isClientPhysicsNPC then
			-- For client-physics NPCs: poll position to check if reached waypoint
			local REACH_DISTANCE = 5 -- studs (reduced from 5 to match client's 0.5 stud threshold better)
			local MAX_TIME = 30 -- seconds timeout
			local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)
			local POLL_INTERVAL = OptimizationConfig.ClientSimulation.POSITION_SYNC_INTERVAL -- Match client sync rate for responsiveness
			local startTime = tick()

			task.spawn(function()
				while isNPCValid() and currentWaypointIndex <= #walkpoints do
					local npcPos = getNPCPosition()
					if npcPos then
						local distance = (Vector3.new(npcPos.X, 0, npcPos.Z) - Vector3.new(waypointPos.X, 0, waypointPos.Z)).Magnitude

						if distance < REACH_DISTANCE then
							-- Reached waypoint
							print(string.format("[TD] Enemy %s reached waypoint %d", tostring(enemy), currentWaypointIndex))
							currentWaypointIndex = currentWaypointIndex + 1
							task.wait() -- Small pause between waypoints
							moveToNextWaypoint()
							return
						end
					end

					-- Timeout check
					if tick() - startTime > MAX_TIME then
						print(string.format("[TD] Enemy %s timeout at waypoint %d", tostring(enemy), currentWaypointIndex))
						currentWaypointIndex = currentWaypointIndex + 1
						moveToNextWaypoint()
						return
					end

					task.wait(POLL_INTERVAL) -- Poll at same rate as client position sync for maximum responsiveness
				end
			end)
		else
			-- For traditional NPCs: use MoveToFinished event
			local humanoid = enemy:FindFirstChildOfClass("Humanoid")
			if not humanoid then
				warn("❌ Enemy has no Humanoid!")
				return
			end

			local connection
			connection = humanoid.MoveToFinished:Connect(function(reached)
				if connection then
					connection:Disconnect()
				end

				if reached then
					currentWaypointIndex = currentWaypointIndex + 1
					task.wait() -- Small pause between waypoints
					moveToNextWaypoint()
				else
					task.wait(1)
					moveToNextWaypoint()
				end
			end)

			-- Timeout fallback (if enemy gets stuck)
			task.delay(30, function()
				if connection then
					connection:Disconnect()
				end
				if enemy and enemy.Parent and currentWaypointIndex <= #walkpoints then
					currentWaypointIndex = currentWaypointIndex + 1
					moveToNextWaypoint()
				end
			end)
		end
	end

	moveToNextWaypoint()
end

-- Function to count active enemies (supports both traditional and client-physics NPCs)
local function countActiveEnemies()
	local count = 0
	for enemyId, enemy in pairs(activeEnemies) do
		local isValid = false

		if typeof(enemy) == "string" then
			-- Client-physics NPC: check if data still exists
			local npcData = NPC_Service:GetClientPhysicsNPCData(enemy)
			isValid = npcData ~= nil and npcData.IsAlive
		else
			-- Traditional NPC: check if model still exists
			isValid = enemy and enemy.Parent
		end

		if isValid then
			count = count + 1
		else
			-- Clean up dead references
			activeEnemies[enemyId] = nil
		end
	end
	return count
end

-- Spawn loop - spawns enemies every 1 second up to max of 3
print("\n✅ Tower Defense Wave System initialized (Max: " .. MAX_ACTIVE_ENEMIES .. " enemies)")

task.spawn(function()
	while true do
		local activeCount = countActiveEnemies()

		if activeCount < MAX_ACTIVE_ENEMIES then
			local enemy, enemyId = spawnWaveEnemy()
			if enemy then
				moveEnemyThroughWaypoints(enemy, enemyId)
			end
		end

		task.wait(SPAWN_INTERVAL)
	end
end)

print(string.rep("=", 50) .. "\n")
