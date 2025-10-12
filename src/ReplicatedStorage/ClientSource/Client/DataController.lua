local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Knit = require(ReplicatedStorage.Packages.Knit)
local Signal = require(ReplicatedStorage.Packages.Signal)

local DataController = Knit.CreateController {
	Name = "DataController",
	Data = nil,
}

---- Services
local ProfileService

local plr = game.Players.LocalPlayer

function DataController:GetPlayerData()
	return DataController.Data
end

function DataController:WaitUntilProfileLoaded()
	repeat task.wait() until DataController.Data
end

function DataController:RequestToUpdateData()
	ProfileService.GetData:Fire()
end

function DataController:KnitStart()	 
	-- updates data
	ProfileService.GetData:Connect(function(newData)

		DataController.Data = newData
	end)

	DataController:RequestToUpdateData()
	DataController:WaitUntilProfileLoaded()

	ProfileService.UpdateSpecificData:Connect(function(Redirectories,newValue)
		local directData = DataController.Data
		for i=1,#Redirectories do
			if not directData[Redirectories[i]] and i ~= #Redirectories then
				local redirectories = "profileData"
				for i2=1,i do
					redirectories = redirectories.."."..Redirectories[i2]
				end
				error("'"..redirectories.."' table does not exist. ALWAYS PREVENT THIS BY MAKING TABLES INSIDE PROFILETEMPLATE.")
				return
			end
			if i ~= #Redirectories then 
				directData = directData[Redirectories[i]]
			end
		end
		directData[Redirectories[#Redirectories]] = newValue
	end)
end

function DataController:KnitInit()	
	ProfileService = Knit.GetService("ProfileService")
end

return DataController