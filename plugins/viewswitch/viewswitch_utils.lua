-- license:BSD-3-Clause
-- copyright-holders:Vas Crabb

-- Shared utility functions for viewswitch plugin

local lib = {}

function lib:parse_layout_views()
	-- Get the ROM name and artwork paths
	local romname = manager.machine.system.name
	local artpath = manager.machine.options.entries.artpath:value()
	
	local layout_views = {}
	local layout_content = nil
	
	-- Try to find and read the default.lay file
	for path in artpath:gmatch('[^;]+') do
		-- Try direct file first
		local layout_path = path .. '/' .. romname .. '/default.lay'
		local file = io.open(layout_path, 'r')
		if file then
			layout_content = file:read('*all')
			file:close()
			break
		end
		
		-- Try ZIP file (this is trickier - MAME handles ZIP internally)
		-- We can try to use MAME's file loading if available
		local zip_path = path .. '/' .. romname .. '.zip'
		if lfs and lfs.attributes(zip_path) then
			-- If we have lfs, the zip exists, but we can't easily extract from Lua
			-- This would require MAME's internal file handling
			-- For now, we'll skip ZIP files and recommend extracting them
		end
	end
	
	-- Parse the XML content to extract view names
	if layout_content then
		-- Simple XML parsing to find <view name="..."> tags
		for view_name in layout_content:gmatch('<view%s+name%s*=%s*["\']([^"\']+)["\']') do
			table.insert(layout_views, view_name)
		end
		
		-- Also try alternate XML formatting patterns
		for view_name in layout_content:gmatch('<view%s+name%s*=%s*["\']([^"\']*)["\'][^>]*>') do
			-- Avoid duplicates
			local found = false
			for _, existing in ipairs(layout_views) do
				if existing == view_name then
					found = true
					break
				end
			end
			if not found and view_name ~= "" then
				table.insert(layout_views, view_name)
			end
		end
	end
	
	return layout_views
end

function lib:get_layout_view_indices(target, layout_view_names)
	-- Match layout view names to actual view indices in the target
	local view_indices = {}
	local target_view_names = target.view_names
	
	for _, layout_view_name in ipairs(layout_view_names) do
		for i, target_view_name in ipairs(target_view_names) do
			if target_view_name == layout_view_name then
				table.insert(view_indices, {index = i, name = target_view_name})
				break
			end
		end
	end
	
	return view_indices
end

function lib:get_layout_only_views(target)
	-- Get view names from the layout file
	local layout_view_names = self:parse_layout_views()
	
	-- If no layout views found, return empty (will trigger fallback)
	if #layout_view_names == 0 then
		return {}
	end
	
	-- Match them to actual view indices
	local layout_views = self:get_layout_view_indices(target, layout_view_names)
	
	return layout_views
end

function lib:get_filtered_views(target, plugin_settings)
	if plugin_settings.layout_only_mode then
		return self:get_layout_only_views(target)
	else
		-- Return all views in the same format
		local all_views = {}
		local view_names = target.view_names
		for i, view_name in ipairs(view_names) do
			table.insert(all_views, {index = i, name = view_name})
		end
		return all_views
	end
end

return lib