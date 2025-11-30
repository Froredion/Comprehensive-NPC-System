--[[
	Debug Test Script - Single Melee NPC

	Spawns exactly 1 melee NPC to debug pathfinding freeze issue
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Knit to initialize
local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

if true then
	return
end

local NPC_Service = Knit.GetService("NPC_Service")

print("\n" .. string.rep("=", 50))
print("🔍 DEBUG TEST - Single Melee NPC")
print(string.rep("=", 50) .. "\n")

-- Use the rig from ReplicatedStorage
local rigModel = ReplicatedStorage:WaitForChild("Assets", 10)
	and ReplicatedStorage.Assets:WaitForChild("NPCs", 10)
	and ReplicatedStorage.Assets.NPCs:WaitForChild("Characters", 10)
	and ReplicatedStorage.Assets.NPCs.Characters:WaitForChild("Rig", 10)

if not rigModel then
	warn("⚠️ No rig model found at: ReplicatedStorage.Assets.NPCs.Characters.Rig")
	return
end

-- Find a Melee spawner
local Workspace = game:GetService("Workspace")
local meleeSpawner = Workspace:FindFirstChild("Spawners")
	and Workspace.Spawners:FindFirstChild("Melee")
	and Workspace.Spawners.Melee:GetChildren()[1] -- Get first melee spawner

local spawnConfig = {
	Name = "DEBUG_MeleeNPC",
	Rotation = CFrame.Angles(0, 0, 0),
	ModelPath = rigModel,

	-- Stats
	MaxHealth = 100,
	WalkSpeed = 16,
	JumpPower = 50,

	-- Behavior
	SightRange = 60,
	SightMode = "Omnidirectional",
	MovementMode = "Melee",
	EnableIdleWander = true,
	EnableCombatMovement = true,

	-- Client Rendering Data
	ClientRenderData = {
		Scale = 1.0,
		CustomColor = Color3.fromRGB(255, 50, 50), -- Red for easy identification
		Transparency = 0,
	},

	CustomData = {
		Faction = "Enemy",
		EnemyType = "Melee",
	},
}

-- Use spawner position if available
if meleeSpawner and meleeSpawner:IsA("BasePart") then
	spawnConfig.SpawnerPart = meleeSpawner
	print("✅ Using Melee spawner at:", meleeSpawner.Position)
elseif meleeSpawner and meleeSpawner:IsA("Model") and meleeSpawner.PrimaryPart then
	spawnConfig.SpawnerPart = meleeSpawner.PrimaryPart
	print("✅ Using Melee spawner (model) at:", meleeSpawner.PrimaryPart.Position)
else
	spawnConfig.Position = Vector3.new(0, 10, 0)
	print("⚠️ No Melee spawner found, using default position")
end

local testNPC = NPC_Service:SpawnNPC(spawnConfig)

if testNPC then
	print("✅ Spawned DEBUG_MeleeNPC successfully")
	print("📍 NPC ID:", testNPC)

	-- Wait for client to claim the NPC
	task.wait(3)

	-- Get NPC's current position and set a distant destination
	local npcData = NPC_Service:GetClientPhysicsNPCData(testNPC)
	local startPos = npcData and npcData.Position or Vector3.new(0, 5, 0)
	local targetPos = startPos + Vector3.new(100, 0, 0) -- Walk 100 studs in X direction

	print("🎯 Setting destination to:", targetPos)
	print("📍 NPC should walk AND jump simultaneously\n")

	-- Set destination so NPC is walking
	-- Note: For client-physics NPCs, destination is set via ActiveNPCs folder
	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if activeNPCsFolder then
		local npcFolder = activeNPCsFolder:FindFirstChild(testNPC)
		if npcFolder then
			local destValue = npcFolder:FindFirstChild("Destination")
			if destValue then
				destValue.Value = targetPos
			end
		end
	end

	task.wait(1) -- Let NPC start walking

	-- Test jumping continuously while walking
	print("🦘 Starting continuous jump test - jumping every 1 second")
	local jumpCount = 0
	while true do
		jumpCount = jumpCount + 1
		print("🦘 Jump #" .. jumpCount)
		NPC_Service:TriggerJump(testNPC)
		task.wait(1)
	end
else
	warn("❌ Failed to spawn DEBUG_MeleeNPC")
end

print("\n💡 Watch the NPC in-game - it should jump while continuing to walk")
print("💡 The NPC should maintain horizontal velocity during jumps")
