--[[
	CollisionConfig - Centralized collision system configuration

	Controls collision behavior for NPCs and Players using PhysicsService collision groups.
	All settings can be toggled on/off at runtime.
]]

local CollisionConfig = {
	-- Collision group names (registered with PhysicsService)
	Groups = {
		NPCs = "NPCs",
		Players = "Players",
	},

	-- Collision settings (true = collide, false = no collision)
	Settings = {
		-- NPC-to-NPC collision (both server-mode and client-mode NPCs)
		NPC_to_NPC = false,

		-- Player-to-NPC collision
		Player_to_NPC = false,

		-- Player-to-Player collision
		Player_to_Player = false,
	},
}

return CollisionConfig
