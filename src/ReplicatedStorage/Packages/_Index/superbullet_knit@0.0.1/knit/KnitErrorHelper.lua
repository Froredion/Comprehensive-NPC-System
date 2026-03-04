--[=[
	@class KnitErrorHelper
	@private

	Helper module for generating context-aware error messages in Superbullet.
	This module detects whether a caller is a Script/LocalScript or a Superbullet module
	and provides appropriate error messages with solutions.
]=]

local KnitErrorHelper = {}

--[=[
	Gets information about the caller of a Superbullet function.
	@param knitModules table -- The services or controllers table to check against
	@return Instance? -- The calling script/module instance
	@return boolean | "module" -- false for Script/LocalScript, "module" for ModuleScript
]=]
function KnitErrorHelper.GetCallerInfo(knitModules: { [string]: any })
	-- Get the full stack trace
	local traceback = debug.traceback("", 2)

	-- Parse the traceback to find the first non-Knit script
	-- Format: "Path.To.Script:LineNumber [optional: function Name]"
	local callerPaths = {}
	for line in traceback:gmatch("[^\r\n]+") do
		-- Match the Roblox traceback format: Path.To.Script:LineNumber
		local fullPath = line:match("^%s*([^%s]+):%d+")

		if fullPath then
			-- Skip Knit internal files
			if not fullPath:find("Knit") and not fullPath:find("Error") then
				table.insert(callerPaths, fullPath)
			end
		end
	end

	-- Try to navigate to the instance using the full path
	for _, fullPath in ipairs(callerPaths) do
		-- Split the path by dots (e.g., "Players.Froredion.PlayerScripts.newfile")
		local pathParts = {}
		for part in fullPath:gmatch("[^%.]+") do
			table.insert(pathParts, part)
		end

		-- Navigate from game to the instance
		local success, foundInstance = pcall(function()
			local current = game
			for _, part in ipairs(pathParts) do
				current = current:FindFirstChild(part)
				if not current then
					return nil
				end
			end
			return current
		end)

		if success and foundInstance and foundInstance:IsA("LuaSourceContainer") then
			-- Return the instance with appropriate flag
			if foundInstance:IsA("Script") or foundInstance:IsA("LocalScript") then
				return foundInstance, false
			elseif foundInstance:IsA("ModuleScript") then
				-- ModuleScripts are ambiguous - could be Superbullet modules or regular modules
				-- Mark as "module" to show both solutions
				return foundInstance, "module"
			else
				-- Unknown script type
				return foundInstance, false
			end
		end
	end

	-- Couldn't find the caller
	return nil, false
end

--[=[
	Generates a context-aware error message based on the caller type.
	Prints the full detailed guide to the console and returns a short error message.
	@param started boolean -- Whether Superbullet has started
	@param methodName string -- The name of the method that was called (e.g., "GetService")
	@param knitModules table -- The services or controllers table to check against
	@param isClient boolean? -- Whether this is client-side (defaults to false)
	@return string -- A short error message for the assert (or empty string if started is true)
]=]
function KnitErrorHelper.GetStartErrorMessage(
	started: boolean,
	methodName: string,
	knitModules: { [string]: any },
	isClient: boolean?
): string
	-- If Superbullet has started, return empty string (no error)
	if started then
		return ""
	end

	local instance, moduleType = KnitErrorHelper.GetCallerInfo(knitModules)
	isClient = isClient or false

	-- Build the detailed help message
	local detailedMessage = "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
		.. "❌ Cannot call "
		.. methodName
		.. " until Superbullet has been started\n"
		.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"

	if instance and (instance:IsA("Script") or instance:IsA("LocalScript")) then
		-- It's a regular Script/LocalScript
		detailedMessage = detailedMessage
			.. "You are calling this from a "
			.. instance.ClassName
			.. ".\n"
			.. "Solution: Use Superbullet.OnStart():await() to wait for Superbullet to start\n"
			.. "\n"
			.. "Example:\n"
			.. "  Superbullet.OnStart():await()\n"
			.. '  local MyService = Superbullet.GetService("MyService")\n'

		-- Add Controller example for client-side
		if isClient then
			detailedMessage = detailedMessage .. '  local MyController = Superbullet.GetController("MyController")\n'
		end
	elseif moduleType == "module" then
		-- It's a ModuleScript - show both solutions since we can't determine if it's Superbullet or not
		detailedMessage = detailedMessage .. "You are calling this from a ModuleScript.\n\n"

		if isClient then
			-- Client-side: Show both Service and Controller examples
			detailedMessage = detailedMessage
				.. "If this is a Superbullet Service:\n"
				.. "  Move Superbullet.GetService() calls to SuperbulletInit()\n\n"
				.. "  Example:\n"
				.. "    function MyService:SuperbulletInit()\n"
				.. '        local OtherService = Superbullet.GetService("OtherService")\n'
				.. "        -- Use OtherService here\n"
				.. "    end\n\n"
				.. "If this is a Superbullet Controller:\n"
				.. "  Move Superbullet.GetController() calls to SuperbulletInit()\n\n"
				.. "  Example:\n"
				.. "    function MyController:SuperbulletInit()\n"
				.. '        local OtherController = Superbullet.GetController("OtherController")\n'
				.. "        -- Use OtherController here\n"
				.. "    end\n\n"
				.. "If this is a regular ModuleScript:\n"
				.. "  Use Superbullet.OnStart():await() before calling\n\n"
				.. "  Example:\n"
				.. "    Superbullet.OnStart():await()\n"
				.. '    local MyService = Superbullet.GetService("MyService")\n'
				.. '    local MyController = Superbullet.GetController("MyController")\n'
		else
			-- Server-side: Show only Service examples
			detailedMessage = detailedMessage
				.. "If this is a Superbullet Service:\n"
				.. "  Move Superbullet.GetService() calls to SuperbulletInit()\n\n"
				.. "  Example:\n"
				.. "    function MyService:SuperbulletInit()\n"
				.. '        local OtherService = Superbullet.GetService("OtherService")\n'
				.. "        -- Use OtherService here\n"
				.. "    end\n\n"
				.. "If this is a regular ModuleScript:\n"
				.. "  Use Superbullet.OnStart():await() before calling\n\n"
				.. "  Example:\n"
				.. "    Superbullet.OnStart():await()\n"
				.. '    local MyService = Superbullet.GetService("MyService")\n'
		end
	else
		-- Fallback for when we can't determine the source
		detailedMessage = detailedMessage .. "Solution: Ensure Superbullet has started before calling this method\n\n"

		if isClient then
			-- Client-side: Show both Service and Controller examples
			detailedMessage = detailedMessage
				.. "For Scripts/LocalScripts/ModuleScripts:\n"
				.. "  Superbullet.OnStart():await()\n"
				.. '  local MyService = Superbullet.GetService("MyService")\n'
				.. '  local MyController = Superbullet.GetController("MyController")\n\n'
				.. "For Superbullet Services:\n"
				.. "  function MyService:SuperbulletInit()\n"
				.. '      local OtherService = Superbullet.GetService("OtherService")\n'
				.. "  end\n\n"
				.. "For Superbullet Controllers:\n"
				.. "  function MyController:SuperbulletInit()\n"
				.. '      local OtherController = Superbullet.GetController("OtherController")\n'
				.. "  end\n"
		else
			-- Server-side: Show only Service examples
			detailedMessage = detailedMessage
				.. "For Scripts/LocalScripts/ModuleScripts:\n"
				.. "  Superbullet.OnStart():await()\n"
				.. '  local MyService = Superbullet.GetService("MyService")\n\n'
				.. "For Superbullet Services:\n"
				.. "  function MyService:SuperbulletInit()\n"
				.. '      local OtherService = Superbullet.GetService("OtherService")\n'
				.. "  end\n"
		end
	end

	detailedMessage = detailedMessage
		.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

	-- Print the detailed message to the console
	warn(detailedMessage)

	-- Return a short error message for the assert
	return "Cannot call " .. methodName .. " until Superbullet has been started. See output above for details."
end

return KnitErrorHelper
