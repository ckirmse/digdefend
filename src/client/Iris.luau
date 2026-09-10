--!strict

-- Thin wrapper around the Wally-installed Iris package. Iris is an untyped
-- immediate-mode GUI library, so it crosses this boundary as `any`. Init() is
-- deferred to ClientDevTools:init() so non-admin clients never run the Iris
-- Heartbeat cycle.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local packages = ReplicatedStorage:WaitForChild("Packages")
local Iris: any = (require :: any)(packages:WaitForChild("Iris"))

return Iris
