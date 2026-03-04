-- AI NOTE: Executes Lua code received from run_lua_code WebSocket messages.
-- Uses loadstring() + pcall() for safe execution with print output capture via LogService.
-- Runs in server context (ServerScriptService) so loadstring and server APIs are available.

local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PREFIX = "[SuperbulletCodeExecutor]"

-- Check if Roblox's built-in loadstring is available (requires ServerScriptService.LoadStringEnabled = true)
local builtinLoadstringEnabled = pcall(function()
	local fn = loadstring("return true")
	return fn and fn()
end)

-- Determine which loadstring to use (server prioritizes built-in, falls back to custom)
local loadstringFn
if builtinLoadstringEnabled then
	loadstringFn = loadstring
else
	-- Fallback to custom Loadstring module
	local success, customLoadstring = pcall(function()
		return require(ReplicatedStorage.Packages.Loadstring)
	end)
	if success then
		loadstringFn = customLoadstring
	else
		warn(PREFIX, "loadstring() is not available and custom Loadstring module not found!")
		warn(PREFIX, "To enable code execution, either:")
		warn(PREFIX, "  1. Set ServerScriptService.LoadStringEnabled = true in Studio (disable in production)")
		warn(PREFIX, "  2. Add Loadstring module to ReplicatedStorage.Packages")
	end
end

local CodeExecutor = {}

-- Execute code and return a structured result table.
-- Print capture limitation: LogService.MessageOut captures ALL server prints during the
-- execution window, including from other scripts running concurrently. This is acceptable
-- for short, infrequent AI debug commands.
-- Check if code will end the playtest (needs deferred execution)
local function isEndTestCode(code)
	return code:find("StudioTestService") and code:find("EndTest")
end

function CodeExecutor.execute(requestId, code)
	if not loadstringFn then
		return {
			success = false,
			error = "loadstring() is not available. Enable ServerScriptService.LoadStringEnabled or add Loadstring module.",
		}
	end

	-- Special case: EndTest must be deferred so we can send response first
	if isEndTestCode(code) then
		local fn, compileError = loadstringFn(code)
		if not fn then
			return {
				success = false,
				error = "Compile error: " .. tostring(compileError),
			}
		end

		-- Delay execution so response can be sent first
		task.delay(0.5, function()
			pcall(fn)
		end)

		return {
			success = true,
			data = {
				output = "Ending playtest...",
				executionTime = 0,
			},
		}
	end

	local capturedOutput = {}

	-- Hook LogService to capture print output during execution
	local logConnection = LogService.MessageOut:Connect(function(message, messageType)
		if messageType == Enum.MessageType.MessageOutput then
			table.insert(capturedOutput, message)
		end
	end)

	local startTime = os.clock()

	-- Compile the code
	local fn, compileError = loadstringFn(code)

	if not fn then
		logConnection:Disconnect()
		warn(PREFIX, "Compile error:", compileError)
		return {
			success = false,
			error = "Compile error: " .. tostring(compileError),
		}
	end

	-- Execute with pcall for safety
	local execSuccess, execResult = pcall(fn)

	local executionTime = math.floor((os.clock() - startTime) * 1000) -- milliseconds

	logConnection:Disconnect()

	if not execSuccess then
		warn(PREFIX, "Execution error:", execResult)
		return {
			success = false,
			error = tostring(execResult),
		}
	end

	-- Build output string from captured prints
	local output = table.concat(capturedOutput, "\n")

	-- If the code returned a value, append it to output
	if execResult ~= nil then
		if output ~= "" then
			output = output .. "\n" .. tostring(execResult)
		else
			output = tostring(execResult)
		end
	end

	return {
		success = true,
		data = {
			output = output,
			executionTime = executionTime,
		},
	}
end

return CodeExecutor
