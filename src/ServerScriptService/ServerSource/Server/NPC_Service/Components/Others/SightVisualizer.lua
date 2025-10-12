local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Knit = require(ReplicatedStorage.Packages.Knit)

local SightVisualizer = {}

---- Configuration
local VISUALIZER_ENABLED = true -- Toggle this to enable/disable visualizer globally
local VISUALIZATION_FOLDER_NAME = "SightVisualization"

---- Colors
local COLOR_SIGHT_RANGE = Color3.fromRGB(100, 200, 255) -- Blue for range
local COLOR_DIRECTIONAL_CONE = Color3.fromRGB(255, 255, 100) -- Yellow for cone
local COLOR_LOS_RAY_CLEAR = Color3.fromRGB(0, 255, 0) -- Green for clear LOS
local COLOR_LOS_RAY_BLOCKED = Color3.fromRGB(255, 0, 0) -- Red for blocked LOS
local COLOR_DETECTED_TARGET = Color3.fromRGB(255, 165, 0) -- Orange for detected targets
local COLOR_CURRENT_TARGET = Color3.fromRGB(255, 0, 255) -- Magenta for current target

---- Cache for persistent visualizations per NPC
local npcVisualCache = {} -- [npcModel] = {folder, sphere, cone, lastRadius, lastAngle}
local npcIdCounter = 0 -- Counter for unique NPC IDs

--[[
	Toggle visualizer on/off
	
	@param enabled boolean - Enable or disable visualizer
]]
function SightVisualizer:SetEnabled(enabled)
	VISUALIZER_ENABLED = enabled
	print("[SightVisualizer] Visualizer", enabled and "ENABLED" or "DISABLED")
end

--[[
	Get visualizer enabled state
	
	@return boolean - Whether visualizer is enabled
]]
function SightVisualizer:IsEnabled()
	return VISUALIZER_ENABLED
end

--[[
	Get or create visualization folder for NPC
	Parent to Workspace to avoid increasing model extent size
	
	@param npcModel Model - NPC model
	@return Folder - Visualization folder
]]
local function getVisualizationFolder(npcModel)
	-- Check cache first
	if npcVisualCache[npcModel] and npcVisualCache[npcModel].folder then
		return npcVisualCache[npcModel].folder
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
	local npcFolderName = npcModel.Name .. "_" .. tostring(npcIdCounter)

	-- Create NPC-specific folder
	local folder = Instance.new("Folder")
	folder.Name = npcFolderName
	folder.Parent = mainFolder

	-- Initialize cache entry
	if not npcVisualCache[npcModel] then
		npcVisualCache[npcModel] = {}
	end
	npcVisualCache[npcModel].folder = folder

	return folder
end

--[[
	Clear temporary visualizations (LOS rays, highlights) but keep persistent ones
	
	@param npcModel Model - NPC model
]]
local function clearTemporaryVisualizations(npcModel)
	local cache = npcVisualCache[npcModel]
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
	
	@param npcModel Model - NPC model
	@param radius number - Sight range radius
]]
local function createSightRangeSphere(npcModel, radius)
	local folder = getVisualizationFolder(npcModel)
	local cache = npcVisualCache[npcModel] -- Get cache AFTER folder initialization

	-- Only recreate if radius changed or sphere doesn't exist
	if cache.sphere and cache.lastRadius == radius then
		return -- Sphere already exists with correct size
	end

	-- Remove old sphere if exists
	if cache.sphere then
		cache.sphere:Destroy()
		cache.sphere = nil
	end

	-- Create sphere
	local sphere = Instance.new("Part")
	sphere.Name = "SightRangeSphere"
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	sphere.Position = npcModel.PrimaryPart.Position
	sphere.Anchored = false
	sphere.CanCollide = false
	sphere.CanQuery = false
	sphere.Transparency = 0.85
	sphere.Color = COLOR_SIGHT_RANGE
	sphere.Material = Enum.Material.Neon
	sphere.Massless = true
	sphere.CastShadow = false
	sphere.Parent = folder

	-- Add weld to follow NPC
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = npcModel.PrimaryPart
	weld.Part1 = sphere
	weld.Parent = sphere

	-- Cache the sphere and radius
	cache.sphere = sphere
	cache.lastRadius = radius
end

--[[
	Create or update directional cone visualization
	Only recreates when angle or radius changes
	
	@param npcModel Model - NPC model
	@param angle number - Cone angle in degrees
	@param radius number - Sight range radius
]]
local function createDirectionalCone(npcModel, angle, radius)
	local folder = getVisualizationFolder(npcModel)
	local cache = npcVisualCache[npcModel] -- Get cache AFTER folder initialization

	-- Only recreate if angle/radius changed or cone doesn't exist
	if cache.cone and cache.lastAngle == angle and cache.lastConeRadius == radius then
		return -- Cone already exists with correct parameters
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
		warn("[SightVisualizer] Cone mesh not found at ReplicatedStorage.Assets.NPCs.Visualizers.Cone")
		return
	end

	-- Clone the cone mesh
	local cone = coneTemplate:Clone()
	cone.Name = "DirectionalCone"

	-- Calculate cone dimensions based on angle and radius
	-- Base diameter = 2 * radius * tan(angle/2)
	local baseRadius = radius * math.tan(math.rad(angle / 2))
	local baseDiameter = baseRadius * 2

	-- Set cone size (tip at +Y, base at -Y in local space)
	-- We need to flip it so tip points forward in -Z direction
	cone.Size = Vector3.new(baseDiameter, radius, baseDiameter)

	-- Set visual properties
	cone.Color = COLOR_DIRECTIONAL_CONE
	cone.Material = Enum.Material.Neon
	cone.Transparency = 0.7
	cone.CanCollide = false
	cone.CanQuery = false
	cone.Anchored = false
	cone.Massless = true
	cone.CastShadow = false
	cone.Parent = folder

	-- Position cone: tip at NPC center, pointing in look direction
	-- Since tip is at +Y and pivot is at center, rotate 90° then offset
	local npcCFrame = npcModel.PrimaryPart.CFrame

	-- Rotate so tip points forward (-Z direction)
	-- Since pivot is at center and height=radius, tip is at -radius/2 after rotation
	-- Move backward by radius/2 so tip is at NPC position
	local coneOffset = CFrame.new(0, -radius / 2, 0) -- the cone is not positioned exactly at the center, hence radius / 1.5
	cone.CFrame = npcCFrame * CFrame.Angles(math.rad(90), 0, 0) * coneOffset

	-- Weld to NPC to follow rotation
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = npcModel.PrimaryPart
	weld.Part1 = cone
	weld.Parent = cone

	-- Cache the cone and parameters
	cache.cone = cone
	cache.lastAngle = angle
	cache.lastConeRadius = radius
end

--[[
	Draw line of sight ray
	
	@param npcModel Model - NPC model
	@param targetPosition Vector3 - Target position
	@param isClear boolean - Whether LOS is clear
	@param targetIndex number - Index of target
]]
local function drawLOSRay(npcModel, targetPosition, isClear, targetIndex)
	local folder = getVisualizationFolder(npcModel)

	-- Remove old ray if exists
	local oldRay = folder:FindFirstChild("LOSRay" .. targetIndex)
	if oldRay then
		oldRay:Destroy()
	end

	local npcPos = npcModel.PrimaryPart.Position
	local distance = (targetPosition - npcPos).Magnitude

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
	
	@param self table - NPC data
	@param detectedTargets table - Array of detected targets
	@param angle number - Cone angle (for directional mode)
]]
function SightVisualizer:UpdateVisualization(self, detectedTargets, angle)
	if not VISUALIZER_ENABLED then
		return
	end

	-- Clear temporary visualizations (LOS rays)
	clearTemporaryVisualizations(self.Model)

	-- Create or update sight range sphere (only if needed)
	createSightRangeSphere(self.Model, self.SightRange)

	-- Create or update directional cone if in directional mode (only if needed)
	if self.SightMode == "Directional" then
		createDirectionalCone(self.Model, angle, self.SightRange)
	end

	-- Draw LOS rays and highlight targets
	if detectedTargets then
		for i, targetData in ipairs(detectedTargets) do
			local targetPos = targetData.Model.PrimaryPart.Position
			local isCurrent = (self.CurrentTarget == targetData.Model)

			-- Draw LOS ray
			drawLOSRay(self.Model, targetPos, true, i)

			-- Highlight target
			highlightTarget(targetData.Model, isCurrent)
		end
	end
end

--[[
	Clean up visualizations for NPC
	
	@param npcModel Model - NPC model
]]
function SightVisualizer:Cleanup(npcModel)
	local cache = npcVisualCache[npcModel]
	if cache then
		-- Destroy the visualization folder
		if cache.folder then
			cache.folder:Destroy()
		end

		-- Clear cache entry
		npcVisualCache[npcModel] = nil
	end

	-- Also clean up any highlights on the NPC model itself
	local highlight = npcModel:FindFirstChild("SightDetectionHighlight")
	if highlight then
		highlight:Destroy()
	end
end

function SightVisualizer.Start()
	-- Component start logic
	print("[SightVisualizer] Initialized. Enabled:", VISUALIZER_ENABLED)
	print("[SightVisualizer] Use SightVisualizer:SetEnabled(true/false) to toggle")
end

function SightVisualizer.Init()
	-- Component init logic
end

return SightVisualizer
