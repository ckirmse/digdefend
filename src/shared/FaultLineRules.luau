--!strict

-- Pure rules for the Fault Line Drill, the Prospector's post (GDD
-- "Classes", 2026-10-22): the post fires a drill wherever the gunner
-- aims, and where it lands a crack races on along the floor in the
-- shot's direction for a fixed length, rock spikes erupting along it;
-- everything standing on the line is hurt and knocked down. The crack
-- follows the ground (the path grid's heights, passed in as a function so
-- this stays testable), never the air, so a flyer is never on it. The
-- server (PostManager) decides the hits with these; every client draws
-- the same spikes from the points the server sends, so the two agree.
local FaultLineRules = {}

export type GroundHeightAt = (x: number, z: number) -> number?

-- something on the ground with a footprint: DamageableManager's Target
export type Body = {
	id: string,
	position: Vector3,
	size: Vector3,
	isAirborne: boolean,
}

-- the flat unit direction of an aim, or nil for one pointing straight up
-- or down
function FaultLineRules.flatDirection(unitDirection: Vector3): Vector3?
	local flat = Vector3.new(unitDirection.X, 0, unitDirection.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

-- the crack's points from the origin out to lengthStuds, one every
-- spacingStuds and one at the end, each snapped to the ground under it;
-- where the ground is unknown (off the grid) the last known height holds
function FaultLineRules.samplePoints(origin: Vector3, flatDirection: Vector3, lengthStuds: number, spacingStuds: number, groundHeightAt: GroundHeightAt): { Vector3 }
	local points = {}
	local spacing = math.max(spacingStuds, 0.5)
	local height = origin.Y
	local distance = 0
	while true do
		local flat = origin + flatDirection * distance
		local ground = groundHeightAt(flat.X, flat.Z)
		if ground then
			height = ground
		end
		table.insert(points, Vector3.new(flat.X, height, flat.Z))
		if distance >= lengthStuds then
			break
		end
		distance = math.min(distance + spacing, lengthStuds)
	end
	return points
end

-- every body standing on the crack: on the ground (its feet within
-- groundToleranceStuds of the ground under it), within the crack's
-- length along the line and half its width plus the body's own half
-- width across it. A flyer is never hit
function FaultLineRules.hitsAlong(origin: Vector3, flatDirection: Vector3, lengthStuds: number, widthStuds: number, bodies: { Body }, groundHeightAt: GroundHeightAt, groundToleranceStuds: number): { string }
	local hitIds = {}
	local across = Vector3.new(-flatDirection.Z, 0, flatDirection.X)
	local halfWidth = widthStuds / 2
	for _, body in bodies do
		if body.isAirborne then
			continue
		end
		local halfFootprint = math.max(body.size.X, body.size.Z) / 2
		local offset = body.position - origin
		local along = offset:Dot(flatDirection)
		if along < -halfFootprint or along > lengthStuds + halfFootprint then
			continue
		end
		if math.abs(offset:Dot(across)) > halfWidth + halfFootprint then
			continue
		end
		local ground = groundHeightAt(body.position.X, body.position.Z)
		local feet = body.position.Y - body.size.Y / 2
		if ground and math.abs(feet - ground) > groundToleranceStuds then
			continue
		end
		table.insert(hitIds, body.id)
	end
	return hitIds
end

return FaultLineRules
