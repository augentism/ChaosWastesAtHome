local UIWidget = require("scripts/managers/ui/ui_widget")

-- The screen-filling rect every one of this mod's full-screen views draws
-- behind its content.
--
-- The alpha is not a constant, because what sits behind these views is not the
-- same in both places they open.
--
-- In the Mourningstar or a mission the view declares game_world_blur, and
-- StateGameplay honours it: the world behind is blurred, and letting some of it
-- through is what makes these screens read as an overlay on the game rather
-- than a slab dropped over it. That is the look the launcher was built with and
-- it is worth keeping.
--
-- Character select has none of that. There is no game world there at all --
-- Managers.world holds only ui_world, ui_overlay and music_world -- so
-- disable_game_world and game_world_blur have nothing to act on. What is
-- actually on screen is MainMenuBackgroundView's ship and character, rendered
-- out of a world_spawner that view owns itself and that the view handler never
-- switches off: a view reporting _pass_draw false stops main_menu_view drawing
-- its 2D character list, but nothing stops that 3D background. It is lit and
-- close to camera, so any alpha short of opaque leaves a face legible through
-- the text.
--
-- Read at definition time rather than patched onto the widget afterwards, which
-- is correct here because each view io_dofiles its definitions from init -- so
-- the file re-executes on every open and cannot cache the answer from whichever
-- screen the view happened to be opened on first.

local backdrop = {}

backdrop.OPAQUE = 255

-- `in_world` is the alpha to use where there is a blurred game world behind.
backdrop.alpha = function (in_world)
	local ui_manager = Managers.ui

	if ui_manager and ui_manager:view_active("main_menu_view") then
		return backdrop.OPAQUE
	end

	return in_world
end

backdrop.definition = function (in_world)
	return UIWidget.create_definition({
		{ pass_type = "rect", style = { color = { backdrop.alpha(in_world), 0, 0, 0 } } },
	}, "screen")
end

return backdrop
