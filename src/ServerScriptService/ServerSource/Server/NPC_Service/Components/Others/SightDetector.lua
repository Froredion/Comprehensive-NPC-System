local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SightDetector = {}

---- Knit Services
local NPC_Service
local SightVisualizer

---- Configuration
local DETECTION_INTERVAL_MIN = 1.0
local DETECTION_INTERVAL_MAX = 3.0
local DETECTION_INTERVAL_TARGETFOUND = 1.5
local DIRECTIONAL_CONE_ANGLE = 120 -- Total cone angle in degrees

--[[
	Check if target is within front-facing cone (Directional mode only)
	
	@param self table - NPC data
	@param targetPosition Vector3 - Target position to check
	@return boolean - True if target is in front cone
]]
local function isInFrontCone(self, targetPosition)
	local npcPos = self.Model.PrimaryPart.Position
	local npcLookVector = self.Model.PrimaryPart.CFrame.LookVector
	local directionToTarget = (targetPosition - npcPos).Unit

	local dotProduct = npcLookVector:Dot(directionToTarget)
	local angleThreshold = math.cos(math.rad(DIRECTIONAL_CONE_ANGLE / 2))

	return dotProduct >= angleThreshold
end

--[[
	Check line of sight to target using raycast
	
	@param self table - NPC data
	@param targetPosition Vector3 - Target position
	@param targetModel Model - Target model (for filtering)
	@return boolean - True if line of sight is clear
]]
local function hasLineOfSight(self, targetPosition, targetModel)
	local npcPos = self.Model.PrimaryPart.Position
	local direction = (targetPosition - npcPos).Unit
	local distance = (targetPosition - npcPos).Magnitude

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.Model, targetModel, workspace:FindFirstChild("Characters") }

	local rayResult = workspace:Raycast(npcPos, direction * distance, raycastParams)

	-- If no hit or hit the target itself, line of sight is clear
	return rayResult == nil or rayResult.Instance:IsDescendantOf(targetModel)
end

--[[
	Check if target is an ally (same faction or both have no faction)

	@param self table - NPC data
	@param targetNPCData table - Target NPC data
	@return boolean - True if target is an ally
]]
local function isAlly(self, targetNPCData)
	local selfFaction = self.CustomData and self.CustomData.Faction
	local targetFaction = targetNPCData.CustomData and targetNPCData.CustomData.Faction

	-- If both have factions, compare them
	if selfFaction and targetFaction then
		return selfFaction == targetFaction
	end

	-- If neither has a faction, treat as allies (NPCs without factions don't attack each other)
	if not selfFaction and not targetFaction then
		return true
	end

	-- One has faction, one doesn't - not allies
	return false
end

--[[
	Check if NPC can attack the target (respects CanAttackAllies setting)

	@param self table - NPC data
	@param targetNPCData table - Target NPC data
	@return boolean - True if can attack
]]
local function canAttackTarget(self, targetNPCData)
	-- Check if they're allies
	if isAlly(self, targetNPCData) then
		-- Only attack allies if CanAttackAllies is true
		return self.CanAttackAllies == true
	end

	-- Not allies, can attack
	return true
end

--[[
	Detect enemies in range
	
	@param self table - NPC data
]]
local function detectEnemies(self)
	local npcPos = self.Model.PrimaryPart.Position
	local detectedTargets = {}

	if self.SightRange == 0 then
		return detectedTargets
	end

	-- 1. Gather Players
	for _, player in pairs(Players:GetPlayers()) do
		local character = player.Character
		if
			character
			and character.PrimaryPart
			and character:FindFirstChild("Humanoid")
			and character.Humanoid.Health > 0
		then
			local targetPos = character.PrimaryPart.Position
			local distance = (targetPos - npcPos).Magnitude

			-- Filter by distance
			if distance <= self.SightRange then
				-- IF Directional mode: Filter by angle
				if self.SightMode == "Directional" then
					if not isInFrontCone(self, targetPos) then
						continue
					end
				end

				-- Check line of sight
				if hasLineOfSight(self, targetPos, character) then
					table.insert(detectedTargets, {
						Model = character,
						Distance = distance,
						Type = "Player",
					})
				end
			end
		end
	end

	-- 2. Gather NPCs
	local npcsFolder = workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild("NPCs")
	if npcsFolder then
		for _, npc in pairs(npcsFolder:GetChildren()) do
			if npc ~= self.Model and npc.PrimaryPart and npc:FindFirstChild("Humanoid") and npc.Humanoid.Health > 0 then
				local targetNPCData = NPC_Service.ActiveNPCs[npc]

				-- Skip if we can't attack this target
				if targetNPCData and not canAttackTarget(self, targetNPCData) then
					continue
				end

				local targetPos = npc.PrimaryPart.Position
				local distance = (targetPos - npcPos).Magnitude

				-- Filter by distance
				if distance <= self.SightRange then
					-- IF Directional mode: Filter by angle
					if self.SightMode == "Directional" then
						if not isInFrontCone(self, targetPos) then
							continue
						end
					end

					-- Check line of sight
					if hasLineOfSight(self, targetPos, npc) then
						table.insert(detectedTargets, {
							Model = npc,
							Distance = distance,
							Type = "NPC",
						})
					end
				end
			end
		end
	end

	-- 3. Prioritize by proximity ONLY (nearest first)
	table.sort(detectedTargets, function(a, b)
		return a.Distance < b.Distance
	end)

	-- 4. Set best target
	if #detectedTargets > 0 then
		self.CurrentTarget = detectedTargets[1].Model
		self.TargetInSight = true
		self.LastSeenTarget = tick()
	else
		self.CurrentTarget = nil
		self.TargetInSight = false
	end

	-- 5. Update visualization
	if SightVisualizer and SightVisualizer:IsEnabled() then
		SightVisualizer:UpdateVisualization(self, detectedTargets, DIRECTIONAL_CONE_ANGLE)
	end

	return detectedTargets
end

--[[
	Randomize detection interval to prevent synchronized detection
	
	@param hasTarget boolean - Whether NPC currently has a target
	@return number - Detection interval
]]
local function randomizeDetectionInterval(hasTarget)
	if hasTarget then
		return DETECTION_INTERVAL_TARGETFOUND
	else
		return math.random() * (DETECTION_INTERVAL_MAX - DETECTION_INTERVAL_MIN) + DETECTION_INTERVAL_MIN
	end
end

--[[
	Main sight detection thread
	
	@param self table - NPC data
]]
local function sightDetectionThread(self)
	while not self.CleanedUp do
		-- Detect enemies
		detectEnemies(self)

		-- Wait with randomized interval
		local interval = randomizeDetectionInterval(self.CurrentTarget ~= nil)
		task.wait(interval)
	end
end

--[[
	Setup sight detector for NPC
	
	@param self table - NPC data
]]
function SightDetector:SetupSightDetector(self)
	-- Start detection thread
	local detectionThread = task.spawn(sightDetectionThread, self)
	table.insert(self.TaskThreads, detectionThread)
end

--[[
	Cleanup sight detector for NPC
	
	@param self table - NPC data
]]
function SightDetector:CleanupSightDetector(self)
	-- Cleanup visualizations
	if SightVisualizer then
		SightVisualizer:Cleanup(self.Model)
	end
end

function SightDetector.Start()
	-- Component start logic
end

function SightDetector.Init()
	NPC_Service = Knit.GetService("NPC_Service")

	-- Get SightVisualizer component
	local success, visualizer = pcall(function()
		return require(script.Parent.SightVisualizer)
	end)

	if success then
		SightVisualizer = visualizer
	else
		warn("[SightDetector] Failed to load SightVisualizer:", visualizer)
	end
end

return SightDetector
