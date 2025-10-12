local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local TemplateService = Knit.CreateService({
	Name = "TemplateService",
})

---- Components
--- component utilities
local componentsInitializer = require(ReplicatedStorage.SharedSource.Utilities.ScriptsLoader.ComponentsInitializer)
--- component folders
local componentsFolder = script:WaitForChild("Components", 5)
TemplateService.Components = {}
for _, v in pairs(componentsFolder:WaitForChild("Others", 10):GetChildren()) do
	TemplateService.Components[v.Name] = require(v)
end
TemplateService.GetComponent = require(componentsFolder["Get()"])
TemplateService.SetComponent = require(componentsFolder["Set()"])

---- Knit Services

function TemplateService:KnitStart() end

function TemplateService:KnitInit()
	---- Components Initializer
	componentsInitializer(script)
end

return TemplateService
