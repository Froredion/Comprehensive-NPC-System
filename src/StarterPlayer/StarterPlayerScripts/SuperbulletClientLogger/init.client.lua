-- SuperbulletClientLogger.client.lua
-- Captures client-side logs and sends them to server via RemoteEvent
-- NOTE: Only runs in Roblox Studio, not in production

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Only run in Studio (useless in production)
if not RunService:IsStudio() then
	return
end

-- Create HttpService disabled warning UI
local function createHttpDisabledUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Create ScreenGui (DisplayOrder high, ResetOnSpawn false, IgnoreGuiInset true)
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SuperbulletHttpWarning"
	screenGui.DisplayOrder = 999999
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	-- Semi-transparent dark overlay
	local overlay = Instance.new("Frame")
	overlay.Name = "Overlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.4
	overlay.BorderSizePixel = 0
	overlay.Parent = screenGui

	-- Main warning container
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 500, 0, 400)
	container.Position = UDim2.new(0.5, -250, 0.5, -200)
	container.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
	container.BorderSizePixel = 0
	container.Parent = screenGui

	-- Container corner rounding
	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = container

	-- Orange/yellow accent bar at top
	local accentBar = Instance.new("Frame")
	accentBar.Name = "AccentBar"
	accentBar.Size = UDim2.new(1, 0, 0, 4)
	accentBar.Position = UDim2.new(0, 0, 0, 0)
	accentBar.BackgroundColor3 = Color3.fromRGB(255, 170, 50)
	accentBar.BorderSizePixel = 0
	accentBar.Parent = container

	-- Warning icon (using text emoji as fallback)
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 60, 0, 60)
	iconLabel.Position = UDim2.new(0.5, -30, 0, 20)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = "⚠️"
	iconLabel.TextSize = 48
	iconLabel.Font = Enum.Font.GothamBold
	iconLabel.TextColor3 = Color3.fromRGB(255, 170, 50)
	iconLabel.Parent = container

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -40, 0, 30)
	title.Position = UDim2.new(0, 20, 0, 85)
	title.BackgroundTransparency = 1
	title.Text = "HttpService is Disabled"
	title.TextSize = 24
	title.Font = Enum.Font.GothamBold
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Parent = container

	-- Subtitle
	local subtitle = Instance.new("TextLabel")
	subtitle.Name = "Subtitle"
	subtitle.Size = UDim2.new(1, -40, 0, 20)
	subtitle.Position = UDim2.new(0, 20, 0, 118)
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Superbullet AI Debugger requires HttpService to be enabled"
	subtitle.TextSize = 14
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextColor3 = Color3.fromRGB(180, 180, 180)
	subtitle.Parent = container

	-- Steps container
	local stepsContainer = Instance.new("Frame")
	stepsContainer.Name = "StepsContainer"
	stepsContainer.Size = UDim2.new(1, -40, 0, 160)
	stepsContainer.Position = UDim2.new(0, 20, 0, 150)
	stepsContainer.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	stepsContainer.BorderSizePixel = 0
	stepsContainer.Parent = container

	local stepsCorner = Instance.new("UICorner")
	stepsCorner.CornerRadius = UDim.new(0, 8)
	stepsCorner.Parent = stepsContainer

	-- Steps header
	local stepsHeader = Instance.new("TextLabel")
	stepsHeader.Name = "StepsHeader"
	stepsHeader.Size = UDim2.new(1, -20, 0, 25)
	stepsHeader.Position = UDim2.new(0, 10, 0, 10)
	stepsHeader.BackgroundTransparency = 1
	stepsHeader.Text = "How to Enable HttpService:"
	stepsHeader.TextSize = 14
	stepsHeader.Font = Enum.Font.GothamBold
	stepsHeader.TextColor3 = Color3.fromRGB(255, 170, 50)
	stepsHeader.TextXAlignment = Enum.TextXAlignment.Left
	stepsHeader.Parent = stepsContainer

	-- Steps text
	local steps = {
		"1. Stop the playtest (click Stop or press Shift+F5)",
		"2. Go to File > Game Settings",
		"3. Navigate to the 'Security' tab",
		"4. Enable 'Allow HTTP Requests'",
		"5. Click 'Save' and restart the playtest"
	}

	for i, step in ipairs(steps) do
		local stepLabel = Instance.new("TextLabel")
		stepLabel.Name = "Step" .. i
		stepLabel.Size = UDim2.new(1, -20, 0, 22)
		stepLabel.Position = UDim2.new(0, 10, 0, 30 + (i - 1) * 24)
		stepLabel.BackgroundTransparency = 1
		stepLabel.Text = step
		stepLabel.TextSize = 13
		stepLabel.Font = Enum.Font.Gotham
		stepLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
		stepLabel.TextXAlignment = Enum.TextXAlignment.Left
		stepLabel.TextWrapped = true
		stepLabel.Parent = stepsContainer
	end

	-- Video tutorial section
	local videoLabel = Instance.new("TextLabel")
	videoLabel.Name = "VideoLabel"
	videoLabel.Size = UDim2.new(0, 120, 0, 20)
	videoLabel.Position = UDim2.new(0, 20, 0, 320)
	videoLabel.BackgroundTransparency = 1
	videoLabel.Text = "Video Tutorial:"
	videoLabel.TextSize = 12
	videoLabel.Font = Enum.Font.GothamMedium
	videoLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	videoLabel.TextXAlignment = Enum.TextXAlignment.Left
	videoLabel.Parent = container

	-- Video URL TextBox (non-editable, copyable)
	local videoUrlBox = Instance.new("TextBox")
	videoUrlBox.Name = "VideoUrlBox"
	videoUrlBox.Size = UDim2.new(1, -160, 0, 24)
	videoUrlBox.Position = UDim2.new(0, 140, 0, 318)
	videoUrlBox.BackgroundColor3 = Color3.fromRGB(50, 50, 58)
	videoUrlBox.BorderSizePixel = 0
	videoUrlBox.Text = "https://youtu.be/uI065F9UaCA"
	videoUrlBox.TextSize = 12
	videoUrlBox.Font = Enum.Font.Code
	videoUrlBox.TextColor3 = Color3.fromRGB(100, 180, 255)
	videoUrlBox.TextXAlignment = Enum.TextXAlignment.Left
	videoUrlBox.ClearTextOnFocus = false
	videoUrlBox.TextEditable = false
	videoUrlBox.Parent = container

	local videoUrlCorner = Instance.new("UICorner")
	videoUrlCorner.CornerRadius = UDim.new(0, 4)
	videoUrlCorner.Parent = videoUrlBox

	local videoUrlPadding = Instance.new("UIPadding")
	videoUrlPadding.PaddingLeft = UDim.new(0, 8)
	videoUrlPadding.PaddingRight = UDim.new(0, 8)
	videoUrlPadding.Parent = videoUrlBox

	-- Footer note
	local footer = Instance.new("TextLabel")
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, -40, 0, 30)
	footer.Position = UDim2.new(0, 20, 1, -35)
	footer.BackgroundTransparency = 1
	footer.Text = "This window cannot be closed. Enable HttpService and restart."
	footer.TextSize = 11
	footer.Font = Enum.Font.GothamMedium
	footer.TextColor3 = Color3.fromRGB(120, 120, 120)
	footer.Parent = container

	-- Subtle pulse animation on the accent bar
	task.spawn(function()
		while screenGui.Parent do
			local tweenIn = TweenService:Create(accentBar, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				BackgroundColor3 = Color3.fromRGB(255, 200, 100)
			})
			tweenIn:Play()
			tweenIn.Completed:Wait()

			local tweenOut = TweenService:Create(accentBar, TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				BackgroundColor3 = Color3.fromRGB(255, 170, 50)
			})
			tweenOut:Play()
			tweenOut.Completed:Wait()
		end
	end)

	return screenGui
end

-- Listen for HttpService disabled notification from server
local httpDisabledEvent = ReplicatedStorage:WaitForChild("SuperbulletHttpDisabled", 5)
if httpDisabledEvent then
	httpDisabledEvent.OnClientEvent:Connect(function()
		createHttpDisabledUI()
	end)
end

-- Wait for RemoteEvent (created by server logger)
local clientLogEvent = ReplicatedStorage:WaitForChild("SuperbulletClientLog", 10)
if not clientLogEvent then
	-- If we can't find it and httpDisabledEvent was fired, UI is already showing
	-- Otherwise warn about missing event
	if not httpDisabledEvent then
		warn("[SuperbulletLogger] Could not find client log event")
	end
	return
end

-- Rate limiting
local LOG_RATE_LIMIT = 10 -- max logs per second
local logCount = 0
local lastResetTime = tick()

local function canSendLog()
	local now = tick()
	if now - lastResetTime >= 1 then
		logCount = 0
		lastResetTime = now
	end

	if logCount >= LOG_RATE_LIMIT then
		return false
	end

	logCount = logCount + 1
	return true
end

-- Send log to server
local function sendLog(level, message, traceback)
	if not canSendLog() then return end

	clientLogEvent:FireServer({
		level = level,
		message = message,
		traceback = traceback
	})
end

-- Map MessageType to log level
local function getLogLevel(messageType)
	if messageType == Enum.MessageType.MessageError then
		return "error"
	elseif messageType == Enum.MessageType.MessageWarning then
		return "warning"
	elseif messageType == Enum.MessageType.MessageInfo then
		return "info"
	elseif messageType == Enum.MessageType.MessageOutput then
		return "debug" -- print() statements
	end
	return "info"
end

-- Listen for client-side log messages
LogService.MessageOut:Connect(function(message, messageType)
	local level = getLogLevel(messageType)
	sendLog(level, message)
end)

-- Client-side code executor for run_lua_code client context
local ClientCodeExecutor = require(script.ClientCodeExecutor)

-- Listen for client query requests via RemoteFunction
local clientQueryFunction = ReplicatedStorage:WaitForChild("SuperbulletClientQuery", 10)
if clientQueryFunction then
	clientQueryFunction.OnClientInvoke = function(payload)
		if type(payload) ~= "table" or type(payload.code) ~= "string" then
			return { success = false, error = "Invalid client query payload" }
		end

		return ClientCodeExecutor.execute(payload.code)
	end
end

print("[SuperbulletLogger] Client logger initialized (Studio only)")
