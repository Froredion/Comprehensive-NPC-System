--[[
	NPCRenderer - Client-side NPC visual rendering system
	
	Purpose: Flexible, developer-friendly NPC rendering with distance-based optimization
	
	This renderer follows the exact process of cloning visual components from asset models
	and parenting them individually to the server NPC model with proper tagging and cleanup.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local NPCRenderer = {}

local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.RenderConfig)
local NPCAnimator = require(script.Parent.NPCAnimator)

-- Constants
local CLIENT_RENDER_TAG = "_ClientRenderedInstance_573"

-- Track rendered NPCs
local RenderedNPCs = {} -- [npcModel] = {renderedParts, connections, renderData}

-- Custom render callback (developers can override this)
NPCRenderer.CustomRenderCallback = nil -- function(npc: Model, renderData: table): table?

--[[
	Initialize the NPCRenderer system
	
	Watches for new NPCs and sets up rendering
]]
function NPCRenderer.InitializeRenderer()
	-- Check if rendering is enabled
	if not RenderConfig.ENABLED then
		print("[NPCRenderer] Rendering disabled via config (RenderConfig.ENABLED = false)")
		print("[NPCRenderer] Initializing NPCAnimator in standalone mode for server NPC animations")
		NPCAnimator.InitializeStandalone()
		return
	end

	print("[NPCRenderer] Client-side NPC rendering enabled")

	-- Watch for NPCs in workspace.Characters.NPCs
	local charactersFolder = workspace:WaitForChild("Characters", 10)
	if not charactersFolder then
		charactersFolder = Instance.new("Folder")
		charactersFolder.Name = "Characters"
		charactersFolder.Parent = workspace
	end

	local npcsFolder = charactersFolder:WaitForChild("NPCs", 10)
	if not npcsFolder then
		npcsFolder = Instance.new("Folder")
		npcsFolder.Name = "NPCs"
		npcsFolder.Parent = charactersFolder
	end

	-- Watch for new NPCs
	npcsFolder.ChildAdded:Connect(function(npc)
		if npc:IsA("Model") then
			task.spawn(function()
				NPCRenderer.OnNPCAdded(npc)
			end)
		end
	end)

	-- Handle existing NPCs
	for _, npc in pairs(npcsFolder:GetChildren()) do
		if npc:IsA("Model") then
			task.spawn(function()
				NPCRenderer.OnNPCAdded(npc)
			end)
		end
	end

	-- Start distance-based rendering updates if enabled
	if RenderConfig.MAX_RENDER_DISTANCE then
		task.spawn(NPCRenderer.DistanceCheckLoop)
	end

	print("[NPCRenderer] Watching for NPCs in workspace.Characters.NPCs")
end

--[[
	Handle when a new NPC is added
	
	@param npc Model - Server NPC model
]]
function NPCRenderer.OnNPCAdded(npc)
	-- Wait for attributes to be set
	task.wait(0.1)
	
	-- Check if should render based on distance
	if RenderConfig.MAX_RENDER_DISTANCE then
		if not NPCRenderer.ShouldRenderByDistance(npc) then
			return
		end
	end
	
	-- Render the NPC
	NPCRenderer.RenderNPC(npc)
	
	-- Monitor for new tools being added (from server)
	local function onChildAdded(child)
		if child:IsA("Tool") and child:GetAttribute("Equipped") and RenderedNPCs[npc] then
			-- Wait for tool to fully load
			task.wait(0.1)
			NPCRenderer.PopulateToolVisuals(npc, child)
		end
	end
	
	-- Connect to new children
	npc.ChildAdded:Connect(onChildAdded)
	
	-- Check existing tools
	for _, child in pairs(npc:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Equipped") then
			onChildAdded(child)
		end
	end
	
	-- Setup cleanup handler
	npc.AncestryChanged:Connect(function()
		if not npc.Parent then
			NPCRenderer.CleanupNPC(npc)
		end
	end)
end

--[[
	Check if NPC should be rendered based on distance
	
	@param npc Model - Server NPC model
	@return boolean - Whether to render
]]
function NPCRenderer.ShouldRenderByDistance(npc)
	if not npc or not npc:FindFirstChild("HumanoidRootPart") then
		return false
	end
	
	local character = Players.LocalPlayer.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end
	
	local distance = (npc.HumanoidRootPart.Position - character.HumanoidRootPart.Position).Magnitude
	return distance <= RenderConfig.MAX_RENDER_DISTANCE
end

--[[
	Render an NPC
	
	@param npc Model - Server NPC model
]]
function NPCRenderer.RenderNPC(npc)
	-- Check if already rendered
	if RenderedNPCs[npc] then
		return
	end

	-- Check render limit
	local renderCount = 0
	for _ in pairs(RenderedNPCs) do
		renderCount = renderCount + 1
	end

	if renderCount >= RenderConfig.MAX_RENDERED_NPCS then
		warn("[NPCRenderer] Max render limit reached:", RenderConfig.MAX_RENDERED_NPCS)
		return
	end

	-- Wait for NPC_ModelPath attribute
	local modelPath = npc:GetAttribute("NPC_ModelPath")
	if not modelPath then
		-- Wait for attribute to be set
		local connection
		connection = npc:GetAttributeChangedSignal("NPC_ModelPath"):Connect(function()
			modelPath = npc:GetAttribute("NPC_ModelPath")
			if modelPath and connection then
				connection:Disconnect()
				NPCRenderer.RenderNPC(npc) -- Retry rendering
			end
		end)

		-- Timeout after 10 seconds
		task.delay(10, function()
			if connection then
				connection:Disconnect()
				warn("[NPCRenderer] Timeout waiting for NPC_ModelPath attribute:", npc.Name)
			end
		end)

		return
	end

	-- Parse custom render data if provided
	local renderData = {}
	local renderDataJSON = npc:GetAttribute("NPC_ClientRenderData")
	if renderDataJSON then
		local success, decoded = pcall(function()
			return HttpService:JSONDecode(renderDataJSON)
		end)
		if success then
			renderData = decoded
		end
	end

	-- Call custom render callback if provided
	if NPCRenderer.CustomRenderCallback then
		local success, customRenderData = pcall(function()
			return NPCRenderer.CustomRenderCallback(npc, renderData)
		end)

		if success and customRenderData then
			RenderedNPCs[npc] = customRenderData
			return
		end
	end

	-- Default rendering
	NPCRenderer.CreateVisual(npc, modelPath, renderData)
end

--[[
	Create visual model for NPC (following exact old process)
	
	@param npc Model - Server NPC model
	@param modelPath string - Path to original character model
	@param renderData table - Custom render data
]]
function NPCRenderer.CreateVisual(npc, modelPath, renderData)
	-- Parse model path and get original model
	local originalModel = game
	for _, pathPart in pairs(string.split(modelPath, ".")) do
		if pathPart == "game" then
			continue
		end
		originalModel = originalModel:FindFirstChild(pathPart)
		if not originalModel then
			warn("[NPCRenderer] Model not found at path:", modelPath)
			return
		end
	end

	-- Clone the visual components from the original model
	local visualModel = originalModel:Clone()
	
	-- Remove Humanoid and HumanoidRootPart from cloned model (server handles these)
	if visualModel:FindFirstChild("Humanoid") then
		visualModel.Humanoid:Destroy()
	end
	if visualModel:FindFirstChild("HumanoidRootPart") then
		visualModel.HumanoidRootPart:Destroy()
	end
	
	-- Get server's HumanoidRootPart for connections
	local serverHumanoidRootPart = npc:FindFirstChild("HumanoidRootPart")
	if not serverHumanoidRootPart then
		warn("[NPCRenderer] Server NPC missing HumanoidRootPart:", npc.Name)
		return
	end
	
	-- Track rendered parts and connections
	local renderedParts = {}
	local connections = {}
	
	-- Parent all visual parts individually to the server model and tag them
	for _, child in pairs(visualModel:GetChildren()) do
		if NPCRenderer.IsRenderableInstance(child) then
			-- Tag as client-rendered instance
			child:SetAttribute(CLIENT_RENDER_TAG, true)
			
			-- Tag all descendants
			for _, descendant in pairs(child:GetDescendants()) do
				descendant:SetAttribute(CLIENT_RENDER_TAG, true)
			end
			
			-- Handle LowerTorso connection to server HumanoidRootPart
			if child.Name == "LowerTorso" and serverHumanoidRootPart then
				NPCRenderer.SetupLowerTorsoConnection(child, serverHumanoidRootPart, originalModel, connections)
			end
			
			-- Make parts non-collidable
			if child:IsA("BasePart") then
				child.CanCollide = false
				child.CollisionGroup = serverHumanoidRootPart.CollisionGroup
			end
			
			-- Parent to server model
			child.Parent = npc
			table.insert(renderedParts, child)
		end
	end
	
	-- Clean up temporary model
	visualModel:Destroy()
	
	-- Check and populate tools before scaling
	NPCRenderer.CheckAndPopulateTools(npc)
	
	-- Handle scaling (boss or custom scale)
	local scale = renderData.Scale or (npc:GetAttribute("IsBoss") and npc:GetAttribute("BossScale"))
	if scale then
		pcall(function()
			npc:ScaleTo(scale)
		end)
	end
	
	-- Store rendered data
	RenderedNPCs[npc] = {
		renderedParts = renderedParts,
		connections = connections,
		renderData = renderData,
	}
	
	-- Build rig from attachments
	task.spawn(function()
		task.wait(0.5)
		if npc:FindFirstChild("Humanoid") then
			npc.Humanoid:BuildRigFromAttachments()
		end
	end)
	
	if RenderConfig.DEBUG_MODE or RunService:IsStudio() then
		print("[NPCRenderer] ✅ Rendered NPC:", npc.Name, "| Parts:", #renderedParts)
	end
end

--[[
	Check if an instance should be rendered
	
	@param instance Instance
	@return boolean
]]
function NPCRenderer.IsRenderableInstance(instance)
	return instance:IsA("BasePart")
		or instance:IsA("Accessory")
		or instance:IsA("Clothing")
		or instance:IsA("SpecialMesh")
		or instance:IsA("Motor6D")
		or instance:IsA("WeldConstraint")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("SurfaceGui")
end

--[[
	Setup LowerTorso connection to server HumanoidRootPart
	
	@param lowerTorso BasePart - Client LowerTorso
	@param serverRoot BasePart - Server HumanoidRootPart
	@param originalModel Model - Original model reference
	@param connections table - Connections table to store cleanup
]]
function NPCRenderer.SetupLowerTorsoConnection(lowerTorso, serverRoot, originalModel, connections)
	local originalLowerTorso = originalModel:FindFirstChild("LowerTorso")
	if not originalLowerTorso then
		return
	end
	
	local rootMotor = lowerTorso:FindFirstChild("Root")
	if not rootMotor or not rootMotor:IsA("Motor6D") then
		return
	end
	
	-- Setup Motor6D
	rootMotor.Part0 = serverRoot
	rootMotor.Part1 = lowerTorso
	rootMotor:SetAttribute(CLIENT_RENDER_TAG, true)
	
	-- Manual positioning function using Motor6D transforms
	local function updateLowerTorsoPosition()
		if lowerTorso.Parent and serverRoot.Parent then
			local c0 = rootMotor.C0
			local c1 = rootMotor.C1
			local cf = serverRoot.CFrame * c1 * c0:Inverse()
			lowerTorso.CFrame = cf
		end
	end
	
	-- Initial positioning
	updateLowerTorsoPosition()
	
	-- Connect to server HumanoidRootPart movement
	local heartbeatConnection
	heartbeatConnection = RunService.Heartbeat:Connect(function()
		if lowerTorso.Parent and serverRoot.Parent then
			updateLowerTorsoPosition()
		else
			if heartbeatConnection then
				heartbeatConnection:Disconnect()
			end
		end
	end)
	
	table.insert(connections, heartbeatConnection)
end

--[[
	Check and populate all tools in NPC
	
	@param npc Model - Server NPC model
]]
function NPCRenderer.CheckAndPopulateTools(npc)
	for _, child in pairs(npc:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Equipped") then
			NPCRenderer.PopulateToolVisuals(npc, child)
		end
	end
end

--[[
	Populate tool with visual components (generalized tool handler)
	
	@param npc Model - Server NPC model
	@param tool Tool - Server tool instance
]]
function NPCRenderer.PopulateToolVisuals(npc, tool)
	-- Check if tool already has visual components
	if #tool:GetChildren() > 0 then
		return
	end
	
	local toolName = tool.Name
	local toolType = npc:GetAttribute("NPC_Tool_Type") or npc:GetAttribute("NPC_Gun_Type") -- Support both
	
	if not toolType then
		warn("[NPCRenderer] NPC missing tool type attribute for tool:", toolName)
		return
	end
	
	-- Get the original tool model from assets
	local assetsPath = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsPath then
		warn("[NPCRenderer] Assets folder not found in ReplicatedStorage")
		return
	end
	
	local armoryFolder = assetsPath:FindFirstChild("Armory")
	if not armoryFolder then
		warn("[NPCRenderer] Armory folder not found in Assets")
		return
	end
	
	local toolTypeFolder = armoryFolder:FindFirstChild(toolType)
	if not toolTypeFolder then
		warn("[NPCRenderer] Tool type folder not found:", toolType)
		return
	end
	
	local originalToolModel = toolTypeFolder:FindFirstChild(toolName)
	if not originalToolModel then
		warn("[NPCRenderer] Tool model not found:", toolName, "in", toolType)
		return
	end
	
	local toolModelCloned = originalToolModel:Clone()
	
	-- Clone visual components from original tool model
	for _, child in pairs(toolModelCloned:GetChildren()) do
		local clonedChild = child
		clonedChild:SetAttribute(CLIENT_RENDER_TAG, true)
		
		-- Tag all descendants
		for _, descendant in pairs(clonedChild:GetDescendants()) do
			descendant:SetAttribute(CLIENT_RENDER_TAG, true)
		end
		
		clonedChild.Parent = tool
	end
	
	-- Create grip weld manually (automatic welding won't trigger)
	local handle = tool:FindFirstChild("Handle")
	if handle then
		NPCRenderer.CreateToolGrip(npc, tool, handle)
	else
		warn("[NPCRenderer] Tool missing Handle for grip:", toolName)
	end
	
	if RenderConfig.DEBUG_MODE or RunService:IsStudio() then
		print("[NPCRenderer] 🔧 Tool Visuals Populated:", npc.Name, "| Tool:", toolName, "| Type:", toolType)
	end
end

--[[
	Create tool grip weld
	
	@param npc Model - Server NPC model
	@param tool Tool - Tool instance
	@param handle BasePart - Tool handle
]]
function NPCRenderer.CreateToolGrip(npc, tool, handle)
	local humanoid = npc:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end
	
	-- Find the right arm/hand based on rig type
	local rightArm = npc:FindFirstChild("Right Arm") or npc:FindFirstChild("RightHand")
	if not rightArm then
		warn("[NPCRenderer] Could not find Right Arm/RightHand for grip on:", npc.Name)
		return
	end
	
	-- Remove any existing grip to avoid duplicates
	local existingGrip = rightArm:FindFirstChild("RightGrip")
	if existingGrip then
		existingGrip:Destroy()
	end
	
	-- Create new grip weld
	local rightGrip = Instance.new("Weld")
	rightGrip.Name = "RightGrip"
	rightGrip.Part0 = rightArm
	rightGrip.Part1 = handle
	
	-- Set proper grip CFrame (standard tool grip)
	rightGrip.C0 = CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)
	rightGrip.C1 = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	
	-- Tag as client-rendered for cleanup
	rightGrip:SetAttribute(CLIENT_RENDER_TAG, true)
	rightGrip.Parent = rightArm
	
	if RenderConfig.DEBUG_MODE or RunService:IsStudio() then
		print("[NPCRenderer] 🤝 Grip created for:", npc.Name, "| Tool:", tool.Name)
	end
end

--[[
	Distance-based rendering check loop
	
	Periodically checks distance to player and renders/unrenders NPCs accordingly
]]
function NPCRenderer.DistanceCheckLoop()
	local localPlayer = Players.LocalPlayer

	while task.wait(RenderConfig.DISTANCE_CHECK_INTERVAL) do
		if not localPlayer.Character or not localPlayer.Character.PrimaryPart then
			continue
		end

		local playerPos = localPlayer.Character.PrimaryPart.Position

		-- Check all NPCs in workspace
		local npcsFolder = workspace:FindFirstChild("Characters") and workspace.Characters:FindFirstChild("NPCs")
		if not npcsFolder then
			continue
		end

		for _, npc in pairs(npcsFolder:GetChildren()) do
			if not npc:IsA("Model") or not npc.PrimaryPart then
				continue
			end

			local npcPos = npc.PrimaryPart.Position
			local distance = (playerPos - npcPos).Magnitude

			local isRendered = RenderedNPCs[npc] ~= nil

			-- Render if within range and not rendered
			if distance <= RenderConfig.MAX_RENDER_DISTANCE and not isRendered then
				NPCRenderer.RenderNPC(npc)
			end

			-- Unrender if out of range and rendered
			if distance > RenderConfig.MAX_RENDER_DISTANCE and isRendered then
				NPCRenderer.CleanupNPC(npc)
			end
		end
	end
end

--[[
	Cleanup rendered NPC
	
	@param npc Model - Server NPC model
]]
function NPCRenderer.CleanupNPC(npc)
	local renderData = RenderedNPCs[npc]
	if not renderData then
		return
	end
	
	-- Disconnect all connections
	if renderData.connections then
		for _, connection in pairs(renderData.connections) do
			if connection then
				connection:Disconnect()
			end
		end
	end
	
	-- Remove all client-rendered parts
	local partsCount = 0
	if renderData.renderedParts then
		for _, part in pairs(renderData.renderedParts) do
			if typeof(part) == "Instance" and part.Parent then
				part:Destroy()
				partsCount = partsCount + 1
			end
		end
	end
	
	-- Remove client-rendered tool visuals
	for _, child in pairs(npc:GetChildren()) do
		if child:IsA("Tool") then
			-- Remove visual components inside tool
			for _, toolChild in pairs(child:GetChildren()) do
				if toolChild:GetAttribute(CLIENT_RENDER_TAG) then
					toolChild:Destroy()
					partsCount = partsCount + 1
				end
			end
			
			-- Remove client-rendered grips
			local humanoid = npc:FindFirstChild("Humanoid")
			if humanoid then
				local rightArm = npc:FindFirstChild("Right Arm") or npc:FindFirstChild("RightHand")
				if rightArm then
					local rightGrip = rightArm:FindFirstChild("RightGrip")
					if rightGrip and rightGrip:GetAttribute(CLIENT_RENDER_TAG) then
						rightGrip:Destroy()
						partsCount = partsCount + 1
					end
				end
			end
		end
	end
	
	-- Remove from tracking
	RenderedNPCs[npc] = nil
	
	if RenderConfig.DEBUG_MODE or RunService:IsStudio() then
		print("[NPCRenderer] 🗑️ Cleaned up NPC:", npc.Name, "| Parts removed:", partsCount)
	end
end

function NPCRenderer.Start()
	-- Component lifecycle Start - initializes renderer watching for NPCs
	NPCRenderer.InitializeRenderer()
end

function NPCRenderer.Init()
	-- Component lifecycle Init - empty, initialization happens in Start()
end

return NPCRenderer
