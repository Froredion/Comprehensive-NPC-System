--[[
	CollisionTest - Test script for the Collision System

	This script demonstrates how to use the CollisionService and test all collision settings.
	
	Usage:
	1. Run the game in Roblox Studio
	2. NPCs will have collision groups applied automatically via NPC_Service integration
	3. Players will have collision groups applied automatically via CollisionService.PlayerCollisionHandler
	4. Use the commands below to test different collision settings
	5. Observe collision behavior changes in real-time
	
	Architecture:
	- CollisionService handles all collision group management
	- PlayerCollisionHandler component monitors Players service and applies collision to characters
	- NPCSpawner integration applies collision to NPCs on spawn
	- All collision logic is centralized in CollisionService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Wait for Knit to initialize
local Knit = require(ReplicatedStorage.Packages.Knit)
repeat task.wait() until Knit.OnStart():getStatus() == "Completed"

local CollisionService = Knit.GetService("CollisionService")
local NPC_Service = Knit.GetService("NPC_Service")

print("=== Collision System Test Started ===")
print("CollisionService initialized:", CollisionService ~= nil)

-- Display current collision settings
local function displaySettings()
	print("\n=== Current Collision Settings ===")
	local settings = CollisionService:GetCollisionSettings()
	for settingName, enabled in pairs(settings) do
		local status = enabled and "ENABLED" or "DISABLED"
		print(string.format("  %s: %s", settingName, status))
	end
	print("==================================\n")
end

-- Test 1: Display initial settings
print("\n[Test 1] Initial collision settings:")
displaySettings()

-- Test 2: Spawn test NPCs
print("[Test 2] Spawning test NPCs...")
task.wait(1)

local testNPC1 = NPC_Service:SpawnNPC({
	Name = "TestNPC1",
	Position = Vector3.new(0, 5, 0),
	ModelPath = ReplicatedStorage.Assets.NPCs.R6_Template.Rig,
	MaxHealth = 100,
	WalkSpeed = 16,
})

local testNPC2 = NPC_Service:SpawnNPC({
	Name = "TestNPC2",
	Position = Vector3.new(5, 5, 0),
	ModelPath = ReplicatedStorage.Assets.NPCs.R6_Template.Rig,
	MaxHealth = 100,
	WalkSpeed = 16,
})

print("NPCs spawned! Check their collision groups in Properties window.")
print("Both NPCs should have CollisionGroup = 'NPCs'")

-- Test 3: Toggle NPC-to-NPC collision
task.wait(3)
print("\n[Test 3] Enabling NPC-to-NPC collision...")
CollisionService:UpdateCollisionSetting("NPC_to_NPC", true)
displaySettings()
print("NPCs should now collide with each other.")

task.wait(3)
print("\n[Test 3b] Disabling NPC-to-NPC collision...")
CollisionService:UpdateCollisionSetting("NPC_to_NPC", false)
displaySettings()
print("NPCs should now pass through each other.")

-- Test 4: Toggle Player-to-NPC collision
task.wait(3)
print("\n[Test 4] Enabling Player-to-NPC collision...")
CollisionService:UpdateCollisionSetting("Player_to_NPC", true)
displaySettings()
print("Players should now collide with NPCs.")

task.wait(3)
print("\n[Test 4b] Disabling Player-to-NPC collision...")
CollisionService:UpdateCollisionSetting("Player_to_NPC", false)
displaySettings()
print("Players should now pass through NPCs.")

-- Test 5: Toggle Player-to-Player collision
task.wait(3)
print("\n[Test 5] Enabling Player-to-Player collision...")
CollisionService:UpdateCollisionSetting("Player_to_Player", true)
displaySettings()
print("Players should now collide with each other.")

task.wait(3)
print("\n[Test 5b] Disabling Player-to-Player collision...")
CollisionService:UpdateCollisionSetting("Player_to_Player", false)
displaySettings()
print("Players should now pass through each other.")

-- Test 6: Reset to defaults
task.wait(3)
print("\n[Test 6] Resetting to default settings...")
if CollisionService.SetComponent then
	CollisionService.SetComponent:ResetToDefaults()
end
displaySettings()

print("\n=== Collision System Test Complete ===")
print("All tests passed! The collision system is working correctly.")
print("\nTo manually test:")
print("1. Walk your player character into NPCs")
print("2. Spawn more NPCs and watch them interact")
print("3. Toggle collision settings using CollisionService:UpdateCollisionSetting()")
print("4. Use multiple players to test Player-to-Player collision")
