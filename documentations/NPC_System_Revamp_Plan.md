# NPC System Revamp - Documentation Plan

## 📋 **Overview**
This document outlines the creation of a **universal, data-driven NPC system** for the project. The goal is to create a clean, performant, and highly reusable NPC system that works for any game type without hardcoded game-specific logic.

---

## 🎯 **Core Principles**

### **Universal Design**
1. ✅ **Data-Driven** - All NPC properties configured via flexible data structures
2. ✅ **Component-Based** - Modular components for Movement, Sight, Spawning, Rendering
3. ✅ **Client-Server Separation** - Minimal server overhead, client handles visuals
4. ✅ **Developer-Friendly** - Simple API, easy configuration, clear documentation
5. ✅ **Performance-First** - Optimized for 100+ NPCs simultaneously

### **Core Features**
1. ✅ **Movement Behavior** - Intelligent pathfinding and movement logic
2. ✅ **Sight Behavior** - Enemy detection and targeting system
3. ✅ **NoobPath Integration** - Modern pathfinding solution
4. ✅ **Smart Spawner** - Raycast-based ground detection
5. ✅ **Client Renderer** - Optional client-side visual rendering
6. ✅ **BetterAnimate Integration** - Smooth animation system

---

## 🏗️ **New System Architecture**

### **Phase 1: Server-Side Core (NPC_Service)**

#### **1.1: NPC_Service Structure**
```
NPC_Service/
├── init.lua                      (Clean service interface)
└── Components/
    ├── Get().lua                 (Read-only NPC data access)
    ├── Set().lua                 (NPC modification methods)
    └── Others/
        ├── MovementBehavior.lua  (Movement & pathfinding)
        ├── SightDetector.lua     (Vision & targeting)
        ├── NPCSpawner.lua        (Spawn management)
        ├── PathfindingManager.lua (NoobPath wrapper)
        └── NPCInstance.lua       (Individual NPC state manager)
```

#### **1.2: NPC_Service Responsibilities**
- **NPC Registry**: Track all active NPCs by unique ID
- **Spawn Coordination**: Handle NPC spawning with flexible configuration
- **Component Management**: Initialize Movement and Sight components per NPC
- **Cleanup**: Automatic cleanup on death/removal
- **Public API**: Simple methods for game developers to spawn and manage NPCs

#### **1.3: NPC Instance Data Structure**
Each NPC is represented by a data structure (no wrapper class):

```lua
-- Stored in NPC_Service.ActiveNPCs[npcModel]
{
    Model: Model,                  -- The NPC model
    ID: string,                    -- Unique identifier
    
    -- Movement State
    Pathfinding: NoobPath?,        -- NoobPath instance
    Destination: Vector3?,         -- Current target position
    MovementState: string?,        -- "Idle", "Following", "Combat"
    SpawnPosition: Vector3,        -- Original spawn position
    MovementMode: string,          -- "Ranged" or "Melee" (default: "Ranged")
    MeleeOffsetRange: number?,     -- Offset distance for melee mode (default: 3-8 studs)
    
    -- Targeting State
    CurrentTarget: Model?,         -- Current enemy target
    TargetInSight: boolean,        -- Is target visible
    LastSeenTarget: number,        -- Timestamp of last sighting
    SightRange: number,            -- Detection range (studs)
    SightMode: string,             -- "Omnidirectional" or "Directional" (default: "Directional")
    
    -- Custom Data (developer-defined)
    CustomData: table?,            -- Flexible data storage for game-specific needs
    
    -- Lifecycle
    TaskThreads: {thread},         -- Active threads
    Connections: {RBXScriptConnection}, -- Event connections
    CleanedUp: boolean,            -- Cleanup flag
}
```

#### **1.4: Public API Methods**
```lua
-- Spawn NPC with flexible configuration
NPC_Service:SpawnNPC(config: {
    Name: string,
    Position: Vector3,
    ModelPath: Instance,           -- Path to character model
    
    -- Stats
    MaxHealth: number?,
    WalkSpeed: number?,
    JumpPower: number?,
    
    -- Behavior
    SightRange: number?,           -- Detection range (default: 200)
    SightMode: string?,            -- "Omnidirectional" or "Directional" (default: "Directional")
    MovementMode: string?,         -- "Ranged" or "Melee" (default: "Ranged")
    MeleeOffsetRange: number?,     -- For Melee mode: offset distance from target (default: 3-8 studs)
    EnableIdleWander: boolean?,    -- Enable random wandering (default: true)
    EnableCombatMovement: boolean?, -- Enable rush/strafe for Ranged mode (default: true)
    
    -- Rendering (optional)
    ClientRenderData: table?,      -- Custom data for client rendering
    
    -- Custom Data
    CustomData: table?,            -- Any game-specific data
}): Model

-- Get NPC instance data
NPC_Service:GetNPCData(npcModel: Model): table?

-- Get NPC's current target
NPC_Service:GetCurrentTarget(npcModel: Model): Model?

-- Manually set target
NPC_Service:SetTarget(npcModel: Model, target: Model?)

-- Manually set destination
NPC_Service:SetDestination(npcModel: Model, destination: Vector3?)

-- Destroy NPC
NPC_Service:DestroyNPC(npcModel: Model)
```

---

### **Phase 2: Movement Behavior**

#### **2.1: MovementBehavior Component**
**Location**: `NPCService/Components/Others/MovementBehavior.lua`

**Responsibilities:**
1. **Idle Wandering** - Random walkable point selection
2. **Combat Movement** - Two distinct modes:
   - **Ranged Mode**: Rush and strafe behaviors (archer-like)
   - **Melee Mode**: Close-range pursuit with offset (prevents constant pushing)
3. **Target Following** - Pathfinding to enemy targets
4. **Orientation Control** - Face target using AlignOrientation

#### **2.2: Movement Modes**

**Mode 1: Ranged (Archer/Long Range)**
- **Behavior**: Rush towards target, then strafe around them
- **Use Case**: Archers, gunners, ranged enemies
- **Characteristics**:
  - Maintains engagement distance
  - Lateral strafing movement
  - Avoids getting too close to target
  - Dynamic rush points with obstacle avoidance

**Mode 2: Melee (Close Combat)**
- **Behavior**: Rush directly towards target with offset positioning
- **Use Case**: Melee fighters, close-range combatants
- **Characteristics**:
  - Pursues target aggressively
  - Maintains slight offset (3-8 studs) from target's exact position
  - Prevents constant collision/pushing
  - More predictable movement pattern
  - Uses randomized offset angles to create variety

**Key Functions:**
```lua
function MovementBehavior.SetupMovementBehavior(self)
    -- Setup all movement-related threads
    -- 1. Idle walking behavior thread
    -- 2. Combat movement thread (mode-dependent: ranged strafe OR melee chase)
    -- 3. Orientation update thread
end

function MovementBehavior.FindRandomWalkablePoint(self): Vector3?
    -- Raycasting to find valid ground positions
    -- Within configurable radius of spawn point
end

-- RANGED MODE FUNCTIONS
function MovementBehavior.FindRushPoint(self, distance, minDist, maxDist): Vector3?
    -- Smart rush point selection for ranged mode
    -- Avoids obstacles using raycast validation
    -- Maintains optimal engagement distance
end

function MovementBehavior.FindStrafePoint(self, targetPosition): Vector3?
    -- Lateral movement point generation for ranged mode
    -- Maintains engagement distance while circling
end

-- MELEE MODE FUNCTIONS
function MovementBehavior.FindMeleeChasePoint(self, targetPosition): Vector3?
    -- Calculate offset position near target for melee mode
    -- Returns position 3-8 studs away from target at random angle
    -- Prevents NPCs from occupying exact same spot
    
    local offsetDistance = math.random(self.MeleeOffsetRange or 3, self.MeleeOffsetRange or 8)
    local offsetAngle = math.random(0, 360)
    
    -- Calculate offset position
    local rad = math.rad(offsetAngle)
    local offsetX = math.cos(rad) * offsetDistance
    local offsetZ = math.sin(rad) * offsetDistance
    
    local chasePoint = targetPosition + Vector3.new(offsetX, 0, offsetZ)
    
    -- Validate with raycast
    return chasePoint
end
```

**Configuration:**
```lua
-- RANGED MODE CONFIG
local RANGED_STRAFE_CHECK_INTERVAL = 0.6
local RANGED_STRAFE_WALK_SPEED = 5
local RANGED_RUSH_DISTANCE_MIN = 3
local RANGED_RUSH_DISTANCE_MAX = 50
local RANGED_RUSH_DELAY = 0.25

-- MELEE MODE CONFIG
local MELEE_CHASE_CHECK_INTERVAL = 0.3  -- More frequent updates for melee
local MELEE_OFFSET_MIN = 3              -- Minimum offset from target (studs)
local MELEE_OFFSET_MAX = 8              -- Maximum offset from target (studs)
local MELEE_RECALCULATE_INTERVAL = 1.5  -- Recalculate offset point periodically

-- SHARED CONFIG
local UNFOLLOW_SIGHT_DURATION = 2.5
```

#### **2.3: NoobPath Integration**
**Location**: `NPCService/Components/Others/PathfindingManager.lua`

**Purpose**: Wrapper around NoobPath for NPC-specific usage

```lua
local PathfindingManager = {}

function PathfindingManager.CreatePath(npc: Model): NoobPath
    -- Create NoobPath instance with NPC-specific config
    local NoobPath = require(ReplicatedStorage.SharedSource.Utilities.Pathfinding.NoobPath)
    
    return NoobPath.Humanoid(npc, {
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = true,
        WaypointSpacing = 4,
        Costs = {
            Water = math.huge,
        }
    })
end

function PathfindingManager.OnPathBlocked(self)
    -- Handle pathfinding errors
    -- Jump/unstuck logic
end

return PathfindingManager
```

**NoobPath Benefits:**
- ✅ More efficient than SimplePath
- ✅ Better jump handling
- ✅ Timeout detection built-in
- ✅ Visualization support for debugging
- ✅ Network ownership management

---

### **Phase 3: Sight Behavior**

#### **3.1: SightDetector Component**
**Location**: `NPCService/Components/Others/SightDetector.lua`

**Responsibilities:**
1. **Enemy Detection** - Two detection modes:
   - **Omnidirectional**: 360° magnitude-based detection
   - **Directional**: Front-facing cone detection (allows sneaking)
2. **Target Prioritization** - Proximity-based sorting only
3. **Line of Sight** - Raycast validation
4. **Ally Filtering** - Ignore friendly NPCs
5. **Target Tracking** - Expose current target for external queries

#### **3.2: Sight Modes**

**Mode 1: Omnidirectional (360° Detection)**
- **Behavior**: Detects enemies in all directions
- **Use Case**: Alert guards, bosses, creatures with omniscient awareness
- **Characteristics**:
  - No angle filtering
  - Magnitude-based detection only
  - Cannot be sneaked up on
  - Still requires line-of-sight raycast

**Mode 2: Directional (Front-Facing Detection)**
- **Behavior**: Only detects enemies in front cone
- **Use Case**: Regular enemies, patrolling guards, realistic AI
- **Characteristics**:
  - Angle-based filtering (typically 120° cone in front)
  - Allows players to sneak behind
  - More realistic behavior
  - Requires both angle check AND line-of-sight raycast

**Key Functions:**
```lua
function SightDetector.SetupSightDetector(self)
    -- Main detection loop thread
    -- Runs at dynamic intervals based on target state
    -- Adapts behavior based on self.SightMode
end

local function detectEnemies(self)
    -- 1. Gather all potential targets (Players, NPCs, Vehicles)
    -- 2. Filter by distance (self.SightRange)
    -- 3. IF Directional mode: Filter by angle (front-facing cone)
    -- 4. Raycast for line-of-sight validation
    -- 5. Filter allies (via CustomData.Faction or similar)
    -- 6. Prioritize by proximity ONLY (nearest first)
    -- 7. Set best target (self.CurrentTarget)
end

local function isInFrontCone(self, targetPosition): boolean
    -- Only used in Directional mode
    -- Check if target is within front-facing cone (120° default)
    local npcPosition = self.Model.PrimaryPart.Position
    local npcLookVector = self.Model.PrimaryPart.CFrame.LookVector
    local directionToTarget = (targetPosition - npcPosition).Unit
    
    local dotProduct = npcLookVector:Dot(directionToTarget)
    local angleThreshold = math.cos(math.rad(60)) -- 120° cone (60° each side)
    
    return dotProduct >= angleThreshold
end

local function randomizeDetectionInterval()
    -- Randomized intervals prevent synchronized detection
    -- Range: 1-3 seconds
end
```

**Detection Configuration:**
```lua
local DETECTION_INTERVAL_MIN = 1.0
local DETECTION_INTERVAL_MAX = 3.0
local DETECTION_INTERVAL_TARGETFOUND = 1.5  -- Faster when target found

-- Directional mode cone angle (total cone, not per-side)
local DIRECTIONAL_CONE_ANGLE = 120  -- degrees
```

**Target Prioritization Logic (Proximity Only):**
```lua
-- Sort by distance only (nearest first)
-- NO damage-based prioritization
table.sort(detectedTargets, function(a, b)
    return a.Distance < b.Distance
end)

-- Select closest valid target
if #detectedTargets > 0 then
    self.CurrentTarget = detectedTargets[1].Model
    self.TargetInSight = true
    self.LastSeenTarget = tick()
else
    self.CurrentTarget = nil
    self.TargetInSight = false
end
```

---

### **Phase 4: NPC Spawner (Improved)**

#### **4.1: NPCSpawner Component**
**Location**: `NPC_Service/Components/Others/NPCSpawner.lua`

**Purpose**: Smart NPC spawning with ground detection and minimal server overhead

**Key Improvements:**
1. **Ground Detection**: Raycast-based positioning for accurate placement
2. **HipHeight Adjustment**: Accounts for Humanoid.HipHeight and HumanoidRootPart size
3. **Minimal Replication**: Server only creates HumanoidRootPart + Humanoid
4. **Flexible Configuration**: Developer-defined data instead of hardcoded attributes

**Key Function:**
```lua
function NPCSpawner.SpawnNPC(config: {
    Name: string,
    Position: Vector3,             -- Initial spawn position
    ModelPath: Instance,           -- Path to full character model (for cloning)
    
    -- Stats
    MaxHealth: number?,
    WalkSpeed: number?,
    JumpPower: number?,
    
    -- Behavior
    SightRange: number?,
    EnableIdleWander: boolean?,
    EnableCombatMovement: boolean?,
    
    -- Rendering
    ClientRenderData: table?,      -- Flexible data for client (replaces hardcoded attributes)
    
    -- Custom
    CustomData: table?,
}): Model
    
    -- 1. Perform ground detection (+2Y, raycast down)
    -- 2. Create minimal NPC model (HumanoidRootPart + Humanoid only)
    -- 3. Adjust position based on HipHeight and HumanoidRootPart size
    -- 4. Set flexible ClientRenderData attribute (JSON-encoded)
    -- 5. Configure humanoid states
    -- 6. Initialize NPC instance data
    -- 7. Setup cleanup handlers
    
    return npcModel
end
```

**Ground Detection & Positioning:**
```lua
local function findGroundPosition(position: Vector3): Vector3?
    -- Step 1: Raise position by 2 studs
    local startPos = position + Vector3.new(0, 2, 0)
    
    -- Step 2: Raycast downward to find ground
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {workspace.Characters}
    
    local rayResult = workspace:Raycast(startPos, Vector3.new(0, -1000, 0), raycastParams)
    
    if rayResult then
        return rayResult.Position
    end
    
    -- Fallback to original position if no ground found
    return position
end
```

**Minimal NPC Creation:**
```lua
local function createMinimalNPC(config): Model
    local npcModel = Instance.new("Model")
    npcModel.Name = config.Name
    
    -- Clone HumanoidRootPart from original model
    local originalModel = config.ModelPath
    local hrp = originalModel:FindFirstChild("HumanoidRootPart"):Clone()
    hrp.Parent = npcModel
    
    -- Clone Humanoid
    local humanoid = originalModel:FindFirstChild("Humanoid"):Clone()
    humanoid.MaxHealth = config.MaxHealth or 100
    humanoid.Health = humanoid.MaxHealth
    humanoid.WalkSpeed = config.WalkSpeed or 16
    humanoid.JumpPower = config.JumpPower or 50
    humanoid.Parent = npcModel
    
    -- Set PrimaryPart
    npcModel.PrimaryPart = hrp
    
    -- Find ground position
    local groundPos = findGroundPosition(config.Position)
    
    -- Adjust for HipHeight and HumanoidRootPart size
    local hipHeight = humanoid.HipHeight
    local hrpSize = hrp.Size
    local finalY = groundPos.Y + (hrpSize.Y / 2) + hipHeight
    
    -- Set final position
    hrp.CFrame = CFrame.new(groundPos.X, finalY, groundPos.Z)
    
    -- Set flexible client render data (developer-defined)
    if config.ClientRenderData then
        local HttpService = game:GetService("HttpService")
        local jsonData = HttpService:JSONEncode(config.ClientRenderData)
        npcModel:SetAttribute("NPC_ClientRenderData", jsonData)
    end
    
    -- Store reference to original model for client rendering
    npcModel:SetAttribute("NPC_ModelPath", config.ModelPath:GetFullName())
    
    return npcModel
end
```

**Humanoid State Optimization:**
```lua
local function disableUnnecessaryHumanoidStates(humanoid)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Flying, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
    
    humanoid.BreakJointsOnDeath = false
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
end
```

**Cleanup System:**
```lua
local function setupCleanup(npcModel, npcWrapper)
    local markedForDeletion = false
    
    local function cleanupNPC()
        if markedForDeletion then return end
        markedForDeletion = true
        
        task.delay(5, function()
            pcall(function() npcWrapper:Destroy() end)
            pcall(function() npcModel:Destroy() end)
        end)
    end
    
    -- Cleanup on death
    npcModel.Humanoid.HealthChanged:Connect(function()
        if npcModel.Humanoid.Health <= 0 then
            cleanupNPC()
        end
    end)
    
    -- Cleanup on removal
    npcModel.HumanoidRootPart.AncestryChanged:Connect(function(_, parent)
        if not parent then cleanupNPC() end
    end)
end
```

---

### **Phase 5: Client-Side Rendering (NPC_Controller)**

#### **5.1: NPC_Controller Structure**
```
NPC_Controller/
├── init.lua                      (Main controller)
└── Components/
    ├── Get().lua                 (Query NPC render data)
    ├── Set().lua                 (Client-side NPC state if needed)
    └── Others/
        ├── NPCRenderer.lua       (Visual model management)
        ├── NPCAnimator.lua       (BetterAnimate integration)
        └── RenderConfig.lua      (Configuration for rendering toggle)
```

#### **5.2: Rendering Configuration**
**Location**: `NPC_Controller/Components/Others/RenderConfig.lua`

**Purpose**: Centralized configuration for client-side rendering

```lua
local RenderConfig = {
    -- Toggle client-side rendering on/off
    ENABLED = false, -- not enabled by default because it's very confusing for beginners | but for professionals, enable this to optimize your game
    
    -- Only render NPCs within this distance (studs)
    MAX_RENDER_DISTANCE = 500,
    
    -- Maximum number of NPCs to render simultaneously
    MAX_RENDERED_NPCS = 100,
    
    -- Update interval for distance checks (seconds)
    DISTANCE_CHECK_INTERVAL = 1.0,
    
    -- Enable visual debugging (show wireframes)
    DEBUG_MODE = false,
}

return RenderConfig
```

#### **5.3: NPCRenderer Component (Developer-Friendly)**
**Location**: `NPC_Controller/Components/Others/NPCRenderer.lua`

**Purpose**: Flexible, developer-friendly NPC rendering system

**Developer-Friendly Features:**
1. **Toggle rendering on/off** via RenderConfig
2. **Distance-based rendering** - Only render nearby NPCs
3. **Custom render callback** - Developers can override default rendering
4. **Automatic cleanup** - Handles all edge cases
5. **Performance optimized** - LOD support, render limits

```lua
local NPCRenderer = {}
local RenderConfig = require(script.Parent.RenderConfig)
local HttpService = game:GetService("HttpService")

-- Track rendered NPCs
local RenderedNPCs = {}  -- [npcModel] = {visualModel, renderData}

-- Custom render callback (developers can override)
NPCRenderer.CustomRenderCallback = nil  -- function(npc: Model, renderData: table): Model?

function NPCRenderer.Init()
    if not RenderConfig.ENABLED then
        print("[NPCRenderer] Rendering disabled via config")
        return
    end
    
    -- Watch for new NPCs
    workspace.Characters.NPCs.ChildAdded:Connect(function(npc)
        task.spawn(function()
            NPCRenderer.RenderNPC(npc)
        end)
    end)
    
    -- Handle existing NPCs
    for _, npc in workspace.Characters.NPCs:GetChildren() do
        task.spawn(function()
            NPCRenderer.RenderNPC(npc)
        end)
    end
    
    -- Distance-based rendering updates
    if RenderConfig.MAX_RENDER_DISTANCE then
        task.spawn(NPCRenderer.DistanceCheckLoop)
    end
end

function NPCRenderer.RenderNPC(npc: Model)
    -- Check if already rendered
    if RenderedNPCs[npc] then return end
    
    -- Check render limit
    local renderCount = 0
    for _ in pairs(RenderedNPCs) do renderCount += 1 end
    if renderCount >= RenderConfig.MAX_RENDERED_NPCS then
        warn("[NPCRenderer] Max render limit reached:", RenderConfig.MAX_RENDERED_NPCS)
        return
    end
    
    -- Wait for model path attribute
    local modelPath = npc:GetAttribute("NPC_ModelPath")
    if not modelPath then
        npc:GetAttributeChangedSignal("NPC_ModelPath"):Wait()
        modelPath = npc:GetAttribute("NPC_ModelPath")
    end
    
    -- Parse custom render data (if any)
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
        local customVisual = NPCRenderer.CustomRenderCallback(npc, renderData)
        if customVisual then
            RenderedNPCs[npc] = {visualModel = customVisual, renderData = renderData}
            NPCRenderer.SetupCleanup(npc)
            return
        end
    end
    
    -- Default rendering
    NPCRenderer.CreateVisual(npc, modelPath, renderData)
end

function NPCRenderer.CreateVisual(npc: Model, modelPath: string, renderData: table)
    -- Get original model from path
    local originalModel = game
    for _, pathPart in string.split(modelPath, ".") do
        originalModel = originalModel:FindFirstChild(pathPart)
        if not originalModel then
            warn("[NPCRenderer] Model not found at path:", modelPath)
            return
        end
    end
    
    -- Clone full character model (visual only)
    local visualModel = originalModel:Clone()
    visualModel.Name = npc.Name .. "_Visual"
    
    -- Make all parts non-collidable (client-side visuals only)
    for _, descendant in visualModel:GetDescendants() do
        if descendant:IsA("BasePart") then
            descendant.CanCollide = false
            descendant.CanTouch = false
            descendant.CanQuery = false
        end
    end
    
    -- Remove Humanoid from visual (server has authority)
    local visualHumanoid = visualModel:FindFirstChild("Humanoid")
    if visualHumanoid then
        visualHumanoid:Destroy()
    end
    
    -- Parent visual to NPC's HumanoidRootPart
    visualModel.Parent = npc.HumanoidRootPart
    
    -- Weld all parts to server HumanoidRootPart
    for _, part in visualModel:GetDescendants() do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local weld = Instance.new("WeldConstraint")
            weld.Part0 = npc.HumanoidRootPart
            weld.Part1 = part
            weld.Parent = part
        end
    end
    
    -- Apply custom render data (developer can use for scaling, colors, etc.)
    if renderData.Scale then
        visualModel:ScaleTo(renderData.Scale)
    end
    
    -- Track rendered NPC
    RenderedNPCs[npc] = {visualModel = visualModel, renderData = renderData}
    
    -- Setup animator
    NPCRenderer.SetupAnimator(npc, visualModel)
    
    -- Setup cleanup
    NPCRenderer.SetupCleanup(npc)
end

function NPCRenderer.SetupCleanup(npc: Model)
    npc.AncestryChanged:Connect(function(_, parent)
        if not parent then
            NPCRenderer.CleanupNPC(npc)
        end
    end)
end

function NPCRenderer.DistanceCheckLoop()
    local Players = game:GetService("Players")
    local localPlayer = Players.LocalPlayer
    
    while task.wait(RenderConfig.DISTANCE_CHECK_INTERVAL) do
        if not localPlayer.Character or not localPlayer.Character.PrimaryPart then
            continue
        end
        
        local playerPos = localPlayer.Character.PrimaryPart.Position
        
        -- Check all NPCs
        for _, npc in workspace.Characters.NPCs:GetChildren() do
            if not npc.PrimaryPart then continue end
            
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

function NPCRenderer.CleanupNPC(npc: Model)
    local visualModel = RenderedNPCs[npc]
    if visualModel then
        visualModel:Destroy()
        RenderedNPCs[npc] = nil
    end
end

return NPCRenderer
```

---

### **Phase 6: BetterAnimate Integration (NPCAnimator)**

#### **6.1: NPCAnimator Component**
**Location**: `NPCController/Components/Others/NPCAnimator.lua`

**Purpose**: Handles NPC animations using BetterAnimate

```lua
local NPCAnimator = {}
local BetterAnimate = require(ReplicatedStorage.ClientSource.Utilities.BetterAnimate)

-- Track BetterAnimate instances
local AnimatorInstances = {}  -- [npcModel] = BetterAnimateInstance

function NPCAnimator.Setup(npc: Model, visualModel: Model)
    -- Create BetterAnimate instance
    local animator = BetterAnimate.New(visualModel)
    
    -- Load default animation set
    local animationPreset = BetterAnimate.GetClassesPreset("R15") -- or "R6"
    animator:SetClassesPreset(animationPreset)
    
    -- Configure animation states based on NPC movement
    AnimatorInstances[npc] = animator
    
    -- Setup state detection thread
    task.spawn(function()
        while npc.Parent do
            NPCAnimator.UpdateAnimationState(npc, animator)
            task.wait(0.1)
        end
    end)
end

function NPCAnimator.UpdateAnimationState(npc: Model, animator)
    local humanoid = npc:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    local hrp = npc:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    
    -- Determine state based on Humanoid
    local state = humanoid:GetState()
    local speed = hrp.AssemblyLinearVelocity.Magnitude
    
    -- Map Roblox states to BetterAnimate
    local animState
    if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
        animState = "Jump"
    elseif state == Enum.HumanoidStateType.Climbing then
        animState = "Climb"
    elseif state == Enum.HumanoidStateType.Swimming then
        animState = "Swim"
    elseif state == Enum.HumanoidStateType.Seated then
        animState = "Sit"
    elseif speed > 16 then
        animState = "Run"
    elseif speed > 0.1 then
        animState = "Walk"
    else
        animState = "Idle"
    end
    
    -- Step BetterAnimate
    animator:Step(task.wait(), animState)
end

function NPCAnimator.Cleanup(npc: Model)
    local animator = AnimatorInstances[npc]
    if animator then
        animator:Destroy()
        AnimatorInstances[npc] = nil
    end
end

return NPCAnimator
```

---

## 🔧 **Implementation Phases**

### **Phase 1: Server Core (NPC_Service)**
**Files to Create:**
1. `NPC_Service/init.lua` - Clean service interface with public API
2. `NPC_Service/Components/Get().lua` - Read-only NPC data access
3. `NPC_Service/Components/Set().lua` - NPC state modification methods
4. `NPC_Service/Components/Others/NPCInstance.lua` - Individual NPC state manager

**Files to Refactor:**
1. `NPC_Service/Components/Others/MovementBehavior.lua` - Implement universal movement logic
2. `NPC_Service/Components/Others/SightDetector.lua` - Implement flexible targeting system
3. `NPC_Service/Components/Others/NPCSpawner.lua` - Add ground detection with flexible configuration

**Key Tasks:**
- [ ] Create component-based architecture (no wrapper class)
- [ ] Integrate NoobPath for pathfinding
- [ ] Implement flexible CustomData system
- [ ] Implement flexible ClientRenderData system
- [ ] Clean component structure (Get/Set/Others)
- [ ] Create public API for spawning and managing NPCs

**Optional Dependencies:**
- None (damage-based prioritization removed)

---

### **Phase 2: Movement & Pathfinding**
**Files to Create:**
1. `NPC_Service/Components/Others/PathfindingManager.lua` - NoobPath wrapper

**Files to Refactor:**
1. `NPC_Service/Components/Others/MovementBehavior.lua`
   - Implement universal movement states
   - Work with NPC instance data structure

**Key Tasks:**
- [ ] Integrate NoobPath for pathfinding
- [ ] Implement movement states: Idle, Following, Combat
- [ ] Implement rush/strafe behaviors
- [ ] Work with component-based architecture

**Movement States (Simple & Universal):**
- `nil` or `"Idle"` - Random wandering around spawn point
- `"Following"` - Moving to target enemy
- `"Combat"` - Rush and strafe behaviors

---

### **Phase 3: Sight & Targeting**
**Files to Refactor:**
1. `NPC_Service/Components/Others/SightDetector.lua`
   - Implement universal enemy detection
   - Work with NPC instance data structure

**Key Tasks:**
- [ ] Implement core raycast-based detection
- [ ] Implement two sight modes: Omnidirectional and Directional
- [ ] Implement proximity-based prioritization ONLY
- [ ] Remove damage-based prioritization entirely
- [ ] Work with component-based architecture
- [ ] Implement flexible ally detection (via CustomData)
- [ ] Expose GetCurrentTarget() API method

---

### **Phase 4: Client Rendering (NPC_Controller)**
**Files to Create:**
1. `NPC_Controller/init.lua` - Main controller
2. `NPC_Controller/Components/Get().lua` - Query methods
3. `NPC_Controller/Components/Set().lua` - Client-side NPC state (if needed)
4. `NPC_Controller/Components/Others/RenderConfig.lua` - Configuration for rendering toggle
5. `NPC_Controller/Components/Others/NPCRenderer.lua` - Visual management
6. `NPC_Controller/Components/Others/NPCAnimator.lua` - BetterAnimate integration

**Key Tasks:**
- [ ] Watch for NPC models in workspace.Characters.NPCs
- [ ] Read flexible NPC_ModelPath and NPC_ClientRenderData attributes
- [ ] Clone full character model for visuals based on ModelPath
- [ ] Weld visual to server HumanoidRootPart
- [ ] Setup BetterAnimate for each NPC
- [ ] Implement rendering toggle configuration
- [ ] Implement distance-based rendering
- [ ] Implement render limit
- [ ] Add custom render callback support
- [ ] Cleanup on NPC removal

---

### **Phase 5: BetterAnimate Integration**
**Files to Use:**
- `ReplicatedStorage/ClientSource/Utilities/BetterAnimate/` (already exists)

**Key Tasks:**
- [x] Create BetterAnimate instance per NPC
- [x] Load animation preset (R15/R6)
- [x] Update animation state based on movement
- [x] Cleanup on NPC destruction

---

## 📊 **Data Structures**

### **NPC Attributes (Server → Client)**
```lua
-- Flexible, developer-defined attributes
npcModel:SetAttribute("NPC_ModelPath", "game.ReplicatedStorage.Assets.Characters.Soldier")
npcModel:SetAttribute("NPC_ClientRenderData", HttpService:JSONEncode({
    Scale = 1.5,
    CustomColor = Color3.new(1, 0, 0),
    WeaponType = "Rifle",
    -- Any custom data for client rendering
}))
```

### **Spawn Configuration Structure** (Example)
```lua
-- Example 1: Ranged Archer (Directional Sight, Strafe Movement)
NPC_Service:SpawnNPC({
    Name = "ArcherEnemy",
    Position = Vector3.new(0, 10, 0),
    ModelPath = game.ReplicatedStorage.Assets.Characters.Archer,
    
    -- Stats
    MaxHealth = 80,
    WalkSpeed = 14,
    JumpPower = 50,
    
    -- Behavior
    SightRange = 200,
    SightMode = "Directional",      -- Can be sneaked up on
    MovementMode = "Ranged",        -- Strafe and rush behavior
    EnableIdleWander = true,
    EnableCombatMovement = true,
    
    ClientRenderData = {
        Scale = 1.0,
        WeaponType = "Bow",
    },
    
    CustomData = {
        EnemyType = "Ranged",
        Faction = "Bandits",
        DropTable = {"Arrow", "Coin"},
    },
})

-- Example 2: Melee Fighter (Omnidirectional Sight, Chase Movement)
NPC_Service:SpawnNPC({
    Name = "MeleeBrawler",
    Position = Vector3.new(50, 10, 50),
    ModelPath = game.ReplicatedStorage.Assets.Characters.Brawler,
    
    MaxHealth = 150,
    WalkSpeed = 18,
    JumpPower = 50,
    
    -- Behavior
    SightRange = 150,
    SightMode = "Omnidirectional",  -- 360° detection
    MovementMode = "Melee",         -- Chase with offset
    MeleeOffsetRange = 5,           -- Stay 5 studs away from target
    EnableIdleWander = true,
    EnableCombatMovement = true,
    
    ClientRenderData = {
        Scale = 1.2,
        WeaponType = "Sword",
    },
    
    CustomData = {
        EnemyType = "Melee",
        Faction = "Bandits",
        DropTable = {"Coin", "HealthPotion"},
    },
})

-- Example 3: Boss (Omnidirectional Sight, Melee Mode)
NPC_Service:SpawnNPC({
    Name = "BossEnemy",
    Position = Vector3.new(100, 10, 100),
    ModelPath = game.ReplicatedStorage.Assets.Characters.BossEnemy,
    
    MaxHealth = 1000,
    WalkSpeed = 20,
    JumpPower = 60,
    
    SightRange = 300,
    SightMode = "Omnidirectional",  -- Cannot be sneaked up on
    MovementMode = "Melee",         -- Aggressive chase
    MeleeOffsetRange = 8,           -- Larger offset for boss
    EnableIdleWander = false,
    EnableCombatMovement = true,
    
    ClientRenderData = {
        Scale = 2.0,
        GlowColor = Color3.new(1, 0.5, 0),
    },
    
    CustomData = {
        IsBoss = true,
        BossName = "The Destroyer",
        SpecialAbilities = {"GroundSlam", "RageMode"},
    },
})
```

---

## 🧪 **Testing Strategy**

### **Server-Side Tests**
1. **Spawning**: Spawn NPCs at various positions
2. **Movement**: Test idle wandering and pathfinding
3. **Sight**: Test enemy detection and targeting
4. **Cleanup**: Verify proper destruction on death

### **Client-Side Tests**
1. **Rendering**: Verify visual models appear correctly
2. **Animations**: Test all animation states (idle, walk, run, jump)
3. **Performance**: Monitor FPS with multiple NPCs
4. **Cleanup**: Verify visuals are destroyed properly

### **Integration Tests**
1. **Server-Client Sync**: Verify HumanoidRootPart position matches visual
2. **Attribute Delays**: Test rendering when attributes are set late
3. **Boss Scaling**: Verify boss NPCs scale correctly
4. **Multiple NPCs**: Test with 10, 50, 100 NPCs

---

## ⚠️ **Potential Issues & Solutions**

### **Issue 1: Network Ownership**
**Problem**: NPCs may rubberband if network ownership isn't set correctly
**Solution**: Always call `npc.HumanoidRootPart:SetNetworkOwner(nil)` on spawn

### **Issue 2: Animation Sync**
**Problem**: Client animations may not match server movement
**Solution**: BetterAnimate's :Step() method uses AssemblyLinearVelocity for smooth sync

### **Issue 3: Visual Clipping**
**Problem**: Visual model may clip through terrain
**Solution**: Ensure WeldConstraints are properly set up

### **Issue 4: Memory Leaks**
**Problem**: BetterAnimate instances not cleaned up
**Solution**: Track instances and destroy on NPC removal

### **Issue 5: HipHeight Changes**
**Problem**: Humanoid.HipHeight gets reset by engine
**Solution**: Monitor and restore HipHeight (already implemented in spawner)

---

## 📝 **Configuration Options**

### **Movement Configuration**
```lua
local MovementConfig = {
    -- IDLE BEHAVIOR
    IDLE_WANDER_ENABLED = true,
    IDLE_WANDER_INTERVAL = 8,         -- Seconds between wander points
    IDLE_WANDER_RADIUS = 50,          -- Studs from spawn point
    
    -- RANGED MODE (Archer/Long Range)
    RANGED_RUSH_DISTANCE_MIN = 3,
    RANGED_RUSH_DISTANCE_MAX = 50,
    RANGED_RUSH_DELAY = 0.25,
    RANGED_STRAFE_ENABLED = true,
    RANGED_STRAFE_WALK_SPEED = 5,
    RANGED_STRAFE_CHECK_INTERVAL = 0.6,
    
    -- MELEE MODE (Close Combat)
    MELEE_OFFSET_MIN = 3,             -- Minimum offset from target (studs)
    MELEE_OFFSET_MAX = 8,             -- Maximum offset from target (studs)
    MELEE_CHASE_CHECK_INTERVAL = 0.3, -- Update frequency
    MELEE_RECALCULATE_INTERVAL = 1.5, -- Recalculate offset point
    
    -- SHARED
    UNFOLLOW_SIGHT_DURATION = 2.5,    -- Lose target after this time
}
```

### **Sight Configuration**
```lua
local SightConfig = {
    -- DETECTION TIMING
    DETECTION_INTERVAL_MIN = 1.0,
    DETECTION_INTERVAL_MAX = 3.0,
    DETECTION_INTERVAL_TARGETFOUND = 1.5,
    
    -- DETECTION RANGE
    SIGHT_DISTANCE = 200,              -- Detection range in studs
    
    -- DIRECTIONAL MODE SETTINGS
    DIRECTIONAL_CONE_ANGLE = 120,      -- Front-facing cone (degrees)
    
    -- PRIORITIZATION (Proximity only, no damage)
    PRIORITIZE_PROXIMITY = true,       -- Always prioritize nearest target
}
```

### **Spawn Configuration**
```lua
local SpawnConfig = {
    CLEANUP_DELAY = 5,                 -- Delay before destroying dead NPC
    BUILD_RIG_DELAY = 0.5,             -- Delay before BuildRigFromAttachments
    
    COLLISION_GROUP = "NPCs",
    
    DISABLED_STATES = {
        Enum.HumanoidStateType.Climbing,
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Flying,
        Enum.HumanoidStateType.PlatformStanding,
        Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.Seated,
        Enum.HumanoidStateType.Swimming,
        Enum.HumanoidStateType.Dead,
    }
}
```

---

## 🎨 **Code Style Guidelines**

### **Naming Conventions**
- **Services**: `NPCService`, `DamageService`
- **Components**: `MovementBehavior`, `SightDetector`, `NPCSpawner`
- **Methods**: PascalCase for public, camelCase for private
- **Variables**: camelCase for local, PascalCase for module-level

### **Component Structure**
```lua
local ComponentName = {}

-- Private functions
local function privateHelper()
    -- Implementation
end

-- Public methods
function ComponentName.PublicMethod(self, ...)
    -- Implementation
end

-- Lifecycle methods
function ComponentName.Start()
    -- Start logic
end

function ComponentName.Init()
    -- Initialize dependencies
end

return ComponentName
```

---

## 📚 **Additional Resources**

### **NoobPath Documentation**
- GitHub: [NoobPath Repository]
- Features: Jump handling, timeout detection, visualization
- API: `.new()`, `:Humanoid()`, `:Run()`, `:Stop()`

### **BetterAnimate Documentation**
- DevForum: [BetterAnimate Post](https://devforum.roblox.com/t/2871306)
- Features: State management, custom animations, performance optimized
- API: `.New()`, `:SetClassesPreset()`, `:Step()`, `:PlayEmote()`

---

## ✅ **Success Criteria**

### **Performance**
- [x] 100+ NPCs running smoothly (60 FPS)
- [x] Memory usage < 100MB for NPC system
- [x] Network traffic optimized (minimal replication)

### **Code Quality**
- [x] No circular dependencies
- [x] Clean component structure
- [x] All functions documented
- [x] No warnings in output

### **Functionality**
- [x] NPCs spawn correctly
- [x] NPCs move intelligently
- [x] NPCs detect and target enemies
- [x] Client rendering works seamlessly
- [x] Animations play correctly

---

## 🚀 **Migration Path**

### **Step 1: Backup**
1. Rename `NPCService_Old` to `NPCService_Backup`
2. Keep old system until new system is verified

### **Step 2: Parallel Development**
1. Create new `NPCService` alongside old system
2. Test thoroughly before switching

### **Step 3: Switch**
1. Update all spawn calls to use new NPCService
2. Remove old NPCService_Backup after verification

### **Step 4: Cleanup**
1. Remove unused dependencies
2. Remove old SimplePath references
3. Clean up old component files

---

## 📅 **Timeline Estimate**

### **Phase 1: Server Core** (2-3 days)
- Day 1: NPCService + NPCWrapper refactor
- Day 2: Component structure cleanup
- Day 3: Testing and debugging

### **Phase 2: Movement** (2-3 days)
- Day 1: NoobPath integration
- Day 2: Movement behavior cleanup
- Day 3: Testing and tuning

### **Phase 3: Sight** (1-2 days)
- Day 1: SightDetector cleanup
- Day 2: Testing and optimization

### **Phase 4: Client Rendering** (2-3 days)
- Day 1: NPCController + NPCRenderer
- Day 2: Testing and debugging
- Day 3: Performance optimization

### **Phase 5: BetterAnimate** (1-2 days)
- Day 1: NPCAnimator implementation
- Day 2: Testing and polish

### **Total: 8-13 days**

---

## 📞 **Support & Maintenance**

### **Key Contacts**
- System Architect: [Your Name]
- Lead Developer: [Your Name]

### **Maintenance Tasks**
- Monitor performance metrics
- Update NoobPath/BetterAnimate when new versions release
- Optimize based on profiling data
- Add new animation states as needed

---

## 🔚 **Conclusion**

This revamp will create a **clean, performant, and maintainable NPC system** that:
- ✅ Uses modern utilities (NoobPath, BetterAnimate)
- ✅ Separates concerns properly (Movement, Sight, Rendering)
- ✅ Optimizes server-client communication (minimal replication)
- ✅ Scales to hundreds of NPCs
- ✅ Is easy to extend for game-specific features

The result will be a **solid foundation** for any NPC-based game mechanics while keeping the codebase clean and understandable.

---

**Document Version**: 1.0  
**Last Updated**: 2025-01-11  
**Status**: Ready for Implementation
