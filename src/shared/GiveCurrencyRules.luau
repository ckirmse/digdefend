--!strict

-- Pure rules for Give Currency (M32): one player sends Gold Bars and Iron
-- Bars to another. The menu steps and clamps its amounts with these and
-- the server checks the request with the same ones, so the two never
-- disagree about what may be sent.
local GiveCurrencyRules = {}

GiveCurrencyRules.REJECT_NOTHING = "nothing"
GiveCurrencyRules.REJECT_BALANCE = "balance"

-- an amount after a press of plus or minus, held between nothing and
-- everything the sender has
function GiveCurrencyRules.stepAmount(amount: number, delta: number, balance: number): number
	return math.clamp(math.floor(amount + delta), 0, math.max(0, math.floor(balance)))
end

-- what a typed amount becomes: whole, never negative, never more than the
-- sender has; anything that is not a number is 0
function GiveCurrencyRules.parseAmount(text: string, balance: number): number
	local value = tonumber(text)
	if not value or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, math.max(0, math.floor(balance)))
end

-- nil when the gift may be sent, else why not
function GiveCurrencyRules.getRejection(goldBars: number, ironBars: number, goldBalance: number, ironBalance: number): string?
	if goldBars <= 0 and ironBars <= 0 then
		return GiveCurrencyRules.REJECT_NOTHING
	end
	if goldBars > goldBalance or ironBars > ironBalance then
		return GiveCurrencyRules.REJECT_BALANCE
	end
	return nil
end

-- "20 Gold Bars", "1 Iron Bar", or "20 Gold Bars and 10 Iron Bars"
function GiveCurrencyRules.describeAmounts(goldBars: number, ironBars: number, goldName: string, ironName: string): string
	local parts = {}
	if goldBars > 0 then
		table.insert(parts, `{goldBars} {goldName}{if goldBars == 1 then "" else "s"}`)
	end
	if ironBars > 0 then
		table.insert(parts, `{ironBars} {ironName}{if ironBars == 1 then "" else "s"}`)
	end
	return table.concat(parts, " and ")
end

return GiveCurrencyRules
