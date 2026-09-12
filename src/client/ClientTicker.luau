--!strict

-- Shared low-frequency ticker (Lucky Squares pattern): one Heartbeat
-- connection serving every manager that needs periodic work, instead of a
-- while-true loop or a per-frame check per manager. Connected only while
-- something is subscribed.
local RunService = game:GetService("RunService")

local ClientTicker = {}

export type Disconnect = () -> ()

type Subscription = {
	intervalSec: number,
	elapsedSec: number,
	callback: () -> (),
}

local subscriptions: { [Subscription]: boolean } = {}
local connection: RBXScriptConnection? = nil

local function disconnectIfIdle()
	if next(subscriptions) == nil and connection then
		connection:Disconnect()
		connection = nil
	end
end

local function ensureConnected()
	if connection then
		return
	end
	connection = RunService.Heartbeat:Connect(
		function(deltaSec: number)
			for subscription in subscriptions do
				subscription.elapsedSec += deltaSec
				if subscription.elapsedSec < subscription.intervalSec then
					continue
				end
				subscription.elapsedSec = 0
				subscription.callback()
			end
		end
	)
end

-- runs callback every intervalSec until the returned disconnect is called
function ClientTicker.every(intervalSec: number, callback: () -> ()): Disconnect
	local subscription: Subscription = {
		intervalSec = intervalSec,
		elapsedSec = 0,
		callback = callback,
	}
	subscriptions[subscription] = true
	ensureConnected()
	return function()
		subscriptions[subscription] = nil
		disconnectIfIdle()
	end
end

return ClientTicker
