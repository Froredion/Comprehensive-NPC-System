-- AI NOTE: Server-side module that routes client-targeted run_lua_code requests to a player
-- via RemoteFunction. Picks the first available player (Studio playtesting = single player),
-- invokes the client with the expression, and returns the result with a 10s timeout.

local Players = game:GetService("Players")

local PREFIX = "[SuperbulletCodeExecutor]"

local ClientQueryRouter = {}
ClientQueryRouter.__index = ClientQueryRouter

function ClientQueryRouter.new(remoteFunction)
	local self = setmetatable({}, ClientQueryRouter)
	self._remoteFunction = remoteFunction
	return self
end

-- Execute a client-side path expression via RemoteFunction.
-- Returns a result table matching the CodeExecutor format:
--   { success, data: { output, executionTime }, error }
function ClientQueryRouter:execute(code, requestId)
	-- Pick the first connected player
	local players = Players:GetPlayers()
	if #players == 0 then
		warn(PREFIX, "No players connected - cannot execute client query")
		return {
			success = false,
			error = "No players connected — cannot execute client query",
		}
	end
	local player = players[1]

	-- Timeout mechanism using BindableEvent as a signal
	local finished = false
	local clientResult = nil
	local signal = Instance.new("BindableEvent")

	-- Invoke client in a separate thread
	task.spawn(function()
		local ok, result = pcall(function()
			return self._remoteFunction:InvokeClient(player, {
				requestId = requestId,
				code = code,
			})
		end)

		if finished then
			-- Timeout already fired, discard
			signal:Destroy()
			return
		end

		if ok then
			clientResult = result
		else
			clientResult = {
				success = false,
				error = "RemoteFunction error: " .. tostring(result),
			}
		end

		finished = true
		signal:Fire()
	end)

	-- Timeout after 10 seconds
	task.delay(10, function()
		if not finished then
			finished = true
			warn(PREFIX, "Client query timed out after 10 seconds")
			clientResult = {
				success = false,
				error = "Client query timed out after 10 seconds",
			}
			signal:Fire()
		end
	end)

	-- Wait for either client response or timeout
	signal.Event:Wait()
	signal:Destroy()

	-- Validate and normalize the client response
	if type(clientResult) ~= "table" then
		warn(PREFIX, "Invalid response from client (expected table, got", type(clientResult), ")")
		return {
			success = false,
			error = "Invalid response from client (expected table, got " .. type(clientResult) .. ")",
		}
	end

	-- If the client returned a PathEvaluator result, wrap it in CodeExecutor format
	if clientResult.success then
		return {
			success = true,
			data = {
				output = clientResult.output or "",
				executionTime = clientResult.executionTime or 0,
			},
		}
	else
		warn(PREFIX, "Client query failed:", clientResult.error or "Unknown client error")
		return {
			success = false,
			error = clientResult.error or "Unknown client error",
		}
	end
end

return ClientQueryRouter
