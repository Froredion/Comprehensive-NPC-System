--[[
	ClientExtension.lua

	Handles dynamic registration of signals, methods, and properties
	on service Client tables from submodules.

	Part of SuperbulletFrameworkV1-Knit (2025)
]]

--[=[
	@class ClientExtension
	@private

	Internal module for dynamic Client table extension.
	Functions are exposed through KnitServer.
]=]

export type Service = {
	Name: string,
	Client: { [any]: any },
	KnitComm: any,
	[any]: any,
}

local ClientExtension = {}

-- Track registered items to prevent duplicates and enable validation
local registeredItems: { [Service]: { [string]: string } } = {}

--// MethodWrapper: Mimics RemoteFunction's .OnServerInvoke pattern
local MethodWrapper = {}
MethodWrapper.__index = MethodWrapper

function MethodWrapper.new(service: Service, methodName: string)
	local self = setmetatable({}, MethodWrapper)
	self._service = service
	self._methodName = methodName
	self._assigned = false
	return self
end

function MethodWrapper:__newindex(key: string, value: any)
	if key == "OnServerInvoke" then
		assert(not self._assigned, `OnServerInvoke for "{self._methodName}" has already been assigned`)
		assert(type(value) == "function", "OnServerInvoke must be a function")

		-- Set the function on Client table
		self._service.Client[self._methodName] = value
		
		-- CRITICAL: Wrap the method to create the actual RemoteFunction
		-- This is what makes the method callable from clients
		self._service.KnitComm:WrapMethod(self._service.Client, self._methodName)
		
		rawset(self, "_assigned", true)
		rawset(self, "_onServerInvoke", value)
	else
		rawset(self, key, value)
	end
end

--// Helper: Validate service and registration state
local function validateRegistration(
	service: Service,
	itemName: string,
	itemType: string,
	locked: boolean
)
	assert(not locked, `Cannot register client {itemType} after component Init phase (before KnitStart)`)
	assert(type(itemName) == "string" and #itemName > 0, `{itemType} name must be a non-empty string`)
	assert(
		type(service) == "table" and service.Name and service.Client,
		"First argument must be a valid Service"
	)
	assert(
		service.KnitComm ~= nil,
		`Service "{service.Name}" was not created with Superbullet.CreateService()`
	)
	assert(
		service.Client[itemName] == nil,
		`{itemType} "{itemName}" already exists on {service.Name}.Client`
	)

	-- Track for debugging
	if not registeredItems[service] then
		registeredItems[service] = {}
	end
	registeredItems[service][itemName] = itemType
end

--[=[
	Registers a new signal on the service's Client table.
	Must be called BEFORE Knit.Start().

	Returns the RemoteSignal immediately so you can chain :Connect().

	```lua
	Knit.RegisterClientSignal(MyService, "OnItemCollected"):Connect(function(player, itemId)
		print(player, "collected", itemId)
	end)
	```

	@param service Service -- The service to register on
	@param signalName string -- The name of the signal
	@param unreliable boolean? -- Use UnreliableRemoteEvent (default: false)
	@param locked boolean -- Internal: whether ClientExtension registration is locked
	@return RemoteSignal
]=]
function ClientExtension.RegisterClientSignal(
	service: Service,
	signalName: string,
	unreliable: boolean?,
	locked: boolean
)
	validateRegistration(service, signalName, "Signal", locked)

	local signal = service.KnitComm:CreateSignal(signalName, unreliable or false)
	service.Client[signalName] = signal

	return signal
end

--[=[
	Registers a new method on the service's Client table.
	Must be called BEFORE Knit.Start().

	Returns a wrapper with .OnServerInvoke property (Roblox-style).

	```lua
	Knit.RegisterClientMethod(MyService, "GetInventory").OnServerInvoke = function(self, player)
		return InventoryManager:GetPlayerInventory(player)
	end
	```

	@param service Service -- The service to register on
	@param methodName string -- The name of the method
	@param locked boolean -- Internal: whether ClientExtension registration is locked
	@return MethodWrapper
]=]
function ClientExtension.RegisterClientMethod(
	service: Service,
	methodName: string,
	locked: boolean
)
	validateRegistration(service, methodName, "Method", locked)

	return MethodWrapper.new(service, methodName)
end

--[=[
	Registers a new property on the service's Client table.
	Must be called BEFORE Knit.Start().

	Returns the RemoteProperty immediately so you can use :Set() / :Get().

	```lua
	local configProp = Knit.RegisterClientProperty(MyService, "GameConfig", {
		MaxPlayers = 10,
		RoundTime = 300,
	})

	-- Later:
	configProp:Set({ MaxPlayers = 20, RoundTime = 600 })
	```

	@param service Service -- The service to register on
	@param propertyName string -- The name of the property
	@param initialValue any -- The initial value
	@param locked boolean -- Internal: whether ClientExtension registration is locked
	@return RemoteProperty
]=]
function ClientExtension.RegisterClientProperty(
	service: Service,
	propertyName: string,
	initialValue: any,
	locked: boolean
)
	validateRegistration(service, propertyName, "Property", locked)

	local property = service.KnitComm:CreateProperty(propertyName, initialValue)
	service.Client[propertyName] = property

	return property
end

--[=[
	Returns all registered items for a service (for debugging).
	@private
]=]
function ClientExtension.GetRegisteredItems(service: Service): { [string]: string }?
	return registeredItems[service]
end

return ClientExtension
