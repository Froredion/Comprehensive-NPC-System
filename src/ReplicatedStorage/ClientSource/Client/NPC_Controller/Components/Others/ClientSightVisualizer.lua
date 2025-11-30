--[[
	ClientSightVisualizer - Client-side visualization for sight detection

	Displays:
	- Sight range sphere (blue)
	- Directional cone (yellow) for directional mode
	- LOS rays (green = clear, red = blocked)
	- Target highlights (orange = detected, magenta = current target)

	Adapted from server-side SightVisualizer for client simulation.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ClientSightVisualizer = {}

---- Configuration
local VISUALIZER_ENABLED = true -- Toggle this to enable/disable visualizer globally
local VISUALIZATION_FOLDER_NAME = "ClientSightVisualization"

---- Colors
local COLOR_SIGHT_RANGE = Color3.fromRGB(100, 200, 255) -- Blue for range
local COLOR_DIRECTIONAL_CONE = Color3.fromRGB(255, 255, 100) -- Yellow for cone
local COLOR_LOS_RAY_CLEAR = Color3.fromRGB(0, 255, 0) -- Green for clear LOS
local COLOR_LOS_RAY_BLOCKED = Color3.fromRGB(255, 0, 0) -- Red for blocked LOS
local COLOR_DETECTED_TARGET = Color3.fromRGB(255, 165, 0) -- Orange for detected targets
local COLOR_CURRENT_TARGET = Color3.fromRGB(255, 0, 255) -- Magenta for current target

---- Cache for persistent visualizations per NPC
local npcVisualCache = {} -- [npcID] = {folder, sphere, cone, lastRadius, lastAngle}
local npcIdCounter = 0 -- Counter for unique NPC IDs

--[[
	Toggle visualizer on/off

	@param enabled boolean - Enable or disable visualizer
]]
function ClientSightVisualizer:SetEnabled(enabled)
	VISUALIZER_ENABLED = enabled
	print("[ClientSightVisualizer] Visualizer", enabled and "ENABLED" or "DISABLED")

	-- Cleanup all visualizations if disabled
	if not enabled then
		ClientSightVisualizer:CleanupAll()
	end
end

--[[
	Get visualizer enabled state

	@return boolean - Whether visualizer is enabled
]]
function ClientSightVisualizer:IsEnabled()
	return VISUALIZER_ENABLED
end

--[[
	Get or create visualization folder for NPC

	@param npcData table - NPC simulation data
	@return Folder - Visualization folder
]]
local function getVisualizationFolder(npcData)
	local npcID = npcData.ID

	-- Check cache first
	if npcVisualCache[npcID] and npcVisualCache[npcID].folder then
		return npcVisualCache[npcID].folder
	end

	-- Get or create main visualization folder in workspace
	local mainFolder = Workspace:FindFirstChild(VISUALIZATION_FOLDER_NAME)
	if not mainFolder then
		mainFolder = Instance.new("Folder")
		mainFolder.Name = VISUALIZATION_FOLDER_NAME
		mainFolder.Parent = Workspace
	end

	-- Generate unique ID for this NPC
	npcIdCounter = npcIdCounter + 1
	local npcFolderName = npcID .. "_" .. tostring(npcIdCounter)

	-- Create NPC-specific folder
	local folder = Instance.new("Folder")
	folder.Name = npcFolderName
	folder.Parent = mainFolder

	-- Initialize cache entry
	if not npcVisualCache[npcID] then
		npcVisualCache[npcID] = {}
	end
	npcVisualCache[npcID].folder = folder

	return folder
end

--[[
	Clear temporary visualizations (LOS rays, highlights) but keep persistent ones

	@param npcData table - NPC simulation data
]]
local function clearTemporaryVisualizations(npcData)
	local npcID = npcData.ID
	local cache = npcVisualCache[npcID]
	if not cache or not cache.folder then
		return
	end

	-- Only clear temporary visualizations (LOS rays)
	for _, child in ipairs(cache.folder:GetChildren()) do
		if child.Name:match("^LOSRay") then
			child:Destroy()
		end
	end
end

--[[
	Create or update sphere to visualize sight range
	Only recreates when radius changes

	@param npcData table - NPC simulation data
	@param radius number - Sight range radius
]]
local function createSightRangeSphere(npcData, radius)
	local folder = getVisualizationFolder(npcData)
	local npcID = npcData.ID
	local cache = npcVisualCache[npcID]

	-- Only recreate if radius changed or sphere doesn't exist
	if cache.sphere and cache.lastRadius == radius then
		-- Update position only
		cache.sphere.Position = npcData.Position
		return
	end

	-- Remove old sphere if exists
	if cache.sphere then
		cache.sphere:Destroy()
		cache.sphere = nil
	end

	-- Get ball template (double-sided mesh, visible from inside)
	local ballTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("NPCs")
		and ReplicatedStorage.Assets.NPCs:FindFirstChild("Visualizers")
		and ReplicatedStorage.Assets.NPCs.Visualizers:FindFirstChild("Ball")

	if not ballTemplate then
		warn("[ClientSightVisualizer] Ball mesh not found at ReplicatedStorage.Assets.NPCs.Visualizers.Ball")
		return
	end

	-- Clone the ball mesh
	local sphere = ballTemplate:Clone()
	sphere.Name = "SightRangeSphere"
	sphere.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	sphere.Position = npcData.Position
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.Transparency = 0.9 -- Higher transparency for double-sided mesh
	sphere.Color = COLOR_SIGHT_RANGE
	sphere.Material = Enum.Material.Neon
	sphere.CastShadow = false
	sphere.Parent = folder

	-- If we have a visual model, weld to it instead of anchoring
	if npcData.VisualModel and npcData.VisualModel.PrimaryPart then
		sphere.Anchored = false
		sphere.Massless = true

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = npcData.VisualModel.PrimaryPart
		weld.Part1 = sphere
		weld.Parent = sphere
	end

	-- Cache the sphere and radius
	cache.sphere = sphere
	cache.lastRadius = radius
end

--[[
	Create or update directional cone visualization
	Only recreates when angle or radius changes

	@param npcData table - NPC simulation data
	@param angle number - Cone angle in degrees
	@param radius number - Sight range radius
]]
local function createDirectionalCone(npcData, angle, radius)
	local folder = getVisualizationFolder(npcData)
	local npcID = npcData.ID
	local cache = npcVisualCache[npcID]

	-- Only recreate if angle/radius changed or cone doesn't exist
	if cache.cone and cache.lastAngle == angle and cache.lastConeRadius == radius then
		-- Update position/rotation only if no visual model
		if not npcData.VisualModel and npcData.Orientation then
			local coneOffset = CFrame.new(0, -radius / 2, 0)
			cache.cone.CFrame = npcData.Orientation * CFrame.Angles(math.rad(90), 0, 0) * coneOffset
		end
		return
	end

	-- Remove old cone if exists
	if cache.cone then
		cache.cone:Destroy()
		cache.cone = nil
	end

	-- Get cone template
	local coneTemplate = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("NPCs")
		and ReplicatedStorage.Assets.NPCs:FindFirstChild("Visualizers")
		and ReplicatedStorage.Assets.NPCs.Visualizers:FindFirstChild("Cone")

	if not coneTemplate then
		warn("[ClientSightVisualizer] Cone mesh not found at ReplicatedStorage.Assets.NPCs.Visualizers.Cone")
		return
	end

	-- Clone the cone mesh
	local cone = coneTemplate:Clone()
	cone.Name = "DirectionalCone"

	-- Calculate cone dimensions based on angle and radius
	local baseRadius = radius * math.tan(math.rad(angle / 2))
	local baseDiameter = baseRadius * 2

	-- Set cone size
	cone.Size = Vector3.new(baseDiameter, radius, baseDiameter)

	-- Set visual properties
	cone.Color = COLOR_DIRECTIONAL_CONE
	cone.Material = Enum.Material.Neon
	cone.Transparency = 0.7
	cone.CanCollide = false
	cone.CanQuery = false
	cone.CastShadow = false
	cone.Parent = folder

	-- Position cone
	local npcCFrame = npcData.Orientation or CFrame.new(npcData.Position)
	local coneOffset = CFrame.new(0, -radius / 2, 0)
	cone.CFrame = npcCFrame * CFrame.Angles(math.rad(90), 0, 0) * coneOffset

	-- If we have a visual model, weld to it
	if npcData.VisualModel and npcData.VisualModel.PrimaryPart then
		cone.Anchored = false
		cone.Massless = true

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = npcData.VisualModel.PrimaryPart
		weld.Part1 = cone
		weld.Parent = cone
	else
		cone.Anchored = true
	end

	-- Cache the cone and parameters
	cache.cone = cone
	cache.lastAngle = angle
	cache.lastConeRadius = radius
end

--[[
	Draw line of sight ray

	@param npcData table - NPC simulation data
	@param targetPosition Vector3 - Target position
	@param isClear boolean - Whether LOS is clear
	@param targetIndex number - Index of target
]]
local function drawLOSRay(npcData, targetPosition, isClear, targetIndex)
	local folder = getVisualizationFolder(npcData)

	-- Remove old ray if exists
	local oldRay = folder:FindFirstChild("LOSRay" .. targetIndex)
	if oldRay then
		oldRay:Destroy()
	end

	local npcPos = npcData.Position

	-- Create beam for ray
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "LOSRay" .. targetIndex
	attachment0.WorldPosition = npcPos
	attachment0.Parent = workspace.Terrain

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "LOSRayEnd" .. targetIndex
	attachment1.WorldPosition = targetPosition
	attachment1.Parent = workspace.Terrain

	local beam = Instance.new("Beam")
	beam.Name = "LOSBeam" .. targetIndex
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Width0 = 0.2
	beam.Width1 = 0.2
	beam.Color = ColorSequence.new(isClear and COLOR_LOS_RAY_CLEAR or COLOR_LOS_RAY_BLOCKED)
	beam.Transparency = NumberSequence.new(0.3)
	beam.LightEmission = 1
	beam.Parent = attachment0

	-- Auto-cleanup after short duration
	task.delay(0.5, function()
		if attachment0 then
			attachment0:Destroy()
		end
		if attachment1 then
			attachment1:Destroy()
		end
	end)
end

--[[
	Highlight detected target

	@param targetModel Model - Target model
	@param isCurrent boolean - Whether this is the current target
]]
local function highlightTarget(targetModel, isCurrent)
	-- Remove old highlight if exists
	local oldHighlight = targetModel:FindFirstChild("SightDetectionHighlight")
	if oldHighlight then
		oldHighlight:Destroy()
	end

	-- Create highlight
	local highlight = Instance.new("Highlight")
	highlight.Name = "SightDetectionHighlight"
	highlight.Adornee = targetModel
	highlight.FillColor = isCurrent and COLOR_CURRENT_TARGET or COLOR_DETECTED_TARGET
	highlight.OutlineColor = isCurrent and COLOR_CURRENT_TARGET or COLOR_DETECTED_TARGET
	highlight.FillTransparency = 0.7
	highlight.OutlineTransparency = 0.3
	highlight.Parent = targetModel

	-- Auto-cleanup after short duration
	task.delay(1, function()
		if highlight then
			highlight:Destroy()
		end
	end)
end

--[[
	Update visualization for NPC

	@param npcData table - NPC simulation data
	@param detectedTargets table - Array of detected targets
	@param angle number - Cone angle (for directional mode)
]]
function ClientSightVisualizer:UpdateVisualization(npcData, detectedTargets, angle)
	if not VISUALIZER_ENABLED then
		return
	end

	local sightRange = npcData.Config.SightRange or 200
	local sightMode = npcData.Config.SightMode or "Omnidirectional"

	-- Clear temporary visualizations (LOS rays)
	clearTemporaryVisualizations(npcData)

	-- Create or update sight range sphere (only if needed)
	createSightRangeSphere(npcData, sightRange)

	-- Create or update directional cone if in directional mode (only if needed)
	if sightMode == "Directional" then
		createDirectionalCone(npcData, angle, sightRange)
	end

	-- Draw LOS rays and highlight targets
	if detectedTargets then
		for i, targetData in ipairs(detectedTargets) do
			local targetPos = targetData.Model.PrimaryPart and targetData.Model.PrimaryPart.Position
			if targetPos then
				local isCurrent = (npcData.CurrentTarget == targetData.Model)

				-- Draw LOS ray
				drawLOSRay(npcData, targetPos, true, i)

				-- Highlight target
				highlightTarget(targetData.Model, isCurrent)
			end
		end
	end
end

--[[
	Clean up visualizations for NPC

	@param npcData table - NPC simulation data
]]
function ClientSightVisualizer:Cleanup(npcData)
	local npcID = npcData.ID
	local cache = npcVisualCache[npcID]

	if cache then
		-- Destroy the visualization folder
		if cache.folder then
			cache.folder:Destroy()
		end

		-- Clear cache entry
		npcVisualCache[npcID] = nil
	end

	-- Also clean up any highlights on the visual model
	if npcData.VisualModel then
		local highlight = npcData.VisualModel:FindFirstChild("SightDetectionHighlight")
		if highlight then
			highlight:Destroy()
		end
	end
end

--[[
	Clean up all visualizations
]]
function ClientSightVisualizer:CleanupAll()
	-- Clear all cached visualizations
	for npcID, cache in pairs(npcVisualCache) do
		if cache.folder then
			cache.folder:Destroy()
		end
	end
	npcVisualCache = {}

	-- Remove main folder
	local mainFolder = Workspace:FindFirstChild(VISUALIZATION_FOLDER_NAME)
	if mainFolder then
		mainFolder:Destroy()
	end
end

function ClientSightVisualizer.Start()
	-- Component initialized
end

function ClientSightVisualizer.Init()
	-- No external dependencies needed
end

return ClientSightVisualizer
