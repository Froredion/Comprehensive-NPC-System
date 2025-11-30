# Collision System Implementation Plan

## 📋 Overview

Create a comprehensive collision system that manages collision groups for NPCs and Players using PhysicsService. The system will handle:
1. **NPC-to-NPC Collision** (Server mode and Client mode)
2. **Player-to-NPC Collision**
3. **Player-to-Player Collision**

All settings will be configurable and can be toggled on/off.

---

## 🎯 Goals

- Implement a server-side Knit service (`CollisionService`) to manage collision groups
- Create a configuration file for collision settings
- Handle collision group assignment for both server-mode and client-mode NPCs
- Handle collision group assignment for players on character spawn
- Integrate seamlessly with existing NPC_Service and player spawning systems

---

## 🔍 Current Codebase Analysis

### Existing Systems

**1. NPC System (`NPC_Service`)**
- **Location**: `src/ServerScriptService/ServerSource/Server/NPC_Service/`
- **Spawn Methods**:
  - **Server Mode**: `NPCSpawner.lua` - Traditional server-side physics
  - **Client Mode**: `ClientPhysicsSpawner.lua` - UseClientPhysics = true
- **Configuration**: `OptimizationConfig.lua` controls UseClientPhysics flag

**2. Player System**
- **ProfileService**: Handles `Players.PlayerAdded` connections
- **No dedicated character spawning service** currently exists
- Need to add `player.CharacterAdded` handling for collision groups

**3. Current Gaps**
- No PhysicsService collision group management
- No collision configuration system
- No player character collision handling
- No integration points for collision assignment

---

## 📁 File Structure Plan

```
src/
├── ServerScriptService/ServerSource/Server/
│   └── CollisionService/                          [NEW SERVICE]
│       ├── init.lua                                [Main service file]
│       └── Components/
│           ├── Get().lua                           [Read collision data]
│           ├── Set().lua                           [Modify collision settings]
│           └── Others/
│               ├── CollisionGroupManager.lua       [Collision group registration & management]
│               └── CharacterCollisionHandler.lua   [Apply collision groups to characters]
│
└── ReplicatedStorage/SharedSource/Datas/
    └── CollisionConfig.lua                         [NEW CONFIG]
```

---

## 🔧 Phase Breakdown

### **Phase 1: Configuration Setup**
**Goal**: Create collision configuration data module

**Files to Create**:
- `src/ReplicatedStorage/SharedSource/Datas/CollisionConfig.lua`

**Configuration Structure**:
```lua
local CollisionConfig = {
    -- Collision group names
    Groups = {
        NPCs = "NPCs",
        Players = "Players",
    },
    
    -- Collision settings (true = collide, false = no collision)
    Settings = {
        NPC_to_NPC = false,        -- NPC-to-NPC collision (both server & client mode)
        Player_to_NPC = false,     -- Player-to-NPC collision
        Player_to_Player = false,  -- Player-to-Player collision
    },
}

return CollisionConfig
```

---

### **Phase 2: CollisionService Core Structure**
**Goal**: Create the main CollisionService with component structure

**Files to Create**:
1. `src/ServerScriptService/ServerSource/Server/CollisionService/init.lua`
2. `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Get().lua`
3. `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Set().lua`
4. `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Others/` (folder)

**Service Structure** (`init.lua`):
```lua
local CollisionService = Knit.CreateService({
    Name = "CollisionService",
    Instance = script,
    Client = {},
})

-- Public API
function CollisionService:ApplyCollisionToCharacter(character, groupName)
    -- Delegate to CharacterCollisionHandler
end

function CollisionService:GetCollisionSettings()
    -- Delegate to Get component
end

function CollisionService:UpdateCollisionSetting(settingName, enabled)
    -- Delegate to Set component
end

function CollisionService:KnitStart()
    -- Initialize collision groups via CollisionGroupManager
end

function CollisionService:KnitInit()
    -- Service initialization
end
```

---

### **Phase 3: Collision Group Manager**
**Goal**: Create the collision group registration and management logic

**File to Create**:
- `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Others/CollisionGroupManager.lua`

**Responsibilities**:
1. Register collision groups with PhysicsService:
   - "NPCs" group
   - "Players" group
2. Configure collision relationships based on `CollisionConfig`:
   - NPC-to-NPC collisions
   - Player-to-NPC collisions
   - Player-to-Player collisions
3. Allow runtime updates to collision settings

**Key Functions**:
```lua
function CollisionGroupManager.RegisterCollisionGroups()
    -- Register "NPCs" and "Players" groups
    -- Set collision relationships based on config
end

function CollisionGroupManager.UpdateCollisionSetting(group1, group2, shouldCollide)
    -- Update PhysicsService collision settings at runtime
end
```

---

### **Phase 4: Character Collision Handler**
**Goal**: Apply collision groups to character models (NPCs and Players)

**File to Create**:
- `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Others/CharacterCollisionHandler.lua`

**Responsibilities**:
1. Apply collision group to all BaseParts in a character model
2. Handle DescendantAdded for new parts
3. Support both NPCs and Players

**Key Functions**:
```lua
function CharacterCollisionHandler.ApplyCollisionGroup(character, groupName)
    -- Apply collision group to existing parts
    -- Connect DescendantAdded for future parts
end

local function onDescendantAdded(descendant, groupName)
    -- Set collision group for new BaseParts
end
```

---

### **Phase 5: Integration with NPC_Service**
**Goal**: Integrate collision system with NPC spawning (both server and client modes)

**Files to Modify**:
1. `src/ServerScriptService/ServerSource/Server/NPC_Service/Components/Others/NPCSpawner.lua`
   - Add collision group assignment after NPC model creation
   - Call `CollisionService:ApplyCollisionToCharacter(npcModel, "NPCs")`

2. `src/ServerScriptService/ServerSource/Server/NPC_Service/Components/Others/ClientPhysicsSpawner.lua`
   - Note: Client-mode NPCs have no server model, but visual model exists on client
   - May need client-side collision handling (future enhancement)
   - For now, document limitation

**Integration Points**:

**NPCSpawner.lua** (Server Mode):
```lua
-- After NPC model is created and configured
-- Apply collision group
if CollisionService then
    CollisionService:ApplyCollisionToCharacter(npcModel, "NPCs")
end
```

**ClientPhysicsSpawner.lua** (Client Mode):
```lua
-- Document: Client-mode NPCs handled by ClientPhysicsRenderer on client
-- Visual model collision needs client-side handling (future enhancement)
-- Server has no physical model to apply collision to
```

---

### **Phase 6: Integration with Player Character Spawning**
**Goal**: Apply collision groups to player characters on spawn/respawn

**File to Modify**:
- `src/ServerScriptService/ServerSource/Server/ProfileService.lua`

**Integration Method**:
Add character spawning handling in ProfileService:

```lua
-- Inside HandlePlayerAdded or similar function
player.CharacterAdded:Connect(function(character)
    -- Wait for character to fully load
    character:WaitForChild("HumanoidRootPart")
    
    -- Apply player collision group
    if CollisionService then
        CollisionService:ApplyCollisionToCharacter(character, "Players")
    end
end)
```

---

### **Phase 7: Get and Set Components**
**Goal**: Implement Get/Set components for retrieving and modifying collision settings

**Files to Implement**:

**Get().lua**:
```lua
-- Read-only access to collision settings
function GetComponent:GetCollisionSettings()
    return CollisionConfig.Settings
end

function GetComponent:GetCollisionGroups()
    return CollisionConfig.Groups
end
```

**Set().lua**:
```lua
-- Modify collision settings at runtime
function SetComponent:UpdateCollisionSetting(settingName, enabled)
    -- Update config
    -- Call CollisionGroupManager to update PhysicsService
end
```

---

## 🔄 Integration Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    CollisionConfig.lua                       │
│  Settings: NPC_to_NPC, Player_to_NPC, Player_to_Player      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                      CollisionService                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         CollisionGroupManager.lua                     │  │
│  │  • RegisterCollisionGroups()                          │  │
│  │  • Configure NPC/Player collision relationships       │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │      CharacterCollisionHandler.lua                    │  │
│  │  • ApplyCollisionGroup(character, groupName)          │  │
│  │  • Handle DescendantAdded for new parts               │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                    │                    │
        ┌───────────┴───────────┐        └──────────────┐
        ▼                       ▼                       ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│   NPC_Service    │  │ ProfileService   │  │  Future: Client  │
│                  │  │                  │  │  Collision (TBD) │
│ NPCSpawner       │  │ CharacterAdded   │  │                  │
│ (Server Mode)    │  │ Connection       │  │                  │
│                  │  │                  │  │                  │
│ Apply "NPCs"     │  │ Apply "Players"  │  │                  │
│ collision group  │  │ collision group  │  │                  │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

---

## 🧪 Testing Strategy

After implementation, test the following scenarios:

### Test 1: NPC-to-NPC Collision (Server Mode)
1. Spawn multiple NPCs with server-side physics
2. Toggle `NPC_to_NPC` setting between true/false
3. Verify NPCs collide or pass through each other

### Test 2: Player-to-NPC Collision
1. Spawn NPCs and test player walking through them
2. Toggle `Player_to_NPC` setting
3. Verify collision behavior changes

### Test 3: Player-to-Player Collision
1. Test with multiple players in-game
2. Toggle `Player_to_Player` setting
3. Verify players collide or pass through each other

### Test 4: Character Respawn
1. Kill and respawn player character
2. Verify collision group is reapplied
3. Test collision behavior persists after respawn

### Test 5: Client-Mode NPCs
1. Document current limitation (visual models on client, no server physics)
2. Note: Future enhancement needed for client-side collision handling

---

## 📝 Implementation Notes

### Key Considerations

1. **PhysicsService Collision Groups**:
   - Groups must be registered before use
   - Collision relationships set via `CollisionGroupSetCollidable()`
   - Parts assigned via `BasePart.CollisionGroup = "GroupName"`

2. **Character Model Handling**:
   - Must iterate through all BaseParts in character
   - Must handle DescendantAdded for new parts (accessories, tools)
   - Must wait for HumanoidRootPart to exist before applying

3. **NPC Server vs Client Mode**:
   - **Server Mode**: Physical model exists on server, collision can be applied directly
   - **Client Mode**: No server model, visual models on client only
     - Future enhancement: Client-side collision group assignment
     - For now, collision will be default (collide with everything)

4. **Runtime Configuration**:
   - Collision settings can be changed at runtime
   - Set components will update both config and PhysicsService

5. **Integration Points**:
   - NPC_Service: Hook into NPCSpawner after model creation
   - ProfileService: Hook into player.CharacterAdded event
   - Minimal changes to existing code

---

## ✅ Success Criteria

- [x] CollisionConfig.lua created with all 3 settings
- [x] CollisionService created with full component structure
- [x] CollisionGroupManager registers groups and configures relationships
- [x] CharacterCollisionHandler applies groups to character models
- [x] NPC_Service integration: Server-mode NPCs get "NPCs" collision group
- [x] ProfileService integration: Players get "Players" collision group
- [x] Runtime configuration works (Get/Set components)
- [x] All 3 collision settings can be toggled
- [x] Character respawn maintains collision groups
- [x] Documentation for client-mode NPC limitation

---

## 🚀 Execution Plan

This plan will be broken into **7 phases**:

1. **Phase 1**: Create CollisionConfig.lua
2. **Phase 2**: Create CollisionService structure (init.lua, Get, Set, Others folder)
3. **Phase 3**: Implement CollisionGroupManager.lua
4. **Phase 4**: Implement CharacterCollisionHandler.lua
5. **Phase 5**: Integrate with NPC_Service (NPCSpawner.lua)
6. **Phase 6**: Integrate with ProfileService (player CharacterAdded)
7. **Phase 7**: Implement Get/Set components for runtime configuration

Each phase will be executed sequentially with verification before proceeding to the next.

---

## 📚 References

**Roblox Documentation**:
- [PhysicsService API](https://create.roblox.com/docs/reference/engine/classes/PhysicsService)
- [Collision Groups](https://create.roblox.com/docs/workspace/collisions#collision-groups)
- [BasePart.CollisionGroup](https://create.roblox.com/docs/reference/engine/classes/BasePart#CollisionGroup)

**Existing Codebase**:
- `src/ServerScriptService/ServerSource/Server/NPC_Service/` - NPC spawning system
- `src/ServerScriptService/ServerSource/Server/ProfileService.lua` - Player connection handling
- `src/ReplicatedStorage/SharedSource/Datas/NPCs/OptimizationConfig.lua` - NPC configuration pattern

---

**END OF PLAN**
