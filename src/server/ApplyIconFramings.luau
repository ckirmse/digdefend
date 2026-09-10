--!strict

-- Edit-mode dev utility, never required at runtime: applies ICON_FRAMING lines
-- copied from a play session's Output window onto the asset templates so the
-- framings persist in the place file. Run from the Studio command bar:
--   require(game.ServerScriptService.Server.ApplyIconFramings)([[
--   ICON_FRAMING {"assetPath":"Weapons.Pistol","cf":[...],"fov":30}
--   ...pasted lines...
--   ]])
local Attributes = require("@game/ReplicatedStorage/Shared/Attributes")
local BakedIconUtil = require("@game/ReplicatedStorage/Shared/BakedIconUtil")
local Constants = require("@game/ReplicatedStorage/Shared/Constants")
local IconFramingFormat = require("@game/ReplicatedStorage/Shared/IconFramingFormat")

return function(pastedText: string)
	if typeof(pastedText) ~= "string" or pastedText == "" then
		warn("ApplyIconFramings: paste the ICON_FRAMING lines from the Output window as one string argument")
		return
	end

	local entries, badLineCount = IconFramingFormat.parseAll(pastedText)
	if badLineCount > 0 then
		warn(`ApplyIconFramings: {badLineCount} malformed ICON_FRAMING line(s) skipped`)
	end
	if #entries == 0 then
		warn("ApplyIconFramings: no valid ICON_FRAMING lines found in the pasted text")
		return
	end

	local appliedCount = 0
	for _, entry in entries do
		local template = BakedIconUtil.findTemplate(entry.assetPath)
		if not template then
			warn(`ApplyIconFramings: no template at asset path "{entry.assetPath}" under {Constants.GAME_ASSETS_FOLDER}`)
			continue
		end
		template:SetAttribute(Attributes.ICON_FRAMING, IconFramingFormat.encodeAttribute(entry.framing))
		appliedCount += 1
		print(`ApplyIconFramings: applied framing for {entry.assetPath}`)
	end
	print(`ApplyIconFramings: {appliedCount}/{#entries} framing(s) applied`)
end
