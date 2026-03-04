local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Superbullet = require(ReplicatedStorage.Packages.Superbullet)
local Signal = require(ReplicatedStorage.Packages.Signal)

local TemplateController = Superbullet.CreateController({
	Name = "TemplateController",
	Instance = script, -- Automatically initializes components
})

--- Superbullet Services

--- Superbullet Controllers

function TemplateController:SuperbulletStart()

end

function TemplateController:SuperbulletInit()

end

return TemplateController
