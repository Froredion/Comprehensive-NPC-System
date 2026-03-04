--[[ [AI NOTE] TEMPLATE — DO NOT COPY THIS COMMENT BLOCK OR ANY [AI NOTE] INLINE COMMENTS INTO GENERATED CODE.
	Strip every [AI NOTE] block comment and every [AI NOTE] inline comment before outputting.

	Client Template Component (Others/Template.lua)
	General-purpose component for miscellaneous client-side logic.

	MODULE PATTERN (DOT SYNTAX BY DEFAULT):
	- This file returns a plain module table (`local module = {}`).
	- All module-level functions use DOT syntax: `module.FunctionName()`, NOT colon syntax.
	- Do NOT use `self` in module-level functions.

	OOP IS ALLOWED (when appropriate):
	- If the logic calls for objects with their own state (e.g., an enemy, a UI widget,
	  a session tracker), you CAN and SHOULD introduce OOP in this file.
	- Use a `.new()` constructor on the module table that returns a metatable object:
	      local MyObject = {}
	      MyObject.__index = MyObject
	      function MyObject.new(args)
	          local self = setmetatable({}, MyObject)
	          -- set up instance fields
	          return self
	      end
	      function MyObject:SomeMethod()  -- colon syntax + self is CORRECT here
	      end
	- Then expose it from the module: `module.MyObject = MyObject` or return it directly.
	- KEY RULE: colon syntax (`:`) and `self` are ONLY for methods on OOP objects.
	  The module table itself (`module.X`) always uses dot syntax.

	COMPONENT LIFECYCLE (auto-called by the framework):
	- `module.Init()` runs first (during SuperbulletInit). Use for setup/wiring.
	- `module.Start()` runs after (during SuperbulletStart, spawned in a new thread). Use for runtime logic.
	- Do NOT call Init() or Start() manually.

	SECTION HEADERS:
	- `---- Utilities`       -> require() modules directly, e.g., `local Utils = require(utilsFolder.Utils)`
	- `---- Superbullet Services`   -> declare variables here, fetch in Init() via `Superbullet.GetService("ServiceName")`
	- `---- Superbullet Controllers`-> declare variables here, fetch in Init() via `Superbullet.GetController("ControllerName")`
	- `---- Components`      -> sibling components, fetch in Init() via parent controller,
	                            e.g., `local Accessor = TemplateController.Components["Accessor"]`
	- `---- Datas`           -> local data/state variables, declared directly
	- `---- Assets`          -> references to game assets/instances, declared directly
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local MarketplaceService = game:GetService("MarketplaceService")
local Superbullet = require(ReplicatedStorage.Packages.Superbullet)
local Signal = require(ReplicatedStorage.Packages.Signal)
local module = {}

---- Superbullet Services -- [AI NOTE] Declare variables here, assign in Init() via Superbullet.GetService()

---- Superbullet Controllers -- [AI NOTE] Declare variables here, assign in Init() via Superbullet.GetController()

---- Utilities
local utilsFolder = ReplicatedStorage.SharedSource.Utilities

---- Components -- [AI NOTE] Declare variables here, assign in Init() via parent controller's .Components["Name"]
--- main parent components
local mainParentFolder = script.Parent.Parent

local plr = game.Players.LocalPlayer
local playerGui = plr.PlayerGui

--- Datas

function module.Start() -- [AI NOTE] Auto-called during SuperbulletStart (new thread). Runtime logic, event connections, loops.

end

function module.Init() -- [AI NOTE] Auto-called during SuperbulletInit. Fetch Superbullet services/controllers/components and set up references here. Runs before Start().

end

return module
