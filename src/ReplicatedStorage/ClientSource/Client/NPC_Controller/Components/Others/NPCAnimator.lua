--[[
	NPCAnimator - BetterAnimate integration for NPC animations
	
	Purpose: Handles client-side NPC animations using BetterAnimate library
	Works independently of NPCRenderer - animates server NPCs or visual models
	
	Features:
	- Full BetterAnimate integration with proper timing
	- MoveDirection calculation for directional animations
	- Event system (MarkerReached, NewState, etc.)
	- Proper cleanup using Trove
	- Debug mode support
	- Inverse kinematics support
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BetterAnimate = require(ReplicatedStorage.ClientSource.Utilities.BetterAnimate)

local NPCAnimator = {}
NPCAnimator.DebugMode = false -- Set to true to enable debug visualization

-- Track BetterAnimate instances for each NPC
local AnimatorInstances = {} -- [npcModel] = {animator, updateThread, targetModel, trove}

--[[
	Setup BetterAnimate for an NPC with full feature support
	
	@param npc Model - Server NPC model
	@param visualModel Model? - Optional client visual model (uses npc if not provided)
	@param options table? - Optional configuration {debug: boolean, inverseKinematics: boolean}
]]
function NPCAnimator.Setup(npc, visualModel, options)
	-- Avoid duplicate setup
	if AnimatorInstances[npc] then
		return
	end

	-- Use visual model if provided, otherwise animate the server NPC directly
	local targetModel = visualModel or npc

	-- Get humanoid and validate
	local humanoid = targetModel:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		warn("[NPCAnimator] No Humanoid found in target model:", targetModel.Name)
		return
	end

	-- Get primary part
	local primaryPart = targetModel.PrimaryPart or targetModel:WaitForChild("HumanoidRootPart", 5)
	if not primaryPart then
		warn("[NPCAnimator] No PrimaryPart/HumanoidRootPart found in target model:", targetModel.Name)
		return
	end

	-- Parse options
	options = options or {}
	local enableDebug = options.debug or NPCAnimator.DebugMode
	local enableIK = options.inverseKinematics ~= false -- Default true

	-- Get rig type
	local rigType = humanoid.RigType.Name -- "R6" or "R15"

	-- Create BetterAnimate instance
	local animator = BetterAnimate.New(targetModel)

	-- Configure BetterAnimate
	local classesPreset = BetterAnimate.GetClassesPreset(rigType)
	if classesPreset then
		animator:SetClassesPreset(classesPreset)
	end

	animator:SetInverseEnabled(enableIK)
	animator:SetDebugEnabled(enableDebug)

	-- Configure FastConfig
	animator.FastConfig.R6ClimbFix = true

	-- Store physical properties for FixCenterOfMass
	local physicalProperties = primaryPart.CurrentPhysicalProperties

	-- Setup event listeners
	NPCAnimator.SetupEvents(animator, npc, targetModel)

	-- Track next state (for Jumping event handling)
	local nextState = nil

	-- Setup Jumping event handler (since we're not using Humanoid.StateChanged)
	animator.Trove:Add(humanoid.Jumping:Connect(function()
		nextState = "Jumping"
	end))

	-- Setup Died event for cleanup
	animator.Trove:Add(humanoid.Died:Once(function()
		NPCAnimator.Cleanup(npc)
	end))

	-- Setup tool animation support
	NPCAnimator.SetupToolSupport(animator, targetModel, primaryPart, physicalProperties)

	-- Setup main animation loop
	local updateThread = animator.Trove:Add(task.defer(function()
		while npc.Parent and targetModel.Parent do
			local deltaTime = task.wait()

			-- BetterAnimate automatically calculates MoveDirection from velocity
			-- This works for both players and NPCs on the client
			-- No need to manually set FastConfig.MoveDirection

			-- Determine current state
			local currentState = nextState or humanoid:GetState().Name

			-- Step animator
			animator:Step(deltaTime, currentState)

			-- Clear next state
			if nextState then
				nextState = nil
			end
		end
	end))

	-- Track instance
	AnimatorInstances[npc] = {
		animator = animator,
		updateThread = updateThread,
		targetModel = targetModel,
		trove = animator.Trove,
	}

	print("[NPCAnimator] Setup animator for:", npc.Name, "Rig:", rigType, "IK:", enableIK, "Debug:", enableDebug)
end

--[[
	Setup BetterAnimate event listeners
	
	@param animator BetterAnimate - BetterAnimate instance
	@param npc Model - Server NPC model
	@param targetModel Model - Model being animated
]]
function NPCAnimator.SetupEvents(animator, npc, targetModel)
	-- MarkerReached: Fired when animation keyframe marker is reached
	animator.Events.MarkerReached:Connect(function(markerName)
		if NPCAnimator.DebugMode then
			print(`[NPCAnimator] {npc.Name} - Marker reached: {markerName}`)
		end
		-- You can add custom logic here (e.g., play sounds, effects, etc.)
	end)

	-- NewMoveDirection: Fired when move direction changes
	animator.Events.NewMoveDirection:Connect(function(moveDirection, moveDirectionName)
		if NPCAnimator.DebugMode then
			print(`[NPCAnimator] {npc.Name} - New move direction: {moveDirectionName}`)
		end

		-- Stop emote when NPC starts moving (if emote system is implemented)
		if moveDirection.Magnitude > 0 then
			pcall(function()
				animator:StopEmote()
			end)
		end
	end)

	-- NewAnimation: Fired when a new animation starts playing
	animator.Events.NewAnimation:Connect(function(class, index, animationData)
		if NPCAnimator.DebugMode then
			print(`[NPCAnimator] {npc.Name} - New animation: {class} [{index}]`)
		end
	end)

	-- NewState: Fired when animation state changes
	animator.Events.NewState:Connect(function(state)
		if NPCAnimator.DebugMode then
			print(`[NPCAnimator] {npc.Name} - New state: {state}`)
		end
	end)
end

--[[
	Setup tool animation support
	
	@param animator BetterAnimate - BetterAnimate instance
	@param targetModel Model - Model being animated
	@param primaryPart BasePart - HumanoidRootPart
	@param physicalProperties PhysicalProperties - Stored physical properties
]]
function NPCAnimator.SetupToolSupport(animator, targetModel, primaryPart, physicalProperties)
	-- Handle tool equipped
	animator.Trove:Add(targetModel.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			pcall(function()
				animator:PlayToolAnimation()
			end)
		end

		-- Fix center of mass when character structure changes
		pcall(function()
			BetterAnimate.FixCenterOfMass(physicalProperties, primaryPart)
		end)
	end))

	-- Handle tool unequipped
	animator.Trove:Add(targetModel.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			pcall(function()
				animator:StopToolAnimation()
			end)
		end

		-- Fix center of mass when character structure changes
		pcall(function()
			BetterAnimate.FixCenterOfMass(physicalProperties, primaryPart)
		end)
	end))
end

--[[
	Cleanup animator for NPC
	
	@param npc Model - Server NPC model
]]
function NPCAnimator.Cleanup(npc)
	local instance = AnimatorInstances[npc]
	if instance then
		-- Destroy animator (Trove handles all cleanup automatically)
		pcall(function()
			instance.animator:Destroy()
		end)

		-- Remove from tracking
		AnimatorInstances[npc] = nil

		print("[NPCAnimator] Cleaned up animator for:", npc.Name)
	end
end

--[[
	Play an emote on an NPC
	
	@param npc Model - Server NPC model
	@param animationId number | string | Animation - Animation to play
	@return boolean - Success status
]]
function NPCAnimator.PlayEmote(npc, animationId)
	local instance = AnimatorInstances[npc]
	if not instance then
		warn("[NPCAnimator] No animator found for NPC:", npc.Name)
		return false
	end

	local success = pcall(function()
		instance.animator:PlayEmote(animationId)
	end)

	return success
end

--[[
	Stop current emote on an NPC
	
	@param npc Model - Server NPC model
	@return boolean - Success status
]]
function NPCAnimator.StopEmote(npc)
	local instance = AnimatorInstances[npc]
	if not instance then
		return false
	end

	local success = pcall(function()
		instance.animator:StopEmote()
	end)

	return success
end

--[[
	Get animator instance for an NPC
	
	@param npc Model - Server NPC model
	@return BetterAnimate? - Animator instance or nil
]]
function NPCAnimator.GetAnimator(npc)
	local instance = AnimatorInstances[npc]
	return instance and instance.animator
end

--[[
	Initialize NPCAnimator to watch for NPCs
	Called when renderer is disabled, or for standalone animation setup
	
	@param options table? - Optional configuration for all NPCs {debug: boolean, inverseKinematics: boolean}
]]
function NPCAnimator.InitializeStandalone(options)
	print("[NPCAnimator] Initializing standalone animation system")

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
				-- Wait for humanoid to ensure NPC is fully loaded
				local humanoid = npc:WaitForChild("Humanoid", 5)
				if humanoid then
					NPCAnimator.Setup(npc, nil, options) -- No visual model, animate server NPC directly
				end
			end)
		end
	end)

	-- Handle existing NPCs
	for _, npc in pairs(npcsFolder:GetChildren()) do
		if npc:IsA("Model") then
			task.spawn(function()
				local humanoid = npc:WaitForChild("Humanoid", 5)
				if humanoid then
					NPCAnimator.Setup(npc, nil, options)
				end
			end)
		end
	end

	-- Cleanup when NPCs are removed
	npcsFolder.ChildRemoved:Connect(function(npc)
		if npc:IsA("Model") then
			NPCAnimator.Cleanup(npc)
		end
	end)

	print("[NPCAnimator] Watching for NPCs in workspace.Characters.NPCs")
end

function NPCAnimator.Start()
	-- Component start logic
	-- Auto-initialize is handled by NPC_Controller or can be called manually
end

function NPCAnimator.Init()
	-- Component init logic
end

return NPCAnimator
