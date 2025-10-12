local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NPCSpawner = {}

---- Knit Services
local NPC_Service

---- Client Configuration
local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.RenderConfig)

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
	@return Vector3? - Ground position or nil if not found
]]
local function findGroundPosition(position)
	-- Step 1: Raise position by 2 studs
	local startPos = position + Vector3.new(0, 2, 0)

	-- Step 2: Raycast downward to find ground
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { workspace:FindFirstChild("Characters") or workspace }

	local rayResult = workspace:Raycast(startPos, Vector3.new(0, -1000, 0), raycastParams)

	if rayResult then
		return rayResult.Position
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
	humanoid.HipHeight = originalHumanoid.HipHeight -- Preserve original HipHeight
	humanoid.Parent = npcModel

	-- Set PrimaryPart
	npcModel.PrimaryPart = hrp

	-- Find ground position
	local groundPos = findGroundPosition(config.Position)

	-- Adjust for HipHeight and HumanoidRootPart size (use original humanoid's HipHeight)
	local hipHeight = originalHumanoid.HipHeight
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

	-- Find ground position
	local groundPos = findGroundPosition(config.Position)

	-- Adjust for HipHeight and HumanoidRootPart size
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
	if not config.Position then
		error("[NPCSpawner] Position is required")
	end
	if not config.ModelPath or not config.ModelPath:IsA("Model") then
		error("[NPCSpawner] ModelPath must be a Model instance")
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

	print("[NPCSpawner] Spawned NPC:", npcModel.Name, "at", npcModel.PrimaryPart.Position)

	return npcModel
end

function NPCSpawner.Start()
	-- Component start logic
end

function NPCSpawner.Init()
	NPC_Service = Knit.GetService("NPC_Service")
end

return NPCSpawner
