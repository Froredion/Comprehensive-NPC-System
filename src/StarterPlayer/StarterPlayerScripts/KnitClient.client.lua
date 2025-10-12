local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ClientSource = ReplicatedStorage:WaitForChild("ClientSource")
local KnitModule = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit")
local Knit = require(KnitModule)

for _, module in pairs(ClientSource:GetDescendants()) do
	if module:IsA("ModuleScript") and module.Name:match("Controller$") then
		require(module)
	end
end

Knit.Start()
	:andThen(function()
	print("Knit Client initiated.")
	KnitModule:SetAttribute("KnitClient_Initialized",true)
end
)
	:catch(warn)