local Model = {}
Model.__index = Model

function Model.is_finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function Model.new()
    return setmetatable({ frame = 0, monsters = {}, next_sample = {} }, Model)
end

function Model:advance()
    self.frame = self.frame + 1
    for key, entry in pairs(self.next_sample) do
        if self.frame - entry.seen > 120 then
            self:remove(key)
        end
    end
end

function Model:should_sample(key, interval)
    local entry = self.next_sample[key]
    if entry and self.frame < entry.due then
        entry.seen = self.frame
        return false
    end
    self.next_sample[key] = { due = self.frame + interval, seen = self.frame }
    return true
end

function Model:set(key, sample)
    if not Model.is_finite(sample.health) or not Model.is_finite(sample.max_health)
        or sample.max_health <= 0 then
        self.monsters[key] = nil
        error("Vida invalida para " .. tostring(sample.name), 0)
    end
    if type(sample.name) ~= "string" or sample.name == "" then
        self.monsters[key] = nil
        error("Nombre de monstruo no valido", 0)
    end
    local previous = self.monsters[key]
    for _, name in ipairs({ "rage", "paralysis", "stun" }) do
        local state = sample[name]
        local old = previous and previous[name]
        if state then
            state.observed_count = (old and old.observed_count or 0)
                + ((state.active and (not old or not old.active)) and 1 or 0)
        end
    end
    self.monsters[key] = {
        key = key,
        name = sample.name,
        portrait = sample.portrait,
        health = math.max(0, sample.health),
        max_health = sample.max_health,
        ratio = math.max(0, math.min(1, sample.health / sample.max_health)),
        pinned = sample.pinned,
        quest_target = sample.quest_target,
        rage = sample.rage,
        stamina = sample.stamina,
        parts = sample.parts,
        wounds = sample.wounds,
        paralysis = sample.paralysis,
        stun = sample.stun,
    }
end

function Model:remove(key)
    self.monsters[key] = nil
    self.next_sample[key] = nil
    if self.focus_key == key then self.focus_key = nil end
end

function Model:clear()
    self.monsters = {}
    self.next_sample = {}
    self.focus_key = nil
end

function Model:focused()
    local row = self.monsters[self.focus_key]
    if row and row.health > 0 then return row end
    if row then self.focus_key = nil end
end

function Model:rows(limit, show_dead, options)
    options = options or {}
    local rows = {}
    for _, monster in pairs(self.monsters) do
        if (show_dead or monster.health > 0)
            and (not options.only_pinned or monster.pinned == true) then
            rows[#rows + 1] = monster
        end
    end
    table.sort(rows, function(a, b)
        if options.prioritize_quest and (a.quest_target == true) ~= (b.quest_target == true) then
            return a.quest_target == true
        end
        if options.prioritize_pinned and (a.pinned == true) ~= (b.pinned == true) then
            return a.pinned == true
        end
        if options.damaged_first and a.ratio ~= b.ratio then
            return a.ratio < b.ratio
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end)
    while #rows > limit do
        rows[#rows] = nil
    end
    return rows
end

return Model
