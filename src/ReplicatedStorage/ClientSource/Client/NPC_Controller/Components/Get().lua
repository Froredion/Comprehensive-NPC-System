--[[
	NPC_Controller Get Component
	
	Purpose: Query methods for client-side NPC rendering
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Get = {}

local NPCRenderer

--[[
	Get all rendered NPCs
	
	@return table - Dictionary of rendered NPCs [npcModel] = {visualModel, renderData}
]]
function Get:GetRenderedNPCs()
	if not NPCRenderer then
		return {}
	end
	
	-- Access RenderedNPCs from NPCRenderer (via require)
	local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.RenderConfig)
	if not RenderConfig.ENABLED then
		return {}
	end
	
	-- Note: This requires NPCRenderer to expose its RenderedNPCs table
	-- For now, return empty table as RenderedNPCs is local to NPCRenderer
	return {}
end

--[[
	Check if an NPC is currently rendered
	
	@param npc Model - Server NPC model
	@return boolean - True if NPC is rendered
]]
function Get:IsNPCRendered(npc)
	local renderedNPCs = self:GetRenderedNPCs()
	return renderedNPCs[npc] ~= nil
end

--[[
	Get visual model for an NPC
	
	@param npc Model - Server NPC model
	@return Model? - Visual model or nil if not rendered
]]
function Get:GetVisualModel(npc)
	local renderedNPCs = self:GetRenderedNPCs()
	if renderedNPCs[npc] then
		return renderedNPCs[npc].visualModel
	end
	return nil
end

function Get.Start()
	-- Component start logic
end

function Get.Init()
	NPCRenderer = require(script.Parent.Others.NPCRenderer)
end

return Get
