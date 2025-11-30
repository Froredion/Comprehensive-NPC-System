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
	- UseAnimationController optimization support (client-side physics NPCs)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BetterAnimate = require(ReplicatedStorage.ClientSource.Utilities.BetterAnimate)

local NPCAnimator = {}
NPCAnimator.DebugMode = true -- Set to true to enable debug visualization

-- Track BetterAnimate instances for each NPC
local AnimatorInstances = {} -- [npcModel] = {animator, updateThread, targetModel, trove, npcData?}

--[[
	Setup BetterAnimate for an NPC with full feature support

	@param npc Model - Server NPC model (or visual model for UseAnimationController)
	@param visualModel Model? - Optional client visual model (uses npc if not provided)
	@param options table? - Optional configuration:
		- debug: boolean - Enable debug visualization
		- inverseKinematics: boolean - Enable inverse kinematics (default true)
		- npcData: table? - For UseAnimationController NPCs, the simulation data from ClientNPCManager
			Contains: Position, MovementState, Velocity, IsJumping, Orientation, etc.
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
	local npcData = options.npcData -- For UseAnimationController NPCs

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

	-- Store reference to npcData for dynamic access (allows late binding via LinkNPCData)
	local npcDataRef = { value = npcData }

	-- Always enable position-based velocity for NPC visual models
	-- This is needed because UseAnimationController NPCs have no physics (AssemblyLinearVelocity = 0)
	-- When npcData is available, use simulation data; otherwise fall back to visual model position
	animator.FastConfig.UsePositionBasedVelocity = true
	animator.FastConfig.PositionProvider = function()
		local data = npcDataRef.value
		return data and data.Position or primaryPart.Position
	end
	animator.FastConfig.OrientationProvider = function()
		local data = npcDataRef.value
		return data and data.Orientation or primaryPart.CFrame
	end

	-- Debug: track frames for debug output
	local debugFrameCounter = 0
	local DEBUG_INTERVAL = 60 -- Print debug every N frames
	local isTracked = options._NPCADBG_IsTracked or false

	if isTracked then print("[NPCADBG] NPCAnimator.Setup: npcData exists:", npcDataRef.value ~= nil) end

	-- Setup main animation loop
	local updateThread = animator.Trove:Add(task.defer(function()
		local loopStarted = false
		local npcDataRetryTimer = 0
		local NPCDATA_RETRY_INTERVAL = 0.5 -- Retry fetching npcData every 0.5s if nil

		while npc.Parent and targetModel.Parent do
			local deltaTime = task.wait()

			if not loopStarted then
				loopStarted = true
				if isTracked then print("[NPCADBG] Animation loop STARTED, npcData:", npcDataRef.value ~= nil and "YES" or "NIL") end
			end

			local currentState
			local currentNPCData = npcDataRef.value

			-- If npcData is nil, periodically try to fetch it
			if not currentNPCData then
				npcDataRetryTimer = npcDataRetryTimer + deltaTime
				if npcDataRetryTimer >= NPCDATA_RETRY_INTERVAL then
					npcDataRetryTimer = 0
					-- Try to get npcData from ClientNPCManager
					local ClientNPCManagerModule = script.Parent:FindFirstChild("ClientNPCManager")
					if ClientNPCManagerModule then
						local manager = require(ClientNPCManagerModule)
						-- Extract npcID from visual model name (format: "npcID_Visual")
						local npcID = npc.Name:gsub("_Visual$", "")
						local fetchedData = manager.GetSimulatedNPC(npcID)
						if fetchedData then
							npcDataRef.value = fetchedData
							currentNPCData = fetchedData
							if isTracked then print("[NPCADBG] Retry SUCCESS - got npcData!") end
						end
					end
				end
			end

			-- Determine animation state
			if currentNPCData then
				-- UseAnimationController mode: use npcData for state
				if currentNPCData.IsJumping then
					currentState = "Jumping"
				elseif nextState then
					currentState = nextState
				else
					currentState = "Running" -- BetterAnimate handles idle/walk/run based on speed
				end

				-- Debug output (only for tracked NPC)
				if isTracked then
					debugFrameCounter = debugFrameCounter + 1
					if debugFrameCounter >= DEBUG_INTERVAL then
						debugFrameCounter = 0
						local velocity = animator._CalculatedVelocity or Vector3.zero
						local speed = animator._Speed or 0
						local currentClass = animator._Class and animator._Class.Current or "?"
						print(string.format(
							"[NPCADBG] npcData=YES, Vel=%.1f, Speed=%.1f, State=%s, Class=%s",
							velocity.Magnitude,
							speed,
							currentState,
							currentClass
						))
					end
				end
			else
				-- No npcData yet - use "Running" state (NOT humanoid state!)
				-- This avoids PlatformStanding which stops all animations
				-- BetterAnimate will determine Idle/Walk/Run from velocity
				currentState = nextState or "Running"

				-- Debug output for nil npcData case (only for tracked NPC)
				if isTracked then
					debugFrameCounter = debugFrameCounter + 1
					if debugFrameCounter >= DEBUG_INTERVAL then
						debugFrameCounter = 0
						local velocity = animator._CalculatedVelocity or Vector3.zero
						local speed = animator._Speed or 0
						local currentClass = animator._Class and animator._Class.Current or "?"
						print(string.format(
							"[NPCADBG] npcData=NIL, using Running fallback, Vel=%.1f, Speed=%.1f, Class=%s",
							velocity.Magnitude,
							speed,
							currentClass
						))
					end
				end
			end

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
		npcDataRef = npcDataRef,
		_NPCADBG_IsTracked = isTracked, -- For debug tracking
	}

	local modeStr = npcData and "UseAnimationController" or "Traditional"
	print("[NPCAnimator] Setup animator for:", npc.Name, "Rig:", rigType, "Mode:", modeStr, "IK:", enableIK, "Debug:", enableDebug)
end

--[[
	Link existing animator instance to npcData (for late binding)

	Used when ClientPhysicsRenderer creates the visual model before
	ClientNPCManager has linked the npcData.

	@param npc Model - The NPC model key
	@param npcData table - The simulation data from ClientNPCManager
]]
function NPCAnimator.LinkNPCData(npc, npcData)
	local instance = AnimatorInstances[npc]
	local isTracked = instance and instance._NPCADBG_IsTracked
	if isTracked then print("[NPCADBG] LinkNPCData: instance exists:", instance ~= nil) end
	if instance then
		-- Update the npcData reference - PositionProvider/OrientationProvider will use it automatically
		instance.npcDataRef.value = npcData
		if isTracked then print("[NPCADBG] LinkNPCData SUCCESS") end
	else
		-- Check if this NPC is tracked even without instance
		local ClientNPCManager = script.Parent:FindFirstChild("ClientNPCManager")
		if ClientNPCManager then
			local manager = require(ClientNPCManager)
			if manager.NPCADBG_TrackedNPC and npc.Name:find(manager.NPCADBG_TrackedNPC) then
				print("[NPCADBG] LinkNPCData FAILED - no animator instance yet!")
			end
		end
	end
end

--[[
	Get the npcData linked to an animator instance

	@param npc Model - The NPC model key
	@return table? - The npcData or nil
]]
function NPCAnimator.GetNPCData(npc)
	local instance = AnimatorInstances[npc]
	return instance and instance.npcDataRef and instance.npcDataRef.value
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
