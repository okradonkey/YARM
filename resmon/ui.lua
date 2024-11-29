local get_frame_flow = require("mod-gui").get_frame_flow

---@module "columns"

---@class ui_module
local ui_module = {
    -- NB: filter names should be single words with optional underscores (_)
    -- They will be used for naming GUI elements
    FILTER_NONE = "none",
    FILTER_WARNINGS = "warnings",
    FILTER_ALL = "all",

    -- Sanity: site names aren't allowed to be longer than this, to prevent them
    -- kicking the buttons off the right edge of the screen
    MAX_SITE_NAME_LENGTH = 64, -- I like square numbers
}

---Update the UI of all of a given force's members
---@param force LuaForce|string|integer
function ui_module.update_force_members(force)
    if not force.players then
        force = game.forces[force]
    end
    for _, p in pairs(force.players) do
        resmon.ui.update_player(p)
    end
end

---Update the given player's UI elements (buttons, sites, etc.). Should be called
---periodically (e.g., on_nth_tick) for each player in the game.
---@param player LuaPlayer Whose UI is being updated?
function ui_module.update_player(player)
    local player_data = storage.player_data[player.index]
    local force_data = storage.force_data[player.force.name]

    if not player_data or not force_data or not force_data.ore_sites then
        return -- early init, nothing ready yet
    end

    local root = ui_module.get_or_create_hud(player)
    root.style = player_data.ui.enable_hud_background and "YARM_outer_frame_no_border_bg" or "YARM_outer_frame_no_border"

    local table_data = resmon.sites.create_sites_yatable_data(player)
    resmon.yatable.render(root, table_data, player_data)
end

---Returns the player's HUD root, creating it if necessary
---@param player LuaPlayer Whose HUD is being fetched?
---@return LuaGuiElement The HUD root, including side buttons
function ui_module.get_or_create_hud(player)
    local frame_flow = get_frame_flow(player)
    local root = frame_flow.YARM_root
    if not root then
        root = frame_flow.add { type = "frame",
            name = "YARM_root",
            direction = "horizontal",
            style = "YARM_outer_frame_no_border" }

        local buttons = root.add { type = "flow",
            name = "buttons",
            direction = "vertical",
            style = "YARM_buttons_v" }

        -- TODO: Refactor the filter buttons (should be able to create them dynamically)
        buttons.add { type = "button", name = "YARM_filter_" .. ui_module.FILTER_NONE, style = "YARM_filter_none",
            tooltip = { "YARM-tooltips.filter-none" } }
        buttons.add { type = "button", name = "YARM_filter_" .. ui_module.FILTER_WARNINGS, style = "YARM_filter_warnings",
            tooltip = { "YARM-tooltips.filter-warnings" } }
        buttons.add { type = "button", name = "YARM_filter_" .. ui_module.FILTER_ALL, style = "YARM_filter_all",
            tooltip = { "YARM-tooltips.filter-all" } }
        buttons.add { type = "button", name = "YARM_toggle_bg", style = "YARM_toggle_bg",
            tooltip = { "YARM-tooltips.toggle-bg" } }
        buttons.add { type = "button", name = "YARM_toggle_surfacesplit", style = "YARM_toggle_surfacesplit",
            tooltip = { "YARM-tooltips.toggle-surfacesplit" } }
        buttons.add { type = "button", name = "YARM_toggle_lite", style = "YARM_toggle_lite",
            tooltip = { "YARM-tooltips.toggle-lite" } }

        ui_module.update_filter_buttons(player)
    end

    return root
end

---Set the button style to ON or OFF if necessary. Will not disturb the style if already correct.
---Relies on the fact that toggle button styles have predictable names: the "on" state's name is
---the same as the "off" state, but with "_on" appended.
---@param button LuaGuiElement The button being targeted
---@param should_be_active boolean Should the button be set to ON or OFF?
function ui_module.update_button_active_style(button, should_be_active)
    local style_name = button.style.name
    local is_active_style = style_name:ends_with("_on")

    if is_active_style and not should_be_active then
        button.style = string.sub(style_name, 1, string.len(style_name) - 3) -- trim "_on"
    elseif should_be_active and not is_active_style then
        button.style = style_name .. "_on"
    end
end

---Update the state of the given player's filter buttons: the active filter's button is
---set to active, the rest set to inactive
---@param player LuaPlayer Whose filters are we updating?
function ui_module.update_filter_buttons(player)
    local player_data = storage.player_data[player.index]
    if not player_data.ui.active_filter then
        player_data.ui.active_filter = ui_module.FILTER_WARNINGS
    end

    local root = ui_module.get_or_create_hud(player)
    local active_filter = player_data.ui.active_filter
    for filter_name, _ in pairs(resmon.sites.filters) do
        local button = root.buttons["YARM_filter_" .. filter_name]
        if button and button.valid then
            ui_module.update_button_active_style(button, filter_name == active_filter)
        end
    end
end

function ui_module.color_for_site(site, player)
    local threshold = player.mod_settings["YARM-warn-timeleft"].value * 60
    if site.is_summary then
        threshold = player.mod_settings["YARM-warn-timeleft_totals"].value * 60
    end
    if site.etd_minutes == -1 then
        site.etd_minutes = threshold
    end
    local factor = (threshold == 0 and 1) or (site.etd_minutes / threshold)
    if factor > 1 then
        factor = 1
    end
    local hue = factor / 3
    return ui_module.hsv2rgb(hue, 1, 0.9)
end

---Turn a HSV (hue, saturation, value) color to RGB
function ui_module.hsv2rgb(h, s, v)
    local r, g, b
    local i = math.floor(h * 6);
    local f = h * 6 - i;
    local p = v * (1 - s);
    local q = v * (1 - f * s);
    local t = v * (1 - (1 - f) * s);
    i = i % 6
    if i == 0 then
        r, g, b = v, t, p
    elseif i == 1 then
        r, g, b = q, v, p
    elseif i == 2 then
        r, g, b = p, v, t
    elseif i == 3 then
        r, g, b = p, q, v
    elseif i == 4 then
        r, g, b = t, p, v
    elseif i == 5 then
        r, g, b = v, p, q
    end
    return { r = r, g = g, b = b }
end

---Update the given site's chart tag (map marker) with the current name and ore count
---@param site yarm_site
function ui_module.update_chart_tag(site)
    local is_chart_tag_enabled = settings.global["YARM-map-markers"].value

    if not is_chart_tag_enabled then
        if site.chart_tag and site.chart_tag.valid then
            -- chart tags were just disabled, so remove them from the world
            site.chart_tag.destroy()
            site.chart_tag = nil
        end
        return
    end

    if not site.chart_tag or not site.chart_tag.valid then
        if not site.force or not site.force.valid or not site.surface.valid then
            return
        end

        local chart_tag = {
            position = site.center,
            text = site.name,
        }
        site.chart_tag = site.force.add_chart_tag(site.surface, chart_tag)
        if not site.chart_tag then
            return
        end -- may fail if chunk is not currently charted accd. to @Bilka
    end

    local display_value = resmon.locale.site_amount(site, resmon.locale.format_number_si)
    local ore_prototype = prototypes.entity[site.ore_type]
    site.chart_tag.text =
        string.format('%s - %s %s', site.name, display_value, resmon.locale.get_rich_text_for_products(ore_prototype))
end

---Performs any migrations of UI-related player data for the given player. Should be
---called on_configuration_changed, but should also be safe to be called
---on_init/on_load (just that it's not likely to do anything).
---@param player LuaPlayer Whose data are we updating?
function ui_module.migrate_player_data(player)
    local player_data = storage.player_data[player.index]

    -- v0.12.0: player UI data moved into own namespace
    if not player_data.ui then
        local root = ui_module.get_or_create_hud(player)
        ---@class player_data_ui
        player_data.ui = {
            active_filter = ui_module.FILTER_WARNINGS,
            enable_hud_background = root.style == "YARM_outer_frame_no_border_bg",
            split_by_surface = root.buttons.YARM_toggle_surfacesplit.style.name:ends_with("_on"),
            show_compact_columns = root.buttons.YARM_toggle_lite.style.name:ends_with("_on"),
        }
    end

    if player_data.active_filter then
        player_data.ui.active_filter = player_data.active_filter
        player_data.active_filter = nil ---@diagnostic disable-line: inject-field
    end

    if player_data.ui.site_colors then
        player_data.ui.site_colors = nil ---@diagnostic disable-line: inject-field
    end
end

function ui_module.update_tags(elem, new_tags)
    local tags = elem.tags
    for k, v in pairs(new_tags) do
        tags[k] = v
    end
    elem.tags = tags
end

return ui_module
