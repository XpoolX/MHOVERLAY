local Model = require("mhoverlay/model")

local Config = {}
Config.path = "mhoverlay.json"

local defaults = {
    enabled = true,
    language = "en",
    x = 40,
    y = 180,
    width = 340,
    scale = 1,
    monsters_size = 100,
    focus_size = 100,
    dps_size = 100,
    activities_size = 100,
    max_monsters = 3,
    sample_frames = 6,
    show_dead = false,
    show_status = false,
    show_monster_icons = true,
    show_rage = true,
    show_stamina = true,
    show_pin = true,
    only_pinned = false,
    prioritize_pinned = true,
    prioritize_quest = true,
    horizontal = true,
    damaged_first = false,
    compact = false,
    opacity = 85,
    show_parts = true,
    parts_details = false,
    max_parts = 4,
    show_wounds = true,
    show_dps = true,
    dps_x = 40,
    dps_y = 520,
    dps_width = 440,
    auto_focus = true,
    focus_x = 40,
    focus_y = 180,
    focus_width = 980,
    show_activities = true,
    activities_collection = true,
    activities_ship = true,
    activities_rations = true,
    activities_x = 520,
    activities_y = 520,
    activities_width = 380,
    show_buffs = true,
    buffs_x = 492,
    buffs_y = 520,
    buffs_width = 300,
    buffs_size = 100,
    buffs_names = false,
    show_stats = true,
    stats_x = 1120,
    stats_y = 180,
    stats_width = 630,
    stats_size = 100,
    hide_on_map = true,
    hide_on_dialogue = true,
    hide_on_loading = true,
    auto_layout = true,
    show_mission_preview = true,
    mission_x = 1120,
    mission_y = 650,
    mission_width = 480,
    mission_size = 100,
}

local ranges = {
    x = { 0, 16384 },
    y = { 0, 16384 },
    width = { 200, 800 },
    scale = { 0.5, 2.5 },
    monsters_size = { 50, 150 },
    focus_size = { 50, 150 },
    dps_size = { 50, 150 },
    activities_size = { 50, 150 },
    max_monsters = { 1, 10 },
    sample_frames = { 1, 60 },
    opacity = { 0, 100 },
    max_parts = { 1, 12 },
    dps_x = { 0, 16384 },
    dps_y = { 0, 16384 },
    dps_width = { 300, 800 },
    focus_x = { 0, 16384 },
    focus_y = { 0, 16384 },
    focus_width = { 420, 1600 },
    activities_x = { 0, 16384 },
    activities_y = { 0, 16384 },
    activities_width = { 300, 800 },
    buffs_x = { 0, 16384 },
    buffs_y = { 0, 16384 },
    buffs_width = { 120, 1200 },
    buffs_size = { 50, 150 },
    stats_x = { 0, 16384 },
    stats_y = { 0, 16384 },
    stats_width = { 260, 1600 },
    stats_size = { 50, 150 },
    mission_x = { 0, 16384 },
    mission_y = { 0, 16384 },
    mission_width = { 300, 800 },
    mission_size = { 50, 150 },
}

function Config.defaults()
    local result = {}
    for key, value in pairs(defaults) do
        result[key] = value
    end
    return result
end

function Config.valid_value(key, value)
    local default = defaults[key]
    if default == nil then return false end
    if key == "language" then return value == "en" or value == "es" end
    if type(default) == "boolean" then return type(value) == "boolean" end
    local range = ranges[key]
    if not Model.is_finite(value) or value < range[1] or value > range[2] then return false end
    return key == "scale" or value % 1 == 0
end

function Config.validate(raw)
    if type(raw) ~= "table" then
        return nil, "La configuracion debe ser un objeto JSON"
    end
    local result = Config.defaults()
    for key, default in pairs(defaults) do
        local value = raw[key]
        if value ~= nil then
            if key == "language" then
                if not Config.valid_value(key, value) then
                    return nil, "Invalid language / Idioma no valido: " .. tostring(value)
                end
            elseif type(default) == "boolean" then
                if type(value) ~= "boolean" then
                    return nil, "Valor booleano no valido: " .. key
                end
            else
                local range = ranges[key]
                if not Model.is_finite(value) or value < range[1] or value > range[2] then
                    return nil, "Valor fuera de rango: " .. key
                end
                if key ~= "scale" and value % 1 ~= 0 then
                    return nil, "Se requiere un entero: " .. key
                end
            end
            result[key] = value
        end
    end
    return result
end

function Config.load(files, json_api)
    local matches = files.glob([[^mhoverlay\.json$]])
    if #matches == 0 then
        return Config.defaults()
    end
    local raw = json_api.load_file(Config.path)
    return Config.validate(raw)
end

function Config.save(settings, json_api)
    local validated, err = Config.validate(settings)
    if not validated then
        error(err, 0)
    end
    if not json_api.dump_file(Config.path, validated) then
        error("No se pudo guardar reframework/data/" .. Config.path, 0)
    end
end

return Config
