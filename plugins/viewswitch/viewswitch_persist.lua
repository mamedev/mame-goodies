-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb

-- helper functions

local function settings_path()
	return manager.machine.options.entries.homepath:value():match('([^;]+)') .. '/viewswitch'
end

local function settings_filename(use_global)
	if use_global then
		return 'global.cfg'
	else
		return manager.machine.system.name .. '.cfg'
	end
end

local function exclude_filename(use_global)
	if use_global then
		return 'viewswitch_exclude.cfg'
	else
		return manager.machine.system.name .. '_exclude.cfg'
	end
end

local function global_settings_filename()
	return 'viewswitch_settings.cfg'
end

local function has_rom_settings()
	local filename = settings_path() .. '/' .. settings_filename(false)
	local file = io.open(filename, 'r')
	if file then
		local content = file:read('a')
		file:close()
		-- Check if file has meaningful content (not just empty or {})
		if content and content:match('%S') then
			local json = require('json')
			local settings = json.parse(content)
			if settings and next(settings) then
				return true
			end
		end
	end
	return false
end

local function has_rom_excludes()
	local filename = settings_path() .. '/' .. exclude_filename(false)
	local file = io.open(filename, 'r')
	if file then
		local content = file:read('a')
		file:close()
		if content and content:match('%S') then
			local json = require('json')
			local settings = json.parse(content)
			if settings and next(settings) then
				return true
			end
		end
	end
	return false
end


-- entry points

local lib = { }

function lib:load_plugin_settings()
	local plugin_settings = { 
		config_mode = 'global',      -- default to global
		layout_only_mode = false     -- default to show all views
	}
	
	-- try to open the plugin settings file
	local filename = settings_path() .. '/' .. global_settings_filename()
	local file = io.open(filename, 'r')
	if file then
		-- try parsing settings as JSON
		local json = require('json')
		local settings = json.parse(file:read('a'))
		file:close()
		if not settings then
			emu.print_error(string.format('Error loading plugin settings: error parsing file "%s" as JSON', filename))
		else
			-- Merge loaded settings with defaults
			for key, value in pairs(settings) do
				plugin_settings[key] = value
			end
			
			-- Migrate old use_global setting to new config_mode
			if plugin_settings.use_global ~= nil then
				plugin_settings.config_mode = plugin_settings.use_global and 'global' or 'rom_specific'
				plugin_settings.use_global = nil
			end
		end
	end
	
	return plugin_settings
end

function lib:save_plugin_settings(plugin_settings)
	-- make sure the settings path is a folder if it exists
	local path = settings_path()
	local stat = lfs.attributes(path)
	if stat and (stat.mode ~= 'directory') then
		emu.print_error(string.format('Error saving plugin settings: "%s" is not a directory', path))
		return
	end

	if not stat then
		lfs.mkdir(path)
		stat = lfs.attributes(path)
	end

	-- try to write the file
	local filename = path .. '/' .. global_settings_filename()
	local json = require('json')
	local text = json.stringify(plugin_settings, { indent = true })
	local file = io.open(filename, 'w')
	if not file then
		emu.print_error(string.format('Error saving plugin settings: error opening file "%s" for writing', filename))
	else
		file:write(text)
		file:close()
	end
end

function lib:load_excluded_views_internal(use_global)
	local excluded_views = { }
	
	-- try to open the exclude settings file
	local filename = settings_path() .. '/' .. exclude_filename(use_global)
	local file = io.open(filename, 'r')
	if file then
		-- try parsing settings as JSON
		local json = require('json')
		local exclude_settings = json.parse(file:read('a'))
		file:close()
		if not exclude_settings then
			emu.print_error(string.format('Error loading view exclude settings: error parsing file "%s" as JSON', filename))
		else
			-- try to interpret the exclude settings
			local render_targets = manager.machine.render.targets
			for i_str, target_excludes in pairs(exclude_settings) do
				local i = tonumber(i_str)  -- convert string key to number
				local target = render_targets[i]
				if target then
					excluded_views[i] = { }
					for j, view_name in pairs(target_excludes) do
						for k, v in ipairs(target.view_names) do
							if view_name == v then
								excluded_views[i][k] = true
								break
							end
						end
					end
				end
			end
		end
	end
	
	return excluded_views
end

function lib:load_excluded_views(config_mode)
	if config_mode == 'global' then
		return self:load_excluded_views_internal(true)
	elseif config_mode == 'rom_specific' then
		return self:load_excluded_views_internal(false)
	elseif config_mode == 'global_with_overrides' then
		-- Try ROM-specific first, fall back to global
		if has_rom_excludes() then
			return self:load_excluded_views_internal(false)
		else
			return self:load_excluded_views_internal(true)
		end
	end
	return { }
end

function lib:load_settings_internal(use_global)
	local switch_hotkeys = { }
	local cycle_hotkeys = { }

	-- try to open the system settings file
	local filename = settings_path() .. '/' .. settings_filename(use_global)
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
						for j, v in ipairs(target.view_names) do
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

function lib:load_settings(config_mode)
	if config_mode == 'global' then
		return self:load_settings_internal(true)
	elseif config_mode == 'rom_specific' then
		return self:load_settings_internal(false)
	elseif config_mode == 'global_with_overrides' then
		-- Try ROM-specific first, fall back to global
		if has_rom_settings() then
			return self:load_settings_internal(false)
		else
			return self:load_settings_internal(true)
		end
	end
	return { }, { }
end

-- Internal function to save to a specific file type
function lib:save_settings_to_file(switch_hotkeys, cycle_hotkeys, save_global)
	-- make sure the settings path is a folder if it exists
	local path = settings_path()
	local stat = lfs.attributes(path)
	if stat and (stat.mode ~= 'directory') then
		emu.print_error(string.format('Error saving quick view switch settings: "%s" is not a directory', path))
		return
	end

	-- Determine filename based on save_global flag
	local filename = path .. '/' .. settings_filename(save_global)
	
	-- if nothing to save, remove existing settings file
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

-- Rest of the functions remain the same...
function lib:save_excluded_views_to_file(excluded_views, save_global)
	-- make sure the settings path is a folder if it exists
	local path = settings_path()
	local stat = lfs.attributes(path)
	if stat and (stat.mode ~= 'directory') then
		emu.print_error(string.format('Error saving view exclude settings: "%s" is not a directory', path))
		return
	end

	-- Determine filename based on save_global flag
	local filename = path .. '/' .. exclude_filename(save_global)
	
	-- For global saves, we need to merge with existing exclusions
	local final_exclude_settings = {}
	
	if save_global then
		-- Load existing global exclusions first
		local existing_file = io.open(filename, 'r')
		if existing_file then
			local json = require('json')
			local existing_settings = json.parse(existing_file:read('a'))
			existing_file:close()
			if existing_settings then
				final_exclude_settings = existing_settings
			end
		end
	end
	
	-- Check if we have any new exclusions to add
	local has_new_excludes = false
	for target_index, target_excludes in pairs(excluded_views) do
		for view_index, excluded in pairs(target_excludes) do
			if excluded then
				has_new_excludes = true
				break
			end
		end
		if has_new_excludes then break end
	end
	
	-- If no new exclusions and we're saving globally, don't modify the file
	if not has_new_excludes and save_global then
		return
	end
	
	-- If no new exclusions and not saving globally, remove the ROM-specific file
	if not has_new_excludes and not save_global then
		os.remove(filename)
		return
	end

	if not stat then
		lfs.mkdir(path)
		stat = lfs.attributes(path)
	end

	-- Add/update current ROM's exclusions to the final settings
	local render_targets = manager.machine.render.targets
	for target_index, target_excludes in pairs(excluded_views) do
		local target = render_targets[target_index]
		if target then
			-- Get existing exclusions for this target (for global saves)
			local existing_target_excludes = {}
			if save_global and final_exclude_settings[tostring(target_index)] then
				existing_target_excludes = final_exclude_settings[tostring(target_index)]
			end
			
			-- Build new exclusion list for this target
			local excluded_list = {}
			
			-- Add existing exclusions first (only for global saves)
			if save_global then
				for _, view_name in pairs(existing_target_excludes) do
					excluded_list[#excluded_list + 1] = view_name
				end
			end
			
			-- Add new exclusions, avoiding duplicates
			for view_index, excluded in pairs(target_excludes) do
				if excluded then
					local view_name = target.view_names[view_index]
					local already_exists = false
					for _, existing_view in pairs(excluded_list) do
						if existing_view == view_name then
							already_exists = true
							break
						end
					end
					if not already_exists then
						excluded_list[#excluded_list + 1] = view_name
					end
				end
			end
			
			-- Only save if we have exclusions for this target
			if #excluded_list > 0 then
				final_exclude_settings[tostring(target_index)] = excluded_list
			elseif not save_global then
				-- For ROM-specific saves, if no exclusions, remove the target entry
				final_exclude_settings[tostring(target_index)] = nil
			end
		end
	end

	-- Check if final settings has any content
	local has_any_excludes = next(final_exclude_settings) ~= nil
	
	if not has_any_excludes then
		os.remove(filename)
	else
		-- try to write the file with pretty formatting
		local json = require('json')
		local file = io.open(filename, 'w')
		if not file then
			emu.print_error(string.format('Error saving view exclude settings: error opening file "%s" for writing', filename))
		else
			file:write('{\n')
			local target_keys = {}
			for k in pairs(final_exclude_settings) do
				table.insert(target_keys, k)
			end
			table.sort(target_keys, function(a, b) return tonumber(a) < tonumber(b) end)
			
			for i, target_key in ipairs(target_keys) do
				local excluded_list = final_exclude_settings[target_key]
				file:write(string.format('  "%s": [\n', target_key))
				
				for j, view_name in ipairs(excluded_list) do
					local comma = (j < #excluded_list) and ',' or ''
					file:write(string.format('    "%s"%s\n', view_name, comma))
				end
				
				local target_comma = (i < #target_keys) and ',' or ''
				file:write(string.format('  ]%s\n', target_comma))
			end
			file:write('}\n')
			file:close()
		end
	end
end

function lib:save_settings(switch_hotkeys, cycle_hotkeys, config_mode)
	-- Determine where to save based on config mode
	local save_global = true  -- Default to global
	
	if config_mode == 'rom_specific' then
		save_global = false  -- Only ROM-specific mode saves to ROM files
	elseif config_mode == 'global_with_overrides' then
		save_global = true   -- Global with overrides saves to global (new defaults)
	-- config_mode == 'global' uses default save_global = true
	end
	
	self:save_settings_to_file(switch_hotkeys, cycle_hotkeys, save_global)
end

function lib:save_excluded_views(excluded_views, config_mode)
	-- Determine where to save based on config mode  
	local save_global = true  -- Default to global
	
	if config_mode == 'rom_specific' then
		save_global = false  -- Only ROM-specific mode saves to ROM files
	elseif config_mode == 'global_with_overrides' then
		save_global = true   -- Global with overrides saves to global (new defaults)
	-- config_mode == 'global' uses default save_global = true
	end
	
	self:save_excluded_views_to_file(excluded_views, save_global)
end

-- New function to copy current settings to ROM files while preserving global files
function lib:copy_to_rom_settings(switch_hotkeys, cycle_hotkeys, excluded_views)
	-- Save current settings as ROM-specific without removing global files
	self:save_settings_to_file(switch_hotkeys, cycle_hotkeys, false)  -- false = ROM file
	self:save_excluded_views_to_file(excluded_views, false)  -- false = ROM file
end

-- New function to check which settings are currently being used
function lib:get_current_settings_info(config_mode)
	local has_rom_settings_file = has_rom_settings()
	local has_rom_excludes_file = has_rom_excludes()
	
	local info = {
		using_rom_settings = false,
		using_rom_excludes = false,
		has_rom_settings = has_rom_settings_file,
		has_rom_excludes = has_rom_excludes_file
	}
	
	if config_mode == 'global_with_overrides' then
		-- Only mark as "using ROM" if the files actually exist
		info.using_rom_settings = has_rom_settings_file
		info.using_rom_excludes = has_rom_excludes_file
	elseif config_mode == 'rom_specific' then
		-- In ROM-specific mode, we're always "using ROM settings" even if files don't exist yet
		info.using_rom_settings = true
		info.using_rom_excludes = true
	end
	-- For 'global' mode, everything stays false (using global)
	
	return info
end

-- New function to remove ROM-specific overrides
function lib:remove_rom_overrides()
	local path = settings_path()
	local rom_settings_file = path .. '/' .. settings_filename(false)
	local rom_excludes_file = path .. '/' .. exclude_filename(false)
	
	os.remove(rom_settings_file)
	os.remove(rom_excludes_file)
end

return lib