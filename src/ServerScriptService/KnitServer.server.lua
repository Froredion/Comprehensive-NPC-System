local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerSource = ServerScriptService:WaitForChild("ServerSource")

local KnitModule = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitModule)

for _, module in pairs(ServerSource.Server:GetDescendants()) do
	if module:IsA("ModuleScript") and module.Name:match("Service$") then
		require(module)
	end
end

Knit.Start():andThen(
	function()
		print("Knit Server initiated.")
		KnitModule:SetAttribute("KnitServer_Initialized",true)
	end
	)
	:catch(warn)