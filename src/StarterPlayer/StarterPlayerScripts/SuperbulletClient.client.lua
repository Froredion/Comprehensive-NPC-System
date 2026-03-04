local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientSource = ReplicatedStorage:WaitForChild("ClientSource")
local SuperbulletModule = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Superbullet")
local Superbullet = require(SuperbulletModule)

for _, module in pairs(ClientSource:GetDescendants()) do
	if module:IsA("ModuleScript") and module.Name:match("Controller$") then
		local ok, err = pcall(require, module)
		if not ok then
			task.spawn(error, "[Superbullet] Failed to load " .. module:GetFullName() .. ": " .. tostring(err))
		end
	end
end

Superbullet.Start()
	:andThen(function()
	print("Superbullet Client initiated.")
	SuperbulletModule:SetAttribute("SuperbulletClient_Initialized",true)
end
)
	:catch(warn)
