local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local TemplateController = Knit.CreateController({
	Name = "TemplateController",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
TemplateController.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	TemplateController.Components[v.Name] = require(v)
end
TemplateController.GetComponent = require(componentsFolder["Get()"])
TemplateController.SetComponent = require(componentsFolder["Set()"])

--- Knit Services

--- Knit Controllers

function TemplateController:KnitStart() end

function TemplateController:KnitInit()
	componentsInitializer(script)
end

return TemplateController
