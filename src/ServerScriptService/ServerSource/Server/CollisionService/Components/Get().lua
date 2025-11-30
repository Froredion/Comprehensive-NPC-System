local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local GetComponent = {}

---- Datas
local CollisionConfig = require(ReplicatedStorage.SharedSource.Datas.CollisionConfig)

---- Knit Services
local CollisionService



--[[
	Get current collision settings
	
	@return table - Current collision settings
]]
function GetComponent:GetCollisionSettings()
	return CollisionConfig.Settings
end

--[[
	Get collision group names
	
	@return table - Collision group names
]]
function GetComponent:GetCollisionGroups()
	return CollisionConfig.Groups
end

--[[
	Get specific collision setting value
	
	@param settingName string - Name of the setting
	@return boolean? - Setting value or nil if not found
]]
function GetComponent:GetCollisionSetting(settingName)
	return CollisionConfig.Settings[settingName]
end

function GetComponent.Start()
	
end

function GetComponent.Init()
	CollisionService = Knit.GetService("CollisionService")
end

return GetComponent
