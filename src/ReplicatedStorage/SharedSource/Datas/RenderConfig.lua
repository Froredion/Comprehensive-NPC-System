--[[
	RenderConfig - Client-side NPC rendering configuration
	
	Purpose: Centralized configuration for toggling and customizing NPC rendering
]]

local RenderConfig = {
	-- Toggle client-side rendering on/off
	-- ⚠️ DISABLED BY DEFAULT - This is very confusing for beginners
	-- For professionals: Enable this to optimize your game by offloading rendering to clients
	ENABLED = true,
	
	-- Only render NPCs within this distance (studs)
	MAX_RENDER_DISTANCE = 500,
	
	-- Maximum number of NPCs to render simultaneously
	MAX_RENDERED_NPCS = 100,
	
	-- Update interval for distance checks (seconds)
	DISTANCE_CHECK_INTERVAL = 1.0,
	
	-- Enable visual debugging (show wireframes, info)
	DEBUG_MODE = false,
}

return RenderConfig
