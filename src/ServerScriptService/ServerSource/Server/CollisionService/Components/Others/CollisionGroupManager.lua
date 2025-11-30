--[[
	CollisionGroupManager - Manages PhysicsService collision groups

	Registers collision groups and configures their collision relationships
	based on CollisionConfig settings.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CollisionGroupManager = {}

---- Datas
local CollisionConfig = require(ReplicatedStorage.SharedSource.Datas.CollisionConfig)

---- Knit Services
local CollisionService

--[[
	Register a collision group with PhysicsService if it doesn't exist
	
	@param groupName string - Name of the collision group
]]
local function registerCollisionGroup(groupName)
	local success, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(groupName)
	end)
	
	if success then
		print("[CollisionGroupManager] Registered collision group:", groupName)
	else
		-- Group might already exist, which is fine
		if not string.find(err, "already registered") then
			warn("[CollisionGroupManager] Error registering collision group:", groupName, err)
		end
	end
end

--[[
	Configure collision relationship between two groups
	
	@param group1 string - First collision group name
	@param group2 string - Second collision group name
	@param shouldCollide boolean - Whether the groups should collide
]]
local function setCollisionRelationship(group1, group2, shouldCollide)
	local success, err = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(group1, group2, shouldCollide)
	end)
	
	if success then
		local status = shouldCollide and "ENABLED" or "DISABLED"
		print(string.format("[CollisionGroupManager] %s <-> %s collision: %s", group1, group2, status))
	else
		warn("[CollisionGroupManager] Error setting collision relationship:", group1, group2, err)
	end
end

--[[
	Register all collision groups and configure their relationships
	Called during CollisionService:KnitStart()
]]
function CollisionGroupManager:RegisterCollisionGroups()
	-- Register collision groups
	registerCollisionGroup(CollisionConfig.Groups.NPCs)
	registerCollisionGroup(CollisionConfig.Groups.Players)
	
	-- Configure collision relationships based on config
	local settings = CollisionConfig.Settings
	
	-- NPC-to-NPC collision
	setCollisionRelationship(
		CollisionConfig.Groups.NPCs,
		CollisionConfig.Groups.NPCs,
		settings.NPC_to_NPC
	)
	
	-- Player-to-NPC collision
	setCollisionRelationship(
		CollisionConfig.Groups.Players,
		CollisionConfig.Groups.NPCs,
		settings.Player_to_NPC
	)
	
	-- Player-to-Player collision
	setCollisionRelationship(
		CollisionConfig.Groups.Players,
		CollisionConfig.Groups.Players,
		settings.Player_to_Player
	)
end

--[[
	Update collision setting at runtime
	
	@param settingName string - Name of the setting (e.g., "NPC_to_NPC")
	@param enabled boolean - Whether collision should be enabled
]]
function CollisionGroupManager:UpdateCollisionSetting(settingName, enabled)
	-- Update config
	CollisionConfig.Settings[settingName] = enabled
	
	-- Map setting name to collision groups
	local groupMappings = {
		NPC_to_NPC = {
			CollisionConfig.Groups.NPCs,
			CollisionConfig.Groups.NPCs
		},
		Player_to_NPC = {
			CollisionConfig.Groups.Players,
			CollisionConfig.Groups.NPCs
		},
		Player_to_Player = {
			CollisionConfig.Groups.Players,
			CollisionConfig.Groups.Players
		},
	}
	
	local groups = groupMappings[settingName]
	if groups then
		setCollisionRelationship(groups[1], groups[2], enabled)
		print(string.format("[CollisionGroupManager] Updated %s to %s", settingName, tostring(enabled)))
	else
		warn("[CollisionGroupManager] Unknown setting name:", settingName)
	end
end

function CollisionGroupManager.Start()
	-- Component start logic
end

function CollisionGroupManager.Init()
	CollisionService = Knit.GetService("CollisionService")
end

return CollisionGroupManager
