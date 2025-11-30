# Collision System Implementation Plan

## Overview
A server-side collision system using Roblox's Physics Service to automatically handle all collision detection between different entity types.

## Architecture
- **Server-only system** - No client controller needed
- **Physics Service-based** - Leverages Roblox's built-in collision detection
- **Collision Groups** - Separate groups for different entity types
- **Event-based handling** - Responds to PhysicsService collision events

## Collision Groups
1. **NPC_Server** - Server-physics NPCs
2. **NPC_Client** - Client-physics NPCs  
3. **Players** - Player characters
4. **Default** - Everything else

## Collision Matrix
| Entity Type | NPC_Server | NPC_Client | Players | Default |
|-------------|------------|------------|---------|---------|
| NPC_Server  | ✅ Collide  | ✅ Collide  | ✅ Collide | ❌ No Collide |
| NPC_Client  | ✅ Collide  | ✅ Collide  | ✅ Collide | ❌ No Collide |
| Players     | ✅ Collide  | ✅ Collide  | ✅ Collide | ❌ No Collide |
| Default     | ❌ No Collide | ❌ No Collide | ❌ No Collide | ✅ Collide |

## Implementation Phases

### Phase 1: Collision Service Setup
- Create `CollisionService` server-side service
- Define collision groups and matrix
- Register collision groups with PhysicsService
- Set up collision event handlers

### Phase 2: Entity Registration System
- Automatic registration of NPCs (both server and client physics)
- Automatic registration of players
- Dynamic collision group assignment
- Entity cleanup on destruction

### Phase 3: Collision Event Handling
- Handle NPC-to-NPC collisions (both modes)
- Handle Player-to-Player collisions  
- Handle Player-to-NPC collisions
- Custom collision response logic

### Phase 4: Integration with Existing Systems
- Integrate with NPC_Service for NPC collision handling
- Integrate with player systems for player collision handling
- Add collision response callbacks for gameplay logic

## Files to Create

### Server-Side
1. `src/ServerScriptService/ServerSource/Server/CollisionService/init.lua` - Main collision service
2. `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Others/CollisionManager.lua` - Core collision logic
3. `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Get().lua` - Read operations
4. `src/ServerScriptService/ServerSource/Server/CollisionService/Components/Set().lua` - Write operations

### Shared Data
1. `src/ReplicatedStorage/SharedSource/Datas/Collision/CollisionConfig.lua` - Collision configuration

## Key Features
- **Automatic Detection** - Physics Service handles all collision detection
- **Performance Optimized** - No manual raycasting or distance checks
- **Extensible** - Easy to add new collision groups
- **Server-Authoritative** - All collision logic runs on server
- **Integration Ready** - Callbacks for custom collision responses

## Benefits of Physics Service Approach
- ✅ No manual collision checking code
- ✅ Automatic handling of all collision types
- ✅ Optimized engine-level performance
- ✅ Built-in collision filtering
- ✅ Easy to maintain and extend