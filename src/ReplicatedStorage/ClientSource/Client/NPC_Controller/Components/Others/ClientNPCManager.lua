--[[
	ClientNPCManager - Main client-side manager for UseAnimationController NPCs

	Responsibilities:
	- Monitor ReplicatedStorage.ActiveNPCs for new NPCs
	- Assign NPCs to this client based on distance
	- Manage simulation ownership and handoff
	- Coordinate with ClientNPCSimulator, ClientPathfinding, and ClientPhysicsRenderer

	This is the entry point for client-side NPC physics handling.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Knit = require(ReplicatedStorage.Packages.Knit)

local ClientNPCManager = {}

---- Dependencies (loaded in Init)
local NPC_Service
local ClientNPCSimulator
local ClientPhysicsRenderer
local ClientSightDetector
local OptimizationConfig

---- State
local SimulatedNPCs = {} -- [npcID] = npcData (NPCs this client is simulating)
local LastSyncTimes = {} -- [npcID] = lastSyncTick
local LocalPlayer = Players.LocalPlayer


---- Constants
local CLAIM_DELAY_BASE = 0.1 -- Base delay before claiming (seconds)
local CLAIM_DELAY_PER_STUD = 0.001 -- Additional delay per stud of distance

--[[
	Initialize the ClientNPCManager

	Called from NPC_Controller:KnitStart
]]
function ClientNPCManager.Initialize()
	-- Watch for new NPCs in ReplicatedStorage.ActiveNPCs
	local activeNPCsFolder = ReplicatedStorage:WaitForChild("ActiveNPCs", 10)
	if not activeNPCsFolder then
		-- Create folder if it doesn't exist (rare case)
		activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
		if not activeNPCsFolder then
			return -- No client-physics NPCs active
		end
	end

	-- Watch for new NPCs
	activeNPCsFolder.ChildAdded:Connect(function(npcFolder)
		ClientNPCManager.OnNPCAdded(npcFolder)
	end)

	-- Handle existing NPCs
	for _, npcFolder in pairs(activeNPCsFolder:GetChildren()) do
		task.spawn(function()
			ClientNPCManager.OnNPCAdded(npcFolder)
		end)
	end

	-- Watch for removed NPCs
	activeNPCsFolder.ChildRemoved:Connect(function(npcFolder)
		ClientNPCManager.OnNPCRemoved(npcFolder.Name)
	end)

	--[[
		SIMULATION LOOP ARCHITECTURE

		We use a dual-loop system: RenderStepped (primary) + Heartbeat (fallback)

		WHY TWO LOOPS?
		---------------
		RenderStepped:
		- Runs immediately before each frame is rendered
		- Tied to client FPS (60 FPS = 60 updates/sec, 144 FPS = 144 updates/sec)
		- Provides the SMOOTHEST movement possible
		- PAUSES when player alt-tabs (window loses focus)

		Heartbeat:
		- Runs at fixed ~60Hz regardless of FPS
		- CONTINUES running even when alt-tabbed
		- Ensures NPCs don't freeze when player isn't focused on window
		- Only activates when RenderStepped hasn't run for >100ms

		EDGE CASE HANDLING:
		-------------------
		1. Normal gameplay: RenderStepped handles everything (smooth)
		2. Player alt-tabs: RenderStepped pauses → Heartbeat takes over
		3. Player returns: RenderStepped resumes → Heartbeat stops interfering

		IMPORTANT: Do not remove either loop!
		- Removing RenderStepped = choppy movement during gameplay
		- Removing Heartbeat = NPCs freeze when alt-tabbed
		- Removing the 100ms check = double updates (both loops run simultaneously)
	]]
	local lastSimTime = tick()
	local renderSteppedRan = false

	-- PRIMARY LOOP: RenderStepped (smooth movement, synced with FPS)
	RunService.RenderStepped:Connect(function(deltaTime)
		renderSteppedRan = true
		lastSimTime = tick()
		ClientNPCManager.SimulationStep(deltaTime)
	end)

	-- FALLBACK LOOP: Heartbeat (keeps NPCs moving when alt-tabbed)
	RunService.Heartbeat:Connect(function(deltaTime)
		-- Only run if RenderStepped hasn't run recently (player likely alt-tabbed)
		local timeSinceLastSim = tick() - lastSimTime

		-- 100ms threshold = RenderStepped paused (window unfocused)
		if timeSinceLastSim > 0.1 then
			renderSteppedRan = false
			ClientNPCManager.SimulationStep(deltaTime)
		end
		-- If RenderStepped is active, do nothing (prevent double updates)
	end)

	-- Start distance check loop
	task.spawn(ClientNPCManager.DistanceCheckLoop)

	-- Start position sync loop
	task.spawn(ClientNPCManager.PositionSyncLoop)

	-- Listen for position updates from server
	ClientNPCManager.ListenForPositionUpdates()

	-- Listen for orphaned NPCs
	ClientNPCManager.ListenForOrphanedNPCs()

	-- Listen for jump triggers from server
	ClientNPCManager.ListenForJumpTriggers()

end

--[[
	Handle when a new NPC is added to ReplicatedStorage.ActiveNPCs
]]
function ClientNPCManager.OnNPCAdded(npcFolder)
	local npcID = npcFolder.Name

	-- Wait a moment for all values to replicate
	task.wait(0.1)

	-- Notify renderer FIRST so visual model exists before simulation starts
	-- This ensures height offset can be calculated from actual model
	if ClientPhysicsRenderer then
		ClientPhysicsRenderer.OnNPCAdded(npcID)
	end

	-- Check if we should simulate this NPC (after renderer has created visual model)
	local shouldSimulate = ClientNPCManager.ShouldSimulateNPC(npcFolder)
	if shouldSimulate then
		ClientNPCManager.StartSimulation(npcFolder)
	end
end

--[[
	Handle when an NPC is removed
]]
function ClientNPCManager.OnNPCRemoved(npcID)
	-- Stop simulation if we were simulating
	if SimulatedNPCs[npcID] then
		ClientNPCManager.StopSimulation(npcID)
	end

	-- Notify renderer
	if ClientPhysicsRenderer then
		ClientPhysicsRenderer.OnNPCRemoved(npcID)
	end
end

--[[
	Check if this client should simulate an NPC

	@param npcFolder Folder - The NPC data folder
	@return boolean
]]
function ClientNPCManager.ShouldSimulateNPC(npcFolder)
	local positionValue = npcFolder:FindFirstChild("Position")
	if not positionValue then
		return false
	end

	local character = LocalPlayer.Character
	if not character or not character.PrimaryPart then
		return false
	end

	local position = positionValue.Value
	local distance = (character.PrimaryPart.Position - position).Magnitude
	local simulationDistance = OptimizationConfig.ClientSimulation.SIMULATION_DISTANCE

	-- Check if within simulation distance
	if distance > simulationDistance then
		return false
	end

	-- Check if we have capacity
	local currentCount = 0
	for _ in pairs(SimulatedNPCs) do
		currentCount = currentCount + 1
	end

	if currentCount >= OptimizationConfig.ClientSimulation.MAX_SIMULATED_PER_CLIENT then
		return false
	end

	return true
end

--[[
	Start simulating an NPC
]]
function ClientNPCManager.StartSimulation(npcFolder)
	local npcID = npcFolder.Name

	-- Don't double-simulate
	if SimulatedNPCs[npcID] then
		return
	end

	-- Claim NPC on server
	local success = NPC_Service:ClaimNPC(npcID)
	if not success then
		return
	end

	-- Parse config
	local configValue = npcFolder:FindFirstChild("Config")
	if not configValue then
		return
	end

	local success2, config = pcall(function()
		return game:GetService("HttpService"):JSONDecode(configValue.Value)
	end)

	if not success2 or not config then
		return
	end

	-- Get initial position
	local positionValue = npcFolder:FindFirstChild("Position")
	local position = positionValue and positionValue.Value or Vector3.new(0, 0, 0)

	-- Get orientation
	local orientationValue = npcFolder:FindFirstChild("Orientation")
	local orientation = orientationValue and orientationValue.Value or CFrame.new()

	-- Get initial destination if set by server
	local destinationValue = npcFolder:FindFirstChild("Destination")
	local initialDestination = destinationValue and destinationValue.Value ~= Vector3.zero and destinationValue.Value or nil

	-- Create simulation data
	local npcData = {
		ID = npcID,
		Folder = npcFolder,
		Config = config,
		Position = position,
		Orientation = orientation,
		Velocity = Vector3.new(0, 0, 0),
		IsAlive = true,

		-- Movement state
		Destination = initialDestination,
		Pathfinding = nil,
		MovementState = "Idle",

		-- Target state
		CurrentTarget = nil,
		TargetInSight = false,
		LastKnownTargetPos = nil,

		-- Jump state
		IsJumping = false,
		JumpVelocity = 0,

		-- Visual model reference (set by renderer)
		VisualModel = nil,

		-- Connections for cleanup
		Connections = {},
	}

	SimulatedNPCs[npcID] = npcData
	LastSyncTimes[npcID] = tick()

	-- Watch for server-set destination changes
	if destinationValue then
		local destConnection = destinationValue.Changed:Connect(function(newDest)
			-- Only update if NPC is still being simulated by us
			if SimulatedNPCs[npcID] and npcData.IsAlive then
				-- Vector3.zero means clear destination
				if newDest == Vector3.zero then
					print(string.format("[TD_CLIENT_MGR] NPC %s: Destination cleared by server", npcID))
					npcData.Destination = nil
				else
					print(string.format("[TD_CLIENT_MGR] NPC %s: New destination from server: %s", npcID, tostring(newDest)))
					npcData.Destination = newDest
				end
			end
		end)
		table.insert(npcData.Connections, destConnection)
	end

	-- Watch for dynamically created Destination value (if server creates it after spawn)
	local childAddedConnection = npcFolder.ChildAdded:Connect(function(child)
		if child.Name == "Destination" and child:IsA("Vector3Value") then
			print(string.format("[TD_CLIENT_MGR] NPC %s: Destination value added dynamically", npcID))

			local destConnection = child.Changed:Connect(function(newDest)
				if SimulatedNPCs[npcID] and npcData.IsAlive then
					if newDest == Vector3.zero then
						print(string.format("[TD_CLIENT_MGR] NPC %s: Destination cleared by server", npcID))
						npcData.Destination = nil
					else
						print(string.format("[TD_CLIENT_MGR] NPC %s: New destination from server: %s", npcID, tostring(newDest)))
						npcData.Destination = newDest
					end
				end
			end)
			table.insert(npcData.Connections, destConnection)

			-- Apply initial value if set
			if child.Value ~= Vector3.zero then
				print(string.format("[TD_CLIENT_MGR] NPC %s: Initial destination from dynamically added value: %s", npcID, tostring(child.Value)))
				npcData.Destination = child.Value
			end
		end
	end)
	table.insert(npcData.Connections, childAddedConnection)

	-- Initialize simulation logic
	if ClientNPCSimulator then
		ClientNPCSimulator.InitializeNPC(npcData)
	end

	-- Setup sight detection
	if ClientSightDetector then
		ClientSightDetector.SetupSightDetector(npcData)
	end

	-- Link npcData to animator if visual model already exists (for UseAnimationController support)
	if ClientPhysicsRenderer then
		local visualModel = ClientPhysicsRenderer.GetVisualModel(npcID)
		if visualModel then
			npcData.VisualModel = visualModel

			-- Link to NPCAnimator for animation state sync
			local NPCAnimator = script.Parent:FindFirstChild("NPCAnimator")
			if NPCAnimator then
				local animator = require(NPCAnimator)
				animator.LinkNPCData(visualModel, npcData)
			end
		end
	end
end

--[[
	Stop simulating an NPC
]]
function ClientNPCManager.StopSimulation(npcID)
	local npcData = SimulatedNPCs[npcID]
	if not npcData then
		return
	end

	-- Cleanup connections (Destination watcher, etc.)
	if npcData.Connections then
		for _, connection in pairs(npcData.Connections) do
			if typeof(connection) == "RBXScriptConnection" then
				pcall(function()
					connection:Disconnect()
				end)
			end
		end
		npcData.Connections = {}
	end

	-- Cleanup sight detection
	if ClientSightDetector then
		ClientSightDetector.CleanupSightDetector(npcData)
	end

	-- Cleanup simulation
	if ClientNPCSimulator then
		ClientNPCSimulator.CleanupNPC(npcData)
	end

	-- Release on server
	NPC_Service:ReleaseNPC(npcID)

	-- Remove from tracking
	SimulatedNPCs[npcID] = nil
	LastSyncTimes[npcID] = nil
end

--[[
	Main simulation step - called every RenderStepped (primary) or Heartbeat (fallback)

	SINGLE-WRITER PATTERN:
	-----------------------
	This is the ONLY place that updates position for NPCs we're simulating.
	npcData.Position is the authoritative source of truth.

	WRITE ORDER:
	1. ClientNPCSimulator updates npcData.Position (in-memory)
	2. We write npcData.Position to positionValue.Value (ReplicatedStorage)
	3. ClientPhysicsRenderer reads positionValue.Value and syncs visual model

	RACE CONDITION PROTECTION:
	---------------------------
	Network updates from other clients are BLOCKED by ListenForPositionUpdates()
	check: `if not SimulatedNPCs[npcID]`. This ensures we never overwrite our
	local simulation with stale network data.
]]
function ClientNPCManager.SimulationStep(deltaTime)
	for npcID, npcData in pairs(SimulatedNPCs) do
		-- Check if NPC still exists
		if not npcData.Folder or not npcData.Folder.Parent then
			ClientNPCManager.StopSimulation(npcID)
			continue
		end

		-- Check if NPC is still alive
		local isAliveValue = npcData.Folder:FindFirstChild("IsAlive")
		if isAliveValue and not isAliveValue.Value then
			npcData.IsAlive = false
			continue
		end

		-- Run simulation step (updates npcData.Position in-memory)
		if ClientNPCSimulator then
			ClientNPCSimulator.SimulateNPC(npcData, deltaTime)
		end

		-- Write simulated position to ReplicatedStorage (SINGLE WRITER)
		-- This is the ONLY place that writes position for simulated NPCs
		local positionValue = npcData.Folder:FindFirstChild("Position")
		if positionValue then
			positionValue.Value = npcData.Position
		end

		-- Write simulated orientation to ReplicatedStorage
		local orientationValue = npcData.Folder:FindFirstChild("Orientation")
		if orientationValue and npcData.Orientation then
			orientationValue.Value = npcData.Orientation
		end
	end
end

--[[
	Distance check loop - handles simulation handoff
]]
function ClientNPCManager.DistanceCheckLoop()
	local checkInterval = OptimizationConfig.ClientSimulation.POSITION_SYNC_INTERVAL

	while true do
		task.wait(checkInterval)

		local character = LocalPlayer.Character
		if not character or not character.PrimaryPart then
			continue
		end

		local playerPos = character.PrimaryPart.Position
		local simulationDistance = OptimizationConfig.ClientSimulation.SIMULATION_DISTANCE
		local handoffDistance = simulationDistance * 1.5 -- Hysteresis

		-- Check for handoff (NPCs we should release)
		for npcID, npcData in pairs(SimulatedNPCs) do
			local distance = (playerPos - npcData.Position).Magnitude

			if distance > handoffDistance then
				ClientNPCManager.ReleaseNPC(npcID)
			end
		end

		-- Check for new NPCs we should simulate
		local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
		if activeNPCsFolder then
			for _, npcFolder in pairs(activeNPCsFolder:GetChildren()) do
				local npcID = npcFolder.Name

				-- Skip if already simulating
				if SimulatedNPCs[npcID] then
					continue
				end

				-- Check if we should pick this up
				if ClientNPCManager.ShouldSimulateNPC(npcFolder) then
					ClientNPCManager.StartSimulation(npcFolder)
				end
			end
		end
	end
end

--[[
	Position sync loop - sends position updates to server
]]
function ClientNPCManager.PositionSyncLoop()
	local syncInterval = OptimizationConfig.ClientSimulation.POSITION_SYNC_INTERVAL

	while true do
		task.wait(syncInterval)

		for npcID, npcData in pairs(SimulatedNPCs) do
			if npcData.IsAlive and npcData.Position then
				-- Debug: print position sync
				if not npcData._lastSyncDebugPrint or tick() - npcData._lastSyncDebugPrint > 3 then
					print(string.format("[TD_CLIENT_SYNC] NPC %s: Sending position to server: %s", npcID, tostring(npcData.Position)))
					npcData._lastSyncDebugPrint = tick()
				end

				-- Send position update to server
				NPC_Service:UpdateNPCPosition(npcID, npcData.Position, npcData.Orientation)
				LastSyncTimes[npcID] = tick()
			end
		end
	end
end

--[[
	Listen for position updates from other clients

	RACE CONDITION PREVENTION:
	--------------------------
	This function MUST only update NPCs that we are NOT simulating.
	If we update an NPC we're simulating, it causes position "blinking":

	Frame 1: Our simulation updates npcData.Position to (10, 3, 10)
	Frame 2: Network update arrives with old position (5, 3, 5)
	Frame 3: Visual model "blinks" backward to old position

	The check `if not SimulatedNPCs[npcID]` prevents this race condition.
]]
function ClientNPCManager.ListenForPositionUpdates()
	NPC_Service.NPCPositionUpdated:Connect(function(npcID, newPosition, newOrientation)
		-- CRITICAL: Only update if we're NOT simulating this NPC ourselves
		-- This prevents race conditions where network updates overwrite local simulation
		if not SimulatedNPCs[npcID] then
			ClientNPCManager.UpdateRemoteNPCPosition(npcID, newPosition, newOrientation)
		end
		-- If we ARE simulating this NPC, ignore network updates completely
		-- Our local simulation is the source of truth
	end)
end

--[[
	Update position of NPC simulated by another client
]]
function ClientNPCManager.UpdateRemoteNPCPosition(npcID, newPosition, newOrientation)
	-- Warn if trying to update simulated NPC (should never happen)
	if SimulatedNPCs[npcID] then
		warn("[ClientNPCManager] RACE CONDITION! UpdateRemoteNPCPosition called for simulated NPC:", npcID)
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

	-- Update position value (renderer watches this)
	local positionValue = npcFolder:FindFirstChild("Position")
	if positionValue then
		positionValue.Value = newPosition
	end

	-- Update orientation if provided
	if newOrientation then
		local orientationValue = npcFolder:FindFirstChild("Orientation")
		if orientationValue then
			orientationValue.Value = newOrientation
		end
	end
end

--[[
	Listen for orphaned NPCs broadcast
]]
function ClientNPCManager.ListenForOrphanedNPCs()
	NPC_Service.NPCsOrphaned:Connect(function(npcPositions)
		ClientNPCManager.HandleOrphanedNPCs(npcPositions)
	end)
end

--[[
	Handle orphaned NPCs - claim those within range
]]
function ClientNPCManager.HandleOrphanedNPCs(npcPositions)
	local character = LocalPlayer.Character
	if not character or not character.PrimaryPart then
		return
	end

	local playerPos = character.PrimaryPart.Position
	local simulationDistance = OptimizationConfig.ClientSimulation.SIMULATION_DISTANCE
	local maxSimulated = OptimizationConfig.ClientSimulation.MAX_SIMULATED_PER_CLIENT

	for npcID, npcPos in pairs(npcPositions) do
		local distance = (playerPos - npcPos).Magnitude

		-- Only attempt to claim if within simulation distance
		if distance <= simulationDistance then
			-- Check if we have capacity
			local currentCount = 0
			for _ in pairs(SimulatedNPCs) do
				currentCount = currentCount + 1
			end

			if currentCount < maxSimulated then
				-- Distance-based delay: closer clients claim faster
				local claimDelay = CLAIM_DELAY_BASE + (distance * CLAIM_DELAY_PER_STUD)

				task.delay(claimDelay, function()
					ClientNPCManager.AttemptClaimNPC(npcID, npcPos)
				end)
			end
		end
	end
end

--[[
	Listen for jump triggers from server
]]
function ClientNPCManager.ListenForJumpTriggers()
	NPC_Service.NPCJumpTriggered:Connect(function(npcID)
		-- Only trigger jump if we're simulating this NPC
		local npcData = SimulatedNPCs[npcID]
		if npcData then
			ClientNPCSimulator.TriggerJump(npcData)
		end
	end)
end

--[[
	Attempt to claim an orphaned NPC
]]
function ClientNPCManager.AttemptClaimNPC(npcID, lastKnownPos)
	-- Check if already being simulated by us
	if SimulatedNPCs[npcID] then
		return
	end

	-- Check if NPC still exists
	local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
	if not activeNPCsFolder then
		return
	end

	local npcFolder = activeNPCsFolder:FindFirstChild(npcID)
	if not npcFolder then
		return
	end

	-- Check if already claimed by another client (position changed)
	local positionValue = npcFolder:FindFirstChild("Position")
	if positionValue then
		local currentPos = positionValue.Value
		if (currentPos - lastKnownPos).Magnitude > 1 then
			-- Another client already claimed and moved it
			return
		end
	end

	-- Start simulating
	ClientNPCManager.StartSimulation(npcFolder)
end

--[[
	Release an NPC (called when moving away)
]]
function ClientNPCManager.ReleaseNPC(npcID)
	if SimulatedNPCs[npcID] then
		NPC_Service:ReleaseNPC(npcID)
		ClientNPCManager.StopSimulation(npcID)
	end
end

--[[
	Get simulated NPC data
]]
function ClientNPCManager.GetSimulatedNPC(npcID)
	return SimulatedNPCs[npcID]
end

--[[
	Check if we're simulating an NPC
]]
function ClientNPCManager.IsSimulating(npcID)
	return SimulatedNPCs[npcID] ~= nil
end

--[[
	Get all simulated NPCs
]]
function ClientNPCManager.GetAllSimulatedNPCs()
	return SimulatedNPCs
end

function ClientNPCManager.Start()
	-- Wait for dependencies to be loaded before initializing
	-- This prevents race condition where Initialize() tries to use NPC_Service before it's loaded
	task.spawn(function()
		-- Wait for NPC_Service to be available
		while not NPC_Service do
			task.wait()
		end

		-- Now safe to initialize
		ClientNPCManager.Initialize()
	end)
end

function ClientNPCManager.Init()
	-- Load dependencies
	OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

	-- Wait for Knit to start before getting services
	task.spawn(function()
		Knit.OnStart():await()
		NPC_Service = Knit.GetService("NPC_Service")

		-- Load other components (they may not exist yet)
		local componentsFolder = script.Parent
		local simulatorModule = componentsFolder:FindFirstChild("ClientNPCSimulator")
		if simulatorModule then
			ClientNPCSimulator = require(simulatorModule)
		end

		local rendererModule = componentsFolder:FindFirstChild("ClientPhysicsRenderer")
		if rendererModule then
			ClientPhysicsRenderer = require(rendererModule)
		end

		local sightDetectorModule = componentsFolder:FindFirstChild("ClientSightDetector")
		if sightDetectorModule then
			ClientSightDetector = require(sightDetectorModule)
		end
	end)
end

return ClientNPCManager
