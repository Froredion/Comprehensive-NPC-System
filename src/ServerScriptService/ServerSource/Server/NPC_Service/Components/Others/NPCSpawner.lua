local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NPCSpawner = {}

---- Knit Services
local NPC_Service

---- Client Configuration
local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.RenderConfig)

---- Configuration
local CLEANUP_DELAY = 5
local DISABLED_STATES = {
	Enum.HumanoidStateType.Climbing,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Flying,
	Enum.HumanoidStateType.PlatformStanding,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.Seated,
	Enum.HumanoidStateType.Swimming,
	Enum.HumanoidStateType.Dead,
}

--[[
	Find ground position using raycast

	@param position Vector3 - Starting position
	@param spawnerPart BasePart? - Optional spawner part to exclude from raycast
	@return Vector3? - Ground position or nil if not found
]]
local function findGroundPosition(position, spawnerPart)
	-- Step 1: Raise position by 2 studs
	local startPos = position + Vector3.new(0, 2, 0)

	-- Step 2: Raycast downward to find ground
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		workspace:FindFirstChild("Characters") or workspace,
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}

	-- Add spawner part to filter if provided
	if spawnerPart then
		raycastParams:AddToFilter(spawnerPart)
	end

	-- Loop to skip non-collidable parts (max 5 iterations)
	local currentStart = startPos
	for _ = 1, 5 do
		local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -1000, 0), raycastParams)

		if not rayResult then
			break -- No hit, use fallback
		end

		if rayResult.Instance.CanCollide then
			return rayResult.Position
		end

		-- Skip this part and continue from just below it
		raycastParams:AddToFilter(rayResult.Instance)
		currentStart = rayResult.Position + Vector3.new(0, -0.1, 0)
	end

	-- Fallback to original position if no ground found
	return position
end

--[[
	Create minimal NPC model (HumanoidRootPart + Humanoid only)
	
	@param config table - NPC configuration
	@return Model - Minimal NPC model
]]
local function createMinimalNPC(config)
	local npcModel = Instance.new("Model")
	npcModel.Name = config.Name

	-- Clone HumanoidRootPart from original model
	local originalModel = config.ModelPath
	local originalHRP = originalModel:FindFirstChild("HumanoidRootPart")
	if not originalHRP then
		warn("[NPCSpawner] Original model missing HumanoidRootPart:", originalModel.Name)
		return nil
	end

	npcModel:ScaleTo(originalModel:GetScale())

	local hrp = originalHRP:Clone()
	hrp.Parent = npcModel

	-- Clone Humanoid
	local originalHumanoid = originalModel:FindFirstChild("Humanoid")
	if not originalHumanoid then
		warn("[NPCSpawner] Original model missing Humanoid:", originalModel.Name)
		return nil
	end

	local humanoid = originalHumanoid:Clone()
	humanoid.MaxHealth = config.MaxHealth or 100
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = config.WalkSpeed or 16
	humanoid.JumpPower = config.JumpPower or 50

	-- Store original HipHeight before parenting
	local originalHipHeight = originalHumanoid.HipHeight
	-- Get the original model's scale to normalize the HipHeight
	local originalModelScale = originalModel:GetScale()

	humanoid.Parent = npcModel

	-- Set PrimaryPart
	npcModel.PrimaryPart = hrp

	-- Apply scale if specified in CustomData
	local scale = npcModel:GetScale()
	if config.CustomData and config.CustomData.Scale then
		local desiredScale = config.CustomData.Scale
		-- Only apply scale if it's different from current scale
		-- Consider small floating point differences when comparing scale values
		if math.abs(desiredScale - scale) > 0.01 then
			npcModel:ScaleTo(desiredScale)
			scale = desiredScale
		end
	end

	-- Set HipHeight AFTER parenting (Roblox resets it to 0 when parenting to minimal models)
	-- Normalize the original HipHeight by dividing by original scale, then multiply by new scale
	-- This accounts for cases where the original model was already scaled
	humanoid.HipHeight = (originalHipHeight / originalModelScale) * scale

	-- Enforce HipHeight stays correct (prevent Roblox from resetting it)
	local scaledHipHeight = (originalHipHeight / originalModelScale) * scale
	humanoid:GetPropertyChangedSignal("HipHeight"):Connect(function()
		if humanoid.HipHeight ~= scaledHipHeight then
			humanoid.HipHeight = scaledHipHeight
		end
	end)

	-- Find ground position (pass spawner part to exclude from raycast)
	local groundPos = findGroundPosition(config.Position, config.SpawnerPart)

	-- Adjust for HipHeight and HumanoidRootPart size (use scaled values)
	-- Use the correctly scaled HipHeight that accounts for the original model's scale
	local hipHeight = (originalHumanoid.HipHeight / originalModelScale) * scale
	local hrpSize = hrp.Size
	local finalY = groundPos.Y + (hrpSize.Y / 2) + hipHeight

	-- Set final position with optional rotation
	local positionCFrame = CFrame.new(groundPos.X, finalY, groundPos.Z)
	if config.Rotation then
		-- Apply rotation to the position CFrame
		hrp.CFrame = positionCFrame * config.Rotation
	else
		hrp.CFrame = positionCFrame
	end

	-- Set flexible client render data (developer-defined)
	if config.ClientRenderData then
		local jsonData = HttpService:JSONEncode(config.ClientRenderData)
		npcModel:SetAttribute("NPC_ClientRenderData", jsonData)
	end

	-- Set custom data (also sent to client for Scale and other attributes)
	if config.CustomData then
		local jsonData = HttpService:JSONEncode(config.CustomData)
		npcModel:SetAttribute("NPC_CustomData", jsonData)
	end

	-- Store reference to original model for client rendering
	npcModel:SetAttribute("NPC_ModelPath", config.ModelPath:GetFullName())

	return npcModel
end

--[[
	Create full NPC model (entire model cloned from original)
	Used when client rendering is disabled
	
	@param config table - NPC configuration
	@return Model - Full NPC model
]]
local function createFullNPC(config)
	local originalModel = config.ModelPath

	-- Clone the entire model
	local npcModel = originalModel:Clone()
	npcModel.Name = config.Name

	-- Get humanoid and HumanoidRootPart
	local humanoid = npcModel:FindFirstChild("Humanoid")
	local hrp = npcModel:FindFirstChild("HumanoidRootPart")

	if not humanoid or not hrp then
		warn("[NPCSpawner] Model missing Humanoid or HumanoidRootPart:", npcModel.Name)
		return nil
	end

	-- Apply config to humanoid
	humanoid.MaxHealth = config.MaxHealth or 100
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = config.WalkSpeed or 16
	humanoid.JumpPower = config.JumpPower or 50

	-- Apply scale if specified in CustomData
	local scale = npcModel:GetScale()
	if config.CustomData and config.CustomData.Scale then
		local desiredScale = config.CustomData.Scale
		-- Only apply scale if it's different from current scale
		-- Only scale if the scale difference is significant (account for small floating-point variations)
		if math.abs(desiredScale - scale) > 0.01 then
			npcModel:ScaleTo(desiredScale)
			scale = desiredScale
		end
	end

	-- Find ground position (pass spawner part to exclude from raycast)
	local groundPos = findGroundPosition(config.Position, config.SpawnerPart)

	-- Adjust for HipHeight and HumanoidRootPart size (scaled)
	-- After ScaleTo, the HipHeight is already at the correctly scaled value
	local hipHeight = humanoid.HipHeight
	local hrpSize = hrp.Size
	local finalY = groundPos.Y + (hrpSize.Y / 2) + hipHeight

	-- Set final position with optional rotation
	local positionCFrame = CFrame.new(groundPos.X, finalY, groundPos.Z)
	if config.Rotation then
		-- Apply rotation to the position CFrame
		hrp.CFrame = positionCFrame * config.Rotation
	else
		hrp.CFrame = positionCFrame
	end

	return npcModel
end

--[[
	Disable unnecessary humanoid states
	
	@param humanoid Humanoid - The humanoid to configure
]]
local function disableUnnecessaryHumanoidStates(humanoid)
	for _, state in pairs(DISABLED_STATES) do
		humanoid:SetStateEnabled(state, false)
	end

	humanoid.BreakJointsOnDeath = false
end

--[[
	Setup cleanup handlers for NPC
	
	@param npcModel Model - The NPC model
	@param npcData table - NPC instance data
]]
local function setupCleanup(npcModel, npcData)
	local markedForDeletion = false

	local function cleanupNPC()
		if markedForDeletion then
			return
		end
		markedForDeletion = true

		-- Delegate cleanup to Set component
		task.delay(CLEANUP_DELAY, function()
			if NPC_Service and NPC_Service.SetComponent then
				NPC_Service.SetComponent:DestroyNPC(npcModel)
			end
		end)
	end

	-- Cleanup on death
	local healthConnection = npcModel.Humanoid.HealthChanged:Connect(function()
		if npcModel.Humanoid.Health <= 0 then
			cleanupNPC()
		end
	end)
	table.insert(npcData.Connections, healthConnection)

	-- Cleanup on removal
	local ancestryConnection = npcModel.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupNPC()
		end
	end)
	table.insert(npcData.Connections, ancestryConnection)
end

--[[
	Initialize NPC instance data structure
	
	@param npcModel Model - The NPC model
	@param config table - NPC configuration
	@return table - NPC instance data
]]
local function initializeNPCData(npcModel, config)
	local npcData = {
		Model = npcModel,
		ID = HttpService:GenerateGUID(false),

		-- Movement State
		CanWalk = config.CanWalk ~= false, -- Default true
		WalkSpeed = config.WalkSpeed or 16, -- Store configured walk speed
		Pathfinding = nil,
		Destination = nil,
		MovementState = nil,
		SpawnPosition = npcModel.PrimaryPart.Position,
		MovementMode = config.MovementMode or "Ranged",
		MeleeOffsetRange = config.MeleeOffsetRange or 5,
		UsePathfinding = config.UsePathfinding ~= false, -- Default true
		EnableIdleWander = config.EnableIdleWander ~= false, -- Default true
		EnableCombatMovement = config.EnableCombatMovement ~= false, -- Default true

		-- Targeting State
		CurrentTarget = nil,
		TargetInSight = false,
		LastSeenTarget = 0,
		SightRange = config.SightRange or 200,
		SightMode = config.SightMode or "Directional",

		-- Custom Data
		CustomData = config.CustomData or {},

		-- Lifecycle
		TaskThreads = {},
		Connections = {},
		CleanedUp = false,
	}

	return npcData
end

--[[
	Spawn NPC with flexible configuration
	
	@param config table - NPC configuration
	@return Model - Spawned NPC model
]]
function NPCSpawner:SpawnNPC(config)
	-- Validate required fields
	if not config.Name then
		error("[NPCSpawner] Name is required")
	end
	if not config.Position and not config.SpawnerPart then
		error("[NPCSpawner] Position or SpawnerPart is required")
	end
	if not config.ModelPath or not config.ModelPath:IsA("Model") then
		error("[NPCSpawner] ModelPath must be a Model instance")
	end

	-- Handle SpawnerPart: extract position and disable collision properties
	if config.SpawnerPart and config.SpawnerPart:IsA("BasePart") then
		config.Position = config.SpawnerPart.Position
		-- Disable collision properties to prevent raycast interference
		config.SpawnerPart.CanCollide = false
		config.SpawnerPart.CanQuery = false
		config.SpawnerPart.CanTouch = false
	end

	-- Create NPC based on RenderConfig
	local npcModel
	if RenderConfig.ENABLED then
		-- Client-side rendering enabled: use minimal NPC (HumanoidRootPart + Humanoid only)
		npcModel = createMinimalNPC(config)
	else
		-- Client-side rendering disabled: use full NPC model
		npcModel = createFullNPC(config)
	end

	if not npcModel then
		error("[NPCSpawner] Failed to create NPC model")
	end

	-- Configure humanoid states
	disableUnnecessaryHumanoidStates(npcModel.Humanoid)

	-- Initialize NPC data
	local npcData = initializeNPCData(npcModel, config)

	-- Register NPC
	NPC_Service.ActiveNPCs[npcModel] = npcData

	-- Setup cleanup
	setupCleanup(npcModel, npcData)

	-- Parent to workspace (make visible)
	local charactersFolder = workspace:FindFirstChild("Characters")
	if not charactersFolder then
		charactersFolder = Instance.new("Folder")
		charactersFolder.Name = "Characters"
		charactersFolder.Parent = workspace
	end

	local npcsFolder = charactersFolder:FindFirstChild("NPCs")
	if not npcsFolder then
		npcsFolder = Instance.new("Folder")
		npcsFolder.Name = "NPCs"
		npcsFolder.Parent = charactersFolder
	end

	npcModel.Parent = npcsFolder

	-- Set network ownership to server (must be done after parenting to workspace)
	npcModel.PrimaryPart:SetNetworkOwner(nil)

	-- Initialize behaviors (Movement and Sight)
	task.defer(function()
		-- Only setup movement if CanWalk is enabled
		if npcData.CanWalk and NPC_Service.Components.MovementBehavior then
			NPC_Service.Components.MovementBehavior.SetupMovementBehavior(npcData)
		end

		if NPC_Service.Components.SightDetector then
			NPC_Service.Components.SightDetector:SetupSightDetector(npcData)
		end
	end)

	return npcModel
end

function NPCSpawner.Start()
	-- Component start logic
end

function NPCSpawner.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return NPCSpawner
