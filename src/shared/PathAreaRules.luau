--!strict

-- Where a monster may walk beside the camp (GDD "Defensive Zones", decided
-- 2026-09-29): a Wave Area may be wider than the Defensive Zone that sits
-- inside it, and monsters routed around walls built to the zone's edge
-- through the strip outside it, where nothing can be built. So a Wave Area
-- cell that lies beside a Defensive Zone is closed: within the zone's span
-- along the approach (the axis on which the zone is offset from the camp)
-- but outside its span across it. Cells beyond the zone, further from the
-- camp, stay open, which is where the spawns are. Pure, unit tested; used
-- by MonsterPathManager when it builds the grid.
local PathAreaRules = {}

-- a zone's flat footprint: its centre and half sizes in world axes (zones
-- are authored axis-aligned)
export type ZoneBox = {
	centerX: number,
	centerZ: number,
	halfX: number,
	halfZ: number,
}

-- which world axis the approach runs along for this zone: the one on which
-- the zone's centre is furthest from the camp's
function PathAreaRules.approachIsX(zone: ZoneBox, campCenterX: number, campCenterZ: number): boolean
	return math.abs(zone.centerX - campCenterX) >= math.abs(zone.centerZ - campCenterZ)
end

-- true when the point sits beside this zone: level with it along the
-- approach, outside it across
function PathAreaRules.isBesideZone(zone: ZoneBox, campCenterX: number, campCenterZ: number, x: number, z: number): boolean
	local isInsideX = math.abs(x - zone.centerX) <= zone.halfX
	local isInsideZ = math.abs(z - zone.centerZ) <= zone.halfZ
	if isInsideX and isInsideZ then
		return false
	end
	if PathAreaRules.approachIsX(zone, campCenterX, campCenterZ) then
		return isInsideX and not isInsideZ
	end
	return isInsideZ and not isInsideX
end

-- true when the point sits beside any of the zones
function PathAreaRules.isBesideAnyZone(zones: { ZoneBox }, campCenterX: number, campCenterZ: number, x: number, z: number): boolean
	for _, zone in zones do
		if PathAreaRules.isBesideZone(zone, campCenterX, campCenterZ, x, z) then
			return true
		end
	end
	return false
end

return PathAreaRules
