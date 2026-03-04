--[=[
	@interface Middleware
	.Inbound ClientMiddleware?
	.Outbound ClientMiddleware?
	@within SuperbulletClient
]=]
type Middleware = {
	Inbound: ClientMiddleware?,
	Outbound: ClientMiddleware?,
}

--[=[
	@type ClientMiddlewareFn (args: {any}) -> (shouldContinue: boolean, ...: any)
	@within SuperbulletClient

	For more info, see [ClientComm](https://sleitnick.github.io/RbxUtil/api/ClientComm/) documentation.
]=]
type ClientMiddlewareFn = (args: { any }) -> (boolean, ...any)

--[=[
	@type ClientMiddleware {ClientMiddlewareFn}
	@within SuperbulletClient
	An array of client middleware functions.
]=]
type ClientMiddleware = { ClientMiddlewareFn }

--[=[
	@type PerServiceMiddleware {[string]: Middleware}
	@within SuperbulletClient
]=]
type PerServiceMiddleware = { [string]: Middleware }

--[=[
	@interface ControllerDef
	.Name string
	.Instance Instance?
	.[any] any
	@within SuperbulletClient
	Used to define a controller when creating it in `CreateController`.

	If `Instance` is provided (typically `script`), Superbullet will automatically
	initialize components found in a `Components` folder within that instance.
]=]
type ControllerDef = {
	Name: string,
	Instance: Instance?,
	[any]: any,
}

--[=[
	@interface Controller
	.Name string
	.[any] any
	@within SuperbulletClient
]=]
type Controller = {
	Name: string,
	[any]: any,
}

--[=[
	@interface Service
	.[any] any
	@within SuperbulletClient
]=]
type Service = {
	[any]: any,
}

--[=[
	@interface KnitOptions
	.ServicePromises boolean?
	.Middleware Middleware?
	.PerServiceMiddleware PerServiceMiddleware?
	@within SuperbulletClient

	- `ServicePromises` defaults to `true` and indicates if service methods use promises.
	- Each service will go through the defined middleware, unless the service
	has middleware defined in `PerServiceMiddleware`.
]=]
type KnitOptions = {
	ServicePromises: boolean,
	Middleware: Middleware?,
	PerServiceMiddleware: PerServiceMiddleware?,
}

local defaultOptions: KnitOptions = {
	ServicePromises = true,
	Middleware = nil,
	PerServiceMiddleware = {},
}

local selectedOptions = nil

--[=[
	@class SuperbulletClient
	@client
]=]
local KnitClient = {}

--[=[
	@prop Player Player
	@within SuperbulletClient
	@readonly
	Reference to the LocalPlayer.
]=]
KnitClient.Player = game:GetService("Players").LocalPlayer

--[=[
	@prop Util Folder
	@within SuperbulletClient
	@readonly
	References the Util folder. Should only be accessed when using Superbullet as
	a standalone module. If using Superbullet from Wally, modules should just be
	pulled in via Wally instead of relying on Superbullet's Util folder, as this
	folder only contains what is necessary for Superbullet to run in Wally mode.
]=]
KnitClient.Util = (script.Parent :: Instance).Parent

local Promise = require(KnitClient.Util.Promise)
local Comm = require(KnitClient.Util.Comm)
local ClientComm = Comm.ClientComm
local KnitErrorHelper = require(script.Parent.KnitErrorHelper)
local Components = require(script.Parent.Components)
local ComponentInitializer = Components.ComponentInitializer

local controllers: { [string]: Controller } = {}
local services: { [string]: Service } = {}
local servicesFolder = nil

local started = false
local startedComplete = false
local onStartedComplete = Instance.new("BindableEvent")

local function DoesControllerExist(controllerName: string): boolean
	local controller: Controller? = controllers[controllerName]

	return controller ~= nil
end

local function GetServicesFolder()
	if not servicesFolder then
		servicesFolder = (script.Parent :: Instance):WaitForChild("Services", 30)
		if not servicesFolder then
			error(
				"\n━━━━━━━━━━━━━━━━━━━━\n"
					.. "❌ Superbullet Error: Services folder not found\n"
					.. "━━━━━━━━━━━━━━━━━━━━\n"
					.. "The server has not finished initializing yet.\n"
					.. "\n"
					.. "Most common cause:\n"
					.. "⚠️  A SuperbulletInit error occurred on the server\n"
					.. "    Check the server console for SuperbulletInit errors above.\n"
					.. "━━━━━━━━━━━━━━━━━━━━"
			)
		end

		-- Wait for server to signal all remotes (including dynamic ones) are ready
		-- Use a loop to handle race conditions where attribute might be set between check and wait
		while not servicesFolder:GetAttribute("Ready") do
			servicesFolder:GetAttributeChangedSignal("Ready"):Wait()
		end
	end

	return servicesFolder
end

local function GetMiddlewareForService(serviceName: string)
	local knitMiddleware = if selectedOptions.Middleware ~= nil then selectedOptions.Middleware else {}
	local serviceMiddleware = selectedOptions.PerServiceMiddleware[serviceName]

	return if serviceMiddleware ~= nil then serviceMiddleware else knitMiddleware
end

local function BuildService(serviceName: string)
	local folder = GetServicesFolder()
	local middleware = GetMiddlewareForService(serviceName)
	local clientComm = ClientComm.new(folder, selectedOptions.ServicePromises, serviceName)
	local service = clientComm:BuildObject(middleware.Inbound, middleware.Outbound)

	services[serviceName] = service

	return service
end

--[=[
	Creates a new controller.

	:::caution
	Controllers must be created _before_ calling `Superbullet.Start()`.
	:::
	```lua
	-- Create a controller
	local MyController = Superbullet.CreateController {
		Name = "MyController",
	}

	function MyController:SuperbulletStart()
		print("MyController started")
	end

	function MyController:SuperbulletInit()
		print("MyController initialized")
	end
	```

	With automatic component initialization:
	```lua
	local MyController = Superbullet.CreateController {
		Name = "MyController",
		Instance = script,  -- Automatically initializes components
	}
	```
]=]
function KnitClient.CreateController(controllerDef: ControllerDef): Controller
	assert(type(controllerDef) == "table", `Controller must be a table; got {type(controllerDef)}`)
	assert(type(controllerDef.Name) == "string", `Controller.Name must be a string; got {type(controllerDef.Name)}`)
	assert(#controllerDef.Name > 0, "Controller.Name must be a non-empty string")
	assert(not DoesControllerExist(controllerDef.Name), `Controller {controllerDef.Name} already exists`)
	assert(not started, `Controllers cannot be created after calling "Superbullet.Start()"`)

	local controller = controllerDef :: Controller

	controllers[controller.Name] = controller

	return controller
end

--[=[
	Requires all the modules that are children of the given parent. This is an easy
	way to quickly load all controllers that might be in a folder.
	```lua
	Superbullet.AddControllers(somewhere.Controllers)
	```
]=]
function KnitClient.AddControllers(parent: Instance): { Controller }
	assert(not started, `Controllers cannot be added after calling "Superbullet.Start()"`)

	local addedControllers = {}
	for _, v in parent:GetChildren() do
		if not v:IsA("ModuleScript") then
			continue
		end

		table.insert(addedControllers, require(v))
	end

	return addedControllers
end

--[=[
	Requires all the modules that are descendants of the given parent.
]=]
function KnitClient.AddControllersDeep(parent: Instance): { Controller }
	assert(not started, `Controllers cannot be added after calling "Superbullet.Start()"`)

	local addedControllers = {}
	for _, v in parent:GetDescendants() do
		if not v:IsA("ModuleScript") then
			continue
		end

		table.insert(addedControllers, require(v))
	end

	return addedControllers
end

--[=[
	Returns a Service object which is a reflection of the remote objects
	within the Client table of the given service. Throws an error if the
	service is not found.

	If a service's Client table contains RemoteSignals and/or RemoteProperties,
	these values are reflected as
	[ClientRemoteSignals](https://sleitnick.github.io/RbxUtil/api/ClientRemoteSignal) and
	[ClientRemoteProperties](https://sleitnick.github.io/RbxUtil/api/ClientRemoteProperty).

	```lua
	-- Server-side service creation:
	local MyService = Superbullet.CreateService {
		Name = "MyService",
		Client = {
			MySignal = Superbullet.CreateSignal(),
			MyProperty = Superbullet.CreateProperty("Hello"),
		},
	}
	function MyService:AddOne(player, number)
		return number + 1
	end

	-------------------------------------------------

	-- Client-side service reflection:
	local MyService = Superbullet.GetService("MyService")

	-- Call a method:
	local num = MyService:AddOne(5) --> 6

	-- Fire a signal to the server:
	MyService.MySignal:Fire("Hello")

	-- Listen for signals from the server:
	MyService.MySignal:Connect(function(message)
		print(message)
	end)

	-- Observe the initial value and changes to properties:
	MyService.MyProperty:Observe(function(value)
		print(value)
	end)
	```

	:::caution
	Services are only exposed to the client if the service has remote-based
	content in the Client table. If not, the service will not be visible
	to the client. `KnitClient.GetService` will only work on services that
	expose remote-based content on their Client tables.
	:::
]=]
function KnitClient.GetService(serviceName: string): Service
	local service = services[serviceName]
	if service then
		return service
	end

	assert(started, KnitErrorHelper.GetStartErrorMessage(started, "GetService", controllers, true)) -- true = client-side
	assert(type(serviceName) == "string", `ServiceName must be a string; got {type(serviceName)}`)

	-- Warn if GetService is called during initialization and takes too long
	if not startedComplete then
		task.spawn(function()
			local Players = game:GetService("Players")
			local player = Players.LocalPlayer
			if not player.Character and Players.CharacterAutoLoads then
				player.CharacterAdded:Wait()
			elseif not player.Character then
				while not player.Character do
					task.wait(2)
				end
			end
			task.wait(5)
			if not startedComplete then
				warn(
					string.format(
						"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
							.. "⚠️  Superbullet Initialization Warning (Client)\n"
							.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
							.. "GetService('%s') called during initialization, and Superbullet has been\n"
							.. "initializing for more than 5 seconds.\n"
							.. "\n"
							.. "Possible causes:\n"
							.. "• Service '%s' does not exist on the server\n"
							.. "• Service has no Client table exposed\n"
							.. "• Server has not finished initializing (check server console)\n"
							.. "• A SuperbulletInit or component Init() is yielding\n"
							.. "\n"
							.. "This is blocking Superbullet from completing initialization.\n"
							.. "\n"
							.. "💡 If none of these are the issue, scroll up in the console\n"
							.. "   to find any other warnings or errors that might be the cause.\n"
							.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━",
						serviceName,
						serviceName
					)
				)
			end
		end)
	end

	return BuildService(serviceName)
end

--[=[
	Gets the controller by name. Throws an error if the controller
	is not found.
]=]
function KnitClient.GetController(controllerName: string): Controller
	local controller = controllers[controllerName]
	if controller then
		return controller
	end

	assert(started, KnitErrorHelper.GetStartErrorMessage(started, "GetController", controllers, true)) -- true = client-side
	assert(type(controllerName) == "string", `ControllerName must be a string; got {type(controllerName)}`)
	error(`Could not find controller "{controllerName}". Check to verify a controller with this name exists.`, 2)
end

--[=[
	Gets a table of all controllers.
]=]
function KnitClient.GetControllers(): { [string]: Controller }
	assert(started, KnitErrorHelper.GetStartErrorMessage(started, "GetControllers", controllers, true)) -- true = client-side

	return controllers
end

--[=[
	@return Promise
	Starts Superbullet. Should only be called once per client.
	```lua
	Superbullet.Start():andThen(function()
		print("Superbullet started!")
	end):catch(warn)
	```

	By default, service methods exposed to the client will return promises.
	To change this behavior, set the `ServicePromises` option to `false`:
	```lua
	Superbullet.Start({ServicePromises = false}):andThen(function()
		print("Superbullet started!")
	end):catch(warn)
	```
]=]
function KnitClient.Start(options: KnitOptions?)
	if started then
		return Promise.reject("Superbullet already started")
	end

	started = true

	table.freeze(controllers)

	if options == nil then
		selectedOptions = defaultOptions
	else
		assert(typeof(options) == "table", `KnitOptions should be a table or nil; got {typeof(options)}`)
		selectedOptions = options
		for k, v in defaultOptions do
			if selectedOptions[k] == nil then
				selectedOptions[k] = v
			end
		end
	end
	if type(selectedOptions.PerServiceMiddleware) ~= "table" then
		selectedOptions.PerServiceMiddleware = {}
	end

	local failedControllers = {}

	return Promise.new(function(resolve)
		-- Init:
		local promisesStartControllers = {}

		for _, controller in controllers do
			local initFn = controller.SuperbulletInit or controller.KnitInit
			if type(initFn) == "function" then
				table.insert(
					promisesStartControllers,
					Promise.new(function(r)
						debug.setmemorycategory(controller.Name)
						local success, err = pcall(function()
							initFn(controller)
						end)
						if success then
							r()
						else
							failedControllers[controller.Name] = true
							-- Get the source path using debug.info
							local source = debug.info(initFn, "s")
							local controllerPath = source:match("^@?(.+)$") or controller.Name
							task.spawn(error,
								string.format(
									"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
										.. "❌ SuperbulletInit Error in Controller: %s\n"
										.. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
										.. "Controller Path: %s\n"
										.. "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
										.. "Error: %s\n"
										.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━",
									controller.Name,
									controllerPath,
									tostring(err)
								)
							)
							r()
						end
					end)
				)
			end
		end

		resolve(Promise.all(promisesStartControllers))
	end):andThen(function()
		-- Initialize Components (setup and init before SuperbulletStart):
		local controllersWithComponents = {}
		for _, controller in controllers do
			if controller.Instance and not failedControllers[controller.Name] then
				local ok, err = pcall(ComponentInitializer.Initialize, controller, controller.Instance)
				if ok then
					table.insert(controllersWithComponents, { controller = controller, instance = controller.Instance })
				else
					failedControllers[controller.Name] = true
					task.spawn(error, "[Superbullet] ComponentInitializer.Initialize failed for " .. controller.Name .. ": " .. tostring(err))
				end
			end
		end

		-- Start:
		for _, controller in controllers do
			local startFn = controller.SuperbulletStart or controller.KnitStart
			if type(startFn) == "function" and not failedControllers[controller.Name] then
				task.spawn(function()
					debug.setmemorycategory(controller.Name)
					local success, err = pcall(startFn, controller)
					if not success then
						task.spawn(error, "[Superbullet] SuperbulletStart error in " .. controller.Name .. ": " .. tostring(err))
					end
				end)
			end
		end

		-- Start Components (after all controllers have started):
		task.defer(function()
			for _, data in controllersWithComponents do
				local ok, err = pcall(ComponentInitializer.Start, data.controller, data.instance)
				if not ok then
					task.spawn(error, "[Superbullet] ComponentInitializer.Start failed for " .. data.controller.Name .. ": " .. tostring(err))
				end
			end
		end)

		startedComplete = true
		onStartedComplete:Fire()

		task.defer(function()
			onStartedComplete:Destroy()
		end)
	end)
end

--[=[
	@return Promise
	Returns a promise that is resolved once Superbullet has started. This is useful
	for any code that needs to tie into Superbullet controllers but is not the script
	that called `Start`.
	```lua
	Superbullet.OnStart():andThen(function()
		local MyController = Superbullet.GetController("MyController")
		MyController:DoSomething()
	end):catch(warn)
	```
]=]
function KnitClient.OnStart()
	if startedComplete then
		return Promise.resolve()
	else
		return Promise.fromEvent(onStartedComplete.Event)
	end
end

return KnitClient
