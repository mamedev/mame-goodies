-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb

-- constants

local MENU_TYPES = {
	MAIN = 0,
	SWITCH = 2,
	CYCLE = 3 }


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

local switch_target_start
local switch_done
local switch_poll


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

	table.insert(items, { 'Quick Switch Hotkeys', '', 'off' })
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
				table.insert(items, { string.format('Screen #%d', target.index - 1), '', 'off' })
			end
			table.insert(switch_target_start, #items + 1)

			-- add an item for each view
			for j, view in pairs(target.view_names) do
				local seq = 'None'
				for k, hotkey in pairs(switch_hotkeys) do
					if (hotkey.target == target.index) and (hotkey.view == j) then
						seq = input:seq_name(hotkey.sequence)
						break
					end
				end
				local flags = ''
				if switch_poll and (switch_poll.target == target.index) and (switch_poll.view == j) then
					flags = 'lr'
				end
				table.insert(items, { view, seq, flags })
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

	table.insert(items, { 'Cycle Hotkeys', '', 'off' })
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
				table.insert(items, { string.format('Screen #%d', target.index - 1), '', 'off' })
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


-- main menu

local function handle_main(index, event)
	if event == 'select' then
		if index == 3 then
			table.insert(menu_stack, MENU_TYPES.SWITCH)
			return true
		elseif index == 4 then
			table.insert(menu_stack, MENU_TYPES.CYCLE)
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

	return items
end


-- entry points

local lib = { }

function lib:init(switch, cycle)
	menu_stack = { MENU_TYPES.MAIN }
	switch_hotkeys = switch
	cycle_hotkeys = cycle
end

function lib:handle_event(index, event)
	local current = menu_stack[#menu_stack]
	if current == MENU_TYPES.MAIN then
		return handle_main(index, event)
	elseif current == MENU_TYPES.SWITCH then
		return handle_switch(index, event)
	elseif current == MENU_TYPES.CYCLE then
		return handle_cycle(index, event)
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
	end
end

return lib
