--[[
	ClientSightDetector - Client-side sight detection for UseAnimationController NPCs

	Handles:
	- Enemy detection within sight range
	- Line of sight raycasting
	- Directional cone filtering (if SightMode is "Directional")
	- Target prioritization by distance

	Adapted from server-side SightDetector for client simulation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ClientSightDetector = {}

---- Dependencies
local ClientSightVisualizer

---- Configuration
local DETECTION_INTERVAL_MIN = 1.0
local DETECTION_INTERVAL_MAX = 3.0
local DETECTION_INTERVAL_TARGETFOUND = 1.5
local DIRECTIONAL_CONE_ANGLE = 120 -- Total cone angle in degrees

---- State
local DetectionThreads = {} -- [npcID] = thread

--[[
	Check if target is within front-facing cone (Directional mode only)

	@param npcData table - NPC simulation data
	@param targetPosition Vector3 - Target position to check
	@return boolean - True if target is in front cone
]]
local function isInFrontCone(npcData, targetPosition)
	local npcPos = npcData.Position
	local npcLookVector = npcData.Orientation and npcData.Orientation.LookVector or Vector3.new(0, 0, -1)
	local directionToTarget = (targetPosition - npcPos).Unit

	local dotProduct = npcLookVector:Dot(directionToTarget)
	local angleThreshold = math.cos(math.rad(DIRECTIONAL_CONE_ANGLE / 2))

	return dotProduct >= angleThreshold
end

--[[
	Check line of sight to target using raycast

	@param npcData table - NPC simulation data
	@param targetPosition Vector3 - Target position
	@param targetModel Model - Target model (for filtering)
	@return boolean - True if line of sight is clear
]]
local function hasLineOfSight(npcData, targetPosition, targetModel)
	local npcPos = npcData.Position
	local direction = (targetPosition - npcPos).Unit
	local distance = (targetPosition - npcPos).Magnitude

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	-- Build filter list
	local filterList = { targetModel, workspace:FindFirstChild("Characters") }
	if npcData.VisualModel then
		table.insert(filterList, npcData.VisualModel)
	end
	raycastParams.FilterDescendantsInstances = filterList

	local rayResult = workspace:Raycast(npcPos, direction * distance, raycastParams)

	-- If no hit or hit the target itself, line of sight is clear
	return rayResult == nil or rayResult.Instance:IsDescendantOf(targetModel)
end

--[[
	Check if target NPC is an ally (same faction or both have no faction)

	@param npcData table - NPC simulation data
	@param targetNPCConfig table - Target NPC's config data
	@return boolean - True if target is an ally
]]
local function isAlly(npcData, targetNPCConfig)
	-- Check faction in config's CustomData
	local selfFaction = npcData.Config and npcData.Config.CustomData and npcData.Config.CustomData.Faction
	local targetFaction = targetNPCConfig and targetNPCConfig.CustomData and targetNPCConfig.CustomData.Faction

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

	@param npcData table - NPC simulation data
	@param targetNPCConfig table? - Target NPC's config data (may be nil if lookup failed)
	@return boolean - True if can attack
]]
local function canAttackTarget(npcData, targetNPCConfig)
	-- If we couldn't get target's config, treat as ally (safe default - don't attack unknown NPCs)
	if not targetNPCConfig then
		local canAttackAllies = npcData.Config and npcData.Config.CanAttackAllies
		return canAttackAllies == true
	end

	-- Check if they're allies
	if isAlly(npcData, targetNPCConfig) then
		-- Only attack allies if CanAttackAllies is true
		local canAttackAllies = npcData.Config and npcData.Config.CanAttackAllies
		return canAttackAllies == true
	end

	-- Not allies, can attack
	return true
end

--[[
	Get NPC config from ActiveNPCs folder

	@param npcModel Model - The NPC model in workspace
	@return table? - Parsed config or nil
]]
local function getNPCConfigFromFolder(npcModel)
	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not activeNPCsFolder then
		return nil
	end

	-- Try multiple ways to find the NPC folder
	local npcFolder = nil

	-- 1. Try by model name
	npcFolder = activeNPCsFolder:FindFirstChild(npcModel.Name)

	-- 2. Try by NPCID attribute if exists
	if not npcFolder then
		local npcID = npcModel:GetAttribute("NPCID")
		if npcID then
			npcFolder = activeNPCsFolder:FindFirstChild(npcID)
		end
	end

	-- 3. Search through all folders to find matching model name in config
	if not npcFolder then
		for _, folder in pairs(activeNPCsFolder:GetChildren()) do
			local configValue = folder:FindFirstChild("Config")
			if configValue then
				local success, config = pcall(function()
					return game:GetService("HttpService"):JSONDecode(configValue.Value)
				end)
				if success and config and config.Name == npcModel.Name then
					npcFolder = folder
					break
				end
			end
		end
	end

	if not npcFolder then
		return nil
	end

	local configValue = npcFolder:FindFirstChild("Config")
	if not configValue then
		return nil
	end

	local success, config = pcall(function()
		return game:GetService("HttpService"):JSONDecode(configValue.Value)
	end)

	return success and config or nil
end

--[[
	Detect enemies in range

	@param npcData table - NPC simulation data
	@return table - List of detected targets
]]
local function detectEnemies(npcData)
	local npcPos = npcData.Position
	local detectedTargets = {}

	local sightRange = npcData.Config.SightRange or 200
	local sightMode = npcData.Config.SightMode or "Omnidirectional"

	if sightRange == 0 then
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
			if distance <= sightRange then
				-- IF Directional mode: Filter by angle
				if sightMode == "Directional" then
					if not isInFrontCone(npcData, targetPos) then
						continue
					end
				end

				-- Check line of sight
				if hasLineOfSight(npcData, targetPos, character) then
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
			-- Skip self (check against visual model)
			if npcData.VisualModel and npc == npcData.VisualModel then
				continue
			end

			if npc.PrimaryPart and npc:FindFirstChild("Humanoid") and npc.Humanoid.Health > 0 then
				-- Get target NPC's config to check faction
				local targetNPCConfig = getNPCConfigFromFolder(npc)

				-- Skip if we can't attack this target
				if not canAttackTarget(npcData, targetNPCConfig) then
					continue
				end

				local targetPos = npc.PrimaryPart.Position
				local distance = (targetPos - npcPos).Magnitude

				-- Filter by distance
				if distance <= sightRange then
					-- IF Directional mode: Filter by angle
					if sightMode == "Directional" then
						if not isInFrontCone(npcData, targetPos) then
							continue
						end
					end

					-- Check line of sight
					if hasLineOfSight(npcData, targetPos, npc) then
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

	-- 3. Prioritize by proximity (nearest first)
	table.sort(detectedTargets, function(a, b)
		return a.Distance < b.Distance
	end)

	-- 4. Set best target
	if #detectedTargets > 0 then
		npcData.CurrentTarget = detectedTargets[1].Model
		npcData.TargetInSight = true
		npcData.LastSeenTarget = tick()
	else
		npcData.CurrentTarget = nil
		npcData.TargetInSight = false
	end

	-- 5. Update visualization
	if ClientSightVisualizer and ClientSightVisualizer:IsEnabled() then
		ClientSightVisualizer:UpdateVisualization(npcData, detectedTargets, DIRECTIONAL_CONE_ANGLE)
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

	@param npcData table - NPC simulation data
]]
local function sightDetectionThread(npcData)
	-- Initial yield to let other initialization complete
	task.wait()

	while npcData.IsAlive and not npcData.CleanedUp do
		-- Detect enemies (wrapped in pcall for safety)
		local success, err = pcall(function()
			detectEnemies(npcData)
		end)

		if not success then
			warn("[ClientSightDetector] Error in detectEnemies:", err)
		end

		-- Wait with randomized interval
		local interval = randomizeDetectionInterval(npcData.CurrentTarget ~= nil)
		task.wait(interval)
	end
end

--[[
	Setup sight detector for NPC

	@param npcData table - NPC simulation data
]]
function ClientSightDetector.SetupSightDetector(npcData)
	local npcID = npcData.ID

	-- Don't create duplicate threads
	if DetectionThreads[npcID] then
		return
	end

	-- Start detection thread
	local thread = task.spawn(sightDetectionThread, npcData)
	DetectionThreads[npcID] = thread
end

--[[
	Cleanup sight detector for NPC

	@param npcData table - NPC simulation data
]]
function ClientSightDetector.CleanupSightDetector(npcData)
	local npcID = npcData.ID

	-- Mark as cleaned up to stop thread
	npcData.CleanedUp = true

	-- Cancel thread if exists
	local thread = DetectionThreads[npcID]
	if thread then
		task.cancel(thread)
		DetectionThreads[npcID] = nil
	end

	-- Cleanup visualizations
	if ClientSightVisualizer then
		ClientSightVisualizer:Cleanup(npcData)
	end

	-- Clear target state
	npcData.CurrentTarget = nil
	npcData.TargetInSight = false
end

--[[
	Force an immediate detection check (useful for events)

	@param npcData table - NPC simulation data
	@return table - Detected targets
]]
function ClientSightDetector.ForceDetection(npcData)
	return detectEnemies(npcData)
end

--[[
	Check if NPC has active sight detection

	@param npcID string - NPC identifier
	@return boolean
]]
function ClientSightDetector.IsActive(npcID)
	return DetectionThreads[npcID] ~= nil
end

function ClientSightDetector.Start()
	-- Component start logic
end

function ClientSightDetector.Init()
	-- Load visualizer component
	local success, visualizer = pcall(function()
		return require(script.Parent.ClientSightVisualizer)
	end)

	if success then
		ClientSightVisualizer = visualizer
	else
		warn("[ClientSightDetector] Failed to load ClientSightVisualizer:", visualizer)
	end
end

return ClientSightDetector
