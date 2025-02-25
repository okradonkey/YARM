---@class click_module
local click_module = {
    handlers = {}
}

---@param event EventData.on_gui_click
function click_module.on_gui_click(event)
    -- Automatic binding: if you add handlers.some_button_name, then a click on a GUI element
    -- named `some_button_name` will automatically be routed to the handler
    if click_module.handlers[event.element.name] then
        click_module.handlers[event.element.name](event)
    -- Remaining bindings are for dynamically-named elements:
    elseif event.element.name:starts_with("YARM_filter_") then
        click_module.set_filter(event)
    end
end

---@param event EventData.on_gui_click
function click_module.set_filter(event)
    local new_filter = string.sub(event.element.name, 1 + string.len("YARM_filter_"))
    local player = game.players[event.player_index]
    local player_data = storage.player_data[player.index]

    player_data.ui.active_filter = new_filter

    resmon.ui.update_filter_buttons(player)
    resmon.ui.update_player(player)
end

-----------------------------------------------------------------------------------------------
-- HANDLERS just need to have the same name as the UI element whose click events they handle --
-----------------------------------------------------------------------------------------------
-- Please put only handlers below this line.

-- Just a local alias to make it easier to read
local handlers = click_module.handlers

---@param event EventData.on_gui_click
function handlers.YARM_rename_confirm(event)
    local player = game.players[event.player_index]
    local player_data = storage.player_data[player.index]
    local force_data = storage.force_data[player.force.name]

    local site_index = player_data.renaming_site --[[@as number]] --can't get here without this being set
    local new_name = player.gui.center.YARM_site_rename.new_name.text
    local new_name_length_without_tags =
        string.len(string.gsub(new_name, "%[[^=%]]+=[^=%]]+%]", "123"))
    -- NB: We replace [rich-text=tags] before checking the name length to allow for the tags
    -- to be part of a site name without quickly bumping up against the MAX_SITE_NAME_LENGTH,
    -- which is otherwise quite restrictive.
    -- Pattern explanation:
    -- * one literal `[`: "%["
    -- * 1+ characters that are not `=` or `]`: "[^=%]]+"
    -- * one literal `=`: "="
    -- * 1+ characters that are not `=` or `]`: "[^=%]]+"
    -- * one literal `]`: "%]"

    if new_name_length_without_tags > resmon.ui.MAX_SITE_NAME_LENGTH then
        player.print { 'YARM-err-site-name-too-long', resmon.ui.MAX_SITE_NAME_LENGTH }
        return
    end

    local site = force_data.ore_sites[site_index]
    site.name_tag = new_name

    resmon.ui.update_chart_tag(site)

    player_data.renaming_site = nil
    player.gui.center.YARM_site_rename.destroy()

    resmon.ui.update_force_members(player.force)
end

---@param event EventData.on_gui_click
function handlers.YARM_rename_cancel(event)
    local player = game.players[event.player_index]
    local player_data = storage.player_data[player.index]

    player_data.renaming_site = nil
    player.gui.center.YARM_site_rename.destroy()

    resmon.ui.update_force_members(player.force)
end

---@param event EventData.on_gui_click
function handlers.YARM_delete_site(event)
    local site_name = event.element.tags.site --[[@as string]]
    local player = game.players[event.player_index]
    local force_data = storage.force_data[player.force.name]
    local site = force_data.ore_sites[site_name]

    if site.deleting_since then
        force_data.ore_sites[site_name] = nil

        if site.chart_tag and site.chart_tag.valid then
            site.chart_tag.destroy()
        end
    else
        site.deleting_since = event.tick
    end

    resmon.ui.update_force_members(player.force)
end

---@param event EventData.on_gui_click
function handlers.YARM_rename_site(event)
    local site_index = event.element.tags.site --[[@as number]]
    local player = game.players[event.player_index]
    local player_data = storage.player_data[player.index]
    local site = storage.force_data[player.force.name].ore_sites[site_index]

    if player.gui.center.YARM_site_rename then
        click_module.handlers.YARM_rename_cancel(event)
        return
    end

    player_data.renaming_site = site_index
    local format = player.mod_settings["YARM-display-name-format"].value --[[@as string]]
    local root = player.gui.center.add { type = "frame",
        name = "YARM_site_rename",
        caption = { "YARM-site-rename-title", resmon.locale.site_display_name(site, format) },
        direction = "horizontal" }

    root.add { type = "textfield", name = "new_name" }.text = site.name_tag or ""
    root.add { type = "button", name = "YARM_rename_cancel", caption = { "YARM-site-rename-cancel" }, style = "back_button" }
    root.add { type = "button", name = "YARM_rename_confirm", caption = { "YARM-site-rename-confirm" }, style = "confirm_button" }

    player.opened = root

    resmon.ui.update_force_members(player.force)
end

---@param event EventData.on_gui_click
function handlers.YARM_goto_site(event)
    local site_name = event.element.tags.site --[[@as number]]
    local player = game.players[event.player_index]
    local force_data = storage.force_data[player.force.name]
    local site = force_data.ore_sites[site_name]

    player.set_controller { type = defines.controllers.remote, position = site.center, surface = site.surface }

    resmon.ui.update_force_members(player.force)
end

---One button handler for both the expand_site and expand_site_cancel buttons
---@param event EventData.on_gui_click
function handlers.YARM_expand_site(event)
    local site_name = event.element.tags.site --[[@as number]]
    local player = game.players[event.player_index]
    local player_data = storage.player_data[player.index]
    local force_data = storage.force_data[player.force.name]
    local site = force_data.ore_sites[site_name]
    local are_we_cancelling_expand = site.is_site_expanding

    --[[ we want to submit the site if we're cancelling the expansion (mostly because submitting the
         site cleans up the expansion-related variables on the site) or if we were adding a new site
         and decide to expand an existing one
    --]]
    if are_we_cancelling_expand and player_data.current_site then
        resmon.submit_site(player)
    end

    --[[ this is to handle cancelling an expansion (by clicking the red button) - submitting the site is
         all we need to do in this case ]]
    if are_we_cancelling_expand then
        resmon.ui.update_force_members(player.force)
        return
    end

    resmon.give_selection_tool(player)
    if player.cursor_stack.valid_for_read and player.cursor_stack.name == "yarm-selector-tool" then
        site.is_site_expanding = true
        player_data.current_site = site

        resmon.ui.update_force_members(player.force)
        resmon.start_recreate_overlay_existing_site(player)
    end
end

---Create an event handler for a toggle button that toggles a UI setting.
---@param ui_setting_name string Which `player_data.ui` setting are we toggling?
---@param button_name string Which button reflects the UI setting name?
---@return function # An event handler that can be dispatched when the toggle button is clicked
local function create_toggle_button_method(button_name, ui_setting_name)
    ---@param event EventData.on_gui_click The click event to be handled
    return function(event)
        local player = game.players[event.player_index]
        local player_data = storage.player_data[player.index]
        local root = resmon.ui.get_or_create_hud(player)
        if not root then
            return
        end

        player_data.ui[ui_setting_name] = not player_data.ui[ui_setting_name]
        local setting_is_on = player_data.ui[ui_setting_name]
        resmon.ui.update_button_active_style(root.buttons[button_name], setting_is_on)
        resmon.ui.update_player(player)
    end
end

local toggle_buttons = {
    ["YARM_toggle_bg"] = "enable_hud_background",
    ["YARM_toggle_surfacesplit"] = "split_by_surface",
    ["YARM_toggle_lite"] = "show_compact_columns",
}

for button_name, setting_name in pairs(toggle_buttons) do
    handlers[button_name] = create_toggle_button_method(button_name, setting_name)
end

return click_module
