-- license:BSD-3-Clause
-- copyright-holders:MAME User
local exports = {
	name = 'layout_rotate',
	version = '3.0',
	description = 'Rotate layout - configurable key binding and rotation modes',
	license = 'BSD-3-Clause',
	author = { name = 'RomRammer' }
}

local layout_rotate = exports

function layout_rotate.startplugin()
	local current_index = 1
	local key_was_pressed = false
	local key_sequence
	local rotation_count = 0
	local waiting_for_key = false
	local selected_key = "KEYCODE_NUMLOCK"  -- Default key
	local binding_cooldown = 0
	local binding_timeout = 0
	local config_file = "layout_rotate_config.txt"
	local plugin_enabled = true
	local current_mode = 1  -- Default to mode 1 (all 4 views)
	
	-- Rotation mode presets
	local rotation_modes = {
		{
			name = "0° and 180° + Flip",
			orientations = {6, 0},
			names = {
				[0] = "Normal (0°)",
				[6] = "180° + Flip"
			}
		},
		{
			name = "0° and 90° + Flip",
			orientations = {5, 0},
			names = {
				[0] = "Normal (0°)",
				[5] = "90° + Flip"
			}
		},
		{
			name = "All 4 Views",
			orientations = {3, 5, 6, 0},
			names = {
				[0] = "Normal (0°)",
				[3] = "270°",
				[5] = "90° + Flip",
				[6] = "180° + Flip"
			}
		}
	}
	
	-- List of common keys to check when binding (excludes TAB, ESC, TILDE, number row, arrow keys, function keys, and main Enter)
	local bindable_keys = {
		-- First row (QWERTY)
		"KEYCODE_Q", "KEYCODE_W", "KEYCODE_E", "KEYCODE_R", "KEYCODE_T",
		"KEYCODE_Y", "KEYCODE_U", "KEYCODE_I", "KEYCODE_O", "KEYCODE_P",
		"KEYCODE_OPENBRACE", "KEYCODE_CLOSEBRACE", "KEYCODE_BACKSLASH",
		-- Second row (ASDF)
		"KEYCODE_A", "KEYCODE_S", "KEYCODE_D", "KEYCODE_F", "KEYCODE_G",
		"KEYCODE_H", "KEYCODE_J", "KEYCODE_K", "KEYCODE_L",
		"KEYCODE_COLON", "KEYCODE_QUOTE",
		-- Third row (ZXCV)
		"KEYCODE_Z", "KEYCODE_X", "KEYCODE_C", "KEYCODE_V", "KEYCODE_B",
		"KEYCODE_N", "KEYCODE_M", "KEYCODE_COMMA", "KEYCODE_STOP", "KEYCODE_SLASH",
		-- Bottom row
		"KEYCODE_SPACE", "KEYCODE_LALT", "KEYCODE_RALT",
		"KEYCODE_LCONTROL", "KEYCODE_RCONTROL", "KEYCODE_LSHIFT", "KEYCODE_RSHIFT",
		"KEYCODE_BACKSPACE",
		-- Numpad keys (multiple variants MAME might use)
		"KEYCODE_0_PAD", "KEYCODE_1_PAD", "KEYCODE_2_PAD", "KEYCODE_3_PAD", "KEYCODE_4_PAD",
		"KEYCODE_5_PAD", "KEYCODE_6_PAD", "KEYCODE_7_PAD", "KEYCODE_8_PAD", "KEYCODE_9_PAD",
		"KEYCODE_ASTERISK", "KEYCODE_ENTER_PAD", "KEYCODE_ENTERPAD", "KEYCODE_NUMPADENTER", 
		"KEYCODE_KP_ENTER", "KEYCODE_PLUS_PAD", "KEYCODE_MINUS_PAD",
		"KEYCODE_SLASH_PAD", "KEYCODE_DEL_PAD", "KEYCODE_PERIOD_PAD",
		-- Alternative numpad codes
		"KEYCODE_0PAD", "KEYCODE_1PAD", "KEYCODE_2PAD", "KEYCODE_3PAD", "KEYCODE_4PAD",
		"KEYCODE_5PAD", "KEYCODE_6PAD", "KEYCODE_7PAD", "KEYCODE_8PAD", "KEYCODE_9PAD",
		"KEYCODE_PLUSPAD", "KEYCODE_MINUSPAD", "KEYCODE_SLASHPAD", "KEYCODE_ASTERISKPAD",
		-- Navigation keys (without arrow keys)
		"KEYCODE_HOME", "KEYCODE_END", "KEYCODE_PGUP", "KEYCODE_PGDN", 
		"KEYCODE_INSERT", "KEYCODE_DEL",
		-- Special keys
		"KEYCODE_CAPSLOCK", "KEYCODE_NUMLOCK", "KEYCODE_SCRLOCK",
		"KEYCODE_PRTSCR", "KEYCODE_PAUSE",
		-- NOTE: Excluded keys - TAB, ESC, TILDE, number row (1-0), arrow keys, function keys (F1-F12), main keyboard Enter
	}
	
	local function get_key_name(keycode)
		if not keycode then return "Unknown" end
		return keycode:gsub("KEYCODE_", ""):gsub("_PAD", " (Numpad)"):gsub("_", " ")
	end
	
	local function load_config()
		-- Wrap in pcall to prevent crashes
		local success, key, mode = pcall(function()
			local file = io.open(config_file, "r")
			if file then
				local saved_key = file:read("*line")
				local saved_mode = file:read("*line")
				file:close()
				
				local result_key = nil
				local result_mode = 1
				
				if saved_key and saved_key ~= "" and saved_key:match("^KEYCODE_") then
					result_key = saved_key
				end
				
				if saved_mode and saved_mode ~= "" then
					local mode_num = tonumber(saved_mode)
					if mode_num and mode_num >= 1 and mode_num <= #rotation_modes then
						result_mode = mode_num
					end
				end
				
				return result_key, result_mode
			end
			return nil, 1
		end)
		
		if success then
			if key then
				emu.print_info(string.format("Loaded config - Key: %s, Mode: %d", tostring(key), mode or 1))
			end
			return key, mode or 1
		else
			emu.print_warning("Could not load config file (will use defaults)")
			return nil, 1
		end
	end
	
	local function save_config(keycode, mode)
		-- Wrap in pcall to prevent crashes
		local success, result = pcall(function()
			local file = io.open(config_file, "w")
			if file then
				file:write(keycode .. "\n")
				file:write(tostring(mode) .. "\n")
				file:close()
				return true
			end
			return false
		end)
		
		if success and result then
			emu.print_info(string.format("Saved config - Key: %s, Mode: %d", keycode, mode))
			return true
		else
			emu.print_warning("Could not save config file")
			return false
		end
	end
	
	local function bind_key(keycode, save_to_file)
		if not keycode then return false end
		
		-- Get fresh input_manager reference
		local success, seq = pcall(function()
			local machine = manager.machine
			if not machine or not machine.input then
				return nil
			end
			return machine.input:seq_from_tokens(keycode)
		end)
		
		if success and seq then
			key_sequence = seq
			selected_key = keycode
			local key_name = get_key_name(keycode)
			emu.print_info(string.format("Layout Rotate: Bound to %s", key_name))
			
			-- Save to config file if requested
			if save_to_file then
				save_config(keycode, current_mode)
			end
			
			return true
		else
			emu.print_warning(string.format("Could not bind: %s", keycode))
			return false
		end
	end
	
		local function set_rotation_mode(mode)
			if mode >= 1 and mode <= #rotation_modes then
				current_mode = mode
				current_index = 1  -- Reset to first orientation in new mode
				
				-- Apply the first orientation of the new mode immediately
				local mode_data = rotation_modes[mode]
				local orientations = mode_data.orientations
				local orientation_value = orientations[current_index]
				
				-- Apply orientation to render targets
				pcall(function()
					local machine = manager.machine
					if machine and machine.render and machine.render.targets then
						for index, target in pairs(machine.render.targets) do
							if target then
								pcall(function()
									target.orientation = orientation_value
								end)
							end
						end
					end
				end)
				
				save_config(selected_key, current_mode)
				emu.print_info(string.format("Rotation mode set to: %s", rotation_modes[mode].name))
				return true
			end
			return false
		end
	
	local function start()
		-- Wrap entire start in pcall to prevent crashes
		local success, error_msg = pcall(function()
			local machine = manager.machine
			if not machine then
				emu.print_error("Layout Rotate: Machine not available")
				plugin_enabled = false
				return
			end
			
			-- Just verify that input and render exist at startup
			if not machine.input or not machine.render or not machine.render.targets then
				emu.print_error("Layout Rotate: Input or render not available")
				plugin_enabled = false
				return
			end
			
			emu.print_info("=== Layout Rotate Plugin Started ===")
			
			-- Try to load saved key and mode
			local saved_key, saved_mode = load_config()
			if saved_key then
				selected_key = saved_key
			end
			if saved_mode then
				current_mode = saved_mode
			end
			
			emu.print_info(string.format("Rotation mode: %s", rotation_modes[current_mode].name))
			
			-- Bind the key (don't save on startup, we just loaded it)
			if bind_key(selected_key, false) then
				emu.print_info(string.format("Press %s to rotate layout", get_key_name(selected_key)))
			else
				emu.print_warning("Failed to bind saved key, trying default")
				if not bind_key("KEYCODE_ASTERISK", false) then
					emu.print_error("Could not bind any key - plugin disabled")
					plugin_enabled = false
				end
			end
		end)
		
		if not success then
			emu.print_error(string.format("Layout Rotate startup error: %s", tostring(error_msg)))
			plugin_enabled = false
		end
	end
	
	local function frame_done()
		-- Early exit if plugin is disabled
		if not plugin_enabled then
			return
		end
		
		-- Wrap in pcall to prevent crashes during frame processing
		local success, error_msg = pcall(function()
			-- Get fresh references each frame to avoid stale references
			local machine = manager.machine
			if not machine then
				return
			end
			
			-- Verify machine is in a valid state
			if not machine.input or not machine.render then
				return
			end
			
			local current_input = machine.input
			local current_targets = machine.render.targets
			
			if not current_input or not current_targets then
				return
			end
			
			-- If waiting for key binding, check all bindable keys
			if waiting_for_key then
				-- Timeout check (600 frames = 10 seconds at 60fps)
				binding_timeout = binding_timeout + 1
				if binding_timeout > 600 then
					waiting_for_key = false
					binding_cooldown = 0
					binding_timeout = 0
					pcall(function()
						if machine and machine.popmessage then
							machine:popmessage("Key binding timed out")
						end
					end)
					emu.print_warning("Key binding timed out")
					return
				end
				
				-- Cooldown to prevent immediate detection
				if binding_cooldown > 0 then
					binding_cooldown = binding_cooldown - 1
					return
				end
				
				-- Safety check on bindable_keys table
				if not bindable_keys or type(bindable_keys) ~= "table" then
					emu.print_warning("Bindable keys table is invalid")
					waiting_for_key = false
					binding_timeout = 0
					return
				end
				
				-- Check each key safely with additional protection
				for _, keycode in ipairs(bindable_keys) do
					if not keycode or type(keycode) ~= "string" then
						goto continue
					end
					
					local seq_success, seq = pcall(function()
						if not current_input then return nil end
						return current_input:seq_from_tokens(keycode)
					end)
					
					if not seq_success or not seq then
						goto continue
					end
					
					local pressed_success, is_pressed = pcall(function()
						if not current_input or not seq then return false end
						return current_input:seq_pressed(seq)
					end)
					
					if pressed_success and is_pressed then
						-- Successfully detected a key press - bind it inline
						waiting_for_key = false
						binding_cooldown = 0
						binding_timeout = 0
						
						-- Do the binding in a protected way
						pcall(function()
							key_sequence = seq
							selected_key = keycode
							
							-- Save to config
							save_config(keycode, current_mode)
							
							-- Show message
							if machine and machine.popmessage then
								machine:popmessage(string.format("Rotation key set to: %s (SAVED)", get_key_name(keycode)))
							end
							
							emu.print_info(string.format("Layout Rotate: Bound to %s", get_key_name(keycode)))
						end)
						
						return
					end
					
					::continue::
				end
				return
			end
			
			-- Normal rotation functionality
			if not key_sequence then
				return
			end
			
			local press_success, is_pressed = pcall(function()
				return current_input:seq_pressed(key_sequence)
			end)
			
			if not press_success or not is_pressed then
				if is_pressed == false then
					key_was_pressed = false
				end
				return
			end
			
			if is_pressed and not key_was_pressed then
				-- Get current mode's orientations
				local mode_data = rotation_modes[current_mode]
				local orientations = mode_data.orientations
				local orientation_names = mode_data.names
				
				current_index = current_index + 1
				if current_index > #orientations then
					current_index = 1
				end
				
				local orientation_value = orientations[current_index]
				rotation_count = rotation_count + 1
				
				pcall(function()
					if machine and machine.popmessage then
						machine:popmessage(string.format("View: %s", orientation_names[orientation_value]))
					end
				end)
				
				-- Safely iterate render targets with additional checks
				pcall(function()
					if current_targets then
						for index, target in pairs(current_targets) do
							if target then
								pcall(function()
									target.orientation = orientation_value
								end)
							end
						end
					end
				end)
				
				key_was_pressed = true
			end
		end)
		
		if not success then
			-- Silently log errors without crashing
			pcall(function()
				emu.print_verbose(string.format("Layout Rotate frame error: %s", tostring(error_msg)))
			end)
		end
	end
	
	-- Menu with key change and rotation mode options
	local function menu_populate()
		local menu = {}
		
		-- Wrap in pcall to prevent menu crashes
		local success = pcall(function()
			if not plugin_enabled then
				table.insert(menu, {"Layout Rotate Plugin", "", "heading"})
				table.insert(menu, {"", "", ""})
				table.insert(menu, {"Plugin Disabled (Error)", "", "off"})
				table.insert(menu, {"Please check console for details", "", "off"})
				return
			end
			
			if waiting_for_key then
				table.insert(menu, {"PRESS ANY KEY TO BIND", "", "heading"})
				table.insert(menu, {"", "", ""})
				table.insert(menu, {"(Press ESC to cancel)", "", "off"})
			else
				-- Safely get current orientation name
				local current_orientation = "Unknown"
				pcall(function()
					local mode_data = rotation_modes[current_mode]
					local orientations = mode_data.orientations
					local orientation_names = mode_data.names
					if orientations[current_index] and orientation_names[orientations[current_index]] then
						current_orientation = orientation_names[orientations[current_index]]
					end
				end)
				
				table.insert(menu, {"Layout Rotate Plugin", "", "heading"})
				table.insert(menu, {"", "", ""})
				table.insert(menu, {string.format("Current Key: %s", get_key_name(selected_key)), "", "off"})
				table.insert(menu, {string.format("Current View: %s", current_orientation), "", "off"})
				table.insert(menu, {"", "", ""})
				
				-- Rotation mode selection (custom display order)
				local display_order = {2, 1, 3}  -- Order: 0° and 90° + Flip, 0° and 180° + Flip, All 4 Views
				for _, mode_index in ipairs(display_order) do
					local mode_data = rotation_modes[mode_index]
					local indicator = (mode_index == current_mode) and " [ACTIVE]" or ""
					table.insert(menu, {string.format("Mode: %s%s", mode_data.name, indicator), "", ""})
				end
				
				table.insert(menu, {"", "", ""})
				table.insert(menu, {"Press Enter to change rotation key", "", "lr"})
				table.insert(menu, {"", "", ""})
				table.insert(menu, {"(Settings are saved automatically)", "", "off"})
			end
		end)
		
		if not success then
			-- Return minimal menu on error
			return {
				{"Layout Rotate", "", "heading"},
				{"", "", ""},
				{"Error displaying menu", "", "off"}
			}
		end
		
		return menu
	end
	
	local function menu_callback(index, event)
		-- Wrap in pcall to prevent callback crashes
		local success, result = pcall(function()
			if not plugin_enabled then
				return false
			end
			
			-- Check if machine is valid
			local machine = manager.machine
			if not machine then
				return false
			end
			
			if waiting_for_key then
				-- ESC cancels key binding
				if event == "cancel" then
					waiting_for_key = false
					binding_cooldown = 0
					binding_timeout = 0
					pcall(function()
						if machine and machine.popmessage then
							machine:popmessage("Key binding cancelled")
						end
					end)
					return false  -- Allow ESC to close menu
				end
				return false
			end
			
			-- Menu indices (need to calculate based on dynamic menu)
			-- Items: heading, blank, current key, current view, blank, mode1, mode2, mode3, blank, change key, blank, settings saved
			local mode_start_index = 6
			local change_key_index = 6 + #rotation_modes + 1
			local display_order = {2, 1, 3}  -- Same order as in menu_populate
			
			-- Handle rotation mode selection (indices 6, 7, 8)
			if event == "select" and index >= mode_start_index and index < mode_start_index + #rotation_modes then
				local display_position = index - mode_start_index + 1
				local selected_mode = display_order[display_position]  -- Map display position to actual mode
				if selected_mode ~= current_mode then
					set_rotation_mode(selected_mode)
					pcall(function()
						if machine and machine.popmessage then
							machine:popmessage(string.format("Mode: %s", rotation_modes[selected_mode].name))
						end
					end)
				end
				return true
			end
			
			-- Handle "Press Enter to change rotation key"
			if event == "select" and index == change_key_index then
				waiting_for_key = true
				binding_cooldown = 10  -- Wait 10 frames before detecting keys
				binding_timeout = 0  -- Reset timeout
				pcall(function()
					if machine and machine.popmessage then
						machine:popmessage("Press any key to bind as rotation key (ESC to cancel)")
					end
				end)
				return true
			end
			
			return false
		end)
		
		return success and result or false
	end
	
	emu.register_prestart(start)
	emu.register_frame_done(frame_done)
	emu.register_menu(menu_callback, menu_populate, "Layout Rotate")
end

return exports
