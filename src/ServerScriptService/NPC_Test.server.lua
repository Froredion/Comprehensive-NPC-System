--[[
	NPC System Phase 5 & 6 Test Script
	
	Tests client-side rendering and BetterAnimate integration
	
	Usage:
	1. Enable client rendering: Set RenderConfig.ENABLED = true
	2. Run this script in Studio
	3. Observe NPCs spawning with visual models and animations
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Knit to initialize
local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

local NPC_Service = Knit.GetService("NPC_Service")

print("\n" .. string.rep("=", 50))
print("🧪 NPC SYSTEM PHASE 5 & 6 TEST")
print("Testing Client-Side Rendering & BetterAnimate")
print(string.rep("=", 50) .. "\n")

-- Test Configuration
local TEST_SPAWN_POSITION = Vector3.new(0, 10, 0)
local TEST_SPAWN_SPACING = 10 -- Studs between NPCs

-- Use the rig from ReplicatedStorage
local rigModel = ReplicatedStorage:WaitForChild("Assets", 10)
	and ReplicatedStorage.Assets:WaitForChild("NPCs", 10)
	and ReplicatedStorage.Assets.NPCs:WaitForChild("Characters", 10)
	and ReplicatedStorage.Assets.NPCs.Characters:WaitForChild("Rig", 10)

if not rigModel then
	warn("⚠️ No rig model found at: ReplicatedStorage.Assets.NPCs.Characters.Rig")
	return
end

-- Get spawn positions from Workspace
local Workspace = game:GetService("Workspace")
local spawnPositions = {}

-- Collect spawner positions
local spawners = Workspace:FindFirstChild("Spawners")
if spawners then
	for _, categoryFolder in pairs(spawners:GetChildren()) do
		if categoryFolder:IsA("Folder") then
			for _, spawner in pairs(categoryFolder:GetChildren()) do
				if spawner:IsA("BasePart") or (spawner:IsA("Model") and spawner.PrimaryPart) then
					local position = spawner:IsA("BasePart") and spawner.Position or spawner.PrimaryPart.Position
					table.insert(spawnPositions, {
						Position = position,
						Category = categoryFolder.Name,
						Name = spawner.Name,
					})
				end
			end
		end
	end
end

-- Test 1: Spawn NPC with Client Rendering Configuration
print("\n📌 Test 1: Spawning test NPCs...")
task.wait(1)

-- Find ClientRender spawner position
local clientRenderSpawner = Workspace:FindFirstChild("Spawners")
	and Workspace.Spawners:FindFirstChild("ClientRender")
	and Workspace.Spawners.ClientRender:FindFirstChild("NPCSpawner_2")

local spawnPos1 = TEST_SPAWN_POSITION
if clientRenderSpawner then
	if clientRenderSpawner:IsA("BasePart") then
		spawnPos1 = clientRenderSpawner.Position
	elseif clientRenderSpawner:IsA("Model") and clientRenderSpawner.PrimaryPart then
		spawnPos1 = clientRenderSpawner.PrimaryPart.Position
	end
end

-- Random rotation for first NPC
local randomAngle1 = math.random(0, 360)
local rotation1 = CFrame.Angles(0, math.rad(randomAngle1), 0)

local testNPC1 = NPC_Service:SpawnNPC({
	Name = "TestRenderedNPC_1",
	Position = spawnPos1,
	Rotation = rotation1,
	ModelPath = rigModel,

	-- Stats
	MaxHealth = 100,
	WalkSpeed = 16,
	JumpPower = 50,

	-- Behavior
	SightRange = 60,
	SightMode = "Directional",
	MovementMode = "Ranged",
	EnableIdleWander = true,
	EnableCombatMovement = true,

	-- Client Rendering Data (optional visual customization for client)
	ClientRenderData = {
		-- Visual scale multiplier for client-side model
		Scale = 1.0,
		-- Custom color tint for client-side model
		CustomColor = Color3.fromRGB(255, 100, 100),
		-- Optional transparency for special effects
		Transparency = 0,
	},

	-- Custom Game Data (gameplay-specific attributes)
	CustomData = {
		-- NPC faction/team identifier
		Faction = "Enemy",
		-- NPC combat classification
		EnemyType = "Ranged",
		-- Experience points awarded on defeat
		ExperienceReward = 50,
		-- Loot table identifier
		LootTableID = "RangedEnemy_T1",
		-- Level/difficulty
		Level = 1,
	},
})

if not testNPC1 then
	warn("❌ Failed to spawn Test NPC 1")
end

-- Test 2: Spawn Multiple NPCs for Distance-Based Rendering Test
task.wait(1)

local testNPCs = {}

-- ⚙️ SPAWN CONFIGURATION - Modify these values to control how many NPCs spawn per category
local SPAWN_LIMITS = {
	Ranged = 3, -- Number of ranged NPCs to spawn
	Melee = 3, -- Number of melee NPCs to spawn
	CantWalk = 1, -- Number of cantwalk NPCs to spawn
	ConeSight = 3, -- Number of cone sight NPCs to spawn
}

-- Counters for each category
local categoryCounters = {
	Ranged = 0,
	Melee = 0,
	CantWalk = 0,
	ConeSight = 0,
}

for i = 1, #spawnPositions do
	local spawnInfo = spawnPositions[i]
	local movementMode = "Ranged"
	local usePathfinding = true
	local canWalk = true
	local sightMode = "Omnidirectional"
	local categoryName = "Ranged"
	local namePrefix = "ranged"

	-- Configure based on spawner category
	if spawnInfo.Category == "Melee" then
		movementMode = "Melee"
		categoryName = "Melee"
		namePrefix = "melee"
	elseif spawnInfo.Category == "No_Pathfinding" then
		usePathfinding = false
	elseif spawnInfo.Category == "CantWalk" then
		canWalk = false
		categoryName = "CantWalk"
		namePrefix = "cantwalk"
	elseif spawnInfo.Category == "ConeSight" then
		sightMode = "Directional"
		categoryName = "ConeSight"
		namePrefix = "conesight"
	end

	-- Check if we've reached the spawn limit for this category
	if categoryCounters[categoryName] >= SPAWN_LIMITS[categoryName] then
		continue -- Skip this spawn
	end

	-- Increment counter for this category
	categoryCounters[categoryName] = categoryCounters[categoryName] + 1
	local npcName = namePrefix .. "_" .. categoryCounters[categoryName]

	-- Give each NPC a different rotation angle
	local rotationAngle = (i * 72) % 360 -- Distribute evenly: 0°, 72°, 144°, 216°, 288°
	local rotation = CFrame.Angles(0, math.rad(rotationAngle), 0)

	local npc = NPC_Service:SpawnNPC({
		Name = npcName,
		Position = spawnInfo.Position,
		Rotation = rotation,
		ModelPath = rigModel,

		MaxHealth = 100,
		WalkSpeed = 16,

		SightRange = 60,
		SightMode = sightMode,
		MovementMode = movementMode,
		UsePathfinding = usePathfinding,
		CanWalk = canWalk,
		EnableIdleWander = true,
		EnableCombatMovement = true,

		ClientRenderData = {
			Scale = 1.0 + (i * 0.1), -- Vary scale for visual difference
			CustomColor = Color3.fromRGB(100 + i * 30, 150, 255 - i * 30),
			Transparency = 0,
		},

		CustomData = {
			Faction = "Enemy",
			EnemyType = spawnInfo.Category,
			ExperienceReward = 25 * i,
			LootTableID = "Test_T" .. i,
			Level = i,
		},
	})

	if npc then
		table.insert(testNPCs, npc)
	end
end

print("\n✅ Spawned " .. #testNPCs .. " NPCs total")

-- Give NPCs a movement target to test animations
if testNPC1 and testNPC1.PrimaryPart then
	local targetPos = testNPC1.PrimaryPart.Position + Vector3.new(20, 0, 0)
	NPC_Service:SetDestination(testNPC1, targetPos)
end

-- -- Cleanup Function (optional)
-- local function cleanupTest()
-- 	print("\n🧹 Cleaning up test NPCs...")
-- 	for _, npc in pairs(testNPCs) do
-- 		if npc and npc.Parent then
-- 			NPC_Service:DestroyNPC(npc)
-- 		end
-- 	end
-- 	if testNPC1 and testNPC1.Parent then
-- 		NPC_Service:DestroyNPC(testNPC1)
-- 	end
-- 	print("✅ Test cleanup complete")
-- end

-- -- Auto-cleanup after 60 seconds (optional)
-- task.delay(60, function()
-- 	print("\n⏰ Auto-cleanup triggered (60 seconds elapsed)")
-- 	cleanupTest()
-- end)

-- print("ℹ️ Test NPCs will auto-cleanup in 60 seconds")
-- print("💡 Run cleanupTest() to manually cleanup NPCs")