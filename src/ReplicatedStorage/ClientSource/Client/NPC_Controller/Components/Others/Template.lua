local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)
local module = {

}

---- Knit Services

---- Knit Controllers


---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Components
--- main parent components
local mainParentFolder = script.Parent.Parent

local plr = game.Players.LocalPlayer
local playerGui = plr.PlayerGui

--- Datas



function module.Start()
	
end

function module.Init()
	
end

return module
