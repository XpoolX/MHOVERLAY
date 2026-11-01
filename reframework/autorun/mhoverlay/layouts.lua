local Config = require("mhoverlay/config")

-- Position, width and scale of every panel, stored per game resolution in a
-- separate file so mhoverlay.json keeps its flat format.
local Layouts = {}
Layouts.path = "mhoverlay_layouts.json"
Layouts.keys = {
    "scale", "x", "y", "width", "monsters_size",
    "focus_x", "focus_y", "focus_width", "focus_size",
    "dps_x", "dps_y", "dps_width", "dps_size",
    "activities_x", "activities_y", "activities_width", "activities_size",
    "buffs_x", "buffs_y", "buffs_width", "buffs_size",
    "mission_x", "mission_y", "mission_width", "mission_size",
    "stats_x", "stats_y", "stats_width", "stats_size",
}
Layouts.max_profiles = 32

function Layouts.resolution(display)
    if not display or type(display.x) ~= "number" or type(display.y) ~= "number"
        or display.x < 1 or display.y < 1 or display.x > 32768 or display.y > 32768 then
        return nil
    end
    return string.format("%dx%d", math.floor(display.x + 0.5), math.floor(display.y + 0.5))
end

function Layouts.capture(settings)
    local layout = {}
    for _, key in ipairs(Layouts.keys) do layout[key] = settings[key] end
    return layout
end

function Layouts.same(settings, layout)
    for _, key in ipairs(Layouts.keys) do
        if settings[key] ~= layout[key] then return false end
    end
    return true
end

function Layouts.apply(settings, layout)
    for _, key in ipairs(Layouts.keys) do settings[key] = layout[key] end
end

local function valid_layout(layout)
    if type(layout) ~= "table" then return false end
    for _, key in ipairs(Layouts.keys) do
        if not Config.valid_value(key, layout[key]) then return false end
    end
    return true
end

local function migrate_layout(layout)
    if type(layout) ~= "table" then return layout end
    local migrated = {}
    for key, value in pairs(layout) do migrated[key] = value end
    local defaults = Config.defaults()
    for _, key in ipairs({ "mission_x", "mission_y", "mission_width", "mission_size",
        "stats_x", "stats_y", "stats_width", "stats_size" }) do
        if migrated[key] == nil then migrated[key] = defaults[key] end
    end
    return migrated
end

function Layouts.validate(raw)
    if type(raw) ~= "table" or type(raw.profiles) ~= "table" then
        return nil, "El archivo de posiciones debe tener un objeto profiles"
    end
    local profiles, count = {}, 0
    for resolution, layout in pairs(raw.profiles) do
        layout = migrate_layout(layout)
        if type(resolution) ~= "string" or not resolution:match("^%d+x%d+$") then
            return nil, "Resolucion no valida en posiciones: " .. tostring(resolution)
        end
        if not valid_layout(layout) then
            return nil, "Posiciones no validas para " .. resolution
        end
        count = count + 1
        if count > Layouts.max_profiles then
            return nil, "Demasiadas resoluciones guardadas"
        end
        profiles[resolution] = Layouts.capture(layout)
    end
    return profiles
end

function Layouts.load(files, json_api)
    for _, match in ipairs(files.glob([[^mhoverlay_layouts\.json$]])) do
        if match == Layouts.path then
            return Layouts.validate(json_api.load_file(Layouts.path))
        end
    end
    return {}
end

function Layouts.save(profiles, json_api)
    local raw = { profiles = profiles }
    local validated, err = Layouts.validate(raw)
    if not validated then error(err, 0) end
    if not json_api.dump_file(Layouts.path, raw) then
        error("No se pudo guardar reframework/data/" .. Layouts.path, 0)
    end
end

function Layouts.sorted(profiles)
    local list = {}
    for resolution in pairs(profiles) do list[#list + 1] = resolution end
    table.sort(list, function(a, b)
        local ax, ay = a:match("^(%d+)x(%d+)$")
        local bx, by = b:match("^(%d+)x(%d+)$")
        ax, ay, bx, by = tonumber(ax), tonumber(ay), tonumber(bx), tonumber(by)
        if ax ~= bx then return ax > bx end
        return ay > by
    end)
    return list
end

-- Tracks the active resolution. A new size must stay stable for `settle`
-- frames before switching so window resizes do not swap layouts mid-drag.
local Tracker = {}
Tracker.__index = Tracker

function Layouts.tracker(profiles, settle)
    return setmetatable({ profiles = profiles, settle = settle or 30, dirty = false }, Tracker)
end

function Tracker:remember(resolution, settings)
    if not self.profiles[resolution] then
        local count = 0
        for _ in pairs(self.profiles) do count = count + 1 end
        if count >= Layouts.max_profiles then return false end
    end
    self.profiles[resolution] = Layouts.capture(settings)
    self.dirty = true
    return true
end

-- Returns true when settings were replaced by a stored layout.
function Tracker:update(resolution, settings)
    if not resolution then return false end
    if resolution ~= self.active then
        if resolution ~= self.pending then
            self.pending, self.pending_frames = resolution, 0
        end
        self.pending_frames = self.pending_frames + 1
        if self.active and self.pending_frames < self.settle then return false end
        local previous = self.active
        self.active, self.pending = resolution, nil
        if not settings.auto_layout then return false end
        if previous and not self.profiles[previous] then self:remember(previous, settings) end
        local stored = self.profiles[resolution]
        if stored and previous then
            Layouts.apply(settings, stored)
            return true
        end
        if stored and not Layouts.same(settings, stored) then
            -- Startup: mhoverlay.json already holds the latest layout; refresh the profile.
            self:remember(resolution, settings)
        end
        return false
    end
    self.pending = nil
    local stored = self.profiles[resolution]
    if settings.auto_layout and stored and not Layouts.same(settings, stored) then
        self:remember(resolution, settings)
    end
    return false
end

return Layouts
