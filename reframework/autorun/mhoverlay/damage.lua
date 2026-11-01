local Model = require("mhoverlay/model")

local Damage = {}
Damage.__index = Damage

local function nonnegative(value, label)
    if not Model.is_finite(value) or value < 0 then
        error(label .. " no valido", 0)
    end
    return value
end

function Damage.new()
    return setmetatable({ players = {}, active = false, elapsed = 0, hits = 0 }, Damage)
end

function Damage:clear()
    self.players = {}
    self.session = nil
    self.active = false
    self.elapsed = 0
    self.hits = 0
    self.started = nil
    self.last_time = nil
    self.faints = nil
end

function Damage:update(session, time)
    if session == nil then
        self.active = false
        return
    end
    if type(session) ~= "string" or session == "" then
        error("Identidad de caza no valida", 0)
    end
    nonnegative(time, "Tiempo de caza")
    if self.session ~= session or (not self.active and session:sub(1, 7) ~= "battle:") then
        self:clear()
        self.session = session
    end
    if not self.active then self.last_time = time end
    self.started = self.started or time
    local now = math.max(self.last_time or time, time)
    local delta = now - (self.last_time or now)
    for _, player in pairs(self.players) do
        if player.present and player.in_combat == true then
            player.elapsed = player.elapsed + delta
        end
    end
    self.last_time = now
    self.elapsed = self.last_time - self.started
    self.active = true
end

function Damage:player(player)
    if type(player.id) ~= "string" or player.id == ""
        or type(player.name) ~= "string" or player.name == ""
        or type(player.is_self) ~= "boolean" then
        error("Identidad de cazador no valida", 0)
    end
    local entry = self.players[player.id]
    if not entry then
        entry = { id = player.id, name = player.name, is_self = player.is_self,
            damage = 0, hits = 0, elapsed = 0 }
        self.players[player.id] = entry
    else
        entry.name = player.name
        entry.is_self = player.is_self
    end
    entry.is_support = player.is_support == true
    entry.damage_available = player.damage_available ~= false
    entry.present = true
    return entry
end

function Damage:sync(roster)
    for _, player in pairs(self.players) do
        player.present = false
        player.in_combat = nil
    end
    for _, player in pairs(roster) do
        if player.in_combat ~= nil and type(player.in_combat) ~= "boolean" then
            error("Estado de combate no valido", 0)
        end
        local entry = self:player(player)
        entry.in_combat = player.in_combat
        entry.timing_available = player.in_combat ~= nil
    end
end

function Damage:add(player, amount)
    nonnegative(amount, "Dano final")
    if not self.active or amount == 0 then return end
    local entry = self:player(player)
    nonnegative(entry.damage + amount, "Dano acumulado")
    entry.damage = entry.damage + amount
    entry.hits = entry.hits + 1
    self.hits = self.hits + 1
end

function Damage:rows()
    local rows, total, leader = {}, 0, 0
    for _, player in pairs(self.players) do
        if player.present and player.damage_available then
            total = total + player.damage
            leader = math.max(leader, player.damage)
        end
    end
    nonnegative(total, "Dano del grupo")
    for _, player in pairs(self.players) do
        if player.present then rows[#rows + 1] = {
            id = player.id, name = player.name, is_self = player.is_self,
            is_support = player.is_support, damage_available = player.damage_available,
            damage = player.damage, hits = player.hits,
            elapsed = player.timing_available and player.elapsed or nil,
            in_combat = player.in_combat,
            dps = player.damage_available and player.timing_available and player.elapsed > 0
                and player.damage / player.elapsed or nil,
            share = player.damage_available and total > 0 and player.damage / total or 0,
            ratio = player.damage_available and leader > 0 and player.damage / leader or 0,
        } end
    end
    table.sort(rows, function(a, b)
        if a.damage ~= b.damage then return a.damage > b.damage end
        if a.name ~= b.name then return a.name < b.name end
        return a.id < b.id
    end)
    return rows, total
end

return Damage
