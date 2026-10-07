--!strict

-- Which way this client is aiming (added 2026-10-07 with the dev panel's
-- third-person toggle). The gameplay place locks the camera to first person,
-- where the aim is the camera's own look through the centre reticle. When the
-- camera sits back from the character (the Classic camera the toggle sets,
-- or any zoom past arm's length), the aim is instead the ray from the camera
-- through the pointer: the mouse, or the finger that tapped. The pick axe and
-- the weapon ask here so both read the view the same way.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ClientCameraView = {}

-- Roblox's first-person camera sits half a stud from the focus; anything
-- past this is a view from behind the character
local FIRST_PERSON_MAX_ZOOM_STUDS = 1.5

function ClientCameraView:isThirdPerson(): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.Focus.Position - camera.CFrame.Position).Magnitude > FIRST_PERSON_MAX_ZOOM_STUDS
end

-- the character's root position, which is what the server measures reach from
function ClientCameraView:getRootPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then
		return root.Position
	end
	return nil
end

-- the aim ray: origin and unit direction. In first person it is the camera's
-- look; in third person it passes through `pointerPosition` (a touch, in
-- screen pixels) or, without one, the mouse
function ClientCameraView:getPointerRay(pointerPosition: Vector2?): (Vector3, Vector3)
	local camera = workspace.CurrentCamera
	if not camera then
		return Vector3.zero, Vector3.zAxis
	end
	if not self:isThirdPerson() then
		return camera.CFrame.Position, camera.CFrame.LookVector
	end
	local position = pointerPosition or UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(position.X, position.Y)
	return ray.Origin, ray.Direction.Unit
end

return ClientCameraView
