local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerSource = ServerScriptService:WaitForChild("ServerSource")

local SuperbulletModule = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Superbullet")
local Superbullet = require(SuperbulletModule)

for _, module in pairs(ServerSource.Server:GetDescendants()) do
	if module:IsA("ModuleScript") and module.Name:match("Service$") then
		local ok, err = pcall(require, module)
		if not ok then
			task.spawn(error, "[Superbullet] Failed to load " .. module:GetFullName() .. ": " .. tostring(err))
		end
	end
end

Superbullet.Start():andThen(
	function()
		print("Superbullet Server initiated.")
		SuperbulletModule:SetAttribute("SuperbulletServer_Initialized",true)
	end
	)
	:catch(warn)
