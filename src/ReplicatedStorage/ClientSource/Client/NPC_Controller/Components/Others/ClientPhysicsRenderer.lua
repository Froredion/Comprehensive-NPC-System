--[[
	ClientPhysicsRenderer - Visual rendering for UseClientPhysics NPCs

	This is DIFFERENT from NPCRenderer.lua:
	- NPCRenderer.lua - Renders visuals on top of server-physics NPCs (traditional approach)
	- ClientPhysicsRenderer.lua - Renders full NPCs from position data only (no server model)

	Handles:
	- Creating full visual NPC models from ReplicatedStorage data
	- Distance-based render/unrender
	- Position synchronization with data values
	- Health bar display (reads from server health values)
	- Animation setup
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local ClientPhysicsRenderer = {}

---- Dependencies
local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.RenderConfig)
local NPCAnimator -- Loaded in Init

---- Collision Configuration
local collisionGroupName = "NPCs" -- Default fallback

---- State
local RenderedNPCs = {} -- [npcID] = { visualModel, connections, ... }
local LocalPlayer = Players.LocalPlayer

---- Constants
local UNRENDER_HYSTERESIS = 1.3 -- Unrender at 1.3x render distance

--[[
	Calculate height offset from visual model
	Uses formula: HipHeight + (RootPartHeight / 2)

	@param visualModel Model - The NPC visual model
	@return number - Height offset from ground
]]
local function getHeightOffsetFromVisualModel(visualModel)
	if not visualModel then
		return 3 -- Default fallback
	end

	local humanoid = visualModel:FindFirstChildOfClass("Humanoid")
	local rootPart = visualModel:FindFirstChild("HumanoidRootPart")

	if humanoid and rootPart then
		local hipHeight = humanoid.HipHeight
		local rootPartHalfHeight = rootPart.Size.Y / 2
		return hipHeight + rootPartHalfHeight
	end

	return 3 -- Default R15 fallback
end

--[[
	Find ground position and snap to correct height

	@param position Vector3 - Current position (may be inaccurate)
	@param heightOffset number - Height offset from ground (HipHeight + RootPartHalfHeight)
	@return Vector3 - Corrected position at proper ground height
]]
function ClientPhysicsRenderer.SnapToGround(position, heightOffset)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	-- Exclude Characters folder and any NPCs folder to avoid hitting other NPCs
	local excludeList = {
		workspace:FindFirstChild("Characters"),
		workspace:FindFirstChild("VisualWaypoints"),
		workspace:FindFirstChild("ClientSightVisualization"),
	}
	raycastParams.FilterDescendantsInstances = excludeList

	-- Cast from above the position to find actual ground
	-- Start higher to ensure we're above any spawn point objects
	local currentStart = Vector3.new(position.X, position.Y + 20, position.Z)

	-- Loop to skip non-collidable parts (max 5 iterations)
	for _ = 1, 5 do
		local rayResult = workspace:Raycast(currentStart, Vector3.new(0, -100, 0), raycastParams)

		if not rayResult then
			break -- No hit
		end

		-- Print if detected part is descendant of workspace.Spawners
		local spawnersFolder = workspace:FindFirstChild("Spawners")
		if spawnersFolder and rayResult.Instance:IsDescendantOf(spawnersFolder) then
			print("[Client Ground Detection] Detected ground on Spawner:", rayResult.Instance:GetFullName())
		end

		if rayResult.Instance.CanCollide then
			-- Found ground - position at ground + height offset
			return Vector3.new(position.X, rayResult.Position.Y + heightOffset, position.Z)
		end

		-- Skip this part and continue from just below it
		raycastParams:AddToFilter(rayResult.Instance)
		currentStart = rayResult.Position + Vector3.new(0, -0.1, 0)
	end

	-- No ground found, return original position
	return position
end

--[[
	Initialize the renderer
]]
function ClientPhysicsRenderer.Initialize()
	-- Start distance check loop
	task.spawn(ClientPhysicsRenderer.DistanceCheckLoop)
end

--[[
	Called when a new client-physics NPC is added
]]
function ClientPhysicsRenderer.OnNPCAdded(npcID)
	-- Check render distance before creating
	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not activeNPCsFolder then
		return
	end

	local npcFolder = activeNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end

	-- Check if should render based on distance
	if ClientPhysicsRenderer.ShouldRenderByDistance(npcFolder) then
		ClientPhysicsRenderer.RenderNPC(npcID)
	end
end

--[[
	Called when a client-physics NPC is removed
]]
function ClientPhysicsRenderer.OnNPCRemoved(npcID)
	ClientPhysicsRenderer.UnrenderNPC(npcID)
end

--[[
	Check if NPC should be rendered based on distance
]]
function ClientPhysicsRenderer.ShouldRenderByDistance(npcFolder)
	if not RenderConfig.ENABLED then
		return true -- If render config is disabled, always render (full models)
	end

	local positionValue = npcFolder:FindFirstChild("Position")
	if not positionValue then
		return false
	end

	local character = LocalPlayer.Character
	if not character or not character.PrimaryPart then
		return false
	end

	local distance = (positionValue.Value - character.PrimaryPart.Position).Magnitude
	return distance <= RenderConfig.MAX_RENDER_DISTANCE
end

--[[
	Render an NPC (create visual model)
]]
function ClientPhysicsRenderer.RenderNPC(npcID)
	-- Check if already rendered
	if RenderedNPCs[npcID] then
		return
	end

	-- Check render limit
	local renderCount = 0
	for _ in pairs(RenderedNPCs) do
		renderCount = renderCount + 1
	end

	if renderCount >= RenderConfig.MAX_RENDERED_NPCS then
		return
	end

	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not activeNPCsFolder then
		return
	end

	local npcFolder = activeNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end

	-- Parse config
	local configValue = npcFolder:FindFirstChild("Config")
	if not configValue then
		return
	end

	local success, config = pcall(function()
		return HttpService:JSONDecode(configValue.Value)
	end)

	if not success or not config then
		warn("[ClientPhysicsRenderer] Failed to parse config for NPC:", npcID)
		return
	end

	-- Get original model
	local originalModel = ClientPhysicsRenderer.GetModelFromPath(config.ModelPath)
	if not originalModel then
		warn("[ClientPhysicsRenderer] Model not found:", config.ModelPath)
		return
	end

	-- Clone visual model
	local visualModel = originalModel:Clone()
	visualModel.Name = npcID .. "_Visual"

	-- IMPORTANT: Disable Humanoid physics BEFORE parenting to workspace
	-- This prevents the Humanoid from "standing up" or applying physics on first frame
	local humanoid = visualModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end

	-- Anchor HumanoidRootPart to completely eliminate physics calculations
	-- We control position manually via CFrame in RenderStepped
	local rootPart = visualModel:FindFirstChild("HumanoidRootPart")
	if rootPart then
		rootPart.Anchored = true
	end

	-- Make all parts non-collidable (client-side visuals only) and apply collision group
	for _, descendant in pairs(visualModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			
			-- Apply collision group for NPCs
			descendant.CollisionGroup = collisionGroupName
		end
	end
	
	-- Monitor for new parts (accessories, tools, etc.) and apply collision group
	visualModel.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CollisionGroup = collisionGroupName
		end
	end)

	-- Apply scale if specified (check both CustomData and ClientRenderData)
	local scale = (config.CustomData and config.CustomData.Scale)
		or (config.ClientRenderData and config.ClientRenderData.Scale)
	if scale then
		pcall(function()
			visualModel:ScaleTo(scale)
		end)
	end

	-- Get initial position
	local positionValue = npcFolder:FindFirstChild("Position")
	local position = positionValue and positionValue.Value or Vector3.new(0, 0, 0)

	-- Get initial orientation
	local orientationValue = npcFolder:FindFirstChild("Orientation")
	local orientation = orientationValue and orientationValue.Value or CFrame.new()

	-- Calculate proper height offset from the ACTUAL visual model (after scaling)
	-- This ensures correct positioning regardless of server's calculation
	local heightOffset = getHeightOffsetFromVisualModel(visualModel)

	-- Find actual ground position and apply correct height offset
	local correctedPosition = ClientPhysicsRenderer.SnapToGround(position, heightOffset)

	-- Update the position value so simulation uses correct position
	if positionValue then
		positionValue.Value = correctedPosition
	end

	-- Set initial position using HumanoidRootPart.CFrame for accuracy
	if rootPart then
		-- Combine corrected position with orientation rotation
		rootPart.CFrame = CFrame.new(correctedPosition) * orientation.Rotation
	end

	-- Ensure Characters/NPCs folder exists
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

	-- Parent to workspace
	visualModel.Parent = npcsFolder

	-- Track connections
	local connections = {}

	-- Continuous CFrame sync via RenderStepped (ensures position stays locked even during idle)
	-- RenderStepped runs before rendering, ideal for visual updates
	local orientationValue = npcFolder:FindFirstChild("Orientation")
	local hrp = visualModel:FindFirstChild("HumanoidRootPart")

	if hrp and positionValue then
		local renderSteppedConnection = RunService.RenderStepped:Connect(function()
			if visualModel and visualModel.Parent and hrp and hrp.Parent then
				--[[
					POSITION SOURCE PRIORITY:
					-------------------------
					1. If this client is simulating the NPC, read directly from npcData.Position
					   - This avoids 1-frame delay from positionValue.Value replication
					   - Eliminates stutter caused by RenderStepped timing race
					2. Otherwise, read from positionValue.Value (remote NPC)
					   - NPCs simulated by other clients use network-replicated values
				]]
				local targetPosition = positionValue.Value
				local targetRotation = orientationValue and orientationValue.Value.Rotation or CFrame.identity

				local ClientNPCManagerModule = script.Parent:FindFirstChild("ClientNPCManager")
				if ClientNPCManagerModule then
					local manager = require(ClientNPCManagerModule)
					local npcData = manager.GetSimulatedNPC(npcID)
					if npcData then
						-- Use direct values from simulation (no delay)
						-- This avoids 1-frame delay from Value replication
						targetPosition = npcData.Position
						if npcData.Orientation then
							targetRotation = npcData.Orientation.Rotation
						end
					end
				end

				hrp.CFrame = CFrame.new(targetPosition) * targetRotation
			end
		end)
		table.insert(connections, renderSteppedConnection)
	end

	-- Setup health bar
	local healthValue = npcFolder:FindFirstChild("Health")
	local maxHealthValue = npcFolder:FindFirstChild("MaxHealth")
	if healthValue and maxHealthValue then
		ClientPhysicsRenderer.SetupHealthBar(visualModel, healthValue, maxHealthValue, connections)
	end

	-- Setup animator (PlatformStand already set earlier before parenting)
	local humanoid = visualModel:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		-- Setup BetterAnimate if available
		if NPCAnimator then
			task.spawn(function()
				task.wait(0.5) -- Wait for model to settle

				-- Get npcData from ClientNPCManager for UseClientPhysics support
				local ClientNPCManagerModule = script.Parent:FindFirstChild("ClientNPCManager")
				local npcData = nil
				if ClientNPCManagerModule then
					local manager = require(ClientNPCManagerModule)
					npcData = manager.GetSimulatedNPC(npcID)
				end

				-- Build options with npcData for UseClientPhysics mode
				local animatorOptions = config.ClientRenderData and config.ClientRenderData.animatorOptions or {}
				animatorOptions.npcData = npcData

				NPCAnimator.Setup(visualModel, nil, animatorOptions)
			end)
		end
	end

	-- Store render data
	RenderedNPCs[npcID] = {
		visualModel = visualModel,
		connections = connections,
		config = config,
	}

	-- Link to ClientNPCManager's simulated NPC data
	local ClientNPCManager = script.Parent:FindFirstChild("ClientNPCManager")
	if ClientNPCManager then
		local manager = require(ClientNPCManager)
		local npcData = manager.GetSimulatedNPC(npcID)
		if npcData then
			npcData.VisualModel = visualModel
		end
	end
end

--[[
	Setup health bar for visual model
]]
function ClientPhysicsRenderer.SetupHealthBar(visualModel, healthValue, maxHealthValue, connections)
	local primaryPart = visualModel.PrimaryPart or visualModel:FindFirstChild("HumanoidRootPart")
	if not primaryPart then
		return
	end

	-- Create health bar UI
	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "HealthBar"
	billboardGui.Size = UDim2.new(4, 0, 0.5, 0)
	billboardGui.StudsOffset = Vector3.new(0, 3, 0)
	billboardGui.AlwaysOnTop = false
	billboardGui.MaxDistance = 100

	local frame = Instance.new("Frame")
	frame.Name = "Background"
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	frame.BorderSizePixel = 0
	frame.Parent = billboardGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = frame

	local healthBar = Instance.new("Frame")
	healthBar.Name = "Health"
	healthBar.Size = UDim2.new(healthValue.Value / maxHealthValue.Value, 0, 1, 0)
	healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = frame

	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(0.3, 0)
	healthCorner.Parent = healthBar

	billboardGui.Parent = primaryPart

	-- Update health bar when server updates health
	local healthConnection = healthValue.Changed:Connect(function(newHealth)
		local percentage = math.clamp(newHealth / maxHealthValue.Value, 0, 1)
		healthBar.Size = UDim2.new(percentage, 0, 1, 0)

		-- Color gradient: green -> yellow -> red
		if percentage > 0.5 then
			healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0) -- Green
		elseif percentage > 0.25 then
			healthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0) -- Yellow
		else
			healthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0) -- Red
		end

		-- Hide if dead
		if newHealth <= 0 then
			billboardGui.Enabled = false
		end
	end)
	table.insert(connections, healthConnection)
end

--[[
	Unrender an NPC (destroy visual model)
]]
function ClientPhysicsRenderer.UnrenderNPC(npcID)
	local renderData = RenderedNPCs[npcID]
	if not renderData then
		return
	end

	-- Disconnect all connections
	if renderData.connections then
		for _, connection in pairs(renderData.connections) do
			if connection then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end
	end

	-- Cleanup animator
	if NPCAnimator and renderData.visualModel then
		NPCAnimator.Cleanup(renderData.visualModel)
	end

	-- Destroy visual model
	if renderData.visualModel then
		renderData.visualModel:Destroy()
	end

	-- Remove from tracking
	RenderedNPCs[npcID] = nil
end

--[[
	Distance check loop - handles render/unrender
]]
function ClientPhysicsRenderer.DistanceCheckLoop()
	while true do
		task.wait(RenderConfig.DISTANCE_CHECK_INTERVAL)

		local character = LocalPlayer.Character
		if not character or not character.PrimaryPart then
			continue
		end

		local playerPos = character.PrimaryPart.Position

		-- Check all NPCs in ReplicatedStorage.ActiveNPCs
		local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
		if not activeNPCsFolder then
			continue
		end

		for _, npcFolder in pairs(activeNPCsFolder:GetChildren()) do
			local npcID = npcFolder.Name
			local positionValue = npcFolder:FindFirstChild("Position")

			if positionValue then
				local npcPos = positionValue.Value
				local distance = (playerPos - npcPos).Magnitude

				local isRendered = RenderedNPCs[npcID] ~= nil

				-- Render if within range and not rendered
				if distance <= RenderConfig.MAX_RENDER_DISTANCE and not isRendered then
					ClientPhysicsRenderer.RenderNPC(npcID)
				end

				-- Unrender if out of range and rendered (with hysteresis)
				local unrenderDistance = RenderConfig.MAX_RENDER_DISTANCE * UNRENDER_HYSTERESIS
				if distance > unrenderDistance and isRendered then
					ClientPhysicsRenderer.UnrenderNPC(npcID)
				end
			end
		end
	end
end

--[[
	Get model from path string
]]
function ClientPhysicsRenderer.GetModelFromPath(modelPath)
	if not modelPath then
		return nil
	end

	local current = game
	for _, pathPart in pairs(string.split(modelPath, ".")) do
		if pathPart == "game" then
			continue
		end
		current = current:FindFirstChild(pathPart)
		if not current then
			return nil
		end
	end

	return current
end

--[[
	Get visual model for an NPC
]]
function ClientPhysicsRenderer.GetVisualModel(npcID)
	local renderData = RenderedNPCs[npcID]
	return renderData and renderData.visualModel
end

--[[
	Check if NPC is rendered
]]
function ClientPhysicsRenderer.IsRendered(npcID)
	return RenderedNPCs[npcID] ~= nil
end

--[[
	Get all rendered NPCs
]]
function ClientPhysicsRenderer.GetAllRenderedNPCs()
	return RenderedNPCs
end

--[[
	Force refresh all NPCs
]]
function ClientPhysicsRenderer.RefreshAll()
	-- Unrender all
	for npcID in pairs(RenderedNPCs) do
		ClientPhysicsRenderer.UnrenderNPC(npcID)
	end

	-- Re-check all NPCs
	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if activeNPCsFolder then
		for _, npcFolder in pairs(activeNPCsFolder:GetChildren()) do
			ClientPhysicsRenderer.OnNPCAdded(npcFolder.Name)
		end
	end
end

function ClientPhysicsRenderer.Start()
	-- Try to load CollisionConfig for collision group names
	local collisionConfigModule = ReplicatedStorage.SharedSource.Datas:WaitForChild("CollisionConfig", 2)
	if collisionConfigModule then
		local config = require(collisionConfigModule)
		if config.Groups and config.Groups.NPCs then
			collisionGroupName = config.Groups.NPCs
			print("[ClientPhysicsRenderer] Using collision group name from CollisionConfig:", collisionGroupName)
		end
	else
		print("[ClientPhysicsRenderer] CollisionConfig not found, using default collision group:", collisionGroupName)
	end
	
	-- Initialize the renderer
	ClientPhysicsRenderer.Initialize()
end

function ClientPhysicsRenderer.Init()
	-- Load NPCAnimator if available
	local animatorModule = script.Parent:FindFirstChild("NPCAnimator")
	if animatorModule then
		NPCAnimator = require(animatorModule)
	end
end

return ClientPhysicsRenderer
