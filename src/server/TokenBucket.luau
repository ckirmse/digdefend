--!strict

-- Pure token-bucket rate limiter. Time is passed in by the caller so the math
-- stays testable without a running scheduler.
local TokenBucket = {}
TokenBucket.__index = TokenBucket

export type TokenBucket = typeof(setmetatable(
	{} :: {
		capacity: number,
		refillPerSec: number,
		tokens: number,
		lastRefillTime: number,
	},
	TokenBucket
))

function TokenBucket:refill(now: number)
	local elapsed = math.max(0, now - self.lastRefillTime)
	self.tokens = math.min(self.capacity, self.tokens + elapsed * self.refillPerSec)
	self.lastRefillTime = now
end

function TokenBucket:tryTake(cost: number, now: number): boolean
	self:refill(now)
	if self.tokens < cost then
		return false
	end
	self.tokens -= cost
	return true
end

function TokenBucket:getTokens(): number
	return self.tokens
end

function TokenBucket.new(capacity: number, refillPerSec: number, now: number): TokenBucket
	local self = setmetatable({}, TokenBucket) :: TokenBucket
	self.capacity = capacity
	self.refillPerSec = refillPerSec
	self.tokens = capacity
	self.lastRefillTime = now
	return self
end

return TokenBucket
