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

	-- Start simulation loop
	RunService.Heartbeat:Connect(function(deltaTime)
		ClientNPCManager.SimulationStep(deltaTime)
	end)

	-- Start distance check loop
	task.spawn(ClientNPCManager.DistanceCheckLoop)

	-- Start position sync loop
	task.spawn(ClientNPCManager.PositionSyncLoop)

	-- Listen for position updates from server
	ClientNPCManager.ListenForPositionUpdates()

	-- Listen for orphaned NPCs
	ClientNPCManager.ListenForOrphanedNPCs()

	print("[ClientNPCManager] Initialized - watching for UseAnimationController NPCs")
end

--[[
	Handle when a new NPC is added to ReplicatedStorage.ActiveNPCs
]]
-- [NPCADBG] Debug: only trace first NPC
local NPCADBG_TrackedNPC = nil
ClientNPCManager.NPCADBG_TrackedNPC = nil -- Exposed for other modules

function ClientNPCManager.OnNPCAdded(npcFolder)
	local npcID = npcFolder.Name

	-- Track first NPC only
	local isTracked = (NPCADBG_TrackedNPC == nil)
	if isTracked then
		NPCADBG_TrackedNPC = npcID
		ClientNPCManager.NPCADBG_TrackedNPC = npcID -- Expose for other modules
		print("[NPCADBG] === TRACKING NPC:", npcID, "===")
	end

	-- Wait a moment for all values to replicate
	task.wait(0.1)

	-- Notify renderer FIRST so visual model exists before simulation starts
	-- This ensures height offset can be calculated from actual model
	if ClientPhysicsRenderer then
		if isTracked then print("[NPCADBG] Calling ClientPhysicsRenderer.OnNPCAdded") end
		ClientPhysicsRenderer.OnNPCAdded(npcID)
	end

	-- Check if we should simulate this NPC (after renderer has created visual model)
	local shouldSimulate = ClientNPCManager.ShouldSimulateNPC(npcFolder)
	if isTracked then print("[NPCADBG] ShouldSimulateNPC:", shouldSimulate) end
	if shouldSimulate then
		if isTracked then print("[NPCADBG] Calling StartSimulation") end
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
		Destination = nil,
		Pathfinding = nil,
		MovementState = "Idle",

		-- Target state
		CurrentTarget = nil,
		TargetInSight = false,

		-- Jump state
		IsJumping = false,
		JumpVelocity = 0,

		-- Visual model reference (set by renderer)
		VisualModel = nil,
	}

	SimulatedNPCs[npcID] = npcData
	LastSyncTimes[npcID] = tick()

	local isTracked = (NPCADBG_TrackedNPC == npcID)
	if isTracked then print("[NPCADBG] Added npcData to SimulatedNPCs") end

	-- Initialize simulation logic
	if ClientNPCSimulator then
		ClientNPCSimulator.InitializeNPC(npcData)
	end

	-- Link npcData to animator if visual model already exists (for UseAnimationController support)
	if ClientPhysicsRenderer then
		local visualModel = ClientPhysicsRenderer.GetVisualModel(npcID)
		if isTracked then print("[NPCADBG] visualModel exists:", visualModel ~= nil) end
		if visualModel then
			npcData.VisualModel = visualModel

			-- Link to NPCAnimator for animation state sync
			local NPCAnimator = script.Parent:FindFirstChild("NPCAnimator")
			if NPCAnimator then
				local animator = require(NPCAnimator)
				if isTracked then print("[NPCADBG] Calling LinkNPCData from StartSimulation") end
				animator.LinkNPCData(visualModel, npcData)
			end
		else
			if isTracked then print("[NPCADBG] No visual model yet - LinkNPCData skipped here") end
		end
	end

	print("[ClientNPCManager] Started simulating NPC:", npcID)
end

--[[
	Stop simulating an NPC
]]
function ClientNPCManager.StopSimulation(npcID)
	local npcData = SimulatedNPCs[npcID]
	if not npcData then
		return
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

	print("[ClientNPCManager] Stopped simulating NPC:", npcID)
end

--[[
	Main simulation step - called every Heartbeat
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

		-- Run simulation step
		if ClientNPCSimulator then
			ClientNPCSimulator.SimulateNPC(npcData, deltaTime)
		end

		-- Update position in folder for renderer to read
		local positionValue = npcData.Folder:FindFirstChild("Position")
		if positionValue then
			positionValue.Value = npcData.Position
		end

		-- Update orientation in folder for renderer to read (every frame for smooth turning)
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
				-- Send position update to server
				NPC_Service:UpdateNPCPosition(npcID, npcData.Position, npcData.Orientation)
				LastSyncTimes[npcID] = tick()
			end
		end
	end
end

--[[
	Listen for position updates from other clients
]]
function ClientNPCManager.ListenForPositionUpdates()
	NPC_Service.NPCPositionUpdated:Connect(function(npcID, newPosition, newOrientation)
		-- Only update if we're NOT simulating this NPC ourselves
		if not SimulatedNPCs[npcID] then
			ClientNPCManager.UpdateRemoteNPCPosition(npcID, newPosition, newOrientation)
		end
	end)
end

--[[
	Update position of NPC simulated by another client
]]
function ClientNPCManager.UpdateRemoteNPCPosition(npcID, newPosition, newOrientation)
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
	-- Initialize the manager
	ClientNPCManager.Initialize()
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
	end)
end

return ClientNPCManager
