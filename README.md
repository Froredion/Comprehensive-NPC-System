# 🎮 Comprehensive NPC System for Roblox

A production-ready, highly flexible NPC system built on **SuperbulletFrameworkV1-Knit** that provides server-authoritative NPCs with client-side rendering optimization, advanced pathfinding, sight detection, and behavior systems.

[![Framework](https://img.shields.io/badge/Framework-SuperbulletV1--Knit-blue)](https://github.com/Froredion/SuperbulletFramework)
[![Roblox](https://img.shields.io/badge/Platform-Roblox-red)](https://roblox.com)
[![License](https://img.shields.io/badge/License-Open%20Source-green)](#)

---

## 📋 Table of Contents

- [Why This is the Best Open-Sourced NPC System](#-why-this-is-the-best-open-sourced-npc-system)
- [Features](#-features)
- [Getting Started](#-getting-started)
- [Configuration](#%EF%B8%8F-configuration)
- [Usage Examples](#-usage-examples)
- [System Components](#-system-components)
- [Future Implementations](#-future-implementations)
- [Testing & Examples](#-testing--examples)
- [Performance](#-performance)
- [Contributing](#-contributing)

---

## ⭐ Why This is the Best Open-Sourced NPC System

### 🏆 Production-Ready Architecture

- **Server-Authoritative Design**: Full server control over NPC behavior and state
- **Modular Component System**: Extensible architecture using `ComponentsInitializer` pattern
- **Framework Integration**: Built on proven SuperbulletFrameworkV1-Knit for scalability
- **Clean Separation of Concerns**: Server/Client/Shared code organization

### 🚀 Performance & Optimization

- **Client-Side Rendering**: Optional client-side rendering system reduces server load
- **Distance-Based Culling**: Intelligent rendering based on player proximity
- **Batch Operations**: Efficient NPC spawning and management
- **Scalable to 100+ NPCs**: Tested and optimized for large-scale scenarios

### 🎯 Advanced Features

- **Dual Sight Modes**: Omnidirectional (360°) and Directional (cone-based) detection
- **Smart Pathfinding**: Integrated NoobPath library with obstacle avoidance and jump handling
- **Flexible Movement**: Ranged, Melee, and custom movement behaviors
- **Customizable Behavior**: Toggle idle wandering, combat movement, pathfinding on/off
- **Visual Debugging**: Built-in sight range and cone visualization tools

### 🛠️ Developer-Friendly

- **Comprehensive Documentation**: Detailed configuration parameters and examples
- **Type-Safe API**: Clear function signatures with parameter validation
- **Easy Integration**: Simple spawn/destroy API with rich configuration
- **Extensible Components**: Add custom behaviors without modifying core system
- **Example Test Scripts**: Ready-to-run examples for learning

### 🔮 Future-Proof

- **Planned Optimizations**: Client-side physics simulation for 1000+ NPCs
- **Advanced Hitbox System**: Batch detection for high fire rate scenarios
- **Actively Maintained**: Regular updates and improvements
- **Open Architecture**: Easy to extend for game-specific needs

---

## ✨ Features

### Core Features

- ✅ **Server-Authoritative NPCs** - Full server control over NPC state and behavior
- ✅ **Client-Side Rendering** - Optional visual rendering on client for optimization
- ✅ **Advanced Pathfinding** - NoobPath integration with jump and obstacle handling
- ✅ **Dual Sight Detection** - Omnidirectional (360°) and Directional (cone-based)
- ✅ **Flexible Movement System** - Ranged, Melee, and custom movement modes
- ✅ **Idle Wandering** - NPCs can randomly wander when idle
- ✅ **Combat Movement** - Dynamic movement during target engagement
- ✅ **Faction System** - NPCs can have factions (same faction won't attack each other)
- ✅ **Visual Customization** - Scale, color tinting, and transparency for client rendering
- ✅ **Custom Data Support** - Attach game-specific attributes to NPCs
- ✅ **Animation Integration** - BetterAnimate system for smooth animations
- ✅ **Visual Debugging** - Sight range and cone visualization tools

### Behavior Configuration

- **SightRange**: Configurable detection range in studs
- **SightMode**: Choose between Omnidirectional or Directional detection
- **CanWalk**: Enable/disable all movement
- **MovementMode**: Ranged or Melee behaviors
- **UsePathfinding**: Toggle advanced pathfinding vs simple MoveTo()
- **EnableIdleWander**: Random wandering when no target
- **EnableCombatMovement**: Dynamic movement during combat

### Visual Features

- **Distance-Based Rendering**: NPCs only render when players are nearby
- **Max Rendered NPCs**: Cap rendering for performance control
- **Client-Side Scale**: Visual scale multiplier
- **Custom Colors**: Color tinting for visual variety
- **Transparency**: Optional transparency effects
- **Health Displays**: Configurable health bar UI

---

## 🚀 Getting Started

### Prerequisites

- Roblox Studio
- Basic knowledge of Lua and Roblox scripting

### Installation

Choose one of the following installation methods:

#### Method 1: SuperbulletAI (Fastest - 60 seconds!) ⚡

The easiest and fastest way to add this NPC System to your game:

1. Visit **[SuperbulletAI](http://ai.superbulletstudios.com/)**
2. Type: `add npc system to my roblox game`
3. Done! The AI will automatically integrate the system into your game

> **Note:** SuperbulletFrameworkV1-Knit will be automatically installed if not present.

#### Method 2: Download RBXL Place File 📦

Perfect for testing and learning:

1. Download `npc_system_place.rbxl` from the [GitHub Repository](https://github.com/Froredion/Comprehensive-NPC-System)
2. Open the file in Roblox Studio
3. Explore the pre-configured test scenarios and examples
4. Copy the source files to your own game when ready

#### Method 3: GitHub + Rojo (For Developers) 🛠️

For version control and advanced development:

1. Clone the repository:
   ```bash
   git clone https://github.com/Froredion/Comprehensive-NPC-System.git
   ```
2. Install [Rojo](https://rojo.space/) if not already installed
3. Build and sync to Roblox Studio:
   ```bash
   rojo serve
   ```
4. Connect from Roblox Studio using the Rojo plugin

### Quick Start Example

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

-- Wait for Knit to initialize
Knit.OnStart():await()

local NPC_Service = Knit.GetService("NPC_Service")

-- Spawn a basic NPC
local myNPC = NPC_Service:SpawnNPC({
    Name = "BasicNPC",
    Position = Vector3.new(0, 10, 0),
    ModelPath = game.ReplicatedStorage.Assets.NPCs.Characters.Rig,

    -- Stats
    MaxHealth = 100,
    WalkSpeed = 16,
    JumpPower = 50,

    -- Behavior
    SightRange = 60,
    SightMode = "Directional",
    MovementMode = "Ranged",
    EnableIdleWander = true,
    EnableCombatMovement = true,
})

-- Set a target
local player = game.Players:GetPlayers()[1]
if player.Character then
    NPC_Service:SetTarget(myNPC, player.Character)
end
```

---

## ⚙️ Configuration

### SpawnNPC Configuration Parameters

```lua
NPC_Service:SpawnNPC({
    -- Identity
    Name: string,              -- NPC name
    Position: Vector3,         -- Spawn position
    Rotation: CFrame?,         -- Optional rotation (default: no rotation)
    ModelPath: Instance,       -- Path to character model (e.g., ReplicatedStorage.Assets.NPCs.Characters.Rig)

    -- Stats
    MaxHealth: number?,        -- Maximum health (default: 100)
    WalkSpeed: number?,        -- Walk speed in studs/second (default: 16)
    JumpPower: number?,        -- Jump power (default: 50)

    -- Detection
    SightRange: number?,       -- Detection range in studs (default: 200)
    SightMode: string?,        -- "Omnidirectional" or "Directional" (default: "Directional")

    -- Movement
    CanWalk: boolean?,         -- Enable/disable all movement (default: true)
    MovementMode: string?,     -- "Ranged" or "Melee" (default: "Ranged")
    MeleeOffsetRange: number?, -- For Melee mode: offset distance in studs (default: 3-8)
    UsePathfinding: boolean?,  -- Use advanced pathfinding vs simple MoveTo() (default: true)
    EnableIdleWander: boolean?,     -- Enable random wandering (default: true)
    EnableCombatMovement: boolean?, -- Enable combat movement (default: true)

    -- Client Rendering (Optional)
    ClientRenderData: {
        Scale: number?,           -- Visual scale multiplier (default: 1.0)
        CustomColor: Color3?,     -- Custom color tint
        Transparency: number?,    -- Transparency (0 = opaque, 1 = invisible)
    }?,

    -- Custom Game Data (Optional)
    CustomData: {
        Faction: string?,         -- NPC faction/team identifier (e.g., "Ally")
        EnemyType: string?,       -- Combat classification (e.g., "Ranged", "Melee")
        -- Add any game-specific attributes here
    }?,
})
```

### Sight Modes Explained

#### Directional (Cone-Based)

- Detects targets in a cone in front of the NPC
- More realistic for NPCs with forward-facing vision
- Better performance for large numbers of NPCs
- Uses cone angle visualization (yellow cone)

#### Omnidirectional (360°)

- Detects targets in all directions
- Suitable for NPCs with "all-seeing" behavior
- Slightly higher performance cost
- Uses sphere visualization (blue sphere)

### Movement Modes Explained

#### Ranged Mode

- Maintains distance from target
- Suitable for archer/mage type NPCs
- Stops at sight range distance
- Can strafe and keep distance

#### Melee Mode

- Moves close to target
- Uses `MeleeOffsetRange` for offset distance (3-8 studs)
- Suitable for sword/melee combat NPCs
- Closes distance aggressively

---

## 📝 Usage Examples

### Example 1: Basic Ranged Enemy (when within distance, NPC will strafe!)

```lua
local rangedEnemy = NPC_Service:SpawnNPC({
    Name = "RangedEnemy_1",
    Position = Vector3.new(0, 10, 0),
    ModelPath = ReplicatedStorage.Assets.NPCs.Characters.Enemy,

    MaxHealth = 100,
    WalkSpeed = 16,

    SightRange = 60,
    SightMode = "Directional",
    MovementMode = "Ranged",

    EnableIdleWander = true,
    EnableCombatMovement = true,

    CustomData = {
        Faction = "Enemy",
        EnemyType = "Ranged",
    },
})
```

### Example 2: Melee NPC with Custom Appearance (choose a model to clone)

```lua
local meleeNPC = NPC_Service:SpawnNPC({
    Name = "MeleeWarrior",
    Position = Vector3.new(20, 10, 0),
    ModelPath = ReplicatedStorage.Assets.NPCs.Characters.Warrior,

    MaxHealth = 150,
    WalkSpeed = 18,

    SightRange = 50,
    SightMode = "Omnidirectional",
    MovementMode = "Melee",
    MeleeOffsetRange = 5,

    ClientRenderData = {
        Scale = 1.2,
        CustomColor = Color3.fromRGB(255, 100, 100),
        Transparency = 0,
    },

    CustomData = {
        Faction = "Ally",
        EnemyType = "Melee",
        Level = 5,
    },
})
```

### Example 3: Stationary Guard NPC (towers for your tower defense game)

```lua
local guard = NPC_Service:SpawnNPC({
    Name = "Guard_1",
    Position = Vector3.new(50, 10, 0),
    ModelPath = ReplicatedStorage.Assets.NPCs.Characters.Guard,

    MaxHealth = 200,
    WalkSpeed = 0,

    SightRange = 100,
    SightMode = "Directional",

    -- Disable movement
    CanWalk = false,
    EnableIdleWander = false,
    EnableCombatMovement = false,

    CustomData = {
        Faction = "Guard",
        EnemyType = "Stationary",
    },
})
```

### Example 4: Tower Defense Enemy Wave

```lua
-- Spawn enemies that follow waypoints
for i = 1, 10 do
    local enemy = NPC_Service:SpawnNPC({
        Name = "TowerDefense_Enemy_" .. i,
        Position = spawnPoint.Position,
        ModelPath = ReplicatedStorage.Assets.NPCs.Characters.Enemy,

        MaxHealth = 100,
        WalkSpeed = 16,

        -- Disable automatic behaviors for manual control
        SightRange = 0,
        UsePathfinding = false,
        EnableIdleWander = false,
        EnableCombatMovement = false,

        ClientRenderData = {
            Scale = 0.4,
            CustomColor = Color3.fromRGB(255, 80, 80),
        },

        CustomData = {
            Faction = "Enemy",
            EnemyType = "TowerDefenseWave",
        },
    })

    -- Manually set destination to waypoint
    NPC_Service:SetDestination(enemy, waypoint1.Position)
end
```

### Managing NPCs

```lua
-- Get NPC data
local npcData = NPC_Service:GetNPCData(myNPC)
print("NPC Health:", npcData.Health)

-- Get current target
local currentTarget = NPC_Service:GetCurrentTarget(myNPC)
if currentTarget then
    print("NPC is targeting:", currentTarget.Name)
end

-- Manually set target
NPC_Service:SetTarget(myNPC, player.Character)

-- Manually set destination
NPC_Service:SetDestination(myNPC, Vector3.new(100, 0, 100))

-- Destroy NPC
NPC_Service:DestroyNPC(myNPC)
```

---

## 🧩 System Components

### Server-Side Components (`NPC_Service`)

- **NPCSpawner** - Handles NPC creation and initialization
- **MovementBehavior** - Controls NPC movement (ranged, melee, idle wandering)
- **PathfindingManager** - Advanced pathfinding with NoobPath integration
- **SightDetector** - Target detection with omnidirectional/directional modes
- **SightVisualizer** - Visual debugging tools for sight ranges and cones

### Client-Side Components (`NPC_Controller`)

- **NPCRenderer** - Client-side visual rendering with distance-based culling
- **NPCAnimator** - Animation handling with BetterAnimate integration

### Shared Components

- **RenderConfig** - Client rendering configuration
- **ProfileTemplate** - Player data template integration
- **NoobPath** - Advanced pathfinding library

---

## 🔮 Future Implementations

### UseAnimationController - Client-Side Physics Optimization

> **Status**: 🚧 Not Yet Implemented

An advanced optimization that offloads NPC physics and pathfinding calculations entirely to the client, enabling support for **1000+ NPCs** with minimal lag.

**Features:**

- Client-side physics simulation
- Client-side pathfinding
- Server only stores positions and health
- 70-95% network traffic reduction
- Suitable for ambient/non-critical NPCs

**⚠️ Security Trade-off:** Client has position authority (no validation) to prevent ping-related false positives. Not recommended for combat NPCs.

📖 **Implementation Plan:** [UseAnimationController_Implementation_Plan.md](https://github.com/Froredion/Comprehensive-NPC-System/blob/master/documentations/Unimplemented/UseAnimationController_Implementation_Plan.md)

---

### EnableOptimizedHitbox - Batch Hitbox Detection

> **Status**: 🚧 Not Yet Implemented

Client-side batch hitbox detection for high fire rate scenarios, significantly reducing network traffic and server load.

**Features:**

- Batch detection for rapid-fire weapons
- Accumulate hits over time window (0.1-0.2s)
- Single network call for multiple hits
- Particularly useful for tower defense with many turrets

**⚠️ Security Trade-off:** Client handles hitbox detection (exploitable). Suitable for PvE tower defense, not competitive PvP.

**Use Cases:**

- Tower defense games with rapid-fire turrets
- Games with 50+ NPCs and high fire rate weapons
- PvE scenarios where hitbox accuracy is less critical

📖 **Implementation Plan:** [Optimized_Hitbox.md](https://github.com/Froredion/Comprehensive-NPC-System/blob/master/documentations/Unimplemented/Optimized_Hitbox.md)

---

## 🧪 Testing & Examples

### Testing Place

Open `npc_system_place.rbxl` in Roblox Studio to see the system in action with pre-configured test scenarios.

### Test Scripts

The following test scripts demonstrate various use cases and can be **safely deleted** after reviewing:

- `src/ServerScriptService/NPC_Test.server.lua` - Basic NPC spawning with client rendering
- `src/ServerScriptService/NPC_TowerDefense_Test.server.lua` - Tower defense wave system example

### Disabling Visualizers

Sight visualizers (cones and spheres) are useful for debugging but may impact performance in production.

**To disable visualizers:**

1. Open `src/ServerScriptService/ServerSource/Server/NPC_Service/Components/Others/SightVisualizer.lua`
2. Change line 8:
   ```lua
   local VISUALIZER_ENABLED = false  -- Set to false to disable
   ```

**Note:** Visualizers themselves may not be 100% accurate and are intended for debugging purposes.

### Render Configuration

Client-side rendering can be configured in `src/ReplicatedStorage/SharedSource/Datas/NPCs/RenderConfig.lua`:

```lua
{
    ENABLED = true,                  -- Toggle client rendering on/off
    MAX_RENDER_DISTANCE = 150,       -- Distance to render NPCs (studs)
    MAX_RENDERED_NPCS = 50,          -- Maximum NPCs to render at once
    DISTANCE_CHECK_INTERVAL = 1.0,   -- How often to check distances (seconds)
    DEBUG_MODE = false,              -- Enable debug visualization
}
```

---

## 📊 Performance

### Current System (Server-Authoritative)

- **50-100 NPCs**: Smooth performance on most servers
- **Client-Side Rendering**: Reduces load with distance-based culling
- **Optimized Pathfinding**: NoobPath with intelligent waypoint handling
- **Sight Detection**: Efficient cone and magnitude checks

### Performance Tips

1. **Use Directional Sight Mode** - Slightly better performance than Omnidirectional
2. **Adjust Render Distance** - Lower `MAX_RENDER_DISTANCE` for better client FPS
3. **Limit Rendered NPCs** - Set `MAX_RENDERED_NPCS` based on target hardware
4. **Disable Visualizers** - Turn off in production builds
5. **Use Faction System** - Same-faction NPCs won't waste cycles targeting each other

### Future Performance (With Unimplemented Features)

- **UseAnimationController**: 1000+ NPCs with smooth gameplay
- **OptimizedHitbox**: 70-95% network traffic reduction for combat

---

## 🤝 Contributing

This is an open-source project. Contributions are welcome!

### Areas for Contribution

- Implement UseAnimationController optimization
- Implement OptimizedHitbox batch detection
- Add more movement behaviors
- Create additional sight detection modes
- Improve pathfinding algorithms
- Add more example test scripts
- Performance optimizations

### Development Guidelines

- Follow the modular component architecture
- Maintain server authority for critical systems
- Document all configuration parameters
- Test with large NPC counts (100+)
- Consider both PvE and PvP use cases

---

## 🔗 Links

- **Framework**: [SuperbulletFrameworkV1-Knit](https://github.com/Froredion/SuperbulletFramework)
- **GitHub Repository**: [Comprehensive-NPC-System](https://github.com/Froredion/Comprehensive-NPC-System)
- **Roblox Profile**: [Froredion](https://www.roblox.com/users/Froredion)

---

## 💬 Support

If you encounter issues or have questions:

1. Check the test scripts for examples
2. Review the configuration parameters
3. Read the future implementation plans
4. Open an issue on GitHub

---

## 🌟 Acknowledgments

- **SuperbulletFramework** - For the robust Knit-based architecture
- **NoobPath** - For advanced pathfinding capabilities
- **BetterAnimate** - For smooth animation handling (modified, better version)
- **Roblox Community** - For feedback and support

---

**Made with ❤️ for the Roblox development community**

_Version 1.0 - Last Updated: October 2025_
