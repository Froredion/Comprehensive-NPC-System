local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")

local Signal = require(ReplicatedStorage.Packages.Signal)
local Knit = require(ReplicatedStorage.Packages.Knit)

local ProfileService = Knit.CreateService({
	Name = "ProfileService",
	Client = {
		GetData = Knit.CreateSignal(),

		--[[
			@description Use this for client to reduce network receive data, this updates DataController.Data
		
			Note: If you use :Connect() and want to retrieve updated data, ensure to add a task.wait() 
			at least for the DataController.Data to update.
		]]
		UpdateSpecificData = Knit.CreateSignal(),
	},

	UpdateSpecificData = Signal.new(),
})

local ActualProfileService =
	require(ServerScriptService:WaitForChild("ServerSource"):WaitForChild("Externals"):WaitForChild("ProfileService"))
local ProfileTemplate = require(ReplicatedStorage.SharedSource.Datas.ProfileTemplate)

local ProfileStore

local Profiles = {} -- [player] = profile
ProfileService.Profiles = Profiles

local function DataSuccessfullyLoaded(player)
	-- Called when a profile is successfully loaded
	-- Add any post-load logic here
end

local function HandlePlayerAdded(player)
	local profile = ProfileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile ~= nil then
		profile:AddUserId(player.UserId) -- GDPR compliance
		profile:Reconcile() -- Fill in missing variables from ProfileTemplate

		profile:ListenToRelease(function()
			Profiles[player] = nil
			-- The profile could've been loaded on another Roblox server
			player:Kick()
		end)

		if player:IsDescendantOf(Players) then
			Profiles[player] = profile
			DataSuccessfullyLoaded(player)
		else
			-- Player left before the profile loaded
			profile:Release()
		end
	else
		-- The profile couldn't be loaded possibly due to other
		-- Roblox servers trying to load this profile at the same time
		player:Kick()
	end
end

local function HandlePlayerRemoving(player)
	local profile = Profiles[player]
	if profile ~= nil then
		profile:Release()
	end
end

function ProfileService:WaitUntilProfileLoaded(player)
	repeat
		task.wait(2)
		if RunService:IsStudio() then
			print("Waiting for profile to load for " .. player.Name .. "...")
		end
	until Profiles[player] or not player:IsDescendantOf(Players)
end

function ProfileService:GetProfile(player)
	if player == nil then
		warn("Player instance is nil when getting profile")
		return nil
	end

	if not Profiles[player] then
		ProfileService:WaitUntilProfileLoaded(player)
	end

	local profile = Profiles[player]
	return profile, profile and profile.Data
end

function ProfileService:ChangeData(player, redirectories, newValue)
	local profile, profileData = ProfileService:GetProfile(player)

	if not profileData then
		warn("Profile data not found for player: " .. (player.Name or "Unknown"))
		return
	end

	local directData = profileData

	-- Navigate through the redirectories path
	for i = 1, #redirectories do
		if not directData[redirectories[i]] and i ~= #redirectories then
			local redirectoriesPath = "profileData"
			for j = 1, i do
				redirectoriesPath = redirectoriesPath .. "." .. redirectories[j]
			end
			error(
				"'"
					.. redirectoriesPath
					.. "' table does not exist. ALWAYS PREVENT THIS BY MAKING TABLES INSIDE PROFILETEMPLATE."
			)
			return
		end

		if i ~= #redirectories then
			directData = directData[redirectories[i]]
		end
	end

	-- Set the new value
	directData[redirectories[#redirectories]] = newValue

	-- Fire update signals
	ProfileService.Client.UpdateSpecificData:Fire(player, redirectories, newValue)
	ProfileService.UpdateSpecificData:Fire(player, redirectories, newValue)
end

function ProfileService.Client:GetOtherPlayer_ProfileData(player, otherPlayer)
	local _, profileData = ProfileService:GetProfile(otherPlayer)
	return profileData
end

function ProfileService.Client:GetProfileAge(player)
	local profile = ProfileService:GetProfile(player)
	if not profile then
		return 0
	end

	local profileAge = os.time() - profile.MetaData.ProfileCreateTime
	return profileAge
end

function ProfileService:KnitStart()
	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(HandlePlayerAdded, player)
	end

	-- Connect player events
	Players.PlayerAdded:Connect(HandlePlayerAdded)
	Players.PlayerRemoving:Connect(HandlePlayerRemoving)

	-- Handle client data requests
	ProfileService.Client.GetData:Connect(function(player)
		ProfileService:WaitUntilProfileLoaded(player)
		local _, profileData = ProfileService:GetProfile(player)
		ProfileService.Client.GetData:Fire(player, profileData)
	end)
end

function ProfileService:KnitInit()
	ProfileStore = ActualProfileService.GetProfileStore("OriginalData1", ProfileTemplate)
end

return ProfileService
