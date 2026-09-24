-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb
local exports = {
	name = 'viewswitch',
	version = '0.0.4',
	description = 'Quick view switch plugin',
	license = 'BSD-3-Clause',
	author = { name = 'Vas Crabb' } }

local viewswitch = exports

local stop_subscription

function viewswitch.startplugin()
	local switch_hotkeys = { }
	local cycle_hotkeys = { }
	local excluded_views = { }
	local plugin_settings = { }

	local input_manager
	local ui_manager = { menu_active = true, ui_active = true }
	local render_targets
	local menu_handler
	local utils  -- Add utils module

	-- Helper function to check if viewswitch.txt exists at startup
	local function should_hide_menu()
		-- Try to get the homepath from environment or use a fallback
		local homepath = os.getenv('HOME') or os.getenv('USERPROFILE') or '.'
		
		-- Common MAME paths to check
		local possible_paths = {
			homepath .. '/.mame/viewswitch/viewswitch.txt',
			homepath .. '/mame/viewswitch/viewswitch.txt',
			'./viewswitch/viewswitch.txt',
			'viewswitch/viewswitch.txt'
		}
		
		-- If manager.machine is available, use the proper path first
		if manager.machine and manager.machine.options and manager.machine.options.entries.homepath then
			local mame_path = manager.machine.options.entries.homepath:value():match('([^;]+)') .. '/viewswitch/viewswitch.txt'
			table.insert(possible_paths, 1, mame_path)  -- Insert at beginning
		end
		
		-- Check all possible paths
		for _, path in ipairs(possible_paths) do
			local file = io.open(path, 'r')
			if file then
				file:close()
				return true  -- File exists, hide menu
			end
		end
		
		return false  -- File doesn't exist anywhere, show menu
	end

	local function get_next_view(target, current_view, increment)
		local view_indices = {}
		
		-- Check if layout-only mode is enabled
		if plugin_settings.layout_only_mode then
			-- Use utils module to get layout views
			if utils then
				local layout_view_names = utils:parse_layout_views()
				
				if #layout_view_names > 0 then
					-- Get layout view indices
					local layout_views = utils:get_layout_view_indices(target, layout_view_names)
					for _, view_info in ipairs(layout_views) do
						table.insert(view_indices, view_info.index)
					end
				end
			end
			
			-- If no layout views found, fall back to all views
			if #view_indices == 0 then
				for i = 1, #target.view_names do
					table.insert(view_indices, i)
				end
			end
		else
			-- Use all views
			for i = 1, #target.view_names do
				table.insert(view_indices, i)
			end
		end
		
		if #view_indices == 0 then
			return current_view  -- No valid views
		end
		
		local target_index = target.index
		local excluded = excluded_views[target_index] or {}
		
		-- Find current position in views array
		local current_pos = 1
		for pos, view_index in ipairs(view_indices) do
			if view_index == current_view then
				current_pos = pos
				break
			end
		end
		
		-- If no exclusions, use simple cycling
		if not next(excluded) then
			local new_pos = current_pos + increment
			if new_pos < 1 then
				new_pos = #view_indices
			elseif new_pos > #view_indices then
				new_pos = 1
			end
			return view_indices[new_pos]
		end
		
		-- Find next non-excluded view
		local tries = 0
		local pos = current_pos
		repeat
			pos = pos + increment
			if pos < 1 then
				pos = #view_indices
			elseif pos > #view_indices then
				pos = 1
			end
			tries = tries + 1
		until (not excluded[view_indices[pos]]) or (tries >= #view_indices)
		
		-- If all views are excluded, return current view
		if tries >= #view_indices then
			return current_view
		end
		
		return view_indices[pos]
	end

	local function frame_done()
		if ui_manager.ui_active and (not ui_manager.menu_active) then
			for k, hotkey in pairs(switch_hotkeys) do
				if input_manager:seq_pressed(hotkey.sequence) then
					render_targets[hotkey.target].view_index = hotkey.view
				end
			end
			for k, hotkey in pairs(cycle_hotkeys) do
				if input_manager:seq_pressed(hotkey.sequence) then
					if not hotkey.pressed then
						local target = render_targets[hotkey.target]
						local next_view = get_next_view(target, target.view_index, hotkey.increment)
						target.view_index = next_view
						hotkey.pressed = true
					end
				else
					hotkey.pressed = false
				end
			end
		end
	end

	local function start()
		-- Load the shared utilities module
		local status, msg = pcall(function () utils = require('viewswitch/viewswitch_utils') end)
		if not status then
			emu.print_error(string.format('Error loading viewswitch utilities: %s', msg))
			utils = nil
		end

		local persister = require('viewswitch/viewswitch_persist')
		plugin_settings = persister:load_plugin_settings()
		switch_hotkeys, cycle_hotkeys = persister:load_settings(plugin_settings.config_mode)
		excluded_views = persister:load_excluded_views(plugin_settings.config_mode)

		local machine = manager.machine
		input_manager = machine.input
		ui_manager = manager.ui
		render_targets = machine.render.targets
	end

	local function stop()
		local persister = require('viewswitch/viewswitch_persist')
		persister:save_plugin_settings(plugin_settings)
		persister:save_settings(switch_hotkeys, cycle_hotkeys, plugin_settings.config_mode)
		persister:save_excluded_views(excluded_views, plugin_settings.config_mode)

		menu_handler = nil
		render_targets = nil
		ui_manager = { menu_active = true, ui_active = true }
		input_manager = nil
		switch_hotkeys = { }
		cycle_hotkeys = { }
		excluded_views = { }
		plugin_settings = { }
		utils = nil
	end

	local function menu_callback(index, event)
		return menu_handler:handle_event(index, event)
	end

	local function menu_populate()
		if not menu_handler then
			local status, msg = pcall(function () menu_handler = require('viewswitch/viewswitch_menu') end)
			if not status then
				emu.print_error(string.format('Error loading quick view switch menu: %s', msg))
			end
			if menu_handler then
				menu_handler:init(switch_hotkeys, cycle_hotkeys, excluded_views, plugin_settings)
			end
		end
		if menu_handler then
			return menu_handler:populate()
		else
			return { { 'Failed to load quick view switch menu', '', 'off' } }
		end
	end

	emu.register_frame_done(frame_done)
	emu.register_prestart(start)
	stop_subscription = emu.add_machine_stop_notifier(stop)
	
	-- Only register the menu if viewswitch.txt doesn't exist
	if not should_hide_menu() then
		emu.register_menu(menu_callback, menu_populate, 'Quick View Switch')
	end
end

return exports