--[[
	Debug Test Script - Single Melee NPC

	Spawns exactly 1 melee NPC to debug pathfinding freeze issue
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Knit to initialize
local Knit = require(ReplicatedStorage.Packages.Knit)
Knit.OnStart():await()

if false then -- Set to true to disable this tester
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
	print("📍 Position:", testNPC.PrimaryPart and testNPC.PrimaryPart.Position or "N/A")

	-- Set a destination to trigger pathfinding
	task.wait(2)
	if testNPC and testNPC.PrimaryPart then
		local targetPos = testNPC.PrimaryPart.Position + Vector3.new(30, 0, 0)
		print("🎯 Setting destination to:", targetPos)
		NPC_Service:SetDestination(testNPC, targetPos)
	end
else
	warn("❌ Failed to spawn DEBUG_MeleeNPC")
end

print("\n💡 Watch for [DEBUG_PATH] prints in client console")
print("💡 The NPC should move toward the target destination")
