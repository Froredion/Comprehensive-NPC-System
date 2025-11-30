local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SetComponent = {}

---- Datas
local CollisionConfig = require(ReplicatedStorage.SharedSource.Datas.CollisionConfig)

---- Knit Services
local CollisionService



--[[
	Update a collision setting at runtime
	
	@param settingName string - Name of the setting (e.g., "NPC_to_NPC")
	@param enabled boolean - Whether collision should be enabled
]]
function SetComponent:UpdateCollisionSetting(settingName, enabled)
	if not CollisionConfig.Settings[settingName] then
		warn("[CollisionService.SetComponent] Invalid setting name:", settingName)
		return
	end
	
	-- Delegate to CollisionGroupManager
	if CollisionService.Components.CollisionGroupManager then
		CollisionService.Components.CollisionGroupManager:UpdateCollisionSetting(settingName, enabled)
	end
end

--[[
	Batch update multiple collision settings
	
	@param settings table - Table of settings to update {settingName = enabled, ...}
]]
function SetComponent:UpdateMultipleSettings(settings)
	for settingName, enabled in pairs(settings) do
		self:UpdateCollisionSetting(settingName, enabled)
	end
end

--[[
	Reset all collision settings to their default values
]]
function SetComponent:ResetToDefaults()
	-- Default: all collisions disabled
	local defaults = {
		NPC_to_NPC = false,
		Player_to_NPC = false,
		Player_to_Player = false,
	}
	
	self:UpdateMultipleSettings(defaults)
end

function SetComponent.Start()
	
end

function SetComponent.Init()
	CollisionService = Knit.GetService("CollisionService")
end

return SetComponent
