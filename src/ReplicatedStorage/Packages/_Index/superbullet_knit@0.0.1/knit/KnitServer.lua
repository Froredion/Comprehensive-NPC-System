--[=[
	@interface Middleware
	.Inbound ServerMiddleware?
	.Outbound ServerMiddleware?
	@within SuperbulletServer
]=]
type Middleware = {
	Inbound: ServerMiddleware?,
	Outbound: ServerMiddleware?,
}

--[=[
	@type ServerMiddlewareFn (player: Player, args: {any}) -> (shouldContinue: boolean, ...: any)
	@within SuperbulletServer

	For more info, see [ServerComm](https://sleitnick.github.io/RbxUtil/api/ServerComm/) documentation.
]=]
type ServerMiddlewareFn = (player: Player, args: { any }) -> (boolean, ...any)

--[=[
	@type ServerMiddleware {ServerMiddlewareFn}
	@within SuperbulletServer
	An array of server middleware functions.
]=]
type ServerMiddleware = { ServerMiddlewareFn }

--[=[
	@interface ServiceDef
	.Name string
	.Client table?
	.Middleware Middleware?
	.Instance Instance?
	.[any] any
	@within SuperbulletServer
	Used to define a service when creating it in `CreateService`.

	The middleware tables provided will be used instead of the Superbullet-level
	middleware (if any). This allows fine-tuning each service's middleware.
	These can also be left out or `nil` to not include middleware.

	If `Instance` is provided (typically `script`), Superbullet will automatically
	initialize components found in a `Components` folder within that instance.
]=]
type ServiceDef = {
	Name: string,
	Client: { [any]: any }?,
	Middleware: Middleware?,
	Instance: Instance?,
	[any]: any,
}

--[=[
	@interface Service
	.Name string
	.Client ServiceClient
	.KnitComm Comm
	.[any] any
	@within SuperbulletServer
]=]
type Service = {
	Name: string,
	Client: ServiceClient,
	KnitComm: any,
	[any]: any,
}

--[=[
	@interface ServiceClient
	.Server Service
	.[any] any
	@within SuperbulletServer
]=]
type ServiceClient = {
	Server: Service,
	[any]: any,
}

--[=[
	@interface KnitOptions
	.Middleware Middleware?
	@within SuperbulletServer

	- Middleware will apply to all services _except_ ones that define
	their own middleware.
]=]
type KnitOptions = {
	Middleware: Middleware?,
}

local defaultOptions: KnitOptions = {
	Middleware = nil,
}

local selectedOptions = nil

--[=[
	@class SuperbulletServer
	@server
	Superbullet server-side lets developers create services and expose methods and signals
	to the clients.

	```lua
	local Superbullet = require(somewhere.Superbullet)

	-- Load service modules within some folder:
	Superbullet.AddServices(somewhere.Services)

	-- Start Superbullet:
	Superbullet.Start():andThen(function()
		print("Superbullet started")
	end):catch(warn)
	```
]=]
local KnitServer = {}

--[=[
	@prop Util Folder
	@within SuperbulletServer
	@readonly
	References the Util folder. Should only be accessed when using Superbullet as
	a standalone module. If using Superbullet from Wally, modules should just be
	pulled in via Wally instead of relying on Superbullet's Util folder, as this
	folder only contains what is necessary for Superbullet to run in Wally mode.
]=]
KnitServer.Util = (script.Parent :: Instance).Parent

local SIGNAL_MARKER = newproxy(true)
getmetatable(SIGNAL_MARKER).__tostring = function()
	return "SIGNAL_MARKER"
end

local UNRELIABLE_SIGNAL_MARKER = newproxy(true)
getmetatable(UNRELIABLE_SIGNAL_MARKER).__tostring = function()
	return "UNRELIABLE_SIGNAL_MARKER"
end

local PROPERTY_MARKER = newproxy(true)
getmetatable(PROPERTY_MARKER).__tostring = function()
	return "PROPERTY_MARKER"
end

local knitRepServiceFolder = Instance.new("Folder")
knitRepServiceFolder.Name = "Services"

local Promise = require(KnitServer.Util.Promise)
local Comm = require(KnitServer.Util.Comm)
local ServerComm = Comm.ServerComm
local KnitErrorHelper = require(script.Parent.KnitErrorHelper)
local Components = require(script.Parent.Components)
local ClientExtension = Components.ClientExtension
local ComponentInitializer = Components.ComponentInitializer

local services: { [string]: Service } = {}
local started = false
local startedComplete = false
local clientExtensionLocked = false -- Separate flag for ClientExtension timing
local onStartedComplete = Instance.new("BindableEvent")

local function DoesServiceExist(serviceName: string): boolean
	local service: Service? = services[serviceName]

	return service ~= nil
end


--[=[
	Constructs a new service.

	:::caution
	Services must be created _before_ calling `Superbullet.Start()`.
	:::
	```lua
	-- Create a service
	local MyService = Superbullet.CreateService {
		Name = "MyService",
		Client = {},
	}

	-- Expose a ToAllCaps remote function to the clients
	function MyService.Client:ToAllCaps(player, msg)
		return msg:upper()
	end

	-- Superbullet will call SuperbulletStart after all services have been initialized
	function MyService:SuperbulletStart()
		print("MyService started")
	end

	-- Superbullet will call SuperbulletInit when Superbullet is first started
	function MyService:SuperbulletInit()
		print("MyService initialize")
	end
	```

	With automatic component initialization:
	```lua
	local MyService = Superbullet.CreateService {
		Name = "MyService",
		Instance = script,  -- Automatically initializes components
	}
	```
]=]
function KnitServer.CreateService(serviceDef: ServiceDef): Service
	assert(type(serviceDef) == "table", `Service must be a table; got {type(serviceDef)}`)
	assert(type(serviceDef.Name) == "string", `Service.Name must be a string; got {type(serviceDef.Name)}`)
	assert(#serviceDef.Name > 0, "Service.Name must be a non-empty string")
	assert(not DoesServiceExist(serviceDef.Name), `Service "{serviceDef.Name}" already exists`)
	assert(not started, `Services cannot be created after calling "Superbullet.Start()"`)

	local service = serviceDef
	service.KnitComm = ServerComm.new(knitRepServiceFolder, serviceDef.Name)

	if type(service.Client) ~= "table" then
		service.Client = { Server = service }
	else
		if service.Client.Server ~= service then
			service.Client.Server = service
		end
	end

	services[service.Name] = service

	return service
end

--[=[
	Requires all the modules that are children of the given parent. This is an easy
	way to quickly load all services that might be in a folder.
	```lua
	Superbullet.AddServices(somewhere.Services)
	```
]=]
function KnitServer.AddServices(parent: Instance): { Service }
	assert(not started, `Services cannot be added after calling "Superbullet.Start()"`)

	local addedServices = {}
	for _, v in parent:GetChildren() do
		if not v:IsA("ModuleScript") then
			continue
		end

		table.insert(addedServices, require(v))
	end

	return addedServices
end

--[=[
	Requires all the modules that are descendants of the given parent.
]=]
function KnitServer.AddServicesDeep(parent: Instance): { Service }
	assert(not started, `Services cannot be added after calling "Superbullet.Start()"`)

	local addedServices = {}
	for _, v in parent:GetDescendants() do
		if not v:IsA("ModuleScript") then
			continue
		end

		table.insert(addedServices, require(v))
	end

	return addedServices
end

--[=[
	Gets the service by name. Throws an error if the service is not found.
]=]
function KnitServer.GetService(serviceName: string): Service
	assert(started, KnitErrorHelper.GetStartErrorMessage(started, "GetService", services, false))
	assert(type(serviceName) == "string", `ServiceName must be a string; got {type(serviceName)}`)

	-- Warn if GetService is called during initialization and takes too long
	if not startedComplete then
		task.spawn(function()
			task.wait(5)
			if not startedComplete then
				warn(
					string.format(
						"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
							.. "⚠️  Superbullet Initialization Warning\n"
							.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
							.. "GetService('%s') called during initialization, and Superbullet has been\n"
							.. "initializing for more than 5 seconds.\n"
							.. "\n"
							.. "Possible causes:\n"
							.. "• Service '%s' does not exist\n"
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

	return assert(services[serviceName], `Could not find service "{serviceName}"`) :: Service
end

--[=[
	Gets a table of all services.
]=]
function KnitServer.GetServices(): { [string]: Service }
	assert(started, KnitErrorHelper.GetStartErrorMessage(started, "GetServices", services, false))

	return services
end

--[=[
	@return SIGNAL_MARKER
	Returns a marker that will transform the current key into
	a RemoteSignal once the service is created. Should only
	be called within the Client table of a service.

	See [RemoteSignal](https://sleitnick.github.io/RbxUtil/api/RemoteSignal)
	documentation for more info.
	```lua
	local MyService = Superbullet.CreateService {
		Name = "MyService",
		Client = {
			-- Create the signal marker, which will turn into a
			-- RemoteSignal when Superbullet.Start() is called:
			MySignal = Superbullet.CreateSignal(),
		},
	}

	function MyService:SuperbulletInit()
		-- Connect to the signal:
		self.Client.MySignal:Connect(function(player, ...) end)
	end
	```
]=]
function KnitServer.CreateSignal()
	return SIGNAL_MARKER
end

--[=[
	@return UNRELIABLE_SIGNAL_MARKER

	Returns a marker that will transform the current key into
	an unreliable RemoteSignal once the service is created. Should
	only be called within the Client table of a service.

	See [RemoteSignal](https://sleitnick.github.io/RbxUtil/api/RemoteSignal)
	documentation for more info.

	:::info Unreliable Events
	Internally, this uses UnreliableRemoteEvents, which allows for
	network communication that is unreliable and unordered. This is
	useful for events that are not crucial for gameplay, since the
	delivery of the events may occur out of order or not at all.

	See  the documentation for [UnreliableRemoteEvents](https://create.roblox.com/docs/reference/engine/classes/UnreliableRemoteEvent)
	for more info.
]=]
function KnitServer.CreateUnreliableSignal()
	return UNRELIABLE_SIGNAL_MARKER
end

--[=[
	@return PROPERTY_MARKER
	Returns a marker that will transform the current key into
	a RemoteProperty once the service is created. Should only
	be called within the Client table of a service. An initial
	value can be passed along as well.

	RemoteProperties are great for replicating data to all of
	the clients. Different data can also be set per client.

	See [RemoteProperty](https://sleitnick.github.io/RbxUtil/api/RemoteProperty)
	documentation for more info.

	```lua
	local MyService = Superbullet.CreateService {
		Name = "MyService",
		Client = {
			-- Create the property marker, which will turn into a
			-- RemoteProperty when Superbullet.Start() is called:
			MyProperty = Superbullet.CreateProperty("HelloWorld"),
		},
	}

	function MyService:SuperbulletInit()
		-- Change the value of the property:
		self.Client.MyProperty:Set("HelloWorldAgain")
	end
	```
]=]
function KnitServer.CreateProperty(initialValue: any)
	return { PROPERTY_MARKER, initialValue }
end

--[=[
	@function RegisterClientSignal
	@within SuperbulletServer

	Registers a new signal on the service's Client table from a submodule.
	Must be called BEFORE Superbullet.Start().

	Returns the RemoteSignal immediately so you can chain :Connect().

	```lua
	-- In a submodule's Init():
	Superbullet.RegisterClientSignal(QuestService, "OnQuestComplete"):Connect(function(player, questId)
		print(player, "completed quest", questId)
	end)
	```

	@param service Service -- The service to register on
	@param signalName string -- The name of the signal
	@param unreliable boolean? -- Use UnreliableRemoteEvent (default: false)
	@return RemoteSignal
]=]
function KnitServer.RegisterClientSignal(service: Service, signalName: string, unreliable: boolean?)
	return ClientExtension.RegisterClientSignal(service, signalName, unreliable, clientExtensionLocked)
end

--[=[
	@function RegisterClientMethod
	@within SuperbulletServer

	Registers a new method on the service's Client table from a submodule.
	Must be called BEFORE Superbullet.Start().

	Returns a wrapper with .OnServerInvoke property (Roblox-style).

	```lua
	-- In a submodule's Init():
	Superbullet.RegisterClientMethod(QuestService, "GetActiveQuests").OnServerInvoke = function(self, player)
		return QuestManager:GetPlayerQuests(player)
	end
	```

	@param service Service -- The service to register on
	@param methodName string -- The name of the method
	@return MethodWrapper
]=]
function KnitServer.RegisterClientMethod(service: Service, methodName: string)
	return ClientExtension.RegisterClientMethod(service, methodName, clientExtensionLocked)
end

--[=[
	@function RegisterClientProperty
	@within SuperbulletServer

	Registers a new property on the service's Client table from a submodule.
	Must be called BEFORE Superbullet.Start().

	Returns the RemoteProperty immediately.

	```lua
	-- In a submodule's Init():
	local prop = Superbullet.RegisterClientProperty(QuestService, "QuestConfig", { MaxActive = 5 })
	prop:Set({ MaxActive = 10 })
	```

	@param service Service -- The service to register on
	@param propertyName string -- The name of the property
	@param initialValue any -- The initial value
	@return RemoteProperty
]=]
function KnitServer.RegisterClientProperty(service: Service, propertyName: string, initialValue: any)
	return ClientExtension.RegisterClientProperty(service, propertyName, initialValue, clientExtensionLocked)
end

--[=[
	@return Promise
	Starts Superbullet. Should only be called once.

	Optionally, `KnitOptions` can be passed in order to set
	Superbullet's custom configurations.

	:::caution
	Be sure that all services have been created _before_
	calling `Start`. Services cannot be added later.
	:::

	```lua
	Superbullet.Start():andThen(function()
		print("Superbullet started!")
	end):catch(warn)
	```

	Example of Superbullet started with options:
	```lua
	Superbullet.Start({
		Middleware = {
			Inbound = {
				function(player, args)
					print("Player is giving following args to server:", args)
					return true
				end
			},
		},
	}):andThen(function()
		print("Superbullet started!")
	end):catch(warn)
	```
]=]
function KnitServer.Start(options: KnitOptions?)
	if started then
		return Promise.reject("Superbullet already started")
	end

	started = true

	table.freeze(services)

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

	local failedServices = {}

	return Promise.new(function(resolve)
		local knitMiddleware = if selectedOptions.Middleware ~= nil then selectedOptions.Middleware else {}

		-- Bind remotes:
		for _, service in services do
			local middleware = if service.Middleware ~= nil then service.Middleware else {}
			local inbound = if middleware.Inbound ~= nil then middleware.Inbound else knitMiddleware.Inbound
			local outbound = if middleware.Outbound ~= nil then middleware.Outbound else knitMiddleware.Outbound

			service.Middleware = nil

			for k, v in service.Client do
				if type(v) == "function" then
					service.KnitComm:WrapMethod(service.Client, k, inbound, outbound)
				elseif v == SIGNAL_MARKER then
					service.Client[k] = service.KnitComm:CreateSignal(k, false, inbound, outbound)
				elseif v == UNRELIABLE_SIGNAL_MARKER then
					service.Client[k] = service.KnitComm:CreateSignal(k, true, inbound, outbound)
				elseif type(v) == "table" and v[1] == PROPERTY_MARKER then
					service.Client[k] = service.KnitComm:CreateProperty(k, v[2], inbound, outbound)
				elseif type(v) == "table" then
					-- Skip already-created RemoteSignals/RemoteProperties from RegisterClient*
					-- These have internal fields like _re (RemoteEvent) or similar
					continue
				end
			end
		end

		-- Init:
		local promisesInitServices = {}
		for _, service in services do
			local initFn = service.SuperbulletInit or service.KnitInit
			if type(initFn) == "function" then
				table.insert(
					promisesInitServices,
					Promise.new(function(r)
						debug.setmemorycategory(service.Name)
						local success, err = pcall(function()
							initFn(service)
						end)
						if success then
							r()
						else
							failedServices[service.Name] = true
							-- Get the source path using debug.info
							local source = debug.info(initFn, "s")
							local servicePath = source:match("^@?(.+)$") or service.Name
							task.spawn(error,
								string.format(
									"\n━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
										.. "❌ SuperbulletInit Error in Service: %s\n"
										.. "━━━━━━━━━━━━━━━━━━━━━━━━━\n"
										.. "Service Path: %s\n"
										.. "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
										.. "Error: %s\n"
										.. "━━━━━━━━━━━━━━━━━━━━━━━━━━━",
									service.Name,
									servicePath,
									tostring(err)
								)
							)
							r()
						end
					end)
				)
			end
		end

		resolve(Promise.all(promisesInitServices))
	end):andThen(function()
		-- Initialize Components (setup and init before SuperbulletStart):
		local servicesWithComponents = {}
		for _, service in services do
			if service.Instance and not failedServices[service.Name] then
				local ok, err = pcall(ComponentInitializer.Initialize, service, service.Instance)
				if ok then
					table.insert(servicesWithComponents, { service = service, instance = service.Instance })
				else
					failedServices[service.Name] = true
					task.spawn(error, "[Superbullet] ComponentInitializer.Initialize failed for " .. service.Name .. ": " .. tostring(err))
				end
			end
		end

		-- Lock ClientExtension before SuperbulletStart phase begins
		-- After this point, no new signals/methods/properties can be registered
		clientExtensionLocked = true

		-- Start:
		for _, service in services do
			local startFn = service.SuperbulletStart or service.KnitStart
			if type(startFn) == "function" and not failedServices[service.Name] then
				task.spawn(function()
					debug.setmemorycategory(service.Name)
					local success, err = pcall(startFn, service)
					if not success then
						task.spawn(error, "[Superbullet] SuperbulletStart error in " .. service.Name .. ": " .. tostring(err))
					end
				end)
			end
		end

		-- Start Components (after all services have started):
		task.defer(function()
			for _, data in servicesWithComponents do
				local ok, err = pcall(ComponentInitializer.Start, data.service, data.instance)
				if not ok then
					task.spawn(error, "[Superbullet] ComponentInitializer.Start failed for " .. data.service.Name .. ": " .. tostring(err))
				end
			end
		end)

		-- Expose service remotes to everyone FIRST (before signaling ready)
		knitRepServiceFolder.Parent = script.Parent

		-- Set ready attribute so clients know all remotes are registered
		-- This happens AFTER component.Init() has registered all dynamic items
		knitRepServiceFolder:SetAttribute("Ready", true)

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
	for any code that needs to tie into Superbullet services but is not the script
	that called `Start`.
	```lua
	Superbullet.OnStart():andThen(function()
		local MyService = Superbullet.Services.MyService
		MyService:DoSomething()
	end):catch(warn)
	```
]=]
function KnitServer.OnStart()
	if startedComplete then
		return Promise.resolve()
	else
		return Promise.fromEvent(onStartedComplete.Event)
	end
end

return KnitServer
