local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Get = {}

---- Knit Services
local NPC_Service

--[[
	Get NPC instance data
	
	@param npcModel Model - The NPC model
	@return table? - NPC data or nil if not found
]]
function Get:GetNPCData(npcModel)
	return NPC_Service.ActiveNPCs[npcModel]
end

--[[
	Get NPC's current target
	
	@param npcModel Model - The NPC model
	@return Model? - Current target or nil
]]
function Get:GetCurrentTarget(npcModel)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData then
		return npcData.CurrentTarget
	end
	return nil
end

--[[
	Check if NPC has a target in sight
	
	@param npcModel Model - The NPC model
	@return boolean - True if target is in sight
]]
function Get:HasTargetInSight(npcModel)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData then
		return npcData.TargetInSight or false
	end
	return false
end

--[[
	Get NPC's movement state
	
	@param npcModel Model - The NPC model
	@return string? - Movement state ("Idle", "Following", "Combat")
]]
function Get:GetMovementState(npcModel)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData then
		return npcData.MovementState
	end
	return nil
end

--[[
	Get NPC's spawn position
	
	@param npcModel Model - The NPC model
	@return Vector3? - Original spawn position
]]
function Get:GetSpawnPosition(npcModel)
	local npcData = NPC_Service.ActiveNPCs[npcModel]
	if npcData then
		return npcData.SpawnPosition
	end
	return nil
end

--[[
	Get all active NPCs
	
	@return table - Dictionary of all active NPCs [npcModel] = npcData
]]
function Get:GetAllNPCs()
	return NPC_Service.ActiveNPCs
end

function Get.Start()
	-- Component start logic
end

function Get.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return Get
