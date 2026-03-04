-- SuperbulletServerLogger.server.lua
-- Collects logs from server and client, batches them, sends to frontend
-- NOTE: Only runs in Roblox Studio, not in production

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local LogService = game:GetService("LogService")
local RunService = game:GetService("RunService")

-- Only run in Studio (useless in production)
if not RunService:IsStudio() then
	return
end

-- Configuration
local BATCH_INTERVAL = 1 -- seconds
local MAX_BATCH_SIZE = 100
local MAX_BUFFER_SIZE = MAX_BATCH_SIZE * 2

-- Read configuration from ServerStorage.Superbullet.Superbullet_Server
local function getConfig()
	local superbulletFolder = ServerStorage:FindFirstChild("Superbullet")
	if not superbulletFolder then
		return { mode = "localhost", port = 13528 }
	end

	local configFolder = superbulletFolder:FindFirstChild("Superbullet_Server")
	if not configFolder then
		return { mode = "localhost", port = 13528 }
	end

	local modeValue = configFolder:FindFirstChild("ConnectionMode")
	local portValue = configFolder:FindFirstChild("Port")
	local tokenValue = configFolder:FindFirstChild("CloudToken")

	return {
		mode = modeValue and modeValue.Value or "localhost",
		port = portValue and portValue.Value or 13528,
		cloudToken = tokenValue and tokenValue.Value or nil,
	}
end

-- Create RemoteEvent for client logs
local clientLogEvent = Instance.new("RemoteEvent")
clientLogEvent.Name = "SuperbulletClientLog"
clientLogEvent.Parent = ReplicatedStorage

-- Create RemoteEvent to notify client if HttpService is disabled
local httpDisabledEvent = Instance.new("RemoteEvent")
httpDisabledEvent.Name = "SuperbulletHttpDisabled"
httpDisabledEvent.Parent = ReplicatedStorage

-- Create RemoteFunction for client-side code queries (path expression evaluator)
local clientQueryFunction = Instance.new("RemoteFunction")
clientQueryFunction.Name = "SuperbulletClientQuery"
clientQueryFunction.Parent = ReplicatedStorage

-- Check if HttpService is enabled
local function isHttpServiceEnabled()
	local success, result = pcall(function()
		-- Try a simple request to check if HttpService is enabled
		-- This will error immediately if HttpService is disabled (before any network call)
		HttpService:GetAsync("http://localhost:1")
	end)

	if not success then
		-- Check if the error is specifically about HttpService being disabled
		local errorMsg = tostring(result):lower()
		if errorMsg:find("http requests are not enabled") or errorMsg:find("httpservice is not enabled") then
			return false
		end
	end

	-- If we got here, HttpService is enabled (even if the request failed for other reasons)
	return true
end

local httpEnabled = isHttpServiceEnabled()

-- Notify players when they join if HttpService is disabled
if not httpEnabled then
	warn("[SuperbulletLogger] HttpService is disabled! Superbullet AI debugger requires HttpService to be enabled.")

	game:GetService("Players").PlayerAdded:Connect(function(player)
		-- Small delay to ensure client is ready
		task.delay(1, function()
			httpDisabledEvent:FireClient(player)
		end)
	end)

	-- Also notify any players already in the game
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		task.delay(1, function()
			httpDisabledEvent:FireClient(player)
		end)
	end
end

-- If HttpService is disabled, don't proceed with logging (client will show UI)
if not httpEnabled then
	return
end

-- Log buffer
local logBuffer = {}
local config = getConfig()

-- Code executor prefix for consistent debug output
local CODE_EXECUTOR_PREFIX = "[SuperbulletCodeExecutor]"

-- WebSocket modules for run_lua_code
local WebSocketClient = require(script.WebSocketClient)
local CodeExecutor = require(script.CodeExecutor)
local ClientQueryRouter = require(script.ClientQueryRouter)

-- Check if backend is reachable (mode-dependent: localhost or cloud)
local function isBackendReachable()
	local url
	if config.mode == "cloud" and config.cloudToken then
		url = "https://superbullet-backend-3948693.superbulletstudios.com/api/superbullet/health"
	else
		url = string.format("http://localhost:%d/health", config.port)
	end

	local success, result = pcall(function()
		return HttpService:GetAsync(url)
	end)

	if success then
		return true
	else
		local errorMsg = tostring(result):lower()
		-- Connection refused or timeout means backend is not running
		if errorMsg:find("connection refused") or errorMsg:find("connect") or errorMsg:find("timeout") then
			return false
		end
		-- Other errors (like 404) mean the server is running but endpoint doesn't exist
		-- This is still a valid connection for our purposes
		return true
	end
end

local backendReachable = isBackendReachable()
if not backendReachable then
	warn(CODE_EXECUTOR_PREFIX, "Backend not reachable at", config.mode == "cloud" and "cloud backend" or ("localhost:" .. config.port))
	warn(CODE_EXECUTOR_PREFIX, "Code execution features will not be available until the backend is running")
end

-- Build endpoint URL
-- NOTE: Cloud mode implementation is in Phase 5
local function getEndpointUrl(endpoint)
	if config.mode == "cloud" and config.cloudToken then
		local baseUrl = "https://superbullet-backend-3948693.superbulletstudios.com"
		return baseUrl .. "/api/superbullet" .. endpoint .. "?token=" .. config.cloudToken
	else
		return string.format("http://localhost:%d%s", config.port, endpoint)
	end
end

-- Get current timestamp in milliseconds (using DateTime for accuracy)
local function getTimestampMs()
	return DateTime.now().UnixTimestampMillis
end

-- Send logs to frontend
local function sendLogs(logs)
	if #logs == 0 then
		return
	end

	local url = getEndpointUrl("/playtest/logs")
	local body = HttpService:JSONEncode({
		token = config.mode == "cloud" and config.cloudToken or nil,
		timestamp = getTimestampMs(),
		logs = logs,
	})

	local success, result = pcall(function()
		return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
	end)

	if not success then
		warn("[SuperbulletLogger] Failed to send logs:", result)
	end
end

-- Notify playtest started
local function notifyPlaytestStart()
	local url = getEndpointUrl("/playtest/start")
	local body = HttpService:JSONEncode({
		token = config.mode == "cloud" and config.cloudToken or nil,
		timestamp = getTimestampMs(),
	})

	pcall(function()
		HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
	end)
end

-- Parse log message to extract script and line info
local function parseLogMessage(message)
	-- Handle various Roblox error formats:
	-- "ServerScriptService.Script:42: error message"
	-- "Players.Player.PlayerScripts.LocalScript:10: error"
	-- "ReplicatedStorage.ModuleScript:5: error"
	-- Match path with potential dots/colons, line number, then message
	local scriptPath, line, msg = message:match("^(.+):(%d+):%s*(.+)$")

	if scriptPath and line then
		-- Extract just the script name (last segment after dot)
		local scriptName = scriptPath:match("[^%.]+$") or scriptPath
		return {
			script = scriptName,
			line = tonumber(line),
			message = msg,
		}
	end

	return { message = message }
end

-- Get formatted time string (HH:MM:SS)
local function getFormattedTime()
	local t = os.date("*t")
	return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

-- Add log to buffer
local function addLog(source, level, message, traceback)
	local parsed = parseLogMessage(message)

	table.insert(logBuffer, {
		timestamp = getTimestampMs(),
		timeFormatted = getFormattedTime(),
		source = source,
		level = level,
		message = parsed.message or message,
		script = parsed.script,
		line = parsed.line,
		traceback = traceback,
	})

	-- Prevent buffer overflow - trim efficiently by creating new table
	if #logBuffer > MAX_BUFFER_SIZE then
		local newBuffer = {}
		local startIndex = #logBuffer - MAX_BATCH_SIZE + 1
		for i = startIndex, #logBuffer do
			table.insert(newBuffer, logBuffer[i])
		end
		logBuffer = newBuffer
	end
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

-- Listen for server-side log messages
LogService.MessageOut:Connect(function(message, messageType)
	local level = getLogLevel(messageType)
	addLog("server", level, message)
end)

-- Listen for client logs via RemoteEvent
clientLogEvent.OnServerEvent:Connect(function(player, logData)
	-- Validate logData
	if type(logData) ~= "table" then
		return
	end
	if type(logData.level) ~= "string" then
		return
	end
	if type(logData.message) ~= "string" then
		return
	end

	-- Sanitize and add player info
	local sanitizedMessage = logData.message:sub(1, 1000) -- Limit message length

	addLog("client", logData.level, sanitizedMessage, logData.traceback)
end)

-- Batch send loop
task.spawn(function()
	-- Notify frontend that playtest started
	notifyPlaytestStart()

	while true do
		task.wait(BATCH_INTERVAL)

		if #logBuffer > 0 then
			-- Collect logs to send
			local logsToSend = {}
			local count = math.min(#logBuffer, MAX_BATCH_SIZE)
			for i = 1, count do
				table.insert(logsToSend, logBuffer[i])
			end

			-- Remove sent logs efficiently
			local newBuffer = {}
			for i = count + 1, #logBuffer do
				table.insert(newBuffer, logBuffer[i])
			end
			logBuffer = newBuffer

			sendLogs(logsToSend)
		end
	end
end)

-- Detect execution context from a run_lua_code message.
-- Returns ("client", strippedCode) or ("server", originalCode).
local function detectContext(message)
	-- 1. Explicit context field from backend
	if message.context == "client" then
		return "client", message.code
	end

	-- 2. --@client prefix in code string
	local code = message.code or ""
	local stripped = code:match("^%-%-@client%s*(.*)")
	if stripped then
		return "client", stripped
	end

	-- 3. Default: server
	return "server", code
end

-- Client query router (initialized once, used by WebSocket handler)
local clientRouter = ClientQueryRouter.new(clientQueryFunction)

-- WebSocket connection for run_lua_code (both localhost and cloud modes)
-- Connects to the backend so it can push run_lua_code requests directly
-- to this game instance instead of routing through the plugin's HTTP polling.
-- Cloud mode requires cloudToken, localhost mode connects to ws://localhost:port/ws
local canConnectWebSocket = (config.mode == "cloud" and config.cloudToken) or (config.mode == "localhost")

if canConnectWebSocket then
	if not backendReachable then
		warn(CODE_EXECUTOR_PREFIX, "Skipping WebSocket connection - backend not reachable")
	else
		local wsClient = WebSocketClient.new(config)

		wsClient:setMessageHandler(function(message)
			if message.type == "run_lua_code" then
				-- Wrap in task.spawn so pings are still processed during execution
				task.spawn(function()
					local context, code = detectContext(message)
					local result

					if context == "client" then
						result = clientRouter:execute(code, message.requestId)
					else
						result = CodeExecutor.execute(message.requestId, code)
					end

					wsClient:sendResponse({
						type = "run_lua_code_response",
						requestId = message.requestId,
						result = result,
						timestamp = DateTime.now().UnixTimestampMillis,
					})
				end)
			end
		end)

		local connected = wsClient:connect()
		if not connected then
			warn(CODE_EXECUTOR_PREFIX, "Failed to initiate WebSocket connection")
		end

		-- Disconnect on game close (registered before log flush BindToClose so it runs first)
		game:BindToClose(function()
			wsClient:disconnect()
		end)
	end
end

-- Notify playtest stopped on game close
game:BindToClose(function()
	-- Send remaining logs in batches to avoid timeout
	while #logBuffer > 0 do
		local logsToSend = {}
		local count = math.min(#logBuffer, MAX_BATCH_SIZE)
		for i = 1, count do
			table.insert(logsToSend, logBuffer[i])
		end

		-- Remove sent logs
		local newBuffer = {}
		for i = count + 1, #logBuffer do
			table.insert(newBuffer, logBuffer[i])
		end
		logBuffer = newBuffer

		sendLogs(logsToSend)
	end

	-- Notify stop
	local url = getEndpointUrl("/playtest/stop")
	local body = HttpService:JSONEncode({
		token = config.mode == "cloud" and config.cloudToken or nil,
		timestamp = getTimestampMs(),
	})

	pcall(function()
		HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
	end)
end)

print("[SuperbulletLogger] Server logger initialized (Studio only)")
