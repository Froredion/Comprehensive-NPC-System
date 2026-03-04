-- AI NOTE: Client-side code executor for run_lua_code client context.
-- Mirrors server-side CodeExecutor: loadstring + pcall with print capture via LogService.
-- Runs in client context so LocalPlayer, PlayerGui, and client-only APIs are accessible.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[SuperbulletCodeExecutor]"

-- Client always uses custom Loadstring module (built-in loadstring not available for clients)
local loadstringFn
local success, customLoadstring = pcall(function()
	return require(ReplicatedStorage.Packages.Loadstring)
end)
if success then
	loadstringFn = customLoadstring
else
	warn(PREFIX, "Client: Loadstring module not found at ReplicatedStorage.Packages.Loadstring")
	warn(PREFIX, "Client code execution will not be available")
end

local ClientCodeExecutor = {}

function ClientCodeExecutor.execute(code)
	if not loadstringFn then
		return {
			success = false,
			error = "Loadstring module not available. Add Loadstring to ReplicatedStorage.Packages.",
		}
	end

	local capturedOutput = {}

	local logConnection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageOutput then
			table.insert(capturedOutput, message)
		end
	end)

	local startTime = os.clock()

	local fn, compileError = loadstringFn(code)
	if not fn then
		logConnection:Disconnect()
		return {
			success = false,
			error = "Compile error: " .. tostring(compileError),
		}
	end

	local execSuccess, execResult = pcall(fn)
	local executionTime = math.floor((os.clock() - startTime) * 1000)

	logConnection:Disconnect()

	if not execSuccess then
		return {
			success = false,
			error = tostring(execResult),
		}
	end

	local output = table.concat(capturedOutput, "\n")
	if execResult ~= nil then
		if output ~= "" then
			output = output .. "\n" .. tostring(execResult)
		else
			output = tostring(execResult)
		end
	end

	return {
		success = true,
		output = output,
		executionTime = executionTime,
	}
end

return ClientCodeExecutor
