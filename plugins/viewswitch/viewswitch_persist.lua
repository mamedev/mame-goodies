-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb

-- helper functions

local function settings_path()
	return manager.machine.options.entries.homepath:value():match('([^;]+)') .. '/viewswitch'
end

local function settings_filename()
	return emu.romname() .. '.cfg'
end


-- entry points

local lib = { }

function lib:load_settings()
	local result = { }

	-- try to open the settings file
	local filename = settings_path() .. '/' .. settings_filename()
	local file = io.open(filename, 'r')
	if not file then
		return result
	end

	-- try parsing settings as JSON
	local json = require('json')
	local settings = json.parse(file:read('a'))
	file:close()
	if not settings then
		emu.print_error(string.format('Error loading quick view switch settings: error parsing file "%s" as JSON', filename))
		return result
	end

	-- try to interpret the settings
	local render_targets = manager.machine.render.targets
	local input = manager.machine.input
	for i, config in pairs(settings) do
		local target = render_targets[i]
		if target then
			for view, hotkey in pairs(config.switch or { }) do
				for j, v in pairs(target.view_names) do
					if view == v then
						table.insert(result, { target = i, view = j, config = hotkey, sequence = input:seq_from_tokens(hotkey) })
						break
					end
				end
			end
		end
	end

	return result
end

function lib:save_settings(switch_hotkeys)
	-- make sure the settings path is a folder if it exists
	local path = settings_path()
	local stat = lfs.attributes(path)
	if stat and (stat.mode ~= 'directory') then
		emu.print_error(string.format('Error saving quick view switch settings: "%s" is not a directory', path))
		return
	end
	local filename = path .. '/' .. settings_filename()

	-- if nothing to save, remove existing settings file
	if #switch_hotkeys == 0 then
		os.remove(filename)
		return
	elseif not stat then
		lfs.mkdir(path)
	end

	-- flatten the settings
	local settings = { }
	local render_targets = manager.machine.render.targets
	local input = manager.machine.input
	for k, hotkey in pairs(switch_hotkeys) do
		local target = settings[hotkey.target]
		if not target then
			target = { switch = { } }
			settings[hotkey.target] = target
		end
		target.switch[render_targets[hotkey.target].view_names[hotkey.view]] = hotkey.config
	end

	-- try to write the file
	local json = require('json')
	local text = json.stringify(settings, { indent = true })
	local file = io.open(filename, 'w')
	if not file then
		emu.print_error(string.format('Error saving quick view switch settings: error opening file "%s" for writing', filename))
		return
	end
	file:write(text)
	file:close()
end

return lib
