--[[
	NPC Mass Spawn Test Script
	
	Spawns 300 NPCs randomly across the Baseplate
	
	Usage:
	1. Run this script in Studio
	2. Observe 300 NPCs spawning randomly on the Baseplate
]]

-- if true then
-- 	return
-- end -- Disable script by default

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Wait for Knit to initialize
local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

local NPC_Service = Knit.GetService("NPC_Service")

print("\n" .. string.rep("=", 50))
print("🧪 NPC MASS SPAWN TEST")
print("Spawning 300 NPCs randomly across the Baseplate")
print(string.rep("=", 50) .. "\n")

-- Baseplate Configuration (from Roblox Studio)
local BASEPLATE_POSITION = Vector3.new(0, -8, 0)
local BASEPLATE_SIZE = Vector3.new(2048, 16, 2048)
local BASEPLATE_TOP_Y = BASEPLATE_POSITION.Y + (BASEPLATE_SIZE.Y / 2) -- Y = 0

-- Spawn Configuration
local NPC_COUNT = 3
local SPAWN_HEIGHT_OFFSET = 5 -- Spawn NPCs slightly above ground
local SPAWN_PADDING = 50 -- Keep NPCs away from edges

-- Player proximity spawn settings
local SPAWN_RADIUS_MIN = 20 -- Minimum distance from player (studs)
local SPAWN_RADIUS_MAX = 150 -- Maximum distance from player (studs)
local PREFER_PLAYER_CHANCE = 0.85 -- 85% chance to spawn near a player

-- Calculate spawn bounds (with padding)
local halfSizeX = (BASEPLATE_SIZE.X / 2) - SPAWN_PADDING
local halfSizeZ = (BASEPLATE_SIZE.Z / 2) - SPAWN_PADDING

-- Use the rig from ReplicatedStorage
local rigModel = ReplicatedStorage:WaitForChild("Assets", 10)
	and ReplicatedStorage.Assets:WaitForChild("NPCs", 10)
	and ReplicatedStorage.Assets.NPCs:WaitForChild("Characters", 10)
	and ReplicatedStorage.Assets.NPCs.Characters:WaitForChild("Rig", 10)

if not rigModel then
	warn("⚠️ No rig model found at: ReplicatedStorage.Assets.NPCs.Characters.Rig")
	return
end

-- Helper function to clamp position within baseplate bounds
local function clampToBaseplate(x, z)
	x = math.clamp(x, -halfSizeX, halfSizeX)
	z = math.clamp(z, -halfSizeZ, halfSizeZ)
	return x, z
end

-- Helper function to get a random player's position
local function getRandomPlayerPosition()
	local players = game:GetService("Players"):GetPlayers()
	local validPositions = {}

	for _, player in ipairs(players) do
		local character = player.Character
		if character and character.PrimaryPart then
			table.insert(validPositions, character.PrimaryPart.Position)
		end
	end

	if #validPositions > 0 then
		return validPositions[math.random(1, #validPositions)]
	end
	return nil
end

-- Helper function to generate random spawn position (prefers near players)
local function getRandomSpawnPosition()
	local spawnY = BASEPLATE_TOP_Y + SPAWN_HEIGHT_OFFSET

	-- Try to spawn near a player
	if math.random() < PREFER_PLAYER_CHANCE then
		local playerPos = getRandomPlayerPosition()
		if playerPos then
			-- Generate random angle and distance from player
			local angle = math.random() * math.pi * 2
			local distance = math.random(SPAWN_RADIUS_MIN, SPAWN_RADIUS_MAX)

			local offsetX = math.cos(angle) * distance
			local offsetZ = math.sin(angle) * distance

			local spawnX = playerPos.X + offsetX
			local spawnZ = playerPos.Z + offsetZ

			-- Clamp to baseplate bounds
			spawnX, spawnZ = clampToBaseplate(spawnX, spawnZ)

			return Vector3.new(spawnX, spawnY, spawnZ)
		end
	end

	-- Fallback: random position on baseplate
	local randomX = math.random(-halfSizeX, halfSizeX)
	local randomZ = math.random(-halfSizeZ, halfSizeZ)

	return Vector3.new(randomX, spawnY, randomZ)
end

-- Helper function to generate random rotation
local function getRandomRotation()
	local randomAngle = math.random(0, 360)
	return CFrame.Angles(0, math.rad(randomAngle), 0)
end

-- Movement modes to randomly assign
local MOVEMENT_MODES = { "Ranged", "Melee" }
local SIGHT_MODES = { "Directional", "Omnidirectional" }

-- Store spawned NPCs
local spawnedNPCs = {}

-- Spawn Rate Configuration
local SPAWN_RATE = 30 -- NPCs per second
local SPAWN_INTERVAL = 1 / SPAWN_RATE -- Time between each spawn (~0.033 seconds)

print("📌 Starting NPC spawn...")
print(string.format("⏱️ Spawn rate: %d NPCs/second (%.3fs interval)", SPAWN_RATE, SPAWN_INTERVAL))
local startTime = tick()
local lastSpawnTime = startTime

for i = 1, NPC_COUNT do
	-- Randomize NPC settings for variety
	local movementMode = MOVEMENT_MODES[math.random(1, #MOVEMENT_MODES)]
	local sightMode = SIGHT_MODES[math.random(1, #SIGHT_MODES)]
	local walkSpeed = math.random(12, 20)
	local sightRange = math.random(40, 80)

	-- Random color for visual distinction
	local randomColor = Color3.fromRGB(math.random(100, 255), math.random(100, 255), math.random(100, 255))

	local spawnConfig = {
		Name = "NPC_" .. i,
		Position = getRandomSpawnPosition(),
		Rotation = getRandomRotation(),
		ModelPath = rigModel,

		-- Stats (with some variation)
		MaxHealth = math.random(80, 150),
		WalkSpeed = walkSpeed,
		JumpPower = 50,

		-- Behavior
		SightRange = sightRange,
		SightMode = sightMode,
		MovementMode = movementMode,
		MeleeOffsetRange = math.random(3, 8),
		UsePathfinding = true, -- DISABLED FOR TESTING
		CanWalk = true,
		EnableIdleWander = true,
		EnableCombatMovement = true,

		-- Client Rendering Data
		ClientRenderData = {
			Scale = 1.0,
			CustomColor = randomColor,
			Transparency = 0,
		},

		-- Custom Game Data
		CustomData = {
			Faction = "Enemy",
			EnemyType = movementMode,
			ExperienceReward = math.random(10, 100),
			Level = math.random(1, 10),
		},
	}

	local npc = NPC_Service:SpawnNPC(spawnConfig)

	if npc then
		table.insert(spawnedNPCs, npc)
	end

	-- Progress update every 50 NPCs
	if i % 50 == 0 then
		print(string.format("✅ Spawned %d / %d NPCs...", i, NPC_COUNT))
	end

	-- Fixed spawn rate: wait until next spawn interval
	if i < NPC_COUNT then
		local elapsed = tick() - lastSpawnTime
		local waitTime = SPAWN_INTERVAL - elapsed
		if waitTime > 0 then
			task.wait(waitTime)
		end
		lastSpawnTime = tick()
	end
end

local elapsedTime = tick() - startTime
print(string.format("\n🎉 Successfully spawned %d NPCs in %.2f seconds!", #spawnedNPCs, elapsedTime))
print(string.format("📊 Target spawn rate: %d NPCs/second", SPAWN_RATE))
print(string.format("📊 Actual spawn rate: %.1f NPCs/second", #spawnedNPCs / elapsedTime))

-- Optional cleanup function
local function cleanupAllNPCs()
	print("\n🧹 Cleaning up all NPCs...")
	local cleanupStart = tick()

	for _, npc in pairs(spawnedNPCs) do
		if npc and (typeof(npc) == "Instance" and npc.Parent) or typeof(npc) == "string" then
			NPC_Service:DestroyNPC(npc)
		end
	end

	spawnedNPCs = {}
	print(string.format("✅ Cleanup complete in %.2f seconds", tick() - cleanupStart))
end

-- Expose cleanup function globally for manual use
_G.CleanupNPCs = cleanupAllNPCs

print("\n💡 TIP: Run _G.CleanupNPCs() in command bar to manually cleanup all NPCs")
