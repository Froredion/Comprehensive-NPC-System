local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local CombatBehavior = {}

---- Knit Services
local NPC_Service
local DamageService
local CombatService

---- Shared Settings
local PunchSettings
local KnockbackHandler

---- ClientCast
local ClientCast

---- Default Constants
local DEFAULT_DAMAGE = 2
local DEFAULT_COOLDOWN = 3.0
local DEFAULT_INITIAL_COOLDOWN = 3.0
local DEFAULT_RANGE = 6
local CHECK_INTERVAL = 0.3
local WIND_UP_DELAY = 0.6
local NPC_ATTACK_ANIM_SPEED = 0.4
local CLIENTCAST_SWING_DURATION = 0.7

--[[
	Check if target is same faction as NPC (defensive check)
	SightDetector already filters allies, but this prevents edge cases.

	@param npcData table - NPC instance data
	@param targetModel Model - Target model
	@return boolean - True if same faction
]]
local function isSameFaction(npcData, targetModel)
	local npcFaction = npcData.CustomData and npcData.CustomData.Faction

	-- Check if target is an NPC with faction data
	local targetNPCData = NPC_Service.ActiveNPCs[targetModel]
	if targetNPCData then
		local targetFaction = targetNPCData.CustomData and targetNPCData.CustomData.Faction
		if npcFaction and targetFaction then
			return npcFaction == targetFaction
		end
		-- Both no faction = allies (matches SightDetector logic)
		if not npcFaction and not targetFaction then
			return true
		end
		return false
	end

	-- Target is a player - players have no faction, so not same faction
	return false
end

--[[
	Play attack animation on NPC humanoid (server-side)

	@param npcHumanoid Humanoid - NPC's humanoid
	@param comboIndex number - Current combo index (1 or 2)
	@return AnimationTrack? - The playing animation track
]]
local function playAttackAnimation(npcHumanoid, comboIndex)
	local anims = PunchSettings and PunchSettings.AttackAnimations or {}
	if #anims == 0 then
		return nil
	end

	local animId = anims[comboIndex]
	local anim = Instance.new("Animation")
	anim.AnimationId = animId
	local track = npcHumanoid:LoadAnimation(anim)
	track:Play(0, 1, NPC_ATTACK_ANIM_SPEED)
	return track
end

--[[
	Play attack swing sound on NPC model

	@param npcModel Model - NPC model to parent sound to
	@param comboIndex number - Current combo index
]]
local function playAttackSound(npcModel, comboIndex)
	local attackSounds = PunchSettings and PunchSettings.AttackSounds or {}
	if #attackSounds == 0 then
		return
	end

	local soundId = attackSounds[math.min(comboIndex, #attackSounds)]
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Parent = npcModel
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
end

--[[
	Create a temporary DmgPoint attachment on the NPC's attacking hand.
	Combo 1 uses RightHand, combo 2 uses LeftHand.

	@param npcModel Model - NPC model
	@param comboIndex number - Current combo index (1 or 2)
	@return Attachment? - The created DmgPoint attachment, or nil
]]
local function createHandDmgPoint(npcModel, comboIndex)
	local handName = comboIndex == 1 and "RightHand" or "LeftHand"
	local hand = npcModel:FindFirstChild(handName, true)
	if not hand then
		-- Fallback: try R15 naming, then R6 naming
		hand = npcModel:FindFirstChild("RightHand", true) or npcModel:FindFirstChild("Right Arm", true)
	end
	if not hand or not hand:IsA("BasePart") then
		return nil
	end

	local dmgPoint = Instance.new("Attachment")
	dmgPoint.Name = "DmgPoint"
	dmgPoint.Parent = hand
	return dmgPoint
end

--[[
	Main melee attack thread
	Checks conditions every CHECK_INTERVAL and attacks when all pass.
	Plays animation + sound, waits wind-up delay, then applies damage + knockback + effects.

	@param npcData table - NPC instance data
]]
local function meleeAttackThread(npcData)
	local initialCooldown = npcData.InitialAttackCooldown or DEFAULT_INITIAL_COOLDOWN
	local lastAttackTime = tick() - (npcData.AttackCooldown or DEFAULT_COOLDOWN) + initialCooldown
	local comboIndex = 1
	local attackDamage = npcData.AttackDamage or DEFAULT_DAMAGE
	local attackCooldown = npcData.AttackCooldown or DEFAULT_COOLDOWN
	local attackRange = npcData.AttackRange or DEFAULT_RANGE
	local maxCombo = #(PunchSettings and PunchSettings.AttackAnimations or {})
	if maxCombo == 0 then maxCombo = 1 end

	while not npcData.CleanedUp do
		task.wait(CHECK_INTERVAL)

		-- Check NPC is alive
		local npcModel = npcData.Model
		if not npcModel or not npcModel.Parent then
			break
		end

		local npcHumanoid = npcModel:FindFirstChild("Humanoid")
		if not npcHumanoid or npcHumanoid.Health <= 0 then
			break
		end

		local npcHRP = npcModel.PrimaryPart
		if not npcHRP then
			break
		end

		-- Check target exists and is alive
		local target = npcData.CurrentTarget
		if not target or not target.Parent then
			continue
		end

		local targetHumanoid = target:FindFirstChild("Humanoid")
		if not targetHumanoid or targetHumanoid.Health <= 0 then
			continue
		end

		local targetHRP = target.PrimaryPart
		if not targetHRP then
			continue
		end

		-- Faction check (defensive)
		if isSameFaction(npcData, target) then
			continue
		end

		-- Range check
		local distance = (npcHRP.Position - targetHRP.Position).Magnitude
		if distance > attackRange then
			continue
		end

		-- Cooldown check
		local now = tick()
		if now - lastAttackTime < attackCooldown then
			continue
		end

		-- All checks passed — begin attack sequence
		lastAttackTime = now

		-- 1. Play slowed animation + swing sound immediately (wind-up)
		playAttackAnimation(npcHumanoid, comboIndex)
		playAttackSound(npcModel, comboIndex)

		-- 2. Create DmgPoint on attacking hand
		local dmgPoint = createHandDmgPoint(npcModel, comboIndex)

		-- Advance combo
		comboIndex = comboIndex % maxCombo + 1

		-- 3. Wait for wind-up delay
		task.wait(WIND_UP_DELAY)

		-- 4. Re-validate NPC is still alive after wind-up
		if npcData.CleanedUp then
			if dmgPoint then dmgPoint:Destroy() end
			break
		end
		if not npcModel.Parent then
			if dmgPoint then dmgPoint:Destroy() end
			break
		end
		if npcHumanoid.Health <= 0 then
			if dmgPoint then dmgPoint:Destroy() end
			break
		end

		-- 5. Create ClientCast caster on the hand (server raycasts, owner=nil)
		if not dmgPoint or not ClientCast then
			continue
		end

		local hand = dmgPoint.Parent
		local raycastParams = RaycastParams.new()
		raycastParams.FilterDescendantsInstances = {npcModel}
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude

		local caster = ClientCast.new(hand, raycastParams)

		-- 6. Track hits via HumanoidCollided with faction check
		local hitTargets = {}
		local targetSet = {}

		local hitConnection = caster.HumanoidCollided:Connect(function(raycastResult, targetHumanoid2)
			local targetCharacter = targetHumanoid2.Parent
			if targetCharacter and not targetSet[targetCharacter] then
				-- Faction check: skip allies
				if not isSameFaction(npcData, targetCharacter) then
					targetSet[targetCharacter] = true
					table.insert(hitTargets, targetCharacter)
				end
			end
		end)

		caster:Start()

		-- 7. Wait for swing duration (ClientCast detects hits during this window)
		task.wait(CLIENTCAST_SWING_DURATION)

		-- 8. Stop/destroy caster and cleanup attachment
		pcall(function()
			hitConnection:Disconnect()
		end)
		pcall(function()
			caster:Stop()
			caster:Destroy()
		end)
		if dmgPoint then
			dmgPoint:Destroy()
		end

		-- 9. Apply damage + knockback + effects to all hit targets
		for _, hitTarget in ipairs(hitTargets) do
			local hitHumanoid = hitTarget:FindFirstChild("Humanoid")
			if not hitHumanoid or hitHumanoid.Health <= 0 then
				continue
			end

			local damageInfo = {
				Damage = attackDamage,
				DamageType = "melee",
				TeamCheck = false,
			}

			local success = DamageService:ApplyDamage(npcModel, hitTarget, damageInfo)

			if success then
				KnockbackHandler:ApplyKnockback(hitTarget, npcHRP.Position)
				CombatService.Client.PlayPunchEffect:FireAll(hitTarget)
				CombatService.Client.PlayHitSound:FireAll(hitTarget)
			end
		end
	end
end

--[[
	Setup combat behavior for an NPC
	Only activates for Melee NPCs with EnableMeleeAttack enabled.

	@param npcData table - NPC instance data
]]
function CombatBehavior.SetupCombatBehavior(npcData)
	-- Only setup for melee NPCs with attacks enabled
	if npcData.MovementMode ~= "Melee" then
		return
	end

	if npcData.EnableMeleeAttack == false then
		return
	end

	-- Start attack thread
	local attackThread = task.spawn(meleeAttackThread, npcData)
	table.insert(npcData.TaskThreads, attackThread)
end

function CombatBehavior.Start()
	-- Component start logic
end

function CombatBehavior.Init()
	NPC_Service = Knit.GetService("NPC_Service")
	DamageService = Knit.GetService("DamageService")
	CombatService = Knit.GetService("CombatService")

	-- Load PunchSettings (same animations/sounds as player punches) — optional for vanilla NPCs
	local datas = ReplicatedStorage:WaitForChild("SharedSource"):WaitForChild("Datas", 10)
	if datas then
		local combat = datas:FindFirstChild("Combat")
		local punchModule = combat and combat:FindFirstChild("PunchSettings")
		if punchModule then
			PunchSettings = require(punchModule)
		end
	end

	-- Load KnockbackHandler from CombatService components (optional)
	KnockbackHandler = CombatService and CombatService.Components and CombatService.Components.KnockbackHandler

	-- Load ClientCast (optional)
	local utilities = ReplicatedStorage:WaitForChild("SharedSource"):WaitForChild("Utilities", 10)
	if utilities then
		local clientCastModule = utilities:FindFirstChild("ClientCast")
		if clientCastModule then ClientCast = require(clientCastModule) end
	end
end

return CombatBehavior
