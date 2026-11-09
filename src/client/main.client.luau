--!strict

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local Enums = require("@game/ReplicatedStorage/Shared/Enums")
local ClientDataManager = require(script.Parent.ClientDataManager)
local ClientDevTools = require(script.Parent.ClientDevTools)
local ClientHelicopterManager = require(script.Parent.ClientHelicopterManager)
local ClientLoadingScreenManager = require(script.Parent.ClientLoadingScreenManager)
local ClientNetManager = require(script.Parent.ClientNetManager)
local ClientOverlayManager = require(script.Parent.ClientOverlayManager)
local ClientPlayerFeedbackManager = require(script.Parent.ClientPlayerFeedbackManager)
local ClientSoundManager = require(script.Parent.ClientSoundManager)

-- progress stages of the arrival loading screen; the fractions only need to
-- read as steady forward motion
local PROGRESS_DATA = 0.15
local PROGRESS_WORLD = 0.45
local PROGRESS_ASSETS = 0.7
local PROGRESS_SYSTEMS = 0.9

ClientLoadingScreenManager:show()
ClientLoadingScreenManager:setProgress(PROGRESS_DATA, "Loading your save...")

-- CurrentPlayer appearing is the server's "you are fully set up" signal; no
-- client system starts before it
ClientDataManager:awaitReady()

ClientLoadingScreenManager:setProgress(PROGRESS_WORLD, "Loading the world...")
-- managers read Studio-authored assets out of ReplicatedStorage at init; on a
-- slow connection those can still be replicating even though CurrentPlayer
-- has arrived
if not game:IsLoaded() then
	game.Loaded:Wait()
end

ClientLoadingScreenManager:setProgress(PROGRESS_ASSETS, "Loading assets...")
local gameAssets = ReplicatedStorage:FindFirstChild(Constants.GAME_ASSETS_FOLDER)
if gameAssets then
	ContentProvider:PreloadAsync({ gameAssets })
end

ClientLoadingScreenManager:setProgress(PROGRESS_SYSTEMS, "Starting up...")
ClientOverlayManager:init()
ClientOverlayManager:setDeferOverlays(true)
ClientSoundManager:init()
ClientNetManager:init()
ClientPlayerFeedbackManager:init()
ClientHelicopterManager:init()

if ClientDataManager:getIsAdmin() then
	ClientDevTools:init()
end

ClientLoadingScreenManager:hide()
ClientOverlayManager:setDeferOverlays(false)

print("Dig Defend client started (" .. tostring(Enums.getName(Enums.PlaceKind, Constants.getPlaceKind())) .. ")")
