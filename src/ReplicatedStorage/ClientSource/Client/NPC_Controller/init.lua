local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)

local NPC_Controller = Knit.CreateController({
	Name = "NPC_Controller",
	Instance = script
})

---- Configuration
local OptimizationConfig = require(ReplicatedStorage.SharedSource.Datas.NPCs.OptimizationConfig)

---- Knit Services

---- Knit Controllers

function NPC_Controller:KnitStart()
	-- Check if UseAnimationController system should be active
	-- This runs after all components are initialized
	if OptimizationConfig.UseAnimationController then
		print("[NPC_Controller] UseAnimationController is enabled globally")
	end

	-- The ClientNPCManager will detect and handle client-physics NPCs
	-- even if the global flag is false (per-NPC override)
end

function NPC_Controller:KnitInit()
end

return NPC_Controller
