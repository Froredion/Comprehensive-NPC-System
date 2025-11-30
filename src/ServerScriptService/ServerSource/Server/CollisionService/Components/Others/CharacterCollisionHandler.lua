--[[
	CharacterCollisionHandler - Applies collision groups to character models

	Handles applying collision groups to all BaseParts in a character model,
	and monitors for new parts being added (accessories, tools, etc.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CharacterCollisionHandler = {}

---- Knit Services
local CollisionService

---- Active character connections
local CharacterConnections = {} -- [character] = {connections}

--[[
	Apply collision group to a single BasePart
	
	@param part BasePart - The part to apply collision to
	@param groupName string - The collision group name
]]
local function applyCollisionToPart(part, groupName)
	if part:IsA("BasePart") then
		part.CollisionGroup = groupName
	end
end

--[[
	Handle new descendants being added to a character
	
	@param descendant Instance - The newly added descendant
	@param groupName string - The collision group to apply
]]
local function onDescendantAdded(descendant, groupName)
	if descendant:IsA("BasePart") then
		applyCollisionToPart(descendant, groupName)
	end
end

--[[
	Apply collision group to all existing parts and monitor for new ones
	
	@param character Model - The character model
	@param groupName string - The collision group name ("NPCs" or "Players")
]]
function CharacterCollisionHandler:ApplyCollisionGroup(character, groupName)
	if not character or not character:IsA("Model") then
		warn("[CharacterCollisionHandler] Invalid character model provided")
		return
	end
	
	if not groupName or (groupName ~= "NPCs" and groupName ~= "Players") then
		warn("[CharacterCollisionHandler] Invalid collision group name:", groupName)
		return
	end
	
	-- Apply collision group to all existing BaseParts
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			applyCollisionToPart(descendant, groupName)
		end
	end
	
	-- Monitor for new parts being added (accessories, tools, etc.)
	if not CharacterConnections[character] then
		CharacterConnections[character] = {}
	end
	
	local descendantConnection = character.DescendantAdded:Connect(function(descendant)
		onDescendantAdded(descendant, groupName)
	end)
	table.insert(CharacterConnections[character], descendantConnection)
	
	-- Cleanup connections when character is removed
	local ancestryConnection = character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			-- Character was removed from workspace
			local connections = CharacterConnections[character]
			if connections then
				for _, connection in ipairs(connections) do
					if typeof(connection) == "RBXScriptConnection" then
						pcall(function()
							connection:Disconnect()
						end)
					end
				end
				CharacterConnections[character] = nil
			end
		end
	end)
	table.insert(CharacterConnections[character], ancestryConnection)
	
	print(string.format("[CharacterCollisionHandler] Applied '%s' collision group to %s", groupName, character.Name))
end

--[[
	Remove collision group from a character and cleanup connections
	
	@param character Model - The character model
]]
function CharacterCollisionHandler:RemoveCollisionGroup(character)
	if not character then
		return
	end
	
	-- Cleanup connections
	local connections = CharacterConnections[character]
	if connections then
		for _, connection in ipairs(connections) do
			if typeof(connection) == "RBXScriptConnection" then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end
		CharacterConnections[character] = nil
	end
	
	-- Reset collision group to Default for all parts
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Default"
		end
	end
end

function CharacterCollisionHandler.Start()
	-- Component start logic
end

function CharacterCollisionHandler.Init()
	CollisionService = Knit.GetService("CollisionService")
end

return CharacterCollisionHandler
