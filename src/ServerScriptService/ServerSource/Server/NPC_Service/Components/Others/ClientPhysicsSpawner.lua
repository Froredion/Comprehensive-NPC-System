--[[
	ClientPhysicsSpawner - Spawner for client-physics NPCs (UseClientPhysics = true)

	This spawner creates data-only NPC representations in ReplicatedStorage.
	No physical model is created on the server - clients handle all physics and rendering.

	WARNING: This is an ADVANCED optimization feature.
	Only use for non-critical NPCs (ambient, visual-only).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ClientPhysicsSpawner = {}

---- Knit Services
local NPC_Service

---- Configuration
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

---- Storage
local ActiveNPCsFolder -- Created in Init

--[[
	Find ground position using raycast

	@param position Vector3 - Starting position
	@param spawnerPart BasePart? - Optional spawner part to exclude from raycast
	@return Vector3 - Ground position (or original if not found)
]]
local function findGroundPosition(position, spawnerPart)
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

	-- Cast from slightly above spawn position downward
	-- This prevents detecting objects far above (like airplanes/projectiles) as ground
	local currentStart = position + Vector3.new(0, 5, 0)

	-- Loop to skip non-collidable parts (max 5 iterations)
	for _ = 1, 5 do
		local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -50, 0), raycastParams)

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

	return position
end

--[[
	Get height offset from model for proper HumanoidRootPart positioning
	Uses formula: HipHeight + (RootPartHeight / 2)

	@param modelPath Model - The NPC model to get height from
	@return number - Height offset from ground
]]
local function getHeightOffsetFromModel(modelPath)
	if not modelPath or not modelPath:IsA("Model") then
		return 3 -- Fallback default
	end

	local humanoid = modelPath:FindFirstChildOfClass("Humanoid")
	local rootPart = modelPath:FindFirstChild("HumanoidRootPart")

	if humanoid and rootPart then
		local hipHeight = humanoid.HipHeight
		local rootPartHalfHeight = rootPart.Size.Y / 2
		return hipHeight + rootPartHalfHeight
	end

	-- Fallback: use default R15 values
	return 3
end

--[[
	Create NPC data folder in ReplicatedStorage

	@param npcID string - Unique NPC identifier
	@param config table - NPC configuration
	@param position Vector3 - Initial position
	@return Folder - The created NPC data folder
]]
local function createNPCDataFolder(npcID, config, position)
	local npcFolder = Instance.new("Folder")
	npcFolder.Name = npcID

	-- Position (Vector3Value)
	local positionValue = Instance.new("Vector3Value")
	positionValue.Name = "Position"
	positionValue.Value = position
	positionValue.Parent = npcFolder

	-- Orientation (CFrameValue) - optional
	local orientationValue = Instance.new("CFrameValue")
	orientationValue.Name = "Orientation"
	orientationValue.Value = config.Rotation or CFrame.new()
	orientationValue.Parent = npcFolder

	-- Health (NumberValue) - server authoritative
	local healthValue = Instance.new("NumberValue")
	healthValue.Name = "Health"
	healthValue.Value = config.MaxHealth or 100
	healthValue.Parent = npcFolder

	-- MaxHealth (NumberValue)
	local maxHealthValue = Instance.new("NumberValue")
	maxHealthValue.Name = "MaxHealth"
	maxHealthValue.Value = config.MaxHealth or 100
	maxHealthValue.Parent = npcFolder

	-- IsAlive (BoolValue)
	local isAliveValue = Instance.new("BoolValue")
	isAliveValue.Name = "IsAlive"
	isAliveValue.Value = true
	isAliveValue.Parent = npcFolder

	-- CurrentTarget (ObjectValue)
	local targetValue = Instance.new("ObjectValue")
	targetValue.Name = "CurrentTarget"
	targetValue.Value = nil
	targetValue.Parent = npcFolder

	-- Config (StringValue - JSON encoded)
	local configData = {
		Name = config.Name,
		ModelPath = config.ModelPath:GetFullName(),
		MaxHealth = config.MaxHealth or 100,
		WalkSpeed = config.WalkSpeed or 16,
		JumpPower = config.JumpPower or 50,
		SightRange = config.SightRange or 200,
		SightMode = config.SightMode or "Directional",
		CanWalk = config.CanWalk ~= false, -- Default true
		MovementMode = config.MovementMode or "Ranged",
		MeleeOffsetRange = config.MeleeOffsetRange or 5,
		EnableIdleWander = config.EnableIdleWander ~= false,
		EnableCombatMovement = config.EnableCombatMovement ~= false,
		SpawnPosition = { X = position.X, Y = position.Y, Z = position.Z },
		MaxWanderRadius = config.MaxWanderRadius or OptimizationConfig.ExploitMitigation.DEFAULT_MAX_WANDER_RADIUS,
		CustomData = config.CustomData or {},
		ClientRenderData = config.ClientRenderData or {},
	}

	local configValue = Instance.new("StringValue")
	configValue.Name = "Config"
	configValue.Value = HttpService:JSONEncode(configData)
	configValue.Parent = npcFolder

	-- SpawnTime (NumberValue)
	local spawnTimeValue = Instance.new("NumberValue")
	spawnTimeValue.Name = "SpawnTime"
	spawnTimeValue.Value = tick()
	spawnTimeValue.Parent = npcFolder

	return npcFolder
end

--[[
	Initialize NPC data structure for internal tracking

	@param npcID string - Unique NPC identifier
	@param config table - NPC configuration
	@param position Vector3 - Initial position
	@return table - NPC data structure
]]
local function initializeNPCData(npcID, config, position)
	local npcData = {
		-- Identity
		ID = npcID,
		Name = config.Name,

		-- Position (replicated from client)
		Position = position,
		Orientation = config.Rotation or CFrame.new(),

		-- State (server authority for health)
		IsAlive = true,
		Health = config.MaxHealth or 100,
		MaxHealth = config.MaxHealth or 100,
		CurrentTarget = nil,

		-- Configuration
		Config = {
			ModelPath = config.ModelPath,
			MaxHealth = config.MaxHealth or 100,
			WalkSpeed = config.WalkSpeed or 16,
			JumpPower = config.JumpPower or 50,
			SightRange = config.SightRange or 200,
			SightMode = config.SightMode or "Directional",
			MovementMode = config.MovementMode or "Ranged",
			MeleeOffsetRange = config.MeleeOffsetRange or 5,
			EnableIdleWander = config.EnableIdleWander ~= false,
			EnableCombatMovement = config.EnableCombatMovement ~= false,
			MaxWanderRadius = config.MaxWanderRadius or OptimizationConfig.ExploitMitigation.DEFAULT_MAX_WANDER_RADIUS,
			CustomData = config.CustomData or {},
			ClientRenderData = config.ClientRenderData or {},
		},

		-- Client Tracking
		OwningClient = nil,
		LastUpdateTime = tick(),

		-- Lifecycle
		SpawnTime = tick(),
		SpawnPosition = position,
		CleanedUp = false,

		-- Flag to identify client-physics NPCs
		UseClientPhysics = true,

		-- Connections for cleanup
		Connections = {},
	}

	return npcData
end

--[[
	Setup cleanup handlers for client-physics NPC

	@param npcID string - The NPC ID
	@param npcData table - NPC instance data
	@param npcFolder Folder - The data folder in ReplicatedStorage
]]
local function setupCleanup(npcID, npcData, npcFolder)
	-- Watch for health changes (death)
	local healthValue = npcFolder:FindFirstChild("Health")
	if healthValue then
		local healthConnection = healthValue.Changed:Connect(function(newHealth)
			npcData.Health = newHealth
			if newHealth <= 0 then
				npcData.IsAlive = false
				local isAliveValue = npcFolder:FindFirstChild("IsAlive")
				if isAliveValue then
					isAliveValue.Value = false
				end

				-- Cleanup after delay
				task.delay(5, function()
					ClientPhysicsSpawner:DestroyNPC(npcID)
				end)
			end
		end)
		table.insert(npcData.Connections, healthConnection)
	end
end

--[[
	Spawn a client-physics NPC (UseClientPhysics = true)

	This creates a data-only representation - no physical model on server.
	Clients handle all physics, pathfinding, and rendering.

	@param config table - NPC configuration (same format as regular SpawnNPC)
	@return string - NPC ID (not a model, since there is no server model)
]]
function ClientPhysicsSpawner:SpawnNPC(config)
	-- Validate required fields
	if not config.Name then
		error("[ClientPhysicsSpawner] Name is required")
	end
	if not config.Position and not config.SpawnerPart then
		error("[ClientPhysicsSpawner] Position or SpawnerPart is required")
	end
	if not config.ModelPath or not config.ModelPath:IsA("Model") then
		error("[ClientPhysicsSpawner] ModelPath must be a Model instance")
	end

	-- Handle SpawnerPart: extract position and disable collision properties
	local spawnPosition = config.Position
	if config.SpawnerPart and config.SpawnerPart:IsA("BasePart") then
		spawnPosition = config.SpawnerPart.Position
		-- Disable collision properties to prevent raycast interference
		config.SpawnerPart.CanCollide = false
		config.SpawnerPart.CanQuery = false
		config.SpawnerPart.CanTouch = false
	end

	-- Generate unique ID
	local npcID = HttpService:GenerateGUID(false)

	-- Find ground position (pass spawner part to exclude from raycast)
	local groundPos = findGroundPosition(spawnPosition, config.SpawnerPart)

	-- Calculate proper height offset from model
	local heightOffset = getHeightOffsetFromModel(config.ModelPath)

	-- Adjust Y for proper HumanoidRootPart height
	local finalPosition = Vector3.new(groundPos.X, groundPos.Y + heightOffset, groundPos.Z)

	-- Create data folder in ReplicatedStorage
	local npcFolder = createNPCDataFolder(npcID, config, finalPosition)
	npcFolder.Parent = ActiveNPCsFolder

	-- Initialize internal NPC data
	local npcData = initializeNPCData(npcID, config, finalPosition)

	-- Store in service registry using ID as key (not model)
	NPC_Service.ActiveClientPhysicsNPCs = NPC_Service.ActiveClientPhysicsNPCs or {}
	NPC_Service.ActiveClientPhysicsNPCs[npcID] = npcData

	-- Setup cleanup handlers
	setupCleanup(npcID, npcData, npcFolder)

	-- Notify ClientPhysicsSync about new NPC
	if NPC_Service.Components.ClientPhysicsSync then
		NPC_Service.Components.ClientPhysicsSync.OnNPCSpawned(npcID, npcData)
	end

	return npcID
end

--[[
	Get NPC data by ID

	@param npcID string - The NPC ID
	@return table? - NPC data or nil if not found
]]
function ClientPhysicsSpawner:GetNPCData(npcID)
	if NPC_Service.ActiveClientPhysicsNPCs then
		return NPC_Service.ActiveClientPhysicsNPCs[npcID]
	end
	return nil
end

--[[
	Apply damage to a client-physics NPC (server-authoritative)

	@param npcID string - The NPC ID
	@param damage number - Amount of damage to apply
]]
function ClientPhysicsSpawner:DamageNPC(npcID, damage)
	local npcData = self:GetNPCData(npcID)
	if not npcData or not npcData.IsAlive then
		return
	end

	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end

	local healthValue = npcFolder:FindFirstChild("Health")
	if healthValue then
		local newHealth = math.max(0, healthValue.Value - damage)
		healthValue.Value = newHealth
	end
end

--[[
	Heal a client-physics NPC (server-authoritative)

	@param npcID string - The NPC ID
	@param amount number - Amount to heal
]]
function ClientPhysicsSpawner:HealNPC(npcID, amount)
	local npcData = self:GetNPCData(npcID)
	if not npcData or not npcData.IsAlive then
		return
	end

	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end

	local healthValue = npcFolder:FindFirstChild("Health")
	local maxHealthValue = npcFolder:FindFirstChild("MaxHealth")
	if healthValue and maxHealthValue then
		local newHealth = math.min(maxHealthValue.Value, healthValue.Value + amount)
		healthValue.Value = newHealth
	end
end

--[[
	Destroy a client-physics NPC

	@param npcID string - The NPC ID
]]
function ClientPhysicsSpawner:DestroyNPC(npcID)
	local npcData = NPC_Service.ActiveClientPhysicsNPCs and NPC_Service.ActiveClientPhysicsNPCs[npcID]
	if not npcData then
		return
	end

	-- Mark as cleaned up
	npcData.CleanedUp = true

	-- Disconnect all connections
	for _, connection in pairs(npcData.Connections) do
		if typeof(connection) == "RBXScriptConnection" then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end

	-- Notify sync system
	if NPC_Service.Components.ClientPhysicsSync then
		NPC_Service.Components.ClientPhysicsSync.OnNPCRemoved(npcID)
	end

	-- Notify fallback simulator
	if NPC_Service.Components.ServerFallbackSimulator then
		NPC_Service.Components.ServerFallbackSimulator.CleanupNPC(npcID)
	end

	-- Remove from registry
	NPC_Service.ActiveClientPhysicsNPCs[npcID] = nil

	-- Remove data folder
	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if npcFolder then
		npcFolder:Destroy()
	end
end

--[[
	Set target for a client-physics NPC

	@param npcID string - The NPC ID
	@param target Model? - Target to set (nil to clear)
]]
function ClientPhysicsSpawner:SetTarget(npcID, target)
	local npcData = self:GetNPCData(npcID)
	if not npcData then
		return
	end

	npcData.CurrentTarget = target

	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if npcFolder then
		local targetValue = npcFolder:FindFirstChild("CurrentTarget")
		if targetValue then
			targetValue.Value = target
		end
	end
end

--[[
	Set destination for a client-physics NPC

	@param npcID string - The NPC ID
	@param destination Vector3? - Destination to set (nil to clear)
]]
function ClientPhysicsSpawner:SetDestination(npcID, destination)
	local npcData = self:GetNPCData(npcID)
	if not npcData then
		return
	end

	npcData.Destination = destination

	local npcFolder = ActiveNPCsFolder:FindFirstChild(npcID)
	if npcFolder then
		-- Create or update Destination value
		local destValue = npcFolder:FindFirstChild("Destination")
		if not destValue then
			destValue = Instance.new("Vector3Value")
			destValue.Name = "Destination"
			destValue.Parent = npcFolder
		end
		destValue.Value = destination or Vector3.zero
	end
end

function ClientPhysicsSpawner.Start()
	-- Component start logic
end

function ClientPhysicsSpawner.Init()
	NPC_Service = Knit.GetService("NPC_Service")

	-- Create ActiveNPCs folder in ReplicatedStorage if it doesn't exist
	ActiveNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not ActiveNPCsFolder then
		ActiveNPCsFolder = Instance.new("Folder")
		ActiveNPCsFolder.Name = "ActiveNPCs"
		ActiveNPCsFolder.Parent = ReplicatedStorage
	end

	-- Initialize registry
	NPC_Service.ActiveClientPhysicsNPCs = {}
end

return ClientPhysicsSpawner
