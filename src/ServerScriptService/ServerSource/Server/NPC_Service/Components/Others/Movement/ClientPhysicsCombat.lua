--[[
	ClientPhysicsCombat - Server-side combat loop for UseClientPhysics NPCs

	Since UseClientPhysics NPCs have no server-side Model, the traditional
	CombatBehavior (which requires a Humanoid/HumanoidRootPart on server) cannot work.

	This component reads NPC position from the ReplicatedStorage data folder and
	applies damage directly to nearby player characters on the server.
	Attack animations are triggered via NPC_Service.Client.NPCAttackTriggered signal.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ClientPhysicsCombat = {}

---- Knit Services
local NPC_Service
local CombatService

---- Shared Settings
local PunchSettings
local SlashSettings
local KnockbackHandler
local CombatConfig

---- Constants
local CHECK_INTERVAL = 0.3 -- Same as CombatBehavior
local HIT_COOLDOWN = 0.3 -- Minimum seconds between player hits per NPC
local MAX_HIT_RANGE = 20 -- Maximum distance for player hit validation
local NPC_ATTACK_ANIM_SPEED = 0.4
local WIND_UP_DELAY = 0.6

---- State
local CombatThread = nil
-- Track last attack time per NPC: { [npcID] = lastAttackTime }
local LastAttackTimes = {}
-- Track combo index per NPC for animation variety
local ComboIndices = {}
-- Per-player hit cooldowns: { [player] = { [npcID] = lastHitTime } }
local PlayerHitCooldowns = {}

--[[
	Check if target player is same faction as NPC (skip allies)

	@param npcData table - NPC instance data
	@param playerCharacter Model - Player character model
	@return boolean - True if same faction (should skip)
]]
local function isSameFaction(npcData, playerCharacter)
	local npcFaction = npcData.Config and npcData.Config.CustomData and npcData.Config.CustomData.Faction
	-- Players have no faction, so if NPC has no faction either, treat as allies
	if not npcFaction then
		return true
	end
	-- Players are never same faction as "Enemy" NPCs
	return false
end

--[[
	Find the nearest alive player character within range of a position

	@param npcPosition Vector3 - NPC position
	@param attackRange number - Maximum attack distance
	@param npcData table - NPC data for faction checking
	@return Model?, number? - Nearest player character and distance, or nil
]]
local function findNearestTarget(npcPosition, attackRange, npcData)
	local nearestCharacter = nil
	local nearestDistance = attackRange + 1

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if not character then
			continue
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			continue
		end

		local hrp = character:FindFirstChild("HumanoidRootPart")
		if not hrp then
			continue
		end

		-- Faction check
		if isSameFaction(npcData, character) then
			continue
		end

		local distance = (hrp.Position - npcPosition).Magnitude
		if distance <= attackRange and distance < nearestDistance then
			nearestCharacter = character
			nearestDistance = distance
		end
	end

	return nearestCharacter, nearestDistance
end

--[[
	Main combat loop - checks all alive client-physics NPCs and attacks nearby players
]]
local function combatLoop()
	while true do
		task.wait(CHECK_INTERVAL)

		if not NPC_Service or not NPC_Service.ActiveClientPhysicsNPCs then
			continue
		end

		local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
		if not activeNPCsFolder then
			continue
		end

		for npcID, npcData in pairs(NPC_Service.ActiveClientPhysicsNPCs) do
			-- Skip dead or cleaned up NPCs
			if not npcData.IsAlive or npcData.CleanedUp then
				continue
			end

			-- Only attack for Melee NPCs with melee attack enabled
			local movementMode = npcData.Config and npcData.Config.MovementMode or "Ranged"
			if movementMode ~= "Melee" then
				continue
			end

			if npcData.EnableMeleeAttack == false then
				continue
			end

			-- Read NPC position from ReplicatedStorage data folder
			local npcFolder = activeNPCsFolder:FindFirstChild(npcID)
			if not npcFolder then
				continue
			end

			local positionValue = npcFolder:FindFirstChild("Position")
			if not positionValue then
				continue
			end

			local npcPosition = positionValue.Value
			local attackRange = npcData.AttackRange or 6
			local attackCooldown = npcData.AttackCooldown or 3.0
			local attackDamage = npcData.AttackDamage or 2

			-- Cooldown check
			local now = tick()
			local lastAttack = LastAttackTimes[npcID]
			if not lastAttack then
				-- First attack uses initial cooldown
				local initialCooldown = npcData.InitialAttackCooldown or 3.0
				LastAttackTimes[npcID] = now - attackCooldown + initialCooldown
				continue
			end

			if (now - lastAttack) < attackCooldown then
				continue
			end

			-- Find nearest target
			local target, distance = findNearestTarget(npcPosition, attackRange, npcData)
			if not target then
				continue
			end

			-- All checks passed - attack!
			LastAttackTimes[npcID] = now

			-- Get combo index
			local maxCombo = #(PunchSettings.AttackAnimations or {})
			if maxCombo == 0 then maxCombo = 1 end
			local comboIndex = ComboIndices[npcID] or 1

			-- Fire attack animation signal to all clients
			NPC_Service.Client.NPCAttackTriggered:FireAll(npcID, comboIndex, NPC_ATTACK_ANIM_SPEED)

			-- Advance combo
			ComboIndices[npcID] = comboIndex % maxCombo + 1

			-- Apply damage after wind-up delay (same as CombatBehavior)
			task.delay(WIND_UP_DELAY, function()
				-- Re-validate target is still alive after wind-up
				if not npcData.IsAlive or npcData.CleanedUp then
					return
				end

				local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
				if not targetHumanoid or targetHumanoid.Health <= 0 then
					return
				end

				local targetHRP = target:FindFirstChild("HumanoidRootPart")
				if not targetHRP then
					return
				end

				-- Re-check range after wind-up
				local postWindUpPos = positionValue.Value
				local postWindUpDistance = (targetHRP.Position - postWindUpPos).Magnitude
				if postWindUpDistance > attackRange then
					return
				end

				-- Apply damage directly (no DamageService since there's no server model)
				targetHumanoid:TakeDamage(attackDamage)

				-- Apply knockback
				if KnockbackHandler then
					local attackerPlayer = nil -- NPC attacker, not a player
					KnockbackHandler:ApplyKnockback(target, postWindUpPos, attackerPlayer)
				end

				-- Fire hit effects for all clients
				if CombatService then
					CombatService.Client.PlayPunchEffect:FireAll(target)
					CombatService.Client.PlayHitSound:FireAll(target)
				end
			end)
		end
	end
end

--[[
	Handle a player-reported hit on a UseClientPhysics NPC.
	Validates inputs, range, cooldown, then applies damage.

	@param player Player - The player who hit the NPC
	@param npcID string - The NPC ID (from ClientPhysicsNPCID attribute)
	@param damageType string - "punch" or "slash"
]]
function ClientPhysicsCombat.HandlePlayerHit(player, npcID, damageType)
	-- Validate inputs
	if type(npcID) ~= "string" or type(damageType) ~= "string" then
		return
	end

	-- Validate NPC exists and is alive
	local npcData = NPC_Service.ActiveClientPhysicsNPCs and NPC_Service.ActiveClientPhysicsNPCs[npcID]
	if not npcData or not npcData.IsAlive then
		return
	end

	-- Validate player character is alive
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Validate range - read NPC position from ReplicatedStorage data folder
	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not activeNPCsFolder then
		return
	end
	local npcFolder = activeNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end
	local positionValue = npcFolder:FindFirstChild("Position")
	local playerHRP = character:FindFirstChild("HumanoidRootPart")
	if positionValue and playerHRP then
		local distance = (positionValue.Value - playerHRP.Position).Magnitude
		if distance > MAX_HIT_RANGE then
			return
		end
	end

	-- Per-player cooldown to prevent spam
	if not PlayerHitCooldowns[player] then
		PlayerHitCooldowns[player] = {}
	end
	local now = tick()
	local lastHit = PlayerHitCooldowns[player][npcID]
	if lastHit and (now - lastHit) < HIT_COOLDOWN then
		return
	end
	PlayerHitCooldowns[player][npcID] = now

	-- Look up damage from damageType
	local damage
	if damageType == "punch" then
		damage = PunchSettings.DamagePerHit
	elseif damageType == "slash" then
		damage = SlashSettings.DamagePerHit
	else
		damage = 10 -- Default fallback
	end

	-- Apply damage via ClientPhysicsSpawner
	if NPC_Service.Components.ClientPhysicsSpawner then
		NPC_Service.Components.ClientPhysicsSpawner:DamageNPC(npcID, damage)
	end

	-- Fire hit sound and effect for all clients
	-- Use player's character as target since client-physics NPCs have no server model
	if CombatService and player.Character then
		CombatService.Client.PlayHitSound:FireAll(player.Character)
		CombatService.Client.PlayPunchEffect:FireExcept(player, player.Character)
	end

	-- Fire knockback signal to all clients
	if positionValue and playerHRP and CombatConfig then
		local direction = (positionValue.Value - playerHRP.Position)
		direction = Vector3.new(direction.X, 0, direction.Z) -- Horizontal only
		if direction.Magnitude > 0 then
			local knockbackVelocity = direction.Unit * CombatConfig.Knockback.BasePower
			NPC_Service.Client.NPCKnockbackTriggered:FireAll(npcID, knockbackVelocity)
		end
	end
end

--[[
	Clean up player-specific state when they leave.

	@param player Player - The player who left
]]
function ClientPhysicsCombat.HandlePlayerLeft(player)
	PlayerHitCooldowns[player] = nil
end

--[[
	Clean up tracking for a destroyed NPC.
	Called externally when NPC is removed.

	@param npcID string - The NPC ID
]]
function ClientPhysicsCombat.CleanupNPC(npcID)
	LastAttackTimes[npcID] = nil
	ComboIndices[npcID] = nil
end

function ClientPhysicsCombat.Start()
	-- Start the combat loop
	CombatThread = task.spawn(combatLoop)
end

function ClientPhysicsCombat.Init()
	NPC_Service = Knit.GetService("NPC_Service")
	CombatService = Knit.GetService("CombatService")

	-- Load combat settings
	local datas = ReplicatedStorage:WaitForChild("SharedSource"):WaitForChild("Datas", 10)
	local combatDatas = datas:WaitForChild("Combat", 10)
	PunchSettings = require(combatDatas:WaitForChild("PunchSettings", 10))
	SlashSettings = require(combatDatas:WaitForChild("SlashSettings", 10))

	-- Load KnockbackHandler from CombatService components
	KnockbackHandler = CombatService.Components.KnockbackHandler

	-- Load CombatConfig for knockback power values
	CombatConfig = require(combatDatas:WaitForChild("CombatConfig", 10))
end

return ClientPhysicsCombat
