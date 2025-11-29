# UseAnimationController - Client-Side Physics Optimization Plan

### This is a work-in-progress documentation plan, it is not implemented yet.

### Duplicate source file:

## 📋 **Overview**

This document outlines the implementation of `UseAnimationController`, an **advanced optimization feature** that offloads NPC physics and pathfinding calculations entirely to the client. This approach can support **1000+ NPCs** with minimal lag by eliminating server-side physics simulation.

---

## ⚠️ **CRITICAL WARNINGS**

### **Security Risk: Client Authority**

> **NOTE**: When `UseAnimationController` is enabled, the client has full authority over NPC pathfinding and movement.
>
> **Anti-exploit validation has been intentionally REMOVED** from this system because:
>
> - Network latency (ping) causes many false positives in position validation
> - Player experience is more important than preventing rare exploit scenarios
> - False positives would negatively impact legitimate users with high ping
> - Position validation checks (max speed, teleport detection) are too strict for real-world network conditions
>
> **Design Decision**: We prioritize smooth gameplay for all users over strict anti-cheat measures.
>
> - Use this for non-critical NPCs where position accuracy isn't gameplay-critical
> - Health remains server-authoritative to maintain gameplay integrity
> - For critical NPCs, consider using traditional server-authoritative movement instead

### **Advanced Configuration**

> **WARNING**: This is an **advanced optimization** that requires:
>
> - Deep understanding of Roblox replication
> - Careful testing across multiple clients
> - Game-specific tuning for best results
> - Acceptance of client authority over positions (no anti-exploit validation)
> - **Not recommended for beginners**

### **No Server Physics**

> **WARNING**: When enabled, the server has **NO physics representation** of NPCs:
>
> - No HumanoidRootPart on server
> - No collision detection on server
> - Only position and health data stored on server (hybrid approach)
> - Client handles all rendering and physics
> - **Significantly reduces server load but loses server authority over positions**
> - Health remains server-authoritative to maintain gameplay integrity

---

## 🎯 **Core Concept**

### **Traditional Approach (Current System)**

```
SERVER:
├── Full NPC Model (HumanoidRootPart + Humanoid)
├── Physics simulation
├── Pathfinding calculations
└── Movement logic

CLIENT:
├── Visual model (welded to server HumanoidRootPart)
├── Animations
└── Rendering
```

### **UseAnimationController Approach (New)**

```
SERVER:
├── Position data (Vector3) - updated by client
├── Health data (Number) - server authority
├── Basic state (alive/dead, target)
└── Minimal replication overhead

CLIENT:
├── Full physics simulation
├── Pathfinding calculations (using NoobPath)
├── Jump simulation
├── Movement logic
├── Visual rendering (only when near)
├── Animations
└── Health bar display (reads from server)
```

**Key Difference**: Client handles **physics/pathfinding**, server stores positions and health.

---

## 🏗️ **Architecture Changes**

### **1. Server-Side Changes**

#### **1.1: Minimal Server Representation**

Instead of creating a full NPC model with HumanoidRootPart + Humanoid, create a **data-only structure**:

```lua
-- NEW: Server-side NPC data (no physical model)
{
    -- Identity
    ID: string,                    -- Unique identifier
    Name: string,                  -- NPC name

    -- Position (replicated from client)
    Position: Vector3,             -- Current position (updated by client)
    Orientation: CFrame?,          -- Current orientation (optional)

    -- State (server authority)
    IsAlive: boolean,              -- Is NPC alive
    Health: number,                -- Current health (server authority)
    MaxHealth: number,             -- Maximum health
    CurrentTarget: Model?,         -- Current target (for validation)

    -- Configuration
    Config: {
        ModelPath: Instance,       -- Path to character model
        MaxHealth: number,
        WalkSpeed: number,
        SightRange: number,
        SightMode: string,
        MovementMode: string,
        -- ... other config
    },

    -- Client Tracking
    OwningClient: Player?,         -- Which client is simulating this NPC
    LastUpdateTime: number,        -- Last position update timestamp

    -- Lifecycle
    SpawnTime: number,
    CleanedUp: boolean,
}
```

#### **1.2: Server Storage Structure**

Store NPC data in `ReplicatedStorage` folder for client access:

```lua
-- Server creates data structure in ReplicatedStorage
game.ReplicatedStorage.ActiveNPCs/
├── NPC_12345/
│   ├── Position: Vector3Value
│   ├── Health: NumberValue           -- Server authority
│   ├── MaxHealth: NumberValue
│   ├── IsAlive: BoolValue
│   ├── CurrentTarget: ObjectValue
│   └── Config: StringValue (JSON-encoded)
```

#### **1.3: Server Responsibilities**

The server's role is **drastically reduced**:

- ✅ Store NPC configuration data
- ✅ Store current NPC positions (updated by clients)
- ✅ Store and manage NPC health (server authority for gameplay integrity)
- ✅ Handle NPC spawning/despawning
- ✅ Handle critical gameplay events (e.g., death, rewards)
- ❌ NO physics simulation
- ❌ NO pathfinding
- ❌ NO movement logic

**Important**: Even though physics are client-side, **health management remains on the server** to maintain gameplay integrity. This allows NPCs to take damage while still benefiting from client-side physics optimization.

---

### **2. Client-Side Changes**

---

#### **Important: Two Rendering Systems**

The NPC system supports **two different rendering approaches**, each with its own renderer:

| Feature             | NPCRenderer.lua                     | ClientPhysicsRenderer.lua           |
| ------------------- | ----------------------------------- | ----------------------------------- |
| **Purpose**         | Render visuals on server NPCs       | Render full NPCs from position data |
| **When Used**       | `UseAnimationController = false`    | `UseAnimationController = true`     |
| **Server Model**    | Full NPC with HumanoidRootPart      | No physical model (data only)       |
| **What It Renders** | Visual parts welded to server model | Complete standalone model           |
| **Position Source** | Server NPC's HumanoidRootPart       | ReplicatedStorage position data     |
| **Collision**       | Server handles                      | No collision (visual only)          |
| **Physics**         | Server-side                         | Client-side                         |
| **Health Display**  | Optional client visuals             | Reads from server health values     |

**Why Two Systems?**

- **Traditional Approach**: Server has full physics control, client renders visuals on top
- **Client Physics Approach**: Server stores position/health only, client handles everything else
- Both systems can run simultaneously (different NPCs can use different approaches)
- `ClientPhysicsRenderer` is specifically for the advanced optimization feature

---

#### **2.1: Client-Side NPC Manager**

**Location**: `NPC_Controller/Components/Others/ClientNPCManager.lua`

**Responsibilities**:

- Monitor `ReplicatedStorage.ActiveNPCs` for new NPCs
- Assign NPCs to clients based on distance
- Handle NPC creation, simulation, and cleanup
- Synchronize positions back to server

```lua
local ClientNPCManager = {}

-- Track which NPCs this client is simulating
local SimulatedNPCs = {}  -- [npcID] = npcData

-- Track which NPCs are visible (rendered)
local RenderedNPCs = {}   -- [npcID] = visualModel

function ClientNPCManager.Init()
    -- Watch for new NPCs in ReplicatedStorage
    local activeNPCsFolder = ReplicatedStorage:WaitForChild("ActiveNPCs")

    activeNPCsFolder.ChildAdded:Connect(function(npcFolder)
        ClientNPCManager.OnNPCAdded(npcFolder)
    end)

    -- Handle existing NPCs
    for _, npcFolder in activeNPCsFolder:GetChildren() do
        ClientNPCManager.OnNPCAdded(npcFolder)
    end

    -- Start simulation loop
    RunService.Heartbeat:Connect(ClientNPCManager.SimulationStep)

    -- Start distance check loop
    task.spawn(ClientNPCManager.DistanceCheckLoop)
end

function ClientNPCManager.OnNPCAdded(npcFolder)
    local npcID = npcFolder.Name

    -- Determine if this client should simulate this NPC
    local shouldSimulate = ClientNPCManager.ShouldSimulateNPC(npcFolder)

    if shouldSimulate then
        ClientNPCManager.StartSimulation(npcFolder)
    else
        -- Just render if nearby, don't simulate
        ClientNPCManager.CheckRenderDistance(npcFolder)
    end
end

function ClientNPCManager.ShouldSimulateNPC(npcFolder): boolean
    -- Distribute NPCs across clients based on distance
    -- Closest client simulates the NPC

    local position = npcFolder.Position.Value
    local localPlayer = Players.LocalPlayer

    if not localPlayer.Character or not localPlayer.Character.PrimaryPart then
        return false
    end

    local distance = (localPlayer.Character.PrimaryPart.Position - position).Magnitude

    -- Simple distribution: closest client simulates
    -- TODO: More advanced load balancing
    return distance <= 200  -- Simulate NPCs within 200 studs
end

return ClientNPCManager
```

#### **2.2: Client-Side Pathfinding (NoobPath)**

**Location**: `NPC_Controller/Components/Others/ClientPathfinding.lua`

**Purpose**: Handle all pathfinding on the client using **NoobPath** (same library as server-side PathfindingManager)

**Note**: We use NoobPath instead of raw PathfindingService because it provides:

- Better jump handling
- Timeout detection
- Visualization support for debugging
- Error handling built-in
- Similar API to server-side PathfindingManager

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientPathfinding = {}

-- Import NoobPath (same as server-side PathfindingManager)
local NoobPath = require(ReplicatedStorage.SharedSource.Utilities.Pathfinding.NoobPath)

--[[
    Create NoobPath instance for client-side NPC
    Similar to PathfindingManager.CreatePath but for client simulation

    @param npcData table - Client-side NPC data
    @param visualModel Model - The visual NPC model with Humanoid
    @return NoobPath - Configured pathfinding instance
]]
function ClientPathfinding.CreatePath(npcData, visualModel)
    local humanoid = visualModel:FindFirstChild("Humanoid")
    if not humanoid then
        warn("[ClientPathfinding] Visual model missing Humanoid")
        return nil
    end

    -- Create NoobPath instance (same pattern as PathfindingManager)
    local path = NoobPath.Humanoid(visualModel, {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,  -- Client handles jumps
        WaypointSpacing = 4,
        Costs = {
            Water = math.huge,  -- Avoid water
        },
    })

    -- Configure path settings
    path.Timeout = true  -- Enable timeout detection
    path.Speed = humanoid.WalkSpeed

    -- Show visualizer in debug mode (optional)
    local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.RenderConfig)
    if RenderConfig.DEBUG_MODE then
        path.Visualize = true
    end

    -- Setup automatic speed synchronization
    humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if path then
            path.Speed = humanoid.WalkSpeed
        end
    end)

    -- Setup error handling
    path.Error:Connect(function(errorType)
        ClientPathfinding.HandlePathError(npcData, errorType)
    end)

    -- Setup trapped detection (stuck/blocked)
    path.Trapped:Connect(function(reason)
        ClientPathfinding.HandlePathBlocked(npcData, visualModel, reason)
    end)

    return path
end

--[[
    Handle pathfinding errors
]]
function ClientPathfinding.HandlePathError(npcData, errorType)
    if errorType == "ComputationError" then
        warn("[ClientPathfinding] Computation error for NPC:", npcData.ID)
        npcData.Destination = nil
    elseif errorType == "TargetUnreachable" then
        npcData.Destination = nil
    end
end

--[[
    Handle NPC being blocked/stuck
    Client-side jump handling
]]
function ClientPathfinding.HandlePathBlocked(npcData, visualModel, reason)
    local humanoid = visualModel:FindFirstChild("Humanoid")
    if not humanoid then return end

    if reason == "ReachTimeout" then
        -- Try jumping to unstuck
        humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
    elseif reason == "ReachFailed" then
        -- Clear destination and retry
        npcData.Destination = nil
    end
end

--[[
    Run pathfinding to destination
    Similar to PathfindingManager.RunPath
]]
function ClientPathfinding.RunPath(npcData, visualModel, destination)
    if not npcData.Pathfinding then
        npcData.Pathfinding = ClientPathfinding.CreatePath(npcData, visualModel)
    end

    if npcData.Pathfinding then
        npcData.Pathfinding:Run(destination)
    end
end

--[[
    Stop pathfinding
]]
function ClientPathfinding.StopPath(npcData)
    if npcData.Pathfinding then
        npcData.Pathfinding:Stop()
    end
end

return ClientPathfinding
```

#### **2.3: Client-Side Jump Simulation**

**Location**: `NPC_Controller/Components/Others/ClientJumpSimulator.lua`

**Purpose**: Simulate realistic jump physics on the client

```lua
local ClientJumpSimulator = {}

local JUMP_POWER = 50  -- Default jump power

function ClientJumpSimulator.SimulateJump(npcData)
    local jumpPower = npcData.Config.JumpPower or JUMP_POWER
    local gravity = workspace.Gravity  -- Use workspace gravity for consistency
    local currentVelocity = Vector3.new(0, jumpPower, 0)

    local startPosition = npcData.Position
    local startTime = tick()

    -- Simulate jump arc
    while currentVelocity.Y > 0 or not ClientJumpSimulator.IsOnGround(npcData.Position) do
        local deltaTime = RunService.Heartbeat:Wait()

        -- Apply gravity
        currentVelocity = currentVelocity - Vector3.new(0, gravity * deltaTime, 0)

        -- Update position
        local newPosition = npcData.Position + (currentVelocity * deltaTime)

        -- Raycast to check for ground
        local rayResult = workspace:Raycast(
            newPosition + Vector3.new(0, 1, 0),
            Vector3.new(0, -2, 0)
        )

        if rayResult then
            -- Landed on ground
            newPosition = rayResult.Position + Vector3.new(0, 0.5, 0)
            break
        end

        -- Update NPC position
        ClientJumpSimulator.UpdatePosition(npcData, newPosition)

        -- Safety timeout
        if tick() - startTime > 3 then
            warn("[ClientJumpSimulator] Jump timeout")
            break
        end
    end
end

function ClientJumpSimulator.IsOnGround(position: Vector3): boolean
    local rayResult = workspace:Raycast(
        position + Vector3.new(0, 0.5, 0),
        Vector3.new(0, -1, 0)
    )

    return rayResult ~= nil
end

function ClientJumpSimulator.UpdatePosition(npcData, newPosition: Vector3)
    npcData.Position = newPosition

    -- Update in ReplicatedStorage for server sync
    local npcFolder = ReplicatedStorage.ActiveNPCs:FindFirstChild(npcData.ID)
    if npcFolder and npcFolder:FindFirstChild("Position") then
        npcFolder.Position.Value = newPosition
    end
end

return ClientJumpSimulator
```

#### **2.4: Client Physics Renderer**

**Location**: `NPC_Controller/Components/Others/ClientPhysicsRenderer.lua`

**Purpose**: Render full NPC models for client-physics NPCs (UseAnimationController = true)

**⚠️ Note**: This is **different** from the existing `NPCRenderer.lua`:

- **NPCRenderer.lua** - Renders visuals on top of server-physics NPCs (traditional approach)
- **ClientPhysicsRenderer.lua** - Renders full NPCs from position data only (no server model)

Both systems coexist and serve different purposes based on `UseAnimationController` setting.

```lua
local ClientPhysicsRenderer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RenderConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.RenderConfig)

local RenderedNPCs = {}  -- [npcID] = visualModel

function ClientPhysicsRenderer.Init()
    task.spawn(ClientPhysicsRenderer.DistanceCheckLoop)
end

function ClientPhysicsRenderer.DistanceCheckLoop()
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer

    while task.wait(RenderConfig.DISTANCE_CHECK_INTERVAL) do
        -- Respect global rendering toggle
        if not RenderConfig.ENABLED then
            continue
        end

        if not localPlayer.Character or not localPlayer.Character.PrimaryPart then
            continue
        end

        local playerPos = localPlayer.Character.PrimaryPart.Position

        -- Check all NPCs in ReplicatedStorage
        local activeNPCsFolder = ReplicatedStorage:FindFirstChild("ActiveNPCs")
        if not activeNPCsFolder then continue end

        for _, npcFolder in activeNPCsFolder:GetChildren() do
            local npcID = npcFolder.Name
            local positionValue = npcFolder:FindFirstChild("Position")

            if positionValue then
                local npcPos = positionValue.Value
                local distance = (playerPos - npcPos).Magnitude

                local isRendered = RenderedNPCs[npcID] ~= nil

                -- Render if within range and not rendered
                if distance <= RenderConfig.MAX_RENDER_DISTANCE and not isRendered then
                    -- Check if we haven't exceeded max rendered NPCs
                    local renderedCount = 0
                    for _ in pairs(RenderedNPCs) do
                        renderedCount = renderedCount + 1
                    end

                    if renderedCount < RenderConfig.MAX_RENDERED_NPCS then
                        ClientPhysicsRenderer.RenderNPC(npcFolder)
                    end
                end

                -- Unrender if out of range and rendered (hysteresis: 1.3x render distance)
                local unrenderDistance = RenderConfig.MAX_RENDER_DISTANCE * 1.3
                if distance > unrenderDistance and isRendered then
                    ClientPhysicsRenderer.UnrenderNPC(npcID)
                end
            end
        end
    end
end

function ClientPhysicsRenderer.RenderNPC(npcFolder)
    local npcID = npcFolder.Name
    local configJSON = npcFolder:FindFirstChild("Config")

    if not configJSON then
        warn("[ClientPhysicsRenderer] No config found for NPC:", npcID)
        return
    end

    local config = HttpService:JSONDecode(configJSON.Value)

    -- Clone visual model
    local originalModel = config.ModelPath
    local visualModel = originalModel:Clone()
    visualModel.Name = npcID .. "_Visual"

    -- Make non-collidable (client-side visuals only)
    for _, descendant in visualModel:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
        end
    end

    -- Parent to workspace
    visualModel.Parent = workspace.Characters.NPCs

    -- Track rendered NPC
    RenderedNPCs[npcID] = visualModel

    -- Setup position sync
    ClientPhysicsRenderer.SetupPositionSync(npcFolder, visualModel)

    -- Setup animator
    ClientPhysicsRenderer.SetupAnimator(visualModel)
end

function ClientPhysicsRenderer.SetupPositionSync(npcFolder, visualModel)
    local positionValue = npcFolder:FindFirstChild("Position")
    local healthValue = npcFolder:FindFirstChild("Health")
    local maxHealthValue = npcFolder:FindFirstChild("MaxHealth")

    if positionValue then
        -- Initial position
        visualModel:PivotTo(CFrame.new(positionValue.Value))

        -- Track position updates
        positionValue.Changed:Connect(function(newPosition)
            visualModel:PivotTo(CFrame.new(newPosition))
        end)
    end

    -- Setup health bar (if needed)
    if healthValue and maxHealthValue then
        ClientPhysicsRenderer.SetupHealthBar(visualModel, healthValue, maxHealthValue)
    end
end

function ClientPhysicsRenderer.SetupHealthBar(visualModel, healthValue, maxHealthValue)
    -- Create health bar UI above NPC
    -- This reads from server-authoritative health values

    local billboardGui = Instance.new("BillboardGui")
    billboardGui.Name = "HealthBar"
    billboardGui.Size = UDim2.new(4, 0, 0.5, 0)
    billboardGui.StudsOffset = Vector3.new(0, 3, 0)
    billboardGui.AlwaysOnTop = true
    billboardGui.Parent = visualModel.PrimaryPart

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 1, 0)
    frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    frame.BorderSizePixel = 0
    frame.Parent = billboardGui

    local healthBar = Instance.new("Frame")
    healthBar.Name = "Health"
    healthBar.Size = UDim2.new(healthValue.Value / maxHealthValue.Value, 0, 1, 0)
    healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)
    healthBar.BorderSizePixel = 0
    healthBar.Parent = frame

    -- Update health bar when server updates health
    healthValue.Changed:Connect(function(newHealth)
        local percentage = math.clamp(newHealth / maxHealthValue.Value, 0, 1)
        healthBar.Size = UDim2.new(percentage, 0, 1, 0)

        -- Color gradient: green -> yellow -> red
        if percentage > 0.5 then
            healthBar.BackgroundColor3 = Color3.fromRGB(0, 255, 0)  -- Green
        elseif percentage > 0.25 then
            healthBar.BackgroundColor3 = Color3.fromRGB(255, 255, 0)  -- Yellow
        else
            healthBar.BackgroundColor3 = Color3.fromRGB(255, 0, 0)  -- Red
        end
    end)
end

function ClientPhysicsRenderer.UnrenderNPC(npcID)
    local visualModel = RenderedNPCs[npcID]

    if visualModel then
        visualModel:Destroy()
        RenderedNPCs[npcID] = nil
    end
end

return ClientPhysicsRenderer
```

---

### **3. Optimized Position Sync System**

#### **3.1: Overview**

The position sync system is **highly optimized** to minimize network traffic and scale to 1000+ NPCs by using **distance-based broadcasting**.

**Key Optimizations:**

1. **Client → Server**: Client sends position updates via Knit service method at configurable intervals (`POSITION_SYNC_INTERVAL`)
2. **Server → Nearby Clients Only**: Server broadcasts position updates **ONLY** to clients within `BROADCAST_DISTANCE` (not all clients)
3. **Result**: 70-95% network traffic reduction compared to broadcasting to all clients
4. **Frequency Control**: Updates fire based on `POSITION_SYNC_INTERVAL` config (default: 0.5 seconds)
5. **No Position Validation**: Server accepts all position updates (no anti-exploit checks to avoid ping-related false positives)

**Network Flow:**

```
Simulating Client:
├── Updates NPC position locally (every Heartbeat)
├── Sends position to server (every POSITION_SYNC_INTERVAL)
└── Via Knit Signal: "UpdateNPCPosition"

Server:
├── Receives position update
├── No validation (accepts all updates - prevents false positives)
├── Updates ReplicatedStorage data
└── Broadcasts ONLY to nearby clients (within BROADCAST_DISTANCE)

Nearby Clients:
├── Receive position update via Knit Signal
├── Update their local rendering
└── No update if client is too far away (optimization)
```

#### **3.2: Client-Side Position Sync**

**Location**: `NPC_Controller/Components/Others/ClientNPCManager.lua`

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local OptimizationConfig = require(game.ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

local ClientNPCManager = {}
local SimulatedNPCs = {}  -- [npcID] = npcData

-- Track last sync time for each NPC
local LastSyncTimes = {}  -- [npcID] = lastSyncTick

function ClientNPCManager.Init()
    -- Wait for NPC service to be available
    local NPC_Service = Knit.GetService("NPC_Service")

    -- ... existing init code ...

    -- Start position sync loop
    task.spawn(ClientNPCManager.PositionSyncLoop)
end

--[[
    Position sync loop - sends position updates to server
    Only sends updates for NPCs this client is simulating
]]
function ClientNPCManager.PositionSyncLoop()
    local NPC_Service = Knit.GetService("NPC_Service")
    local syncInterval = OptimizationConfig.ClientSimulation.POSITION_SYNC_INTERVAL

    while task.wait(syncInterval) do
        for npcID, npcData in pairs(SimulatedNPCs) do
            -- Only sync if NPC is alive and has a position
            if npcData.IsAlive and npcData.Position then
                -- Send position update to server via Knit signal
                NPC_Service:UpdateNPCPosition(npcID, npcData.Position, npcData.Orientation)

                -- Track last sync time
                LastSyncTimes[npcID] = tick()
            end
        end
    end
end

--[[
    Listen for position updates from other clients
    This receives updates for NPCs simulated by other clients
]]
function ClientNPCManager.ListenForPositionUpdates()
    local NPC_Service = Knit.GetService("NPC_Service")

    -- Connect to Knit signal for NPC position updates
    NPC_Service.NPCPositionUpdated:Connect(function(npcID, newPosition, newOrientation)
        -- Only update if we're NOT simulating this NPC ourselves
        if not SimulatedNPCs[npcID] then
            ClientNPCManager.UpdateRemoteNPCPosition(npcID, newPosition, newOrientation)
        end
    end)
end

--[[
    Update position of NPC being simulated by another client
]]
function ClientNPCManager.UpdateRemoteNPCPosition(npcID, newPosition, newOrientation)
    -- Update in ReplicatedStorage
    local npcFolder = ReplicatedStorage.ActiveNPCs:FindFirstChild(npcID)
    if npcFolder then
        local positionValue = npcFolder:FindFirstChild("Position")
        if positionValue then
            positionValue.Value = newPosition
        end

        -- Update orientation if provided
        if newOrientation and npcFolder:FindFirstChild("Orientation") then
            npcFolder.Orientation.Value = newOrientation
        end
    end
end

return ClientNPCManager
```

#### **3.3: Server-Side Distance-Based Broadcasting**

**Location**: `NPC_Service/Components/Others/ClientPhysicsSync.lua`

**Purpose**: Receive position updates from clients and broadcast only to nearby players

```lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

local ClientPhysicsSync = {}

-- Track NPC positions for distance checks
local NPCPositions = {}  -- [npcID] = Vector3

--[[
    Initialize the sync system
    Setup Knit service method for clients to call
]]
function ClientPhysicsSync.Init(NPCService)
    -- This is called from NPC_Service.KnitInit

    -- Clients will call this method to update NPC positions
    function NPCService.Client:UpdateNPCPosition(player: Player, npcID: string, position: Vector3, orientation: CFrame?)
        ClientPhysicsSync.HandlePositionUpdate(player, npcID, position, orientation)
    end
end

--[[
    Handle position update from client
    Validates and broadcasts to nearby clients only
]]
function ClientPhysicsSync.HandlePositionUpdate(fromPlayer: Player, npcID: string, newPosition: Vector3, newOrientation: CFrame?)
    -- Validate NPC exists
    local npcFolder = ReplicatedStorage.ActiveNPCs:FindFirstChild(npcID)
    if not npcFolder then
        warn("[ClientPhysicsSync] Invalid NPC ID:", npcID)
        return
    end

    -- REMOVED: Position validation (caused false positives from ping/latency)
    -- We accept all position updates to ensure smooth gameplay for high-ping users
    -- Anti-exploit validation has been intentionally disabled

    -- Update position tracking (for reference, no validation)
    local oldPosition = NPCPositions[npcID]

    -- Update position in ReplicatedStorage
    local positionValue = npcFolder:FindFirstChild("Position")
    if positionValue then
        positionValue.Value = newPosition
    end

    if newOrientation and npcFolder:FindFirstChild("Orientation") then
        npcFolder.Orientation.Value = newOrientation
    end

    -- Track position
    NPCPositions[npcID] = newPosition

    -- Broadcast to nearby clients ONLY
    ClientPhysicsSync.BroadcastToNearbyClients(npcID, newPosition, newOrientation)
end

--[[
    Broadcast position update only to clients within BROADCAST_DISTANCE
    This is the KEY optimization - reduces network traffic by 70-90%
]]
function ClientPhysicsSync.BroadcastToNearbyClients(npcID: string, position: Vector3, orientation: CFrame?)
    local broadcastDistance = OptimizationConfig.ClientSimulation.BROADCAST_DISTANCE

    -- Get all players and check distance
    for _, player in pairs(Players:GetPlayers()) do
        local character = player.Character
        if character and character.PrimaryPart then
            local playerPosition = character.PrimaryPart.Position
            local distance = (playerPosition - position).Magnitude

            -- Only send update if player is within broadcast distance
            if distance <= broadcastDistance then
                -- Fire client signal via Knit
                ClientPhysicsSync.FireClientPositionUpdate(player, npcID, position, orientation)
            end
        end
    end
end

--[[
    Fire position update to specific client
]]
function ClientPhysicsSync.FireClientPositionUpdate(player: Player, npcID: string, position: Vector3, orientation: CFrame?)
    -- This fires the Knit signal that clients listen to
    -- Using :Fire() instead of :FireAll() for targeted updates
    local NPCService = require(script.Parent.Parent.Parent)  -- Get NPC_Service
    NPCService.Client.NPCPositionUpdated:Fire(player, npcID, position, orientation)
end

--[[
    REMOVED: Anti-exploit validation intentionally disabled

    Position validation has been removed because:
    - Network latency (ping) causes many false positives
    - Players with high ping would experience stuttering/rejection of legitimate movements
    - The tolerance multipliers (1.5x, 2x, etc.) are never enough for all network conditions
    - User experience is more important than preventing rare exploit scenarios

    Original validation checked if position changes exceeded max speed,
    but real-world testing showed this negatively impacted legitimate users.

    For critical gameplay NPCs, use server-authoritative movement instead of UseAnimationController.
]]

-- This function has been removed - no validation performed
-- function ClientPhysicsSync.ValidatePositionUpdate(...) -- REMOVED

--[[
    Cleanup when NPC is removed
]]
function ClientPhysicsSync.CleanupNPC(npcID: string)
    NPCPositions[npcID] = nil
end

return ClientPhysicsSync
```

#### **3.4: Knit Service Integration**

**Location**: `NPC_Service/init.lua`

Add the position sync system to the NPC_Service:

```lua
local Knit = require(game.ReplicatedStorage.Packages.Knit)
local NPC_Service = Knit.CreateService({
    Name = "NPC_Service",
    Client = {
        -- Signal for broadcasting NPC position updates to clients
        -- Only fired to nearby clients (within BROADCAST_DISTANCE)
        NPCPositionUpdated = Knit.CreateSignal(),
    },
})

function NPC_Service:KnitInit()
    -- Load components
    NPC_Service.Components = require(script.Components)

    -- Initialize client physics sync system
    local ClientPhysicsSync = require(script.Components.Others.ClientPhysicsSync)
    ClientPhysicsSync.Init(NPC_Service)
end

-- ... rest of service code ...

return NPC_Service
```

#### **3.5: Network Traffic Comparison**

**Traditional Approach** (all clients receive all updates):

```
1000 NPCs × 30 updates/sec × 100 players = 3,000,000 updates/sec
Network load: EXTREME (unplayable)
```

**Optimized Approach** (only nearby clients receive updates):

```
1000 NPCs × 30 updates/sec × ~5 nearby players = 150,000 updates/sec
Network load: 95% reduction (playable)
```

**Key Benefits:**

- ✅ 70-95% reduction in network traffic
- ✅ Players only receive updates for nearby NPCs
- ✅ Scales better with large player counts
- ✅ Configurable broadcast distance

---

### **4. Client Disconnection Handling**

#### **4.1: Overview**

When a client that is simulating NPCs disconnects, those NPCs must be reassigned to other nearby clients. This system is designed to keep server load minimal - **clients handle the reassignment logic themselves**.

**Key Principles:**
- Server only tracks which client owns each NPC (lightweight)
- Server broadcasts "owner left" events (minimal work)
- Clients compete to claim orphaned NPCs based on distance
- No server-side simulation fallback (maintains zero server physics)

#### **4.2: Server-Side Ownership Tracking**

**Location**: `NPC_Service/Components/Others/ClientPhysicsSync.lua`

Add ownership tracking to the existing sync system:

```lua
-- Track which client is simulating each NPC
local NPCOwnership = {}  -- [npcID] = Player

-- Track last update time for timeout detection
local LastUpdateTimes = {}  -- [npcID] = tick()

-- Timeout threshold (seconds) - if no update received, NPC is orphaned
local OWNERSHIP_TIMEOUT = 3.0

--[[
    Called when client claims ownership of an NPC
    Server just records this - no validation (minimal load)
]]
function ClientPhysicsSync.ClaimNPC(player: Player, npcID: string)
    -- Simple ownership assignment - no complex logic
    NPCOwnership[npcID] = player
    LastUpdateTimes[npcID] = tick()
end

--[[
    Called when client releases an NPC (intentional handoff)
]]
function ClientPhysicsSync.ReleaseNPC(player: Player, npcID: string)
    if NPCOwnership[npcID] == player then
        NPCOwnership[npcID] = nil
        LastUpdateTimes[npcID] = nil

        -- Broadcast that this NPC needs a new owner
        ClientPhysicsSync.BroadcastOrphanedNPC(npcID)
    end
end

--[[
    Handle player disconnection
    Called from Players.PlayerRemoving
]]
function ClientPhysicsSync.HandlePlayerLeft(player: Player)
    local orphanedNPCs = {}

    -- Find all NPCs owned by this player
    for npcID, owner in pairs(NPCOwnership) do
        if owner == player then
            NPCOwnership[npcID] = nil
            LastUpdateTimes[npcID] = nil
            table.insert(orphanedNPCs, npcID)
        end
    end

    -- Broadcast orphaned NPCs to all remaining clients
    -- Clients will compete to claim them based on distance
    if #orphanedNPCs > 0 then
        ClientPhysicsSync.BroadcastOrphanedNPCs(orphanedNPCs)
    end
end

--[[
    Broadcast orphaned NPCs to nearby clients
    Server does minimal work - just sends the list
]]
function ClientPhysicsSync.BroadcastOrphanedNPCs(npcIDs: {string})
    local NPCService = require(script.Parent.Parent.Parent)

    -- Get positions for distance-based claiming
    local npcPositions = {}
    for _, npcID in ipairs(npcIDs) do
        local npcFolder = ReplicatedStorage.ActiveNPCs:FindFirstChild(npcID)
        if npcFolder and npcFolder:FindFirstChild("Position") then
            npcPositions[npcID] = npcFolder.Position.Value
        end
    end

    -- Fire to all clients - they decide if they should claim
    NPCService.Client.NPCsOrphaned:FireAll(npcPositions)
end

--[[
    Broadcast single orphaned NPC
]]
function ClientPhysicsSync.BroadcastOrphanedNPC(npcID: string)
    ClientPhysicsSync.BroadcastOrphanedNPCs({npcID})
end
```

#### **4.3: Client-Side Claiming System**

**Location**: `NPC_Controller/Components/Others/ClientNPCManager.lua`

Add claiming logic to handle orphaned NPCs:

```lua
local CLAIM_DELAY_BASE = 0.1  -- Base delay before claiming (seconds)
local CLAIM_DELAY_PER_STUD = 0.001  -- Additional delay per stud of distance

--[[
    Listen for orphaned NPC broadcasts
    Clients compete to claim based on distance (closer = faster claim)
]]
function ClientNPCManager.ListenForOrphanedNPCs()
    local NPC_Service = Knit.GetService("NPC_Service")

    NPC_Service.NPCsOrphaned:Connect(function(npcPositions: {[string]: Vector3})
        ClientNPCManager.HandleOrphanedNPCs(npcPositions)
    end)
end

--[[
    Handle orphaned NPCs - claim those within range
    Uses distance-based delay so closest client claims first
]]
function ClientNPCManager.HandleOrphanedNPCs(npcPositions: {[string]: Vector3})
    local localPlayer = Players.LocalPlayer
    if not localPlayer.Character or not localPlayer.Character.PrimaryPart then
        return
    end

    local playerPos = localPlayer.Character.PrimaryPart.Position
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
    Server accepts first valid claim (no complex arbitration)
]]
function ClientNPCManager.AttemptClaimNPC(npcID: string, lastKnownPos: Vector3)
    -- Check if already being simulated by us
    if SimulatedNPCs[npcID] then
        return
    end

    -- Check if NPC still exists
    local npcFolder = ReplicatedStorage.ActiveNPCs:FindFirstChild(npcID)
    if not npcFolder then
        return
    end

    -- Check if already claimed by checking for recent position updates
    local positionValue = npcFolder:FindFirstChild("Position")
    if positionValue then
        -- If position changed from last known, someone else claimed it
        local currentPos = positionValue.Value
        if (currentPos - lastKnownPos).Magnitude > 1 then
            -- Another client already claimed and moved it
            return
        end
    end

    -- Claim the NPC
    local NPC_Service = Knit.GetService("NPC_Service")
    NPC_Service:ClaimNPC(npcID)

    -- Start simulating
    ClientNPCManager.StartSimulation(npcFolder)
end

--[[
    Release NPCs when player is leaving or moving away
]]
function ClientNPCManager.ReleaseNPC(npcID: string)
    if SimulatedNPCs[npcID] then
        -- Notify server
        local NPC_Service = Knit.GetService("NPC_Service")
        NPC_Service:ReleaseNPC(npcID)

        -- Stop local simulation
        ClientNPCManager.StopSimulation(npcID)
    end
end

--[[
    Graceful handoff when moving away from NPCs
    Called periodically from DistanceCheckLoop
]]
function ClientNPCManager.CheckForHandoff()
    local localPlayer = Players.LocalPlayer
    if not localPlayer.Character or not localPlayer.Character.PrimaryPart then
        return
    end

    local playerPos = localPlayer.Character.PrimaryPart.Position
    local simulationDistance = OptimizationConfig.ClientSimulation.SIMULATION_DISTANCE
    local handoffDistance = simulationDistance * 1.5  -- Hysteresis

    for npcID, npcData in pairs(SimulatedNPCs) do
        local distance = (playerPos - npcData.Position).Magnitude

        -- Release if too far away
        if distance > handoffDistance then
            ClientNPCManager.ReleaseNPC(npcID)
        end
    end
end
```

#### **4.4: Knit Service Additions**

**Location**: `NPC_Service/init.lua`

Add the new signals and methods:

```lua
local NPC_Service = Knit.CreateService({
    Name = "NPC_Service",
    Client = {
        NPCPositionUpdated = Knit.CreateSignal(),
        NPCsOrphaned = Knit.CreateSignal(),  -- NEW: Broadcast orphaned NPCs
    },
})

function NPC_Service:KnitInit()
    -- ... existing init code ...

    -- Handle player leaving
    Players.PlayerRemoving:Connect(function(player)
        ClientPhysicsSync.HandlePlayerLeft(player)
    end)
end

-- Client methods for claiming/releasing
function NPC_Service.Client:ClaimNPC(player: Player, npcID: string)
    ClientPhysicsSync.ClaimNPC(player, npcID)
end

function NPC_Service.Client:ReleaseNPC(player: Player, npcID: string)
    ClientPhysicsSync.ReleaseNPC(player, npcID)
end
```

#### **4.5: Timeout Detection (Optional Heartbeat)**

For cases where a client crashes without proper disconnection, add optional timeout detection. This runs infrequently to minimize server load:

```lua
-- Run every 5 seconds (very low server load)
local TIMEOUT_CHECK_INTERVAL = 5.0

function ClientPhysicsSync.StartTimeoutChecker()
    task.spawn(function()
        while true do
            task.wait(TIMEOUT_CHECK_INTERVAL)
            ClientPhysicsSync.CheckForTimeouts()
        end
    end)
end

function ClientPhysicsSync.CheckForTimeouts()
    local now = tick()
    local orphanedNPCs = {}

    for npcID, lastUpdate in pairs(LastUpdateTimes) do
        if now - lastUpdate > OWNERSHIP_TIMEOUT then
            -- NPC hasn't received updates - owner likely crashed
            NPCOwnership[npcID] = nil
            LastUpdateTimes[npcID] = nil
            table.insert(orphanedNPCs, npcID)
        end
    end

    if #orphanedNPCs > 0 then
        ClientPhysicsSync.BroadcastOrphanedNPCs(orphanedNPCs)
    end
end
```

#### **4.6: Server Load Analysis**

**Server work when client disconnects:**
1. Loop through ownership table: O(n) where n = NPCs owned by that player
2. Collect orphaned NPC IDs: Simple table insert
3. Fire signal to all clients: Single network call

**Server does NOT:**
- Simulate any NPC physics
- Calculate which client should take over
- Validate claims (first come, first served)
- Run complex arbitration logic

**Result:** Minimal server impact even with 1000+ NPCs

---

## 🔧 **Configuration Structure**

### **Configuration File Location**

**Path**: `src/ReplicatedStorage/SharedSource/Datas/NPCs/OptimizationConfig.lua`

```lua
--[[
    OptimizationConfig - Advanced NPC optimization settings

    ⚠️ WARNING: UseAnimationController is an ADVANCED optimization
    - Offloads ALL physics to client
    - Client has full position authority (no anti-exploit validation)
    - Requires extensive testing
    - NOT recommended for beginners
]]

local OptimizationConfig = {
    --[[
        UseAnimationController - Enable client-side physics simulation

        ⚠️ CRITICAL WARNINGS:
        1. NO physics on server at all
        2. Client handles ALL pathfinding and movement
        3. Client has full position authority (no validation - prevents ping false positives)
           >> We accept that clients can manipulate NPC positions
           >> This is intentional trade-off for smooth gameplay at all ping levels
        4. Only suitable for non-critical NPCs (ambient, visual-only)
        5. Requires more testing for specific use cases
        6. Everything is rendered on client-side for optimization

        When enabled:
        - Server stores positions and health (no HumanoidRootPart, no physics)
        - Health managed by server for gameplay integrity
        - Client calculates pathfinding (using NoobPath)
        - Client simulates jumps (physics simulation)
        - Client handles all physics and movement
        - NPCs only rendered when player is nearby
        - Instead of HumanoidRootPart, only positions are saved

        Performance: Can handle 1000+ NPCs with barely any lag
        Security: Client has position authority (no validation - prevents ping-related false positives)
                  Health remains server-authoritative to protect gameplay integrity
        Use Case: Ambient NPCs, crowds, background characters (non-gameplay-critical)

        ⚠️ DO NOT USE FOR:
        - Combat NPCs (enemies, bosses)
        - NPCs that drop loot or rewards
        - NPCs tied to game progression
        - Any NPC that affects gameplay outcomes
    ]]
    UseAnimationController = false,  -- DISABLED by default

    -- Client-side simulation settings (only if UseAnimationController = true)
    ClientSimulation = {
        -- Distance at which client starts simulating NPC (studs)
        SIMULATION_DISTANCE = 200,

        -- Maximum NPCs one client can simulate
        MAX_SIMULATED_PER_CLIENT = 50,

        -- How often client syncs position to server (seconds)
        POSITION_SYNC_INTERVAL = 0.5,

        -- Distance threshold for server to broadcast position updates (studs)
        -- Server only sends position updates to clients within this range
        BROADCAST_DISTANCE = 250,
    },

    --[[
        ⚠️ NOTE: Rendering settings are in RenderConfig.lua
        To avoid duplication, refer to:
        - RenderConfig.MAX_RENDER_DISTANCE (distance to render NPCs)
        - RenderConfig.MAX_RENDERED_NPCS (max NPCs to render)
        - RenderConfig.DISTANCE_CHECK_INTERVAL (distance check frequency)
        - RenderConfig.DEBUG_MODE (debug visualization)
    ]]

    -- Jump simulation settings
    JumpSimulation = {
        -- ⚠️ NOTE: Gravity is read from workspace.Gravity at runtime
        -- This ensures consistency with game physics settings

        -- Default jump power if not specified (studs/s)
        DEFAULT_JUMP_POWER = 50,

        -- Jump timeout (seconds)
        JUMP_TIMEOUT = 3.0,

        -- Ground check distance (studs)
        GROUND_CHECK_DISTANCE = 1.0,
    },

    -- Pathfinding settings (client-side)
    ClientPathfinding = {
        -- Pathfinding agent radius (studs)
        AGENT_RADIUS = 2,

        -- Pathfinding agent height (studs)
        AGENT_HEIGHT = 5,

        -- Enable jump in pathfinding
        AGENT_CAN_JUMP = true,

        -- Waypoint spacing (studs)
        WAYPOINT_SPACING = 4,

        -- Terrain costs
        TERRAIN_COSTS = {
            Water = math.huge,  -- Avoid water
        },

        -- Recompute path if NPC deviates this much (studs)
        RECOMPUTE_THRESHOLD = 10,
    },
}

return OptimizationConfig
```

---

### **Configuration Separation: OptimizationConfig vs RenderConfig**

To avoid duplication and maintain clean separation of concerns, the configuration is split into two files:

#### **OptimizationConfig.lua** - Client Physics & Simulation

- `UseAnimationController` - Enable/disable client-side physics
- `ClientSimulation` settings:
  - `SIMULATION_DISTANCE` - When clients start simulating NPCs
  - `MAX_SIMULATED_PER_CLIENT` - Max NPCs one client can simulate
  - `POSITION_SYNC_INTERVAL` - How often position syncs to server
  - `BROADCAST_DISTANCE` - Server only broadcasts to nearby clients
- `JumpSimulation` settings (uses `workspace.Gravity` at runtime)
- `ClientPathfinding` settings (NoobPath configuration)

#### **RenderConfig.lua** - Visual Rendering Control

- `ENABLED` - Toggle all client-side rendering on/off
- `MAX_RENDER_DISTANCE` - Distance to render NPCs visually
- `MAX_RENDERED_NPCS` - Maximum NPCs to render at once
- `DISTANCE_CHECK_INTERVAL` - How often to check render distances
- `DEBUG_MODE` - Enable debug visualization

**Why Separate?**

- **OptimizationConfig**: Advanced features for physics simulation (UseAnimationController)
- **RenderConfig**: General rendering controls (works with or without UseAnimationController)
- **No Duplication**: Each setting exists in only one place
- **Clear Responsibility**: Physics vs Rendering concerns are separated

---

### **NPC Spawn Configuration Update**

Update the `SpawnNPC` configuration to include the new optimization flag:

```lua
--[[
    Spawn NPC with flexible configuration

    @param config table - Configuration for NPC spawning
        ... (existing parameters)

        -- OPTIMIZATION (ADVANCED)
        - UseAnimationController: boolean? - Enable client-side physics (default: false)
            ⚠️ WARNING: This is an ADVANCED feature with the following implications:
                1. NO physics simulation on server
                2. Client handles ALL pathfinding and movement
                3. Client has position authority (no validation to prevent ping false positives)
                4. Only for non-critical NPCs (ambient, visual-only)
                5. Everything rendered on client-side
                6. Can handle 1000+ NPCs with smooth gameplay at all ping levels
]]
function NPC_Service:SpawnNPC(config)
    -- Check if UseAnimationController is enabled
    local useAnimController = config.UseAnimationController or OptimizationConfig.UseAnimationController

    if useAnimController then
        -- Use client-side physics approach
        return NPC_Service.Components.NPCSpawner:SpawnClientPhysicsNPC(config)
    else
        -- Use traditional server-side physics approach
        return NPC_Service.Components.NPCSpawner:SpawnNPC(config)
    end
end
```

---

## 📊 **Implementation Phases**

### **Phase 1: Server-Side Foundation**

**Files to Create:**

1. `SharedSource/Datas/NPCs/OptimizationConfig.lua` - Configuration file
2. `NPC_Service/Components/Others/ClientPhysicsSpawner.lua` - Spawner for client-physics NPCs

**Files to Modify:**

1. `NPC_Service/init.lua` - Add UseAnimationController parameter
2. `NPC_Service/Components/Others/NPCSpawner.lua` - Add conditional logic

**Tasks:**

- [ ] Create OptimizationConfig with all settings
- [ ] Create data structure in ReplicatedStorage for NPC data (Position, Health, IsAlive, etc.)
- [ ] Implement ClientPhysicsSpawner (no physical model, just data)
- [ ] Implement server-side health storage (simple storage, server-authoritative for health)
- [ ] Add cleanup handlers for client-physics NPCs

### **Phase 2: Client-Side Manager & Position Sync**

**Files to Create:**

1. `NPC_Controller/Components/Others/ClientNPCManager.lua` - Main client manager
2. `NPC_Controller/Components/Others/ClientNPCSimulator.lua` - NPC simulation logic
3. `NPC_Service/Components/Others/ClientPhysicsSync.lua` - Server-side position sync handler

**Tasks:**

- [ ] Watch ReplicatedStorage.ActiveNPCs for new NPCs
- [ ] Implement client assignment algorithm (distance-based)
- [ ] Create simulation loop (Heartbeat)
- [ ] Implement position synchronization to server via Knit signal
- [ ] Implement server-side distance-based broadcasting (only send to nearby clients)
- [ ] ~~Add position validation~~ - REMOVED (causes false positives)
- [ ] Setup Knit service signals (UpdateNPCPosition, NPCPositionUpdated, NPCsOrphaned)
- [ ] Implement ownership tracking (NPCOwnership table)
- [ ] Implement ClaimNPC/ReleaseNPC methods
- [ ] Setup Players.PlayerRemoving handler for disconnection
- [ ] Implement client-side orphaned NPC listener
- [ ] Implement distance-based claiming with delay (closer = faster)
- [ ] Implement graceful handoff when player moves away (CheckForHandoff)
- [ ] Add timeout detection for crashed clients (optional heartbeat check)

### **Phase 3: Client-Side Pathfinding (NoobPath)**

**Files to Create:**

1. `NPC_Controller/Components/Others/ClientPathfinding.lua` - NoobPath pathfinding wrapper
2. `NPC_Controller/Components/Others/ClientMovement.lua` - Movement behaviors

**Tasks:**

- [ ] Implement NoobPath wrapper (similar to server-side PathfindingManager)
- [ ] Port MovementBehavior logic to client
- [ ] Setup error and trapped event handlers
- [ ] Implement waypoint following with NoobPath:Run()
- [ ] Handle pathfinding errors and timeouts

### **Phase 4: Jump Simulation**

**Files to Create:**

1. `NPC_Controller/Components/Others/ClientJumpSimulator.lua` - Jump physics

**Tasks:**

- [ ] Implement gravity simulation
- [ ] Implement ground detection (raycasting)
- [ ] Implement jump arc calculation
- [ ] Handle edge cases (falling, obstacles)

### **Phase 5: Client Physics Rendering**

**Files to Create:**

1. `NPC_Controller/Components/Others/ClientPhysicsRenderer.lua` - Client-side renderer for physics NPCs

**⚠️ Note**: This is separate from existing `NPCRenderer.lua`:

- `NPCRenderer.lua` - Handles traditional server-physics NPCs
- `ClientPhysicsRenderer.lua` - Handles UseAnimationController client-physics NPCs

**Tasks:**

- [ ] Implement distance checking loop (uses RenderConfig settings)
- [ ] Implement render/unrender logic for client-physics NPCs
- [ ] Setup position synchronization from ReplicatedStorage data
- [ ] Create full visual models (not just visuals on top of server model)
- [ ] Setup health bar display (reads from server health values)
- [ ] Respect RenderConfig.MAX_RENDERED_NPCS limit

### **Phase 6: Testing & Optimization**

**Tasks:**

- [ ] Test with 100 NPCs
- [ ] Test with 500 NPCs
- [ ] Test with 1000+ NPCs
- [ ] Profile client performance
- [ ] Profile server performance
- [ ] Test with multiple clients
- [ ] Test client disconnection (NPC reassignment)
- [ ] Test exploit scenarios (document behavior, no mitigation implemented)

---

## 🧪 **Testing Strategy**

### **Performance Testing**

1. **Baseline Test** (Traditional System)

   - Spawn 100 NPCs with server physics
   - Measure server FPS, memory, network traffic
   - Measure client FPS, memory

2. **Client Physics Test** (New System)
   - Spawn 100, 500, 1000 NPCs with UseAnimationController
   - Measure server FPS, memory, network traffic
   - Measure client FPS, memory
   - Compare results with baseline

### **Functionality Testing**

1. **Pathfinding**

   - Verify NPCs navigate correctly
   - Verify jump handling
   - Verify obstacle avoidance

2. **Rendering**

   - Verify NPCs render at correct distance
   - Verify NPCs unrender when far away
   - Verify smooth transitions

3. **Multi-Client Testing**
   - Test with 2+ clients in same server
   - Verify NPC distribution across clients
   - Verify position synchronization

### **Exploit Testing** (Documentation Only - No Mitigation)

1. **Position Manipulation** (Expected Behavior - Not Prevented)

   - Test if client can teleport NPCs (will succeed - acceptable trade-off)
   - Test if client can freeze NPCs (will succeed - acceptable trade-off)
   - Test if client can make NPCs walk through walls (will succeed - acceptable trade-off)
   - Document these behaviors for developers to understand system limitations

2. **Mitigation Strategies**
   - Server-side validation for critical events (combat/damage only)
   - ❌ Position sanity checks REMOVED (caused false positives from ping/latency)
   - ❌ Rate limiting REMOVED (punishes legitimate high-ping players)
   - **Note**: We accept position exploit risks to maintain smooth gameplay for all users

---

## 📈 **Expected Performance**

### **Traditional System (Current)**

```
Server:
- 100 NPCs: ~40-50 FPS
- 200 NPCs: ~20-30 FPS
- 500 NPCs: < 10 FPS (unplayable)

Client:
- 100 NPCs: ~50-60 FPS
- 200 NPCs: ~40-50 FPS

Network:
- High replication overhead (HumanoidRootPart positions)
```

### **UseAnimationController System (New)**

```
Server:
- 100 NPCs: ~55-60 FPS
- 500 NPCs: ~55-60 FPS
- 1000 NPCs: ~50-55 FPS
- 2000 NPCs: ~40-50 FPS

Client (per client):
- Simulating 50 NPCs: ~45-55 FPS
- Rendering 100 NPCs: ~40-50 FPS

Network:
- Minimal replication (Vector3 positions only)
- ~80-90% reduction in network traffic
```

**Key Improvements:**

- ✅ Server FPS stays high regardless of NPC count
- ✅ Network traffic reduced by 80-90%
- ✅ Can support 1000+ NPCs
- ⚠️ Client FPS depends on simulation/render load
- ⚠️ Requires careful load distribution

---

## 🔐 **Security Considerations**

### **⚠️ Anti-Exploit Validation: INTENTIONALLY DISABLED**

**This system does NOT include anti-exploit validation for position updates.**

**Reasoning:**

- Network latency and ping variations cause too many false positives
- Players with high ping (200ms+) would have their legitimate movements rejected
- No tolerance multiplier (1.5x, 2x, 3x) works reliably for all network conditions
- False positives negatively impact user experience more than exploits would
- Stuttering, rubber-banding, and position rejection are unacceptable for gameplay

**Design Philosophy:**

> **User experience > Anti-cheat strictness**
>
> We prioritize smooth gameplay for legitimate users over preventing rare exploit scenarios.
> If position accuracy is critical for your game, use server-authoritative movement instead.

### **Potential Exploit Scenarios** (No Mitigation)

1. **NPC Teleportation**

   - **Attack**: Client sends fake position updates
   - **Mitigation**: NONE - Accepted as trade-off for smooth gameplay

2. **NPC Freezing**

   - **Attack**: Client stops updating NPC positions
   - **Mitigation**: NONE - Other clients can still see/interact with NPCs

3. **Wall Clipping**

   - **Attack**: Client makes NPCs walk through walls
   - **Mitigation**: NONE - Visual only, no gameplay impact if NPCs are non-critical

4. **Combat Manipulation**
   - **Attack**: Client makes NPCs attack/target incorrectly
   - **Mitigation**: Server validates all combat/damage events (health is server-authoritative)

### **What IS Protected**

✅ **Health/Damage** - Server-authoritative, cannot be exploited
✅ **Combat Events** - Server validates all damage dealing
✅ **NPC Spawning** - Server controls what NPCs exist
✅ **NPC Configuration** - Server defines NPC properties

### **What is NOT Protected**

❌ **Position Updates** - Client has full authority, no validation
❌ **Movement Paths** - Client controls pathfinding
❌ **Visual State** - Client controls animations/rendering

### **Removed Validation Code** (For Reference)

```lua
-- THIS CODE HAS BEEN REMOVED - DO NOT IMPLEMENT
--[[
-- Original validation function (REMOVED due to false positives)
function ValidatePositionUpdate(npcData, oldPosition, newPosition, deltaTime)
    local distance = (newPosition - oldPosition).Magnitude
    local maxSpeed = npcData.Config.WalkSpeed or 16
    local maxDistance = maxSpeed * deltaTime * 1.5  -- Even 1.5x tolerance caused issues

    if distance > maxDistance then
        -- This would reject legitimate high-ping players
        return false  -- PROBLEM: Too many false positives
    end

    return true
end
]]
```

### **Use Case Guidelines**

**✅ Safe to Use:**

- Ambient NPCs (villagers, crowds)
- Visual-only NPCs (decorative)
- Non-combat NPCs
- Background characters

**❌ NOT Safe to Use:**

- Combat NPCs (enemies, bosses)
- NPCs that drop loot
- NPCs tied to progression
- NPCs that affect gameplay outcomes

---

## 🎓 **Developer Guidelines**

### **When to Enable UseAnimationController**

**Enable When:**

- You need to support many NPCs (500+)
- NPCs are purely visual (no gameplay impact)
- Server performance is bottleneck
- You understand the security implications

**Do NOT Enable When:**

- NPCs are critical to gameplay
- NPCs handle combat or loot (position accuracy matters)
- You're new to Roblox development
- Position accuracy is essential for game mechanics

### **Best Practices**

1. **Start Small**

   - Test with 10-50 NPCs first
   - Gradually increase to 100, 500, 1000
   - Monitor performance at each step

2. **Server Authority for Critical Systems**

   - Always validate combat/damage events on server (health is server-authoritative)
   - ❌ DO NOT implement position validation (causes false positives from ping)
   - ❌ DO NOT implement rate limiting (punishes high-ping players)
   - Accept that client has position authority as a design trade-off

3. **Distribute Load**

   - Don't let one client simulate all NPCs
   - Use distance-based distribution
   - Consider client performance capabilities

4. **Monitor Performance**
   - Track client FPS
   - Track simulation count per client
   - Track network traffic
   - Adjust settings based on data

---

## 📅 **Implementation Timeline**

### **Phase 1: Foundation** (2-3 days)

- Day 1: Create OptimizationConfig and data structures
- Day 2: Implement ClientPhysicsSpawner
- Day 3: Testing and debugging

### **Phase 2: Client Manager** (3-4 days)

- Day 1-2: ClientNPCManager implementation
- Day 3: Position synchronization
- Day 4: Testing and debugging

### **Phase 3: Pathfinding & Movement** (3-4 days)

- Day 1-2: ClientPathfinding implementation
- Day 3: ClientMovement behaviors
- Day 4: Testing and debugging

### **Phase 4: Jump Simulation** (2 days)

- Day 1: Jump physics implementation
- Day 2: Testing and edge cases

### **Phase 5: Client Physics Rendering** (2-3 days)

- Day 1-2: ClientPhysicsRenderer implementation (separate from existing NPCRenderer)
- Day 3: Testing and optimization

### **Phase 6: Testing & Optimization** (3-4 days)

- Day 1-2: Performance testing
- Day 3-4: Multi-client testing
- Note: No anti-exploit validation implemented (intentionally disabled due to ping false positives)

**Total: 16-21 days**

---

## 🚀 **Migration Path**

### **Step 1: Parallel Implementation**

- Keep existing system running
- Implement new system alongside
- Add feature flag to toggle between systems

### **Step 2: Gradual Rollout**

- Test with small group of players
- Monitor performance metrics
- Gather feedback

### **Step 3: Optimize**

- Tune configuration based on data
- Adjust render distances
- Optimize simulation distribution

### **Step 4: Full Deployment**

- Enable for all players
- Monitor server performance
- Monitor client performance
- Adjust as needed

---

## 📝 **Configuration Examples**

### **Example 1: Ambient Village NPCs (Safe for UseAnimationController)**

```lua
-- Spawn 100 villagers with client-side physics
for i = 1, 100 do
    NPC_Service:SpawnNPC({
        Name = "Villager_" .. i,
        Position = GetRandomVillagePosition(),
        ModelPath = game.ReplicatedStorage.Assets.NPCs.Villager,

        MaxHealth = 100,
        WalkSpeed = 10,

        SightRange = 50,
        SightMode = "Directional",
        MovementMode = "Ranged",

        EnableIdleWander = true,
        EnableCombatMovement = false,  -- No combat

        -- ENABLE CLIENT-SIDE PHYSICS
        UseAnimationController = true,

        CustomData = {
            Faction = "Villager",
            IsAmbient = true,
        },
    })
end
```

### **Example 2: Combat NPCs (NOT Safe for UseAnimationController)**

```lua
-- Spawn combat enemies with traditional server physics
NPC_Service:SpawnNPC({
    Name = "CombatEnemy",
    Position = Vector3.new(0, 10, 0),
    ModelPath = game.ReplicatedStorage.Assets.NPCs.Enemy,

    MaxHealth = 150,
    WalkSpeed = 16,

    SightRange = 200,
    SightMode = "Directional",
    MovementMode = "Melee",

    EnableIdleWander = true,
    EnableCombatMovement = true,

    -- DO NOT ENABLE for combat NPCs
    UseAnimationController = false,  -- Server physics

    CustomData = {
        Faction = "Enemy",
        DropTable = {"Coin", "Weapon"},
    },
})
```

---

## 🔚 **Conclusion**

The `UseAnimationController` optimization is a **powerful but risky** feature that can dramatically improve NPC performance by offloading physics to the client. When used correctly, it enables games to support **1000+ NPCs** with minimal lag.

**Key Takeaways:**

- ✅ Massive performance improvement (server-side)
- ✅ 70-95% network traffic reduction via distance-based broadcasting
- ✅ Enables large-scale NPC systems (1000+ NPCs)
- ✅ Uses workspace.Gravity for physics consistency
- ✅ Respects RenderConfig for rendering settings (no duplication)
- ⚠️ Client has position authority (no anti-exploit validation to prevent ping false positives)
- ⚠️ Requires extensive testing
- ⚠️ Only suitable for non-critical NPCs where position accuracy isn't gameplay-critical

**Recommended Use Cases:**

- Ambient NPCs (crowds, villagers)
- Visual-only NPCs (background characters)
- Non-gameplay-critical NPCs

**NOT Recommended For:**

- Combat NPCs
- NPCs that drop loot
- NPCs tied to progression

---

## 📝 **Recent Updates**

### Version 1.2 (2025-11-28)

- **Client disconnection handling**: Added comprehensive system for NPC reassignment when simulating client leaves
  - Server-side ownership tracking (lightweight - just a table lookup)
  - `ClaimNPC`/`ReleaseNPC` methods for ownership management
  - `NPCsOrphaned` Knit signal broadcasts orphaned NPCs to remaining clients
  - Distance-based claiming: closer clients claim faster (delay = base + distance × factor)
  - Graceful handoff when player moves away from NPCs
  - Optional timeout detection for crashed clients (runs every 5 seconds)
  - Zero server physics simulation maintained - clients handle all reassignment logic
- **Fixed deprecated API**: Replaced `SetPrimaryPartCFrame` with `PivotTo` in ClientPhysicsRenderer

### Version 1.1 (2025-10-12)

- **Removed duplicate configurations**: Rendering settings now exclusively in `RenderConfig.lua`
- **Dynamic gravity**: Changed to use `workspace.Gravity` instead of hardcoded values
- **Distance-based broadcasting**: Added optimized position sync system using Knit signals
  - Server only broadcasts updates to nearby clients (70-95% network reduction)
  - Client sends position updates via Knit service method
  - No position validation (prevents false positives from network latency)
- **Configuration separation**: Clear distinction between `OptimizationConfig` (physics) and `RenderConfig` (rendering)
- **Added ClientPhysicsSync component**: Server-side handler for distance-based position broadcasting
- **Clarified rendering systems**: Renamed to `ClientPhysicsRenderer` and added comparison table
  - Existing `NPCRenderer.lua` handles traditional server-physics NPCs
  - New `ClientPhysicsRenderer.lua` handles UseAnimationController client-physics NPCs
  - Both systems coexist and serve different purposes

---

**Document Version**: 1.2
**Last Updated**: 2025-11-28
**Status**: Implementation Plan (Updated - Ready for Implementation)
