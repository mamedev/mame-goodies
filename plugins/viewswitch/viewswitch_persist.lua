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
	local switch_hotkeys = { }
	local cycle_hotkeys = { }

	-- try to open the system settings file
	local filename = settings_path() .. '/' .. settings_filename()
	local file = io.open(filename, 'r')
	if file then
		-- try parsing settings as JSON
		local json = require('json')
		local settings = json.parse(file:read('a'))
		file:close()
		if not settings then
			emu.print_error(string.format('Error loading quick view switch settings: error parsing file "%s" as JSON', filename))
		else
			-- try to interpret the settings
			local render_targets = manager.machine.render.targets
			local input = manager.machine.input
			for i, config in pairs(settings) do
				local target = render_targets[i]
				if target then
					for view, hotkey in pairs(config.switch or { }) do
						for j, v in pairs(target.view_names) do
							if view == v then
								table.insert(switch_hotkeys, { target = i, view = j, config = hotkey, sequence = input:seq_from_tokens(hotkey) })
								break
							end
						end
					end
					for increment, hotkey in pairs(config.cycle or { }) do
						local j = tonumber(increment)
						if j then
							table.insert(cycle_hotkeys, { target = i, increment = j, config = hotkey, sequence = input:seq_from_tokens(hotkey) })
						end
					end
				end
			end
		end
	end

	return switch_hotkeys, cycle_hotkeys
end

function lib:save_settings(switch_hotkeys, cycle_hotkeys)
	-- make sure the settings path is a folder if it exists
	local path = settings_path()
	local stat = lfs.attributes(path)
	if stat and (stat.mode ~= 'directory') then
		emu.print_error(string.format('Error saving quick view switch settings: "%s" is not a directory', path))
		return
	end

	-- if nothing to save, remove existing settings file
	local filename = path .. '/' .. settings_filename()
	if (#switch_hotkeys == 0) and (#cycle_hotkeys == 0) then
		os.remove(filename)
	else
		if not stat then
			lfs.mkdir(path)
			stat = lfs.attributes(path)
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
		for k, hotkey in pairs(cycle_hotkeys) do
			local target = settings[hotkey.target]
			local cycle
			if target then
				cycle = target.cycle
				if not cycle then
					cycle = { }
					target.cycle = cycle
				end
			else
				cycle = { }
				target = { cycle = cycle }
				settings[hotkey.target] = target
			end
			cycle[hotkey.increment] = hotkey.config
		end

		-- try to write the file
		local json = require('json')
		local text = json.stringify(settings, { indent = true })
		local file = io.open(filename, 'w')
		if not file then
			emu.print_error(string.format('Error saving quick view switch settings: error opening file "%s" for writing', filename))
		else
			file:write(text)
			file:close()
		end
	end
end

return lib
