local plugin = {}

-- make this a data table
local ENCOUNTER_ADDRESS = 0x00e0
local BACKGROUND_CHR_ROM_ADDRESS = 0x6002 -- 00, Title Screen, 01 rest of the game (including continue menu)
local SPRITES_CHR_ROM_ADDRESS = 0x6003 -- 03, in battle, 02 rest of the game (including continue menu)
local MAP_ID_ADDRESS = 0x0045 -- 00 means map has not loaded
local PLAYER_LEVEL_ADDRESS = 0x00C7
local PLAYER_HP_ADDRESS = 0x00C5
local DIALOG_TEXT_POINTER = 0x009F -- this is a pointer to the current line of dialog text, useful for game logic-driven events that have no discernible state to key off
local DIALOG_CHARACTER_POINTER = 0x0008 -- pointer to the current character being fed to the PPU
local EXCELLENT_MOVE_TERMINATOR = 0x004c -- !
local EXCELLENT_MOVE_WORD_POINTER = 0x0033 -- move!
local FAILED_WORD_POINTER = 0x0012

local player_level = 1
local current_hp = 1
local swap_tracking_table = {}

local DIALOG_WORD_TABLE = {
	{ value=0x002D, name='Excellent' },
	{ value=0x000B, name='Failed' }
}

local ENCOUNTER_TABLE = {
	{ value=0xFFFF, name=' ' },
	{ value=0x0000, name='Slime' },
	{ value=0x0001, name='Red Slime' },
	{ value=0x0002, name='Drakee' },
	{ value=0x0003, name='Ghost' },
	{ value=0x0004, name='Magician' },
	{ value=0x0005, name='Magidrakee' },
	{ value=0x0006, name='Scorpion' },
	{ value=0x0007, name='Druin' },
	{ value=0x0008, name='Poltergeist' },
	{ value=0x0009, name='Droll' },
	{ value=0x000a, name='Drakeema' },
	{ value=0x000b, name='Skeleton' },
	{ value=0x000c, name='Warlock' },
	{ value=0x000d, name='Metal Scorpion' },
	{ value=0x000e, name='Wolf' },
	{ value=0x000f, name='Wraith' },
	{ value=0x0010, name='Metal Slime' },
	{ value=0x0011, name='Specter' },
	{ value=0x0012, name='Wolflord' },
	{ value=0x0013, name='Druinlord' },
	{ value=0x0014, name='Drollmagi' },
	{ value=0x0015, name='Wyvern' },
	{ value=0x0016, name='Rogue Scorpion' },
	{ value=0x0017, name='Wraith Knight' },
	{ value=0x0018, name='Golem' },
	{ value=0x0019, name='Goldman' },
	{ value=0x001a, name='Knight' },
	{ value=0x001b, name='Magiwyvern' },
	{ value=0x001c, name='Demon Knight' },
	{ value=0x001d, name='Werewolf' },
	{ value=0x001e, name='Green Dragon' },
	{ value=0x001f, name='Starwyvern' },
	{ value=0x0020, name='Wizard' },
	{ value=0x0021, name='Axe Knight' },
	{ value=0x0022, name='Blue Dragon' },
	{ value=0x0023, name='Stoneman' },
	{ value=0x0024, name='Armored Knight' },
	{ value=0x0025, name='Red Dragon' },
	{ value=0x0026, name='Dragonlord (1st form)' },
	{ value=0x0027, name='Dragonlord (2nd form)' }
}

function build_settings()
	return
	{
		{ name='enable_encounter_swap', type='boolean', label='Enable shuffling on enemy encounters' },
		{ name='encounter_type', type='select', label='', default=0xFFFF, options=get_encounter_names() },
		{ name='enable_level_up_swap', type='boolean', label='Shuffle on level up' },
		{ name='enable_critical_hit_swap', type='boolean', label='Shuffle on critical hit' },
		{ name='enable_death_swap', type='boolean', label='Shuffle on death' }
	}
end

function get_encounter_names()
	local names = {}

	for k, v in ipairs(ENCOUNTER_TABLE) do
		names[k] = v.name
	end

	return names
end

plugin.name = "Dragon Quest 1 Game State Shuffler"
plugin.author = "Lixivial"
plugin.minversion = "2.6.2"
plugin.settings = build_settings()

plugin.description =
[[
	Adds auto-shuffle behavior on various configurable in-game events.

	Events include:

	  - Enemy encounter
	  - Level up
	  - On critical hit
	  - Death
]]

function plugin.on_game_load(data, settings)
	log_message('romname, romhash loaded ' .. gameinfo.getromname() .. ', ' .. gameinfo.getromhash())

	swap_tracking_table[gameinfo.getromhash()] = swap_tracking_table[gameinfo.getromhash()] or {}

	on_title_screen = memory.read_u8(BACKGROUND_CHR_ROM_ADDRESS) == 00
	player_level = mainmemory.read_u8(PLAYER_LEVEL_ADDRESS)
	current_hp = mainmemory.read_u8(PLAYER_HP_ADDRESS)

	log_message('on_title_screen ' .. tostring(memory.read_u8(BACKGROUND_CHR_ROM_ADDRESS) == 00))

	if on_title_screen == true or player_level == 255 then player_level = 1 end

	log_message('game load player level ' .. player_level)
	log_message('game load current hp ' .. current_hp)
	log_message('game load swap_tracking_table ' .. serializeTable(swap_tracking_table[gameinfo.getromhash()]))
end

function plugin.on_frame(data, settings)
	will_swap = false

	if settings.enable_critical_hit_swap then
		will_swap = check_critical_hit_swap_rules()

		swap_tracking_table[gameinfo.getromhash()]["enable_critical_hit_swap"] = nil

		-- TODO: Adjust will_swap data type to track what is causing the swap and clean up this logic to avoid nested if's
		if will_swap then swap_tracking_table[gameinfo.getromhash()]["enable_critical_hit_swap"] = true end
	end

	if settings.enable_encounter_swap and settings.encounter_type ~= nil and not will_swap then
		will_swap = check_encounter_swap_rules(settings.encounter_type)
	end

	if settings.enable_level_up_swap and not will_swap then
		will_swap = check_level_up_swap_rules()
	end

	if settings.enable_death_swap and not will_swap then
		will_swap = check_death_swap_rules()
	end

	if will_swap then
		swap_game()
		return
	end
end

function get_encounter_by_name(name)
	for k, v in ipairs(ENCOUNTER_TABLE) do
		if v.name == name then return ENCOUNTER_TABLE[k] end
	end
end

function get_encounter_by_value(value)
	for k, v in ipairs(ENCOUNTER_TABLE) do
		if v.value == value then return ENCOUNTER_TABLE[k] end
	end
end

function check_critical_hit_swap_rules()
	has_swapped = swap_tracking_table[gameinfo.getromhash()]["enable_critical_hit_swap"]

	-- Check the tracking value since we've already swapped and are trying to swap again upon load
	if (has_swapped == true or has_swapped == nil) then
		return false
	end

	-- Check the dialog pointer to ensure it is currently processing the phrase "Excellent move!" and has finished doing so
	if (mainmemory.read_u8(DIALOG_TEXT_POINTER) == EXCELLENT_MOVE_WORD_POINTER and
		mainmemory.read_u8(0x0008) == EXCELLENT_MOVE_TERMINATOR and
		has_swapped == false) then
		log_message('initiating swap because tracking table value is: ' .. tostring(has_swapped))
		log_message("initiate excellent move swap")
		return true
	end

	return false
end

function check_encounter_swap_rules(encounter_type)
	encounter = mainmemory.read_u8(ENCOUNTER_ADDRESS)
	selected_encounter = get_encounter_by_name(encounter_type)
	in_battle = memory.read_u8(BACKGROUND_CHR_ROM_ADDRESS) == 01 and memory.read_u8(SPRITES_CHR_ROM_ADDRESS) == 03

	if encounter == nil or selected_encounter == nil then return false end

	if in_battle == false then return false end

	return encounter == selected_encounter.value
end

function check_level_up_swap_rules()
	player_level_in_memory = mainmemory.read_u8(PLAYER_LEVEL_ADDRESS)
	on_title_screen = memory.read_u8(BACKGROUND_CHR_ROM_ADDRESS) == 00

	if player_level_in_memory <= 1 then return false end

	if on_title_screen then return false end

	-- break this out into a separate handler
	if player_level_in_memory > player_level then
		log_message('player_level_in_memory ' .. player_level_in_memory)

		player_level = player_level_in_memory
		return true
	end;

	return (player_level_in_memory > player_level)
end

function check_death_swap_rules()
	current_hp_in_memory = mainmemory.read_u8(PLAYER_HP_ADDRESS)
	on_title_screen = memory.read_u8(BACKGROUND_CHR_ROM_ADDRESS) == 00
	map_has_not_loaded = memory.read_u8(MAP_ID_ADDRESS) == 00

	if on_title_screen or map_has_not_loaded then return false end

	return (current_hp_in_memory == 0)
end

function println(message)
	input_break = input.get()

	if input_break["Backslash"] then
		log_message(message)
	end
end

OR, XOR, AND = 1, 3, 4

function bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then -- test the rightmost bits
          result = result + bitval      -- set the current bit
      end
      bitval = bitval * 2 -- shift left
      a = math.floor(a/2) -- shift right
      b = math.floor(b/2)
    end
    return result
end

function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0

    local tmp = string.rep(" ", depth)
    if name then
    	if not string.match(name, '^[a-zA-z_][a-zA-Z0-9_]*$') then
    		name = string.gsub(name, "'", "\\'")
    		name = "['".. name .. "']"
    	end
    	tmp = tmp .. name .. " = "
     end

    if type(val) == "table" then
        tmp = tmp .. "{" .. (not skipnewlines and "\n" or "")

        for k, v in pairs(val) do
            tmp =  tmp .. serializeTable(v, k, skipnewlines, depth + 1) .. "," .. (not skipnewlines and "\n" or "")
        end

        tmp = tmp .. string.rep(" ", depth) .. "}"
    elseif type(val) == "number" then
        tmp = tmp .. tostring(val)
    elseif type(val) == "string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val) == "boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "\"[inserializeable datatype:" .. type(val) .. "]\""
    end

    return tmp
end

return plugin