# NPC System Architecture

## Overview

The NPC System is a modular, client-server architecture that manages NPC spawning, behavior, rendering, and physics. It supports two modes: **Server-Side Physics** (traditional) and **Client-Side Physics** (optimized for 1000+ NPCs).

---

## System Components

### Server-Side (`NPC_Service`)

**Location**: `src/ServerScriptService/ServerSource/Server/NPC_Service/`

#### Core Components

- **NPCSpawner** - Spawns NPCs with server-side physics (traditional mode)
- **ClientPhysicsSpawner** - Spawns NPCs with client-side physics (optimized mode)
- **MovementBehavior** - Handles NPC movement logic (ranged, melee, idle wandering)
- **PathfindingManager** - Manages pathfinding using NoobPath library
- **SightDetector** - Detects targets (omnidirectional or directional vision)
- **SightVisualizer** - Visual debugging for sight ranges and cones
- **ClientPhysicsSync** - Syncs client-side NPC data to server
- **ServerFallbackSimulator** - Server-side simulation fallback for client physics NPCs
- **Get()** - Read NPC data
- **Set()** - Modify NPC data

---

### Client-Side (`NPC_Controller`)

**Location**: `src/ReplicatedStorage/ClientSource/Client/NPC_Controller/`

#### Core Components

- **NPCRenderer** - Renders NPC visual models on client (traditional mode)
- **NPCAnimator** - Handles NPC animations using BetterAnimate
- **ClientPhysicsRenderer** - Renders and simulates client physics NPCs
- **ClientNPCManager** - Manages client-side NPC instances
- **ClientNPCSimulator** - Main client-side physics simulation loop
- **ClientMovement** - Client-side movement behavior
- **ClientPathfinding** - Client-side pathfinding using NoobPath
- **ClientSightDetector** - Client-side target detection
- **ClientSightVisualizer** - Client-side sight debugging visuals
- **ClientJumpSimulator** - Handles client-side NPC jumping
- **Get()** - Read client NPC data
- **Set()** - Modify client NPC data

---

### Shared Components

**Location**: `src/ReplicatedStorage/SharedSource/Datas/NPCs/`

- **RenderConfig** - Client rendering configuration (distance culling, render limits)
- **OptimizationConfig** - Global optimization flags (UseClientPhysics)

---

## System Flow

### Traditional Server-Side Physics Mode

```
1. NPC_Service:SpawnNPC(config) called
2. NPCSpawner creates NPC model on server
3. MovementBehavior & SightDetector initialize
4. PathfindingManager handles pathfinding
5. NPCRenderer (client) clones visual model
6. NPCAnimator (client) handles animations
```

### Client-Side Physics Mode (UseClientPhysics = true)

```
1. NPC_Service:SpawnNPC(config) called with UseClientPhysics=true
2. ClientPhysicsSpawner creates minimal server data
3. Data synced to clients via ClientPhysicsSync
4. ClientPhysicsRenderer (client) creates full NPC model
5. ClientNPCSimulator (client) runs physics loop
6. ClientMovement & ClientPathfinding handle behavior
7. ClientSightDetector detects targets
8. ServerFallbackSimulator provides backup server simulation
```

---

## Component Connections

### Server Components
```
NPC_Service (Main)
├── NPCSpawner ──────────┐
├── ClientPhysicsSpawner ┤
├── MovementBehavior ────┤
├── PathfindingManager ──┤
├── SightDetector ───────┤
├── SightVisualizer ─────┤
├── ClientPhysicsSync ───┤
├── ServerFallbackSimulator
├── Get()
└── Set()
```

### Client Components
```
NPC_Controller (Main)
├── NPCRenderer ─────────┐
├── NPCAnimator ─────────┤
├── ClientPhysicsRenderer ┤
├── ClientNPCManager ────┤
├── ClientNPCSimulator ──┤
├── ClientMovement ──────┤
├── ClientPathfinding ───┤
├── ClientSightDetector ─┤
├── ClientSightVisualizer ┤
├── ClientJumpSimulator ─┤
├── Get()
└── Set()
```

---

## Data Flow

### Traditional Mode
```
Server (NPC_Service)
    ↓ (Replicates NPC Model)
Client (NPC_Controller)
    ↓ (Reads ModelPath attribute)
NPCRenderer (Clones visual)
    ↓
NPCAnimator (Animates visual)
```

### Client Physics Mode
```
Server (NPC_Service)
    ↓ (Sends NPC data via RemoteEvents)
ClientPhysicsSync
    ↓
Client (ClientNPCManager)
    ↓
ClientPhysicsRenderer (Creates full model)
    ↓
ClientNPCSimulator (Physics loop)
    ├── ClientMovement
    ├── ClientPathfinding
    ├── ClientSightDetector
    └── ClientJumpSimulator
    ↓ (Sends position updates)
Server (ServerFallbackSimulator)
```

---

## Key Differences Between Modes

| Feature | Traditional Mode | Client Physics Mode |
|---------|-----------------|---------------------|
| **Physics** | Server | Client |
| **Pathfinding** | Server | Client |
| **Network Traffic** | High | Low (70-95% reduction) |
| **NPC Limit** | ~100 NPCs | 1000+ NPCs |
| **Security** | Full server authority | Client has position authority |
| **Use Case** | Combat NPCs | Ambient/background NPCs |

---

## Configuration Files

- **RenderConfig.lua** - Controls client rendering behavior
  - `ENABLED` - Toggle client rendering
  - `MAX_RENDER_DISTANCE` - Distance culling
  - `MAX_RENDERED_NPCS` - Render limit

- **OptimizationConfig.lua** - Global optimization settings
  - `UseClientPhysics` - Global client physics toggle

---

## API Entry Points

### Server API
```lua
-- Spawn NPC (traditional or client physics based on config)
NPC_Service:SpawnNPC(config)

-- Read NPC data
NPC_Service.GetComponent:GetNPCData(npcModel)
NPC_Service.GetComponent:GetCurrentTarget(npcModel)
NPC_Service.GetComponent:GetAllNPCs()

-- Modify NPC data
NPC_Service.SetComponent:SetTarget(npcModel, target)
NPC_Service.SetComponent:SetDestination(npcModel, destination)
NPC_Service.SetComponent:SetCustomData(npcModel, key, value)
NPC_Service.SetComponent:DestroyNPC(npcModel)
```

### Client API
```lua
-- Read rendered NPC data
NPC_Controller.GetComponent:GetRenderedNPCs()

-- Access client NPC manager
NPC_Controller.Components.ClientNPCManager
```

---

## External Dependencies

- **NoobPath** - Advanced pathfinding library
- **BetterAnimate** - Animation system
- **Knit** - Framework for services/controllers
- **ProfileService** - Player data management (collision integration)
