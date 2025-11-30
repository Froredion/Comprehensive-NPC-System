--[[
	OptimizationConfig - Advanced NPC optimization settings

	WARNING: UseClientPhysics is an ADVANCED optimization
	- Offloads ALL physics to client
	- Client has full position authority (no anti-exploit validation)
	- Requires extensive testing
	- NOT recommended for beginners

	For implementation details, see:
	documentations/Unimplemented/UseClientPhysics_Implementation/Main.md
]]

local OptimizationConfig = {
	--[[
		UseClientPhysics - Enable client-side physics simulation

		CRITICAL WARNINGS:
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

		DO NOT USE FOR:
		- Combat NPCs (enemies, bosses)
		- NPCs that drop loot or rewards
		- NPCs tied to game progression
		- Any NPC that affects gameplay outcomes
	]]
	UseClientPhysics = false, -- DISABLED by default

	-- Client-side simulation settings (only if UseClientPhysics = true)
	ClientSimulation = {
		-- Distance at which client starts simulating NPC (studs)
		SIMULATION_DISTANCE = 200,

		-- Maximum NPCs one client can simulate
		MAX_SIMULATED_PER_CLIENT = 50,

		--[[
			How often client syncs position to server (seconds)

			TOWER DEFENSE OPTIMIZATION:
			- Lower value (e.g., 0.1) = More frequent updates, smoother NPC movement, but higher server load
			- Higher value (e.g., 0.5) = Less frequent updates, lower server load, but NPCs appear to "stop" briefly

			Recommended values:
			- For smooth Tower Defense: 0.1 seconds (10 updates/sec)
			- For low server load and for any other games: 0.5 seconds (2 updates/sec) - current setting

			Trade-off: More frequent updates = smoother gameplay but higher network/server usage
		]]
		POSITION_SYNC_INTERVAL = 0.1,

		-- Distance threshold for server to broadcast position updates (studs)
		-- Server only sends position updates to clients within this range
		BROADCAST_DISTANCE = 250,
	},

	--[[
		NOTE: Rendering settings are in RenderConfig.lua
		To avoid duplication, refer to:
		- RenderConfig.MAX_RENDER_DISTANCE (distance to render NPCs)
		- RenderConfig.MAX_RENDERED_NPCS (max NPCs to render)
		- RenderConfig.DISTANCE_CHECK_INTERVAL (distance check frequency)
		- RenderConfig.DEBUG_MODE (debug visualization)
	]]

	-- Jump simulation settings
	JumpSimulation = {
		-- NOTE: Gravity is read from workspace.Gravity at runtime
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
			Water = math.huge, -- Avoid water
		},

		-- Recompute path if NPC deviates this much (studs)
		RECOMPUTE_THRESHOLD = 10,
	},

	-- Server fallback settings (for unclaimed NPCs)
	ServerFallback = {
		-- Enable server fallback for unclaimed NPCs
		ENABLED = true,

		-- How long to wait before server takes over (seconds)
		UNCLAIMED_TIMEOUT = 5.0,

		-- Server simulation rate (updates per second)
		-- 1 FPS = minimal load, NPCs still move slowly
		SIMULATION_FPS = 1,

		-- Simplified movement speed (fraction of normal speed)
		-- Lower = less server work, NPCs move slower when unclaimed
		SPEED_MULTIPLIER = 0.5,

		-- Maximum NPCs server will simulate as fallback
		-- Prevents server overload if many NPCs unclaimed
		MAX_SERVER_SIMULATED = 100,
	},

	-- Minimal exploit mitigation settings
	ExploitMitigation = {
		-- Enable soft bounds checking (clamps position, doesn't reject)
		SOFT_BOUNDS_ENABLED = true,

		-- Default max wander radius if not specified per-NPC (studs)
		DEFAULT_MAX_WANDER_RADIUS = 500,

		-- Client-side ground check interval (seconds)
		GROUND_CHECK_INTERVAL = 2.0,

		-- Height tolerance before snapping to ground (studs)
		GROUND_SNAP_TOLERANCE = 10,
	},
}

return OptimizationConfig
