local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Superbullet = require(ReplicatedStorage.Packages.Superbullet)
local Signal = require(ReplicatedStorage.Packages.Signal)

local TemplateService = Superbullet.CreateService({
	Name = "TemplateService",
	Instance = script, -- Automatically initializes components
})

---- Superbullet Services

function TemplateService:SuperbulletStart()

end

function TemplateService:SuperbulletInit()

end

return TemplateService
