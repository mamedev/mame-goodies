-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb

-- constants

local MENU_TYPES = {
	MAIN = 0,
	SWITCH = 2,
	CYCLE = 3,
	EXCLUDE = 4,
	SETTINGS = 5 }


-- helper functions

local function general_input_setting(token)
	return manager.ui:get_general_input_setting(manager.machine.ioport:token_to_input_type(token))
end

local function get_targets()
	-- find targets with selectable views
	local result = { }
	for k, target in pairs(manager.machine.render.targets) do
		if (not target.hidden) and (#target.view_names > 0) then
			table.insert(result, target)
		end
	end
	return result
end


-- globals

local menu_stack

local commonui

local switch_hotkeys
local cycle_hotkeys
local excluded_views
local plugin_settings

local switch_target_start
local switch_done
local switch_poll

local exclude_target_start
local exclude_done

local settings_done
local settings_config_mode_index
local settings_remove_overrides_index
local settings_layout_only_index  -- Add this missing declaration
local pending_config_mode  -- Track pending changes

-- Use shared utility module for layout parsing
local utils

local function get_filtered_views(target)
	if not utils then
		local status, msg = pcall(function () utils = require('viewswitch/viewswitch_utils') end)
		if not status then
			emu.print_error(string.format('Error loading viewswitch utilities: %s', msg))
			-- Fallback to all views if utils can't load
			local all_views = {}
			local view_names = target.view_names
			for i, view_name in ipairs(view_names) do
				table.insert(all_views, {index = i, name = view_name})
			end
			return all_views
		end
	end
	
	return utils:get_filtered_views(target, plugin_settings)
end

-- quick switch hotkeys menu

local function handle_switch(index, event)
	if switch_poll then
		-- special handling for entering hotkey
		if switch_poll.poller:poll() then
			if switch_poll.poller.sequence then
				local found
				for k, hotkey in pairs(switch_hotkeys) do
					if (hotkey.target == switch_poll.target) and (hotkey.view == switch_poll.view) then
						found = hotkey
						break
					end
				end
				if not found then
					found = { target = switch_poll.target, view = switch_poll.view }
					table.insert(switch_hotkeys, found)
				end
				found.sequence = switch_poll.poller.sequence
				found.config = manager.machine.input:seq_to_tokens(switch_poll.poller.sequence)
			end
			switch_poll = nil
			return true
		end
		return false
	end

	if (event == 'back') or ((event == 'select') and (index == switch_done)) then
		switch_target_start = nil
		switch_done = nil
		table.remove(menu_stack)
		return true
	else
		for target = #switch_target_start, 1, -1 do
			if index >= switch_target_start[target] then
				local view = index - switch_target_start[target] + 1
				if event == 'select' then
					if not commonui then
						commonui = require('commonui')
					end
					switch_poll = { target = target, view = view, poller = commonui.switch_polling_helper() }
					return true
				elseif event == 'clear' then
					for k, hotkey in pairs(switch_hotkeys) do
						if (hotkey.target == target) and (hotkey.view == view) then
							table.remove(switch_hotkeys, k)
							return true
						end
					end
				end
				return false
			end
		end
	end
	return false
end

local function populate_switch()
	-- find targets with selectable views
	local targets = get_targets()

	switch_target_start = { }
	local items = { }

	local mode_text = plugin_settings.layout_only_mode and 'Layout Views Only' or 'All Views'
	table.insert(items, { 'Quick Switch Hotkeys (' .. mode_text .. ')', '', 'off' })
	table.insert(items, { string.format('Press %s to clear hotkey', general_input_setting('UI_CLEAR')), '', 'off' })

	if #targets == 0 then
		table.insert(items, { '---', '', '' })
		table.insert(items, { 'No selectable views', '', 'off' })
	else
		local input = manager.machine.input
		for i, target in pairs(targets) do
			-- Get views based on current setting
			local filtered_views = get_filtered_views(target)
			
			-- Special handling for layout-only mode when no layout found
			if plugin_settings.layout_only_mode and #filtered_views == 0 then
				table.insert(items, { '---', '', '' })
				if #targets > 1 then
					table.insert(items, { string.format('Screen #%d', target.index - 1), '', 'off' })
				end
				table.insert(items, { 'No layout file found', '', 'off' })
			else
				-- add separator and target heading if multiple targets
				table.insert(items, { '---', '', '' })
				if #targets > 1 then
					local target_desc = plugin_settings.layout_only_mode and 'Layout Views Only' or 'All Views'
					table.insert(items, { string.format('Screen #%d (%s)', target.index - 1, target_desc), '', 'off' })
				end
				table.insert(switch_target_start, #items + 1)

				-- add an item for each view
				for _, view_info in ipairs(filtered_views) do
					local seq = 'None'
					for k, hotkey in pairs(switch_hotkeys) do
						if (hotkey.target == target.index) and (hotkey.view == view_info.index) then
							seq = input:seq_name(hotkey.sequence)
							break
						end
					end
					local flags = ''
					if switch_poll and (switch_poll.target == target.index) and (switch_poll.view == view_info.index) then
						flags = 'lr'
					end
					table.insert(items, { view_info.name, seq, flags })
				end
			end
		end
	end

	table.insert(items, { '---', '', '' })
	table.insert(items, { 'Done', '', '' })
	switch_done = #items

	if switch_poll then
		return switch_poll.poller:overlay(items)
	else
		return items
	end
end


-- cycle hotkeys menu

local function handle_cycle(index, event)
	if switch_poll then
		-- special handling for entering hotkey
		if switch_poll.poller:poll() then
			if switch_poll.poller.sequence then
				local found
				for k, hotkey in pairs(cycle_hotkeys) do
					if (hotkey.target == switch_poll.target) and (hotkey.increment == switch_poll.increment) then
						found = hotkey
						break
					end
				end
				if not found then
					found = { target = switch_poll.target, increment = switch_poll.increment }
					table.insert(cycle_hotkeys, found)
				end
				found.sequence = switch_poll.poller.sequence
				found.config = manager.machine.input:seq_to_tokens(switch_poll.poller.sequence)
			end
			switch_poll = nil
			return true
		end
		return false
	end

	if (event == 'back') or ((event == 'select') and (index == switch_done)) then
		switch_target_start = nil
		switch_done = nil
		table.remove(menu_stack)
		return true
	else
		for target = #switch_target_start, 1, -1 do
			if index >= switch_target_start[target] then
				local increment = ((index - switch_target_start[target]) == 0) and 1 or -1
				if event == 'select' then
					if not commonui then
						commonui = require('commonui')
					end
					switch_poll = { target = target, increment = increment, poller = commonui.switch_polling_helper() }
					return true
				elseif event == 'clear' then
					for k, hotkey in pairs(cycle_hotkeys) do
						if (hotkey.target == target) and (hotkey.increment == increment) then
							table.remove(cycle_hotkeys, k)
							return true
						end
					end
				end
				return false
			end
		end
	end
	return false
end

local function populate_cycle()
	-- find targets with selectable views
	local targets = get_targets()

	switch_target_start = { }
	local items = { }

	local mode_text = plugin_settings.layout_only_mode and 'Layout Views Only' or 'All Views'
	table.insert(items, { 'Cycle Hotkeys (' .. mode_text .. ')', '', 'off' })
	table.insert(items, { string.format('Press %s to clear hotkey', general_input_setting('UI_CLEAR')), '', 'off' })

	if #targets == 0 then
		table.insert(items, { '---', '', '' })
		table.insert(items, { 'No selectable views', '', 'off' })
	else
		local input = manager.machine.input
		for i, target in pairs(targets) do
			-- add separator and target heading if multiple targets
			table.insert(items, { '---', '', '' })
			if #targets > 1 then
				local target_desc = plugin_settings.layout_only_mode and 'Layout Views Only' or 'All Views'
				table.insert(items, { string.format('Screen #%d (%s)', target.index - 1, target_desc), '', 'off' })
			end
			table.insert(switch_target_start, #items + 1)

			-- add items for next view and previous view
			local seq
			local flags
			seq = 'None'
			flags = ''
			for k, hotkey in pairs(cycle_hotkeys) do
				if (hotkey.target == target.index) and (hotkey.increment == 1) then
					seq = input:seq_name(hotkey.sequence)
					break
				end
			end
			if switch_poll and (switch_poll.target == target.index) and (switch_poll.increment == 1) then
				flags = 'lr'
			end
			table.insert(items, { 'Next view', seq, flags })
			seq = 'None'
			flags = ''
			for k, hotkey in pairs(cycle_hotkeys) do
				if (hotkey.target == target.index) and (hotkey.increment == -1) then
					seq = input:seq_name(hotkey.sequence)
					break
				end
			end
			if switch_poll and (switch_poll.target == target.index) and (switch_poll.increment == -1) then
				flags = 'lr'
			end
			table.insert(items, { 'Previous view', seq, flags })
		end
	end

	table.insert(items, { '---', '', '' })
	table.insert(items, { 'Done', '', '' })
	switch_done = #items

	if switch_poll then
		return switch_poll.poller:overlay(items)
	else
		return items
	end
end


-- exclude views menu

local function handle_exclude(index, event)
	if (event == 'back') or ((event == 'select') and (index == exclude_done)) then
		exclude_target_start = nil
		exclude_done = nil
		table.remove(menu_stack)
		return true
	else
		for target = #exclude_target_start, 1, -1 do
			if index >= exclude_target_start[target] then
				local view = index - exclude_target_start[target] + 1
				if event == 'select' then
					-- toggle exclude status
					if not excluded_views[target] then
						excluded_views[target] = { }
					end
					excluded_views[target][view] = not excluded_views[target][view]
					return true
				end
				return false
			end
		end
	end
	return false
end

local function populate_exclude()
	-- find targets with selectable views
	local targets = get_targets()

	exclude_target_start = { }
	local items = { }

	local mode_text = plugin_settings.layout_only_mode and 'Layout Views Only' or 'All Views'
	table.insert(items, { 'Exclude Views from Cycle (' .. mode_text .. ')', '', 'off' })
	table.insert(items, { 'Select views to exclude from cycling', '', 'off' })

	if #targets == 0 then
		table.insert(items, { '---', '', '' })
		table.insert(items, { 'No selectable views', '', 'off' })
	else
		for i, target in pairs(targets) do
			-- Get views based on current setting (NOT hardcoded to layout only)
			local filtered_views = get_filtered_views(target)
			
			-- Special handling for layout-only mode when no layout found
			if plugin_settings.layout_only_mode and #filtered_views == 0 then
				table.insert(items, { '---', '', '' })
				if #targets > 1 then
					table.insert(items, { string.format('Screen #%d', target.index - 1), '', 'off' })
				end
				table.insert(items, { 'No layout file found', '', 'off' })
			else
				-- add separator and target heading if multiple targets
				table.insert(items, { '---', '', '' })
				if #targets > 1 then
					local target_desc = plugin_settings.layout_only_mode and 'Layout Views Only' or 'All Views'
					table.insert(items, { string.format('Screen #%d (%s)', target.index - 1, target_desc), '', 'off' })
				end
				table.insert(exclude_target_start, #items + 1)

				-- add an item for each view
				for _, view_info in ipairs(filtered_views) do
					local flags = ''
					if excluded_views[target.index] and excluded_views[target.index][view_info.index] then
						flags = 'lr'
					end
					local status = (excluded_views[target.index] and excluded_views[target.index][view_info.index]) and 'Excluded' or 'Included'
					table.insert(items, { view_info.name, status, flags })
				end
			end
		end
	end

	table.insert(items, { '---', '', '' })
	table.insert(items, { 'Done', '', '' })
	exclude_done = #items

	return items
end


-- plugin settings menu

local function handle_settings(index, event)
	if event == 'back' then
		-- Cancel any pending changes
		pending_config_mode = nil
		settings_done = nil
		settings_config_mode_index = nil
		settings_remove_overrides_index = nil
		settings_layout_only_index = nil
		table.remove(menu_stack)
		return true
	elseif (event == 'select') and (index == settings_done) then
		-- Apply pending changes before exiting
		if pending_config_mode and pending_config_mode ~= plugin_settings.config_mode then
			local old_config_mode = plugin_settings.config_mode
			plugin_settings.config_mode = pending_config_mode
			
			local persister = require('viewswitch/viewswitch_persist')
			
			-- Handle the transition based on the modes
			if old_config_mode == 'global' and pending_config_mode == 'rom_specific' then
				persister:copy_to_rom_settings(switch_hotkeys, cycle_hotkeys, excluded_views)
			elseif old_config_mode == 'rom_specific' and pending_config_mode == 'global' then
				persister:save_settings_to_file(switch_hotkeys, cycle_hotkeys, true)
				persister:save_excluded_views_to_file(excluded_views, true)
			else
				persister:save_settings(switch_hotkeys, cycle_hotkeys, old_config_mode)
				persister:save_excluded_views(excluded_views, old_config_mode)
			end
			
			-- Save plugin settings
			persister:save_plugin_settings(plugin_settings)
			
			-- Clear current arrays and load settings for new mode
			for i = #switch_hotkeys, 1, -1 do
				table.remove(switch_hotkeys, i)
			end
			for i = #cycle_hotkeys, 1, -1 do
				table.remove(cycle_hotkeys, i)
			end
			for k in pairs(excluded_views) do
				excluded_views[k] = nil
			end
			
			-- Load new settings
			local new_switch, new_cycle = persister:load_settings(plugin_settings.config_mode)
			local new_excluded = persister:load_excluded_views(plugin_settings.config_mode)
			
			-- Rebuild arrays with proper references
			for k, hotkey in pairs(new_switch) do
				table.insert(switch_hotkeys, hotkey)
			end
			for k, hotkey in pairs(new_cycle) do
				hotkey.pressed = false
				table.insert(cycle_hotkeys, hotkey)
			end
			for target_index, target_excludes in pairs(new_excluded) do
				excluded_views[target_index] = { }
				for view_index, excluded in pairs(target_excludes) do
					excluded_views[target_index][view_index] = excluded
				end
			end
		end
		
		pending_config_mode = nil
		settings_done = nil
		settings_config_mode_index = nil
		settings_remove_overrides_index = nil
		settings_layout_only_index = nil
		table.remove(menu_stack)
		return true
	elseif event == 'select' then
		if index == settings_config_mode_index then
			-- Cycle through config modes
			local current_mode = pending_config_mode or plugin_settings.config_mode
			
			if current_mode == 'global' then
				pending_config_mode = 'rom_specific'
			elseif current_mode == 'rom_specific' then
				pending_config_mode = 'global_with_overrides'
			else -- global_with_overrides
				pending_config_mode = 'global'
			end
			
			return true
		elseif index == settings_layout_only_index then
			-- Toggle layout-only mode
			plugin_settings.layout_only_mode = not plugin_settings.layout_only_mode
			
			-- Save the setting immediately since it doesn't require mode transitions
			local persister = require('viewswitch/viewswitch_persist')
			persister:save_plugin_settings(plugin_settings)
			
			return true
		elseif index == settings_remove_overrides_index then
			-- Remove ROM overrides option
			if plugin_settings.config_mode == 'global_with_overrides' then
				local persister = require('viewswitch/viewswitch_persist')
				persister:remove_rom_overrides()
				
				-- Reload settings to reflect the removal of overrides
				for i = #switch_hotkeys, 1, -1 do
					table.remove(switch_hotkeys, i)
				end
				for i = #cycle_hotkeys, 1, -1 do
					table.remove(cycle_hotkeys, i)
				end
				for k in pairs(excluded_views) do
					excluded_views[k] = nil
				end
				
				local new_switch, new_cycle = persister:load_settings(plugin_settings.config_mode)
				local new_excluded = persister:load_excluded_views(plugin_settings.config_mode)
				
				for k, hotkey in pairs(new_switch) do
					table.insert(switch_hotkeys, hotkey)
				end
				for k, hotkey in pairs(new_cycle) do
					hotkey.pressed = false
					table.insert(cycle_hotkeys, hotkey)
				end
				for target_index, target_excludes in pairs(new_excluded) do
					excluded_views[target_index] = { }
					for view_index, excluded in pairs(target_excludes) do
						excluded_views[target_index][view_index] = excluded
					end
				end
				
				return true
			end
		end
	end
	return false
end

local function populate_settings()
	local items = { }
	local persister = require('viewswitch/viewswitch_persist')
	
	-- Use pending config mode for display if user has made changes
	local display_mode = pending_config_mode or plugin_settings.config_mode
	local settings_info = persister:get_current_settings_info(plugin_settings.config_mode)

	-- Reset indices
	settings_config_mode_index = nil
	settings_remove_overrides_index = nil
	settings_layout_only_index = nil

	table.insert(items, { 'Plugin Settings', '', 'off' })
	table.insert(items, { '---', '', '' })
	
	-- Show current/pending configuration mode
	local config_description = ''
	local mode_flags = ''
	
	if display_mode == 'global' then
		config_description = 'Global'
	elseif display_mode == 'rom_specific' then
		config_description = 'ROM-specific'
	else -- global_with_overrides
		config_description = 'Global with ROM overrides'
	end
	
	-- Add indicator if there are unsaved changes
	if pending_config_mode and pending_config_mode ~= plugin_settings.config_mode then
		config_description = config_description .. ' (unsaved)'
		mode_flags = 'lr'
	end
	
	table.insert(items, { 'Configuration mode', config_description, mode_flags })
	settings_config_mode_index = #items
	table.insert(items, { '---', '', '' })
	
	-- Add layout-only toggle setting
	local layout_only_status = plugin_settings.layout_only_mode and 'Layout views only' or 'All views'
	table.insert(items, { 'View filter', layout_only_status, '' })
	settings_layout_only_index = #items
	table.insert(items, { '---', '', '' })
	
	-- Show mode descriptions
	table.insert(items, { 'Global: Same settings for all ROMs', '', 'off' })
	table.insert(items, { 'ROM-specific: Different settings per ROM', '', 'off' })
	table.insert(items, { 'Global with overrides: Global defaults,', '', 'off' })
	table.insert(items, { '  ROM-specific when customized', '', 'off' })
	table.insert(items, { '---', '', '' })
	table.insert(items, { 'Layout views only: Show only views from', '', 'off' })
	table.insert(items, { '  default.lay file (excludes built-in views)', '', 'off' })
	table.insert(items, { 'All views: Show all available views', '', 'off' })
	
	-- Show preview of what will happen if there are pending changes
	if pending_config_mode and pending_config_mode ~= plugin_settings.config_mode then
		table.insert(items, { '---', '', '' })
		table.insert(items, { 'Preview of changes:', '', 'off' })
		
		if pending_config_mode == 'rom_specific' then
			table.insert(items, { '  Will create ROM-specific config files', '', 'off' })
		elseif pending_config_mode == 'global_with_overrides' then
			if settings_info.has_rom_settings or settings_info.has_rom_excludes then
				table.insert(items, { '  Will use existing ROM overrides', '', 'off' })
			else
				table.insert(items, { '  Will use global settings (no overrides)', '', 'off' })
			end
		elseif pending_config_mode == 'global' then
			table.insert(items, { '  Will use global settings only', '', 'off' })
		end
	end
	
	-- Show current status for current mode (not pending)
	if plugin_settings.config_mode == 'global_with_overrides' and not pending_config_mode then
		table.insert(items, { '---', '', '' })
		
		-- Show what this ROM is currently using
		local status_text = 'This ROM is using: '
		if settings_info.using_rom_settings or settings_info.using_rom_excludes then
			status_text = status_text .. 'ROM overrides'
		else
			status_text = status_text .. 'Global settings'
		end
		table.insert(items, { status_text, '', 'off' })
		
		-- Show detailed breakdown if there are mixed settings
		if settings_info.using_rom_settings ~= settings_info.using_rom_excludes then
			if settings_info.using_rom_settings then
				table.insert(items, { '  Hotkeys: ROM override', '', 'off' })
			else
				table.insert(items, { '  Hotkeys: Global', '', 'off' })
			end
			if settings_info.using_rom_excludes then
				table.insert(items, { '  Excluded views: ROM override', '', 'off' })
			else
				table.insert(items, { '  Excluded views: Global', '', 'off' })
			end
		end
		
		-- Add option to remove ROM overrides if they exist
		if settings_info.has_rom_settings or settings_info.has_rom_excludes then
			table.insert(items, { 'Remove ROM overrides', '', '' })
			settings_remove_overrides_index = #items
		end
	end
	
	table.insert(items, { '---', '', '' })
	
	-- Change "Done" text based on whether there are pending changes
	local done_text = 'Done'
	if pending_config_mode and pending_config_mode ~= plugin_settings.config_mode then
		done_text = 'Save & Exit'
	end
	table.insert(items, { done_text, '', '' })
	settings_done = #items

	return items
end


-- main menu

local function handle_main(index, event)
	if event == 'select' then
		if index == 3 then
			table.insert(menu_stack, MENU_TYPES.SWITCH)
			return true
		elseif index == 4 then
			table.insert(menu_stack, MENU_TYPES.CYCLE)
			return true
		elseif index == 5 then
			table.insert(menu_stack, MENU_TYPES.EXCLUDE)
			return true
		elseif index == 6 then
			table.insert(menu_stack, MENU_TYPES.SETTINGS)
			return true
		end
	end
	return false
end

local function populate_main()
	local items = { }

	table.insert(items, { 'Quick View Switch', '', 'off' })
	table.insert(items, { '---', '', '' })
	table.insert(items, { 'Quick switch hotkeys', '', '' })
	table.insert(items, { 'Cycle hotkeys', '', '' })
	table.insert(items, { 'Exclude views', '', '' })
	table.insert(items, { 'Settings', '', '' })

	return items
end


-- entry points

local lib = { }

function lib:init(switch, cycle, exclude, settings)
	menu_stack = { MENU_TYPES.MAIN }
	switch_hotkeys = switch
	cycle_hotkeys = cycle
	excluded_views = exclude or { }
	plugin_settings = settings or { config_mode = 'global', layout_only_mode = false }
	pending_config_mode = nil  -- Reset pending changes when plugin initializes
end

function lib:handle_event(index, event)
	local current = menu_stack[#menu_stack]
	if current == MENU_TYPES.MAIN then
		return handle_main(index, event)
	elseif current == MENU_TYPES.SWITCH then
		return handle_switch(index, event)
	elseif current == MENU_TYPES.CYCLE then
		return handle_cycle(index, event)
	elseif current == MENU_TYPES.EXCLUDE then
		return handle_exclude(index, event)
	elseif current == MENU_TYPES.SETTINGS then
		return handle_settings(index, event)
	end
end

function lib:populate()
	local current = menu_stack[#menu_stack]
	if current == MENU_TYPES.MAIN then
		return populate_main()
	elseif current == MENU_TYPES.SWITCH then
		return populate_switch()
	elseif current == MENU_TYPES.CYCLE then
		return populate_cycle()
	elseif current == MENU_TYPES.EXCLUDE then
		return populate_exclude()
	elseif current == MENU_TYPES.SETTINGS then
		return populate_settings()
	end
end

return lib