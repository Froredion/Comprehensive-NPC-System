local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NPC_Service = Knit.CreateService({
	Name = "NPC_Service",
	Client = {},

	-- Registry of all active NPCs
	ActiveNPCs = {}, -- [npcModel] = npcData
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
NPC_Service.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	NPC_Service.Components[v.Name] = require(v)
end
NPC_Service.GetComponent = require(componentsFolder["Get()"])
NPC_Service.SetComponent = require(componentsFolder["Set()"])

---- Knit Services
-- No external services needed for core functionality

--[[
	Spawn NPC with flexible configuration
	
	@param config table - Configuration for NPC spawning
		- Name: string - NPC name
		- Position: Vector3 - Spawn position
		- ModelPath: Instance - Path to character model (e.g., ReplicatedStorage.Assets.NPCs.Characters.Rig)
		- MaxHealth: number? - Maximum health (default: 100)
		- WalkSpeed: number? - Walk speed in studs/second (default: 16)
		- JumpPower: number? - Jump power (default: 50)
		- SightRange: number? - Detection range in studs (default: 200)
		- SightMode: string? - "Omnidirectional" or "Directional" (default: "Directional")
		- CanWalk: boolean? - Enable/disable all movement (default: true)
		- MovementMode: string? - "Ranged" or "Melee" (default: "Ranged")
		- MeleeOffsetRange: number? - For Melee mode: offset distance in studs (default: 3-8 studs)
		- UsePathfinding: boolean? - Use advanced pathfinding vs simple MoveTo() (default: true)
		- EnableIdleWander: boolean? - Enable random wandering (default: true)
		- EnableCombatMovement: boolean? - Enable combat movement (default: true)
		- ClientRenderData: table? - Optional visual customization for client-side rendering (besides Scale, others are attributes)
			* Scale: number? - Visual scale multiplier (default: 1.0)
		- CustomData: table? - Game-specific attributes for gameplay logic
			* Faction: string? - NPC faction/team identifier (e.g., "Ally") >> same team NPCs won't target each other
			* EnemyType: string? - Combat classification (e.g., "Ranged", "Melee")
		
	@return Model - The spawned NPC model
]]
function NPC_Service:SpawnNPC(config)
	return NPC_Service.Components.NPCSpawner:SpawnNPC(config)
end

--[[
	Get NPC instance data
	
	@param npcModel Model - The NPC model
	@return table? - NPC data or nil if not found
]]
function NPC_Service:GetNPCData(npcModel)
	return NPC_Service.GetComponent:GetNPCData(npcModel)
end

--[[
	Get NPC's current target
	
	@param npcModel Model - The NPC model
	@return Model? - Current target or nil
]]
function NPC_Service:GetCurrentTarget(npcModel)
	return NPC_Service.GetComponent:GetCurrentTarget(npcModel)
end

--[[
	Manually set target for NPC
	
	@param npcModel Model - The NPC model
	@param target Model? - Target to set (nil to clear)
]]
function NPC_Service:SetTarget(npcModel, target)
	NPC_Service.SetComponent:SetTarget(npcModel, target)
end

--[[
	Manually set destination for NPC
	
	@param npcModel Model - The NPC model
	@param destination Vector3? - Destination to set (nil to clear)
]]
function NPC_Service:SetDestination(npcModel, destination)
	NPC_Service.SetComponent:SetDestination(npcModel, destination)
end

--[[
	Destroy NPC and cleanup
	
	@param npcModel Model - The NPC model to destroy
]]
function NPC_Service:DestroyNPC(npcModel)
	NPC_Service.SetComponent:DestroyNPC(npcModel)
end

function NPC_Service:KnitStart()
	-- Post-initialization logic can go here
end

function NPC_Service:KnitInit()
	---- Components Initializer
	componentsInitializer(script)
end

return NPC_Service
