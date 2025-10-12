local function componentsInitializer(selectedScript)
	for _, v in pairs(selectedScript.Components:GetDescendants()) do
		if v:IsA("ModuleScript") then
			local module = require(v)
			if typeof(module) ~= "function" then
				if not module.Init then
					warn("Component " .. v.Name .. " does not have an Init function")
					continue
				end

				local succ, err = pcall(function()
					module.Init()
				end)

				if not succ then
					warn("Error initializing component: " .. err)
				end

				task.spawn(function()
					module.Start()
				end)
			end
		end
	end
end

return componentsInitializer
