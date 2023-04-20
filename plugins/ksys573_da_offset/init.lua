-- license:BSD-3-Clause
-- copyright-holders:windyfairy
local exports = {
	name = 'ksys573_da_offset',
	version = '0.0.1',
	description = 'Konami System 573 digital audio offset plugin',
	license = 'BSD-3-Clause',
	author = { name = 'windyfairy' }
}


local plugindir

local stop_subscription

local function load_settings()
	local json = require('json')

	local function calculate_offset_from_milliseconds(milliseconds)
		return math.floor((emu.attotime.from_msec(milliseconds):as_double() * 44100) + 0.5)
	end

	local function get_processed_offset_value(val)
		local match = string.match(val, "([-]?[%d]+[%.]?[%d]*)%s*[mM][sS]")
		if match ~= nil then
			return calculate_offset_from_milliseconds(tonumber(match))
		end

		return math.floor(val + 0.5)
	end

	local function load_json(dirname)
		local filename = dirname .. '/settings.json'
		local file = io.open(filename, 'r')
		if not file then
			return nil
		end
		local parsed, pos, msg = json.parse(file:read('a'))
		file:close()
		if not parsed then
			emu.print_error(string.format('Error loading System 573 audio offset settings: error parsing %s as JSON: %s', filename, msg))
			return nil
		elseif type(parsed) ~= 'table' then
			emu.print_error(string.format('Error loading System 573 audio offset settings: %s has incorrect JSON type %s (must be table)', filename, type(parsed)))
			return nil
		end
		return parsed
	end

	local loaded_settings = load_json(plugindir)
	if not loaded_settings then
		emu.print_error(string.format('Error loading System 573 audio offset settings: error opening or parsing %s as JSON', filename))
		loaded_settings = {}
	end

	if not loaded_settings['default'] then
		loaded_settings['default'] = 0
	else
		loaded_settings['default'] = get_processed_offset_value(loaded_settings['default'])
	end

	if not loaded_settings['overrides'] then
		loaded_settings['overrides'] = {}
	end

	for k, v in pairs(loaded_settings['overrides']) do
		loaded_settings['overrides'][k] = get_processed_offset_value(v)
	end

	local datadir = manager.machine.options.entries.homepath:value():match('([^;]+)') .. '/' .. exports.name
	local local_settings = load_json(datadir)
	if local_settings then
		if local_settings['default'] then
			loaded_settings['default'] = get_processed_offset_value(local_settings['default'])
		end

		if local_settings['overrides'] then
			for k, v in pairs(local_settings['overrides']) do
				loaded_settings['overrides'][k] = get_processed_offset_value(v)
			end
		end
	end

	return loaded_settings
end


local ksys573_da_offset = exports

function ksys573_da_offset.set_folder(path)
	plugindir = path
end

function ksys573_da_offset.startplugin()
	local counter_offset
	local passthrough_counter_high, passthrough_counter_low

	local function install_counter_passthrough(memory)
		local max = math.max
		local memory_read_i16 = memory.read_i16
		local counter_current = 0
		local is_callback_read = false

		local function get_offset_counter()
			return max(0, counter_current - counter_offset)
		end

		local function counter_high_callback(offset, data, mask)
			if mask == 0xffff0000 then
				-- hack because reading memory directly also calls the callback
				if is_callback_read == true then
					return data
				end

				return get_offset_counter() & mask
			end

			return data
		end

		local function counter_low_callback(offset, data, mask)
			if mask == 0x0000ffff then
				is_callback_read = true
				local counter_upper = memory_read_i16(memory, 0x1f6400ca)
				is_callback_read = false
				counter_current = (data & mask) | (counter_upper << 16)
				return get_offset_counter() & mask
			end

			return data
		end

		passthrough_counter_high = memory:install_read_tap(0x1f6400c8, 0x1f6400cb, "counter_high", counter_high_callback)
		passthrough_counter_low = memory:install_read_tap(0x1f6400cc, 0x1f6400cf, "counter_low",  counter_low_callback)
	end

	local function menu_callback(index, event)
		return false
	end

	local function menu_populate()
		local menu = {}
		table.insert(menu, { 'System 573 Digital Audio Delay', '', 'off' })
		if not counter_offset then
			table.insert(menu, { 'Not applicable for this system', '', 'off' })
		elseif counter_offset == 0 then
			table.insert(menu, { 'No offset specified for this system', '', 'off' })
		else
			table.insert(menu, { string.format('%d samples', counter_offset), '', 'off' })
		end
		return menu
	end

	emu.register_prestart(
			function ()
				if not manager.machine.devices[":k573dio"] then
					counter_offset = nil
					return
				end

				local settings = load_settings()
				counter_offset = settings['default']

				local override_offset = settings['overrides'][manager.machine.system.name]
				if override_offset ~= nil then
					emu.print_verbose(string.format('System 573 audio offset override for %s found: %s -> %s', manager.machine.system.name, counter_offset, override_offset))
					counter_offset = override_offset
				end

				-- don't hook the code if no offset is specified
				if counter_offset == 0 then
					return
				end

				install_counter_passthrough(manager.machine.devices[":maincpu"].spaces["program"], counter_offset)
				emu.print_verbose(string.format('System 573 audio counter is now being offset by %s samples.', counter_offset))
			end)

	stop_subscription = emu.add_machine_stop_notifier(
			function ()
				if passthrough_counter_high then
					passthrough_counter_high:remove()
					passthrough_counter_high = nil
				end
				if passthrough_counter_low then
					passthrough_counter_low:remove()
					passthrough_counter_low = nil
				end
				counter_offset = nil
			end)

	emu.register_menu(menu_callback, menu_populate, 'System 573 Digital Audio Offset')
end

return exports
