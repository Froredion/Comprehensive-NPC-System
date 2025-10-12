local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local NPC_Renderer = {}

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities
local modelUtilsFolder = utilsFolder.Model
local ScaleModel = require(modelUtilsFolder.ScaleModel)

---- Data
local player = Players.LocalPlayer
local GameSettings = require(ReplicatedStorage.SharedSource.Datas.GameSettings)

-- Track rendered NPCs
local renderedNPCs = {}
local renderConnection
local lastUpdateTime = 0
local UPDATE_FREQUENCY = 1 / 30 -- Update 30 frames per second

-- Get streaming properties from GameSettings
local function getStreamingRadius()
	return GameSettings.StreamingSettings.StreamingMinRadius, GameSettings.StreamingSettings.StreamingTargetRadius
end

-- Function to check if an NPC should be rendered based on distance and streaming
local function shouldRenderNPC(npcModel)
	if not npcModel or not npcModel:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false
	end

	local distance = (npcModel.HumanoidRootPart.Position - character.HumanoidRootPart.Position).Magnitude
	local minRadius, targetRadius = getStreamingRadius()

	-- Render if within custom streaming target radius (400 studs)
	return distance <= targetRadius
end

-- Function to populate server-created gun tool with visual components
local function populateNPCGunVisuals(npcModel, gunTool)
	-- Check if gun already has visual components
	if #gunTool:GetChildren() > 0 then
		return -- Gun already has components
	end

	local gunName = gunTool.Name
	local gunType = npcModel:GetAttribute("NPC_Gun_Type")

	if not gunType then
		warn("NPC missing gun type attribute for gun:", gunName)
		return
	end

	-- Get the original gun model from assets
	local assetsPath = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsPath then
		warn("Assets folder not found in ReplicatedStorage")
		return
	end

	local armoryFolder = assetsPath:FindFirstChild("Armory")
	if not armoryFolder then
		warn("Armory folder not found in Assets")
		return
	end

	local gunTypeFolder = armoryFolder:FindFirstChild(gunType)
	if not gunTypeFolder then
		warn("Gun type folder not found:", gunType)
		return
	end

	local originalGunModel = gunTypeFolder:FindFirstChild(gunName)
	if not originalGunModel then
		warn("Gun model not found:", gunName, "in", gunType)
		return
	end

	local gunModelCloned = originalGunModel:Clone()

	-- Clone visual components from original gun model
	for _, child in pairs(gunModelCloned:GetChildren()) do
		local clonedChild = child
		clonedChild:SetAttribute("_ClientRenderedInstance_573", true)

		-- Tag all descendants as client-rendered
		for _, descendant in pairs(clonedChild:GetDescendants()) do
			descendant:SetAttribute("_ClientRenderedInstance_573", true)
		end

		clonedChild.Parent = gunTool
	end

	-- Create RightGrip weld manually since automatic welding won't trigger
	local handle = gunTool:FindFirstChild("Handle")
	if handle then
		local humanoid = npcModel:FindFirstChild("Humanoid")
		if humanoid then
			-- Find the right arm/hand based on rig type
			local rightArm = npcModel:FindFirstChild("Right Arm") or npcModel:FindFirstChild("RightHand")

			if rightArm then
				-- Remove any existing RightGrip to avoid duplicates
				local existingGrip = rightArm:FindFirstChild("RightGrip")
				if existingGrip then
					existingGrip:Destroy()
				end

				-- Create new RightGrip weld
				local rightGrip = Instance.new("Weld")
				rightGrip.Name = "RightGrip"
				rightGrip.Part0 = rightArm
				rightGrip.Part1 = handle

				-- Set proper grip CFrame (standard tool grip)
				rightGrip.C0 = CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)
				rightGrip.C1 = CFrame.new(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)

				-- Tag as client-rendered for cleanup
				rightGrip:SetAttribute("_ClientRenderedInstance_573", true)
				rightGrip.Parent = rightArm

				if RunService:IsStudio() then
					print("🤝 RightGrip created for:", npcModel.Name, "| Gun:", gunName)
				end
			else
				warn("Could not find Right Arm/RightHand for RightGrip on:", npcModel.Name)
			end
		end
	else
		warn("Gun tool missing Handle for RightGrip:", gunName)
	end

	if RunService:IsStudio() then
		print("🔫 NPC Gun Visuals Populated:", npcModel.Name, "| Gun:", gunName, "| Type:", gunType)
	end
end

-- Function to check for and populate guns in an NPC
local function checkAndPopulateNPCGuns(npcModel)
	-- Look for gun tools that need visual population
	for _, child in pairs(npcModel:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Equipped") then
			populateNPCGunVisuals(npcModel, child)
		end
	end
end

-- Function to render NPC visual components
local function renderNPCVisuals(npcModel)
	-- Prevent double rendering
	if renderedNPCs[npcModel] then
		return
	end

	local rarityName = npcModel:GetAttribute("NPC_Render_Rarity")
	local npcName = npcModel:GetAttribute("NPC_Render_Name")

	if not rarityName or not npcName then
		warn("NPC missing render attributes:", npcModel.Name, "Rarity:", rarityName, "Name:", npcName)
		return
	end

	-- Get the full crew model from assets
	local assetsPath = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsPath then
		warn("Assets folder not found in ReplicatedStorage")
		return
	end

	local crewsFolder = assetsPath:FindFirstChild("Crews")
	if not crewsFolder then
		warn("Crews folder not found in Assets")
		return
	end

	local rarityFolder = crewsFolder:FindFirstChild(rarityName)
	if not rarityFolder then
		warn("Rarity folder not found:", rarityName)
		return
	end

	local originalCrewModel = rarityFolder:FindFirstChild(npcName)
	if not originalCrewModel then
		warn("Crew model not found:", npcName, "in", rarityName)
		return
	end

	-- Clone the visual components from the original model
	local visualModel = originalCrewModel:Clone()

	-- Remove the Humanoid and HumanoidRootPart from the cloned model (server handles these)
	if visualModel:FindFirstChild("Humanoid") then
		visualModel.Humanoid:Destroy()
	end
	if visualModel:FindFirstChild("HumanoidRootPart") then
		visualModel.HumanoidRootPart:Destroy()
	end

	-- Get server's HumanoidRootPart for connections
	local serverHumanoidRootPart = npcModel:FindFirstChild("HumanoidRootPart")

	-- Track the rendered parts for cleanup
	local renderedParts = {}

	-- Parent all visual parts to the same server model and tag them
	for _, child in pairs(visualModel:GetChildren()) do
		if
			child:IsA("BasePart")
			or child:IsA("Accessory")
			or child:IsA("Clothing")
			or child:IsA("SpecialMesh")
			or child:IsA("Motor6D")
			or child:IsA("WeldConstraint")
			or child:IsA("Decal")
			or child:IsA("Texture")
			or child:IsA("SurfaceGui")
		then
			-- Tag as client-rendered instance
			child:SetAttribute("_ClientRenderedInstance_573", true)

			-- Handle LowerTorso connection to server HumanoidRootPart using ToObjectSpace/ToWorldSpace
			if child.Name == "LowerTorso" and serverHumanoidRootPart then
				local originalLowerTorso = originalCrewModel:FindFirstChild("LowerTorso")
				if originalLowerTorso then
					local childRoot = child:FindFirstChild("Root")
					if childRoot and childRoot:IsA("Motor6D") then
						-- Clone the Motor6D for reference but don't rely on it activating
						local rootMotor = childRoot
						rootMotor.Part0 = serverHumanoidRootPart -- Visual LowerTorso
						rootMotor.Part1 = child -- Server HumanoidRootPart
						rootMotor:SetAttribute("_ClientRenderedInstance_573", true)

						-- Use ToObjectSpace/ToWorldSpace for immediate positioning
						local function updateLowerTorsoPosition()
							if child.Parent and serverHumanoidRootPart.Parent then
								-- Calculate the relative position using the Motor6D's C0 and C1
								local c0 = childRoot.C0
								local c1 = childRoot.C1

								-- Apply the motor6D transformation manually
								local cf = serverHumanoidRootPart.CFrame * c1 * c0:Inverse()
								child.CFrame = cf
							end
						end

						-- Initial positioning
						updateLowerTorsoPosition()

						-- Connect to server HumanoidRootPart movement for continuous updates
						local heartbeatConnection
						heartbeatConnection = game:GetService("RunService").Heartbeat:Connect(function()
							if child.Parent and serverHumanoidRootPart.Parent then
								updateLowerTorsoPosition()
								heartbeatConnection:Disconnect()
							end
						end)

						-- Store connection for cleanup
						if not renderedParts.connections then
							renderedParts.connections = {}
						end
						table.insert(renderedParts.connections, heartbeatConnection)
					end
				end
			end

			if child:IsA("BasePart") then
				child.CanCollide = false
				child.CollisionGroup = serverHumanoidRootPart.CollisionGroup
			end

			-- Parent to the same server model
			child.Parent = npcModel
			table.insert(renderedParts, child)
		end
	end

	-- Check and populate guns before scaling (so gun components scale properly)
	checkAndPopulateNPCGuns(npcModel)

	-- Handle boss scaling using model:ScaleTo()
	local isBoss = npcModel:GetAttribute("IsBoss")
	local bossScale = npcModel:GetAttribute("BossScale")
	if isBoss and bossScale then
		pcall(function()
			npcModel:ScaleTo(bossScale)
		end)
	end

	-- Store that this NPC has been rendered with reference to rendered parts
	renderedNPCs[npcModel] = renderedParts

	-- Clean up the temporary model
	visualModel:Destroy()

	local partsCount = 0
	for _, part in pairs(renderedParts) do
		if typeof(part) == "Instance" then
			partsCount = partsCount + 1
		end
	end

	task.spawn(function()
		task.wait(0.5)
		npcModel.Humanoid:BuildRigFromAttachments()
	end)

	if RunService:IsStudio() then
		print(
			"✅ NPC Rendered:",
			npcModel.Name,
			"| Rarity:",
			rarityName,
			"| Model:",
			npcName,
			"| Parts added:",
			partsCount
		)
	end
end

-- Function to remove rendered visuals (when NPC goes out of range)
local function removeNPCVisuals(npcModel)
	local renderedData = renderedNPCs[npcModel]
	if not renderedData then
		return
	end

	-- Disconnect any heartbeat connections for positioning
	if renderedData.connections then
		for _, connection in pairs(renderedData.connections) do
			if connection then
				connection:Disconnect()
			end
		end
	end

	-- Remove all client-rendered parts from the model
	local partsCount = 0
	for _, part in pairs(renderedData) do
		if typeof(part) == "Instance" and part.Parent then
			part:Destroy()
			partsCount = partsCount + 1
		end
	end

	-- Remove client-rendered gun visuals (but keep the server gun tools)
	for _, child in pairs(npcModel:GetChildren()) do
		if child:IsA("Tool") then
			-- Remove only the visual components inside the gun tool, not the tool itself
			for _, gunChild in pairs(child:GetChildren()) do
				if gunChild:GetAttribute("_ClientRenderedInstance_573") then
					gunChild:Destroy()
					partsCount = partsCount + 1
				end
			end
			-- Also remove any client-rendered welds in the NPC's limbs related to this gun
			local humanoid = npcModel:FindFirstChild("Humanoid")
			if humanoid then
				local rightArm = npcModel:FindFirstChild("Right Arm") or npcModel:FindFirstChild("RightHand")
				if rightArm then
					local rightGrip = rightArm:FindFirstChild("RightGrip")
					if rightGrip and rightGrip:GetAttribute("_ClientRenderedInstance_573") then
						rightGrip:Destroy()
						partsCount = partsCount + 1
					end
				end
			end
		end
	end

	renderedNPCs[npcModel] = nil

	if RunService:IsStudio() then
		print("🗑️ NPC Visual Removed:", npcModel.Name, "| Parts removed:", partsCount)
	end
end

-- Function to handle NPC rendering based on streaming
local function updateNPCRendering()
	local charactersFolder = workspace:FindFirstChild("Characters")
	if not charactersFolder then
		return
	end

	local npcsFolder = charactersFolder:FindFirstChild("NPCs")
	if not npcsFolder then
		return
	end

	for _, npcModel in pairs(npcsFolder:GetChildren()) do
		if npcModel:IsA("Model") then
			local shouldRender = shouldRenderNPC(npcModel)
			local isRendered = renderedNPCs[npcModel] ~= nil

			if shouldRender and not isRendered then
				-- Render the NPC
				renderNPCVisuals(npcModel)
			elseif not shouldRender and isRendered then
				-- Remove visuals to save performance
				removeNPCVisuals(npcModel)
			end
		end
	end
end

-- Function to handle new NPCs being added
local function onNPCAdded(npcModel)
	if not npcModel:IsA("Model") then
		return
	end

	-- Wait for attributes to be set
	task.wait(0.1)

	-- Check if this NPC should be immediately rendered
	if shouldRenderNPC(npcModel) then
		renderNPCVisuals(npcModel)
	end

	-- Monitor for new tools being added (guns from server)
	local function onChildAdded(child)
		if child:IsA("Tool") and child:GetAttribute("Equipped") and renderedNPCs[npcModel] then
			-- Wait a moment for the tool to fully load before populating
			task.wait(0.1)
			populateNPCGunVisuals(npcModel, child)
		end
	end

	-- Connect to new children being added to the NPC
	npcModel.ChildAdded:Connect(onChildAdded)

	-- Also check existing tools that might have been added before monitoring started
	for _, child in pairs(npcModel:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Equipped") then
			onChildAdded(child)
		end
	end

	-- Handle NPC removal
	npcModel.AncestryChanged:Connect(function()
		if not npcModel.Parent then
			-- Clean up rendered parts and connections if they exist
			removeNPCVisuals(npcModel)
		end
	end)
end

-- Function to setup NPC folder monitoring
local function setupNPCMonitoring()
	local charactersFolder = workspace:WaitForChild("Characters", 10)
	if not charactersFolder then
		warn("Characters folder not found in workspace")
		return
	end

	local npcsFolder = charactersFolder:WaitForChild("NPCs", 10)
	if not npcsFolder then
		warn("NPCs folder not found in Characters")
		return
	end

	-- Handle existing NPCs
	for _, npcModel in pairs(npcsFolder:GetChildren()) do
		if npcModel:IsA("Model") then
			onNPCAdded(npcModel)
		end
	end

	-- Handle new NPCs
	npcsFolder.ChildAdded:Connect(onNPCAdded)
end

function NPC_Renderer.Start()
	-- Setup NPC monitoring
	setupNPCMonitoring()

	-- Start the rendering update loop with throttling
	renderConnection = RunService.RenderStepped:Connect(function()
		local currentTime = tick()
		if currentTime - lastUpdateTime >= UPDATE_FREQUENCY then
			lastUpdateTime = currentTime
			updateNPCRendering()
		end
	end)

	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(leavingPlayer)
		if leavingPlayer == player then
			if renderConnection then
				renderConnection:Disconnect()
			end
		end
	end)
end

function NPC_Renderer.Init()
	-- Initialize the NPC renderer
end

return NPC_Renderer
