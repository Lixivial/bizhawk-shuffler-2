local plugin = {}
local HOTKEY_OPTIONS = {
	'Ctrl+Shift+End',
	'Ctrl+Shift+Delete',
	'Ctrl+Shift+D',
	'Alt+Shift+End',
	'Alt+Shift+Delete',
	'Alt+Shift+D',
	'Backslash',
	'RightCtrl',
}

plugin.name = "Skip to Next Game"
plugin.author = "Lixivial"
plugin.minversion = "2.6.2"
plugin.settings =
{
	{ name='hotkey', type='select', label='Hotkey to trigger skip', default="Alt+Shift+D", options=HOTKEY_OPTIONS }
}

plugin.description =
[[
	This simple plugin allows an assignable hotkey for skipping to the next game in the shuffler list and reset the timer.
]]

function plugin.on_frame(data, settings)
	input_break = input.get()
	if input_break[settings.hotkey] then
		log_message('skipping ' .. config.current_game)
		swap_game()
	end
end

return plugin