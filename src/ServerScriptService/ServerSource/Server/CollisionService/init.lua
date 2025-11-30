local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CollisionService = Knit.CreateService({
	Name = "CollisionService",
	Instance = script, -- Automatically initializes components
	Client = {},
})

---- Datas
local CollisionConfig = require(ReplicatedStorage.SharedSource.Datas.CollisionConfig)

---- Knit Services
-- None required for now

--[[
	Apply collision group to a character (NPC or Player)
	
	@param character Model - The character model to apply collision to
	@param groupName string - The collision group name ("NPCs" or "Players")
]]
function CollisionService:ApplyCollisionToCharacter(character, groupName)
	if CollisionService.Components.CharacterCollisionHandler then
		CollisionService.Components.CharacterCollisionHandler:ApplyCollisionGroup(character, groupName)
	end
end

--[[
	Get current collision settings
	
	@return table - Current collision settings
]]
function CollisionService:GetCollisionSettings()
	if CollisionService.GetComponent then
		return CollisionService.GetComponent:GetCollisionSettings()
	end
	return CollisionConfig.Settings
end

--[[
	Update a collision setting at runtime
	
	@param settingName string - Name of the setting (e.g., "NPC_to_NPC")
	@param enabled boolean - Whether collision should be enabled
]]
function CollisionService:UpdateCollisionSetting(settingName, enabled)
	if CollisionService.SetComponent then
		CollisionService.SetComponent:UpdateCollisionSetting(settingName, enabled)
	end
end

function CollisionService:KnitStart()
	-- Initialize collision groups via CollisionGroupManager
	if CollisionService.Components.CollisionGroupManager then
		CollisionService.Components.CollisionGroupManager:RegisterCollisionGroups()
		print("[CollisionService] Collision groups registered and configured")
	end
	
	-- Initialize player collision monitoring
	if CollisionService.Components.PlayerCollisionHandler then
		CollisionService.Components.PlayerCollisionHandler:Initialize()
	end
end

function CollisionService:KnitInit()
	-- Service initialization
end

return CollisionService
