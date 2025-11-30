local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NPC_Service = Knit.CreateService({
	Name = "NPC_Service",
	Instance = script,
	Client = {
		-- Signals for UseAnimationController client-physics system
		NPCPositionUpdated = Knit.CreateSignal(), -- Broadcast NPC position updates to nearby clients
		NPCsOrphaned = Knit.CreateSignal(), -- Broadcast when NPCs need new owners
		NPCJumpTriggered = Knit.CreateSignal(), -- Broadcast when NPC should jump (for testing/manual control)
	},

	-- Registry of all active NPCs (traditional server-physics NPCs)
	ActiveNPCs = {}, -- [npcModel] = npcData

	-- Registry for client-physics NPCs (UseAnimationController = true)
	ActiveClientPhysicsNPCs = {}, -- [npcID] = npcData
})

---- Configuration
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

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
		- ClientRenderData: table? - Optional visual customization for client-side rendering
		- CustomData: table? - Game-specific attributes for gameplay logic
			* Scale: number? - Visual scale multiplier (default: 1.0)
			* Faction: string? - NPC faction/team identifier (e.g., "Ally") >> same team NPCs won't target each other
			* EnemyType: string? - Combat classification (e.g., "Ranged", "Melee")

		-- OPTIMIZATION (ADVANCED)
		- UseAnimationController: boolean? - Enable client-side physics (default: false)
			WARNING: This is an ADVANCED feature with the following implications:
				1. NO physics simulation on server
				2. Client handles ALL pathfinding and movement
				3. Client has position authority (no validation to prevent ping false positives)
				4. Only for non-critical NPCs (ambient, visual-only)
				5. Everything rendered on client-side
				6. Can handle 1000+ NPCs with smooth gameplay at all ping levels
			For implementation details, see: documentations/Unimplemented/UseAnimationController_Implementation/Main.md

		- EnableOptimizedHitbox: boolean? - (UNIMPLEMENTED) Enable client-side batch hitbox detection for high fire rate scenarios
			This enables batch detection for weapons/turrets with high fire rates, significantly reducing network traffic and server load.
			Particularly useful for tower defense games with many NPCs and rapid-fire turrets (recommended for 50+ NPCs with high fire rate weapons).
			For implementation details, see: documentations/Unimplemented/Optimized_Hitbox.md

	@return Model|string - The spawned NPC model (traditional) or NPC ID (UseAnimationController)
]]
function NPC_Service:SpawnNPC(config)
	-- Check if UseAnimationController is enabled (per-NPC or global)
	local useAnimController = config.UseAnimationController
	if useAnimController == nil then
		useAnimController = OptimizationConfig.UseAnimationController
	end

	if useAnimController then
		-- Use client-side physics approach (returns NPC ID, not model)
		return NPC_Service.Components.ClientPhysicsSpawner:SpawnNPC(config)
	else
		-- Use traditional server-side physics approach (returns model)
		return NPC_Service.Components.NPCSpawner:SpawnNPC(config)
	end
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

	@param npcModelOrID Model|string - The NPC model (traditional) or NPC ID (UseAnimationController)
]]
function NPC_Service:DestroyNPC(npcModelOrID)
	if typeof(npcModelOrID) == "string" then
		-- Client-physics NPC (UseAnimationController)
		if NPC_Service.Components.ClientPhysicsSpawner then
			NPC_Service.Components.ClientPhysicsSpawner:DestroyNPC(npcModelOrID)
		end
	else
		-- Traditional server-physics NPC
		NPC_Service.SetComponent:DestroyNPC(npcModelOrID)
	end
end

--[[
	Damage a client-physics NPC (UseAnimationController only)
	Health is server-authoritative for gameplay integrity.

	@param npcID string - The NPC ID
	@param damage number - Amount of damage to apply
]]
function NPC_Service:DamageClientPhysicsNPC(npcID, damage)
	if NPC_Service.Components.ClientPhysicsSpawner then
		NPC_Service.Components.ClientPhysicsSpawner:DamageNPC(npcID, damage)
	end
end

--[[
	Heal a client-physics NPC (UseAnimationController only)

	@param npcID string - The NPC ID
	@param amount number - Amount to heal
]]
function NPC_Service:HealClientPhysicsNPC(npcID, amount)
	if NPC_Service.Components.ClientPhysicsSpawner then
		NPC_Service.Components.ClientPhysicsSpawner:HealNPC(npcID, amount)
	end
end

--[[
	Get client-physics NPC data by ID

	@param npcID string - The NPC ID
	@return table? - NPC data or nil if not found
]]
function NPC_Service:GetClientPhysicsNPCData(npcID)
	if NPC_Service.Components.ClientPhysicsSpawner then
		return NPC_Service.Components.ClientPhysicsSpawner:GetNPCData(npcID)
	end
	return nil
end

--[[
	Trigger a jump for a client-physics NPC (UseAnimationController only)
	Broadcasts to all clients - the simulating client will execute the jump.

	@param npcID string - The NPC ID
]]
function NPC_Service:TriggerJump(npcID)
	-- Verify NPC exists
	if not NPC_Service.ActiveClientPhysicsNPCs[npcID] then
		warn("[NPC_Service] TriggerJump: NPC not found:", npcID)
		return
	end

	-- Broadcast to all clients - the one simulating this NPC will handle it
	NPC_Service.Client.NPCJumpTriggered:FireAll(npcID)
end

---- Client Methods for UseAnimationController ----

--[[
	Client method: Update NPC position (called by simulating client)
]]
function NPC_Service.Client:UpdateNPCPosition(player, npcID, position, orientation)
	if NPC_Service.Components.ClientPhysicsSync then
		NPC_Service.Components.ClientPhysicsSync.HandlePositionUpdate(player, npcID, position, orientation)
	end
end

--[[
	Client method: Claim ownership of an NPC
]]
function NPC_Service.Client:ClaimNPC(player, npcID)
	if NPC_Service.Components.ClientPhysicsSync then
		return NPC_Service.Components.ClientPhysicsSync.ClaimNPC(player, npcID)
	end
	return false
end

--[[
	Client method: Release ownership of an NPC
]]
function NPC_Service.Client:ReleaseNPC(player, npcID)
	if NPC_Service.Components.ClientPhysicsSync then
		NPC_Service.Components.ClientPhysicsSync.ReleaseNPC(player, npcID)
	end
end

function NPC_Service:KnitStart()
	-- Post-initialization logic can go here
end

function NPC_Service:KnitInit()

	---- Handle player disconnection for UseAnimationController system
	Players.PlayerRemoving:Connect(function(player)
		if NPC_Service.Components.ClientPhysicsSync then
			NPC_Service.Components.ClientPhysicsSync.HandlePlayerLeft(player)
		end
	end)
end

return NPC_Service
