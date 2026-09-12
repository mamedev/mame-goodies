-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb
local exports = {
	name = 'controlspy',
	version = '0.0.1',
	description = 'Control state display plugin',
	license = 'BSD-3-Clause',
	author = { name = 'Vas Crabb' } }

local inputspy = exports

local stop_subscription

function inputspy.startplugin()
	local strformat = string.format
	local inputman, uiman
	local code_value, code_name
	local containers
	local devices
	local deviceperline


	local function start()
		inputman = manager.machine.input
		uiman = manager.ui
		code_value = inputman.code_value
		code_name = inputman.code_name
		containers = { }
		for i, target in pairs(manager.machine.render.targets) do
			if (not target.hidden) and target.ui_container then
				table.insert(containers, { target.index, target.ui_container, 'right' })
			end
		end
		devices = { }
		for name, class in pairs(inputman.device_classes) do
			if class.enabled then
				for i, device in pairs(class.devices) do
					table.insert(devices, device)
				end
			end
		end
		if #devices == 0 then
			devices = nil
		end
	end


	local function stop()
		inputman = nil
		uiman = nil
		code_value = nil
		code_name = nil
		containers = nil
		devices = nil
	end


	local function process_frame_done()
		if devices and not uiman.menu_active then
			local text = ''
			local first
			for i, device in pairs(devices) do
				first = true
				for i, item in pairs(device.items) do
					local code = item.code
					local current = code_value(inputman, code)
					if current ~= 0 then
						if deviceperline and not first then
							text = text .. strformat(', %s = %d', item.name, current)
						else
							first = false
							local fmt = (#text > 0) and '\n%s = %d' or '%s = %d'
							text = text .. strformat(fmt, code_name(inputman, code), current)
						end
					end
				end
			end
			if #text > 0 then
				for index, container in pairs(containers) do
					local align = container[3]
					if align then
						container[2]:draw_text(align, 0, text, 0xffffffff, 0xff000000)
					end
				end
			end
		end
	end


	local function menu_callback(index, event)
		if index == 1 then
			if (event == 'left') or (event == 'right') or (event == 'select') then
				deviceperline = not deviceperline
				return true
			elseif (event == 'clear') and deviceperline then
				deviceperline = false
				return true
			end
		else
			if event == 'clear' then
				containers[index - 1][3] = 'right'
				return true
			elseif event == 'left' then
				if containers[index - 1][3] == 'right' then
					containers[index - 1][3] = 'left'
				else
					containers[index - 1][3] = nil
				end
				return true
			elseif event == 'right' then
				if containers[index - 1][3] == 'left' then
					containers[index - 1][3] = 'right'
				else
					containers[index - 1][3] = 'left'
				end
				return true
			end
		end
	end


	local function menu_populate()
		local result = { { 'Display style', deviceperline and 'One device per line' or 'One item per line', deviceperline and 'l' or 'r' } }
		for i, container in pairs(containers) do
			local align = container[3]
			local name = strformat('Show on screen %d', container[1] - 1)
			local value = (align == 'left') and 'Left' or (align == 'right') and 'Right' or 'Off'
			local flags = (align == 'left') and 'lr' or (align == 'right') and 'l' or 'r'
			table.insert(result, { name, value, flags })
		end
		return result
	end


	emu.register_frame_done(process_frame_done)
	emu.register_prestart(start)
	stop_subscription = emu.add_machine_stop_notifier(stop)
	emu.register_menu(menu_callback, menu_populate, "Control State Display")
end

return exports
