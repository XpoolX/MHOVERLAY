local Wilds = {}
Wilds.__index = Wilds
Wilds.version = "1.0"

local Model = require("mhoverlay/model")
local Portraits = require("mhoverlay/portraits")
local Locale = require("mhoverlay/locale")

local function accessor(definition, name)
    local result = definition:get_method(name)
    if result then
        return function(object) return result:call(object) end
    end
    local property = name:match("^get_(.+)$")
    if property then
        for _, candidate in ipairs({ property, "<" .. property .. ">k__BackingField" }) do
            if definition:get_field(candidate) then
                return function(object) return object:get_field(candidate) end
            end
        end
    end
    error("Falta " .. definition:get_full_name() .. "." .. name
        .. (property and " (tampoco existe el campo " .. property .. ")" or ""), 0)
end

local function get(object, name)
    return accessor(object:get_type_definition(), name)(object)
end

local function field(object, name)
    local definition = object:get_type_definition()
    if not definition:get_field(name) then
        error("Falta " .. definition:get_full_name() .. "." .. name, 0)
    end
    return object:get_field(name)
end

local function required_method(definition, name)
    local result = definition:get_method(name)
    if not result then
        error("Falta " .. definition:get_full_name() .. "." .. name, 0)
    end
    return result
end

local function condition(object, current_name, maximum_name)
    if not object then
        return nil
    end
    local valid = get(object, "get_IsValid")
    if type(valid) ~= "boolean" then
        error("IsValid no es booleano", 0)
    end
    if not valid then
        return nil
    end
    local active = get(object, "get_IsActive")
    if type(active) ~= "boolean" then
        error("IsActive no es booleano", 0)
    end
    local current, maximum
    if active then
        current = get(object, "get_CurrentTimer")
        maximum = get(object, "get_ActivateTime")
    else
        current = get(object, current_name)
        maximum = get(object, maximum_name)
    end
    if not Model.is_finite(current) or not Model.is_finite(maximum) or maximum <= 0 then
        error("Estado de monstruo con valores o limite invalidos", 0)
    end
    return {
        active = active,
        current = math.max(0, current),
        maximum = maximum,
        remaining = active and math.max(0, maximum - current) or nil,
        ratio = math.max(0, math.min(1, active and (maximum - current) / maximum
            or current / maximum)),
    }
end

local function integer(value, label, minimum, maximum)
    if not Model.is_finite(value) or value % 1 ~= 0
        or value < minimum or value > maximum then
        error(label .. " no es un entero valido", 0)
    end
    return value
end

local function boolean(value, label)
    if type(value) ~= "boolean" then
        error(label .. " no es booleano", 0)
    end
    return value
end

local function each_slot(array, visit)
    if not array then return end
    local size = integer(array:get_size(), "Longitud del array", 0, 512)
    for index = 0, size - 1 do
        local entry = array:get_element(index)
        if entry then visit(entry, index) end
    end
end

local function bad_condition(conditions, type_name)
    local result
    local entries = get(conditions, "get__Conditions")
    if not entries then error("Conditions._Conditions no disponible", 0) end
    each_slot(entries, function(entry)
        local definition = entry:get_type_definition()
        for _ = 1, 32 do
            if not definition then return end
            if definition:get_full_name() == type_name then
                local candidate = condition(entry, "get_Value", "get_LimitValue")
                if not candidate then return end
                -- Multiple sources share a type; display one complete snapshot, never a sum.
                local better = not result
                if result then
                    if candidate.active ~= result.active then
                        better = candidate.active
                    else
                        local score = candidate.active and candidate.remaining or candidate.ratio
                        local previous = result.active and result.remaining or result.ratio
                        better = score > previous
                            or (score == previous and (candidate.maximum > result.maximum
                                or (candidate.maximum == result.maximum
                                    and candidate.current > result.current)))
                    end
                end
                if better then result = candidate end
                return
            end
            definition = definition.get_parent_type and definition:get_parent_type() or nil
        end
        error("Jerarquia de estado de monstruo demasiado profunda", 0)
    end)
    return result
end

local function read_parts(context)
    local module = get(context, "get_Parts")
    if not module then return nil end
    local array = get(module, "get_BreakParts")
    if not array then return nil end
    local result = { total = 0, broken = 0, invalid = 0, entries = {} }
    local issues = {}
    each_slot(array, function(part, index)
        local ok, maximum, broken = pcall(function()
            local raw_maximum = get(part, "get_MaxBreakCount")
            if not Model.is_finite(raw_maximum) or raw_maximum % 1 ~= 0
                or raw_maximum < 0 or raw_maximum > 1000 then
                error("MaxBreakCount no valido: " .. tostring(raw_maximum), 0)
            end
            if raw_maximum == 0 then return 0 end
            return raw_maximum, boolean(get(part, "get_IsBreakAll"), "IsBreakAll")
        end)
        if not ok then
            result.invalid = result.invalid + 1
            if #issues < 8 then issues[#issues + 1] = string.format("parte #%d: %s", index, tostring(maximum)) end
            return
        end
        if maximum == 0 then return end
        result.total = result.total + 1
        if broken then result.broken = result.broken + 1 end
        result.entries[#result.entries + 1] = { index = index, broken = broken }
    end)
    return result, issues
end

function Wilds:read_wounds(context)
    local module = get(context, "get_Scar")
    if not module then return nil end
    local array = get(module, "get_ScarParts")
    if not array then return nil end
    if not self.scar_states then
        local definition = self.sdk.find_type_definition("app.cEmModuleScar.cScarParts.STATE")
        if not definition then error("Falta enum app.cEmModuleScar.cScarParts.STATE", 0) end
        local states = {}
        for _, enum_field in ipairs(definition:get_fields()) do
            if enum_field:is_static() then
                local value = enum_field:get_data(nil)
                if Model.is_finite(value) and value % 1 == 0 then
                    states[value] = enum_field:get_name()
                end
            end
        end
        if not next(states) then error("Enum de heridas sin valores legibles", 0) end
        self.scar_states = states
    end
    local result = { states = {}, total = 0 }
    each_slot(array, function(scar)
        local value = get(scar, "get_State")
        local label = self.scar_states[value]
        if not label then error("Estado de herida desconocido: " .. tostring(value), 0) end
        result.total = result.total + 1
        result.states[label] = (result.states[label] or 0) + 1
    end)
    return result
end

function Wilds.new(sdk_api, model, settings, report)
    return setmetatable({
        sdk = sdk_api,
        model = model,
        settings = settings,
        report = report,
        ready = false,
        hook_calls = 0,
        samples = 0,
        feature_failures = {},
    }, Wilds)
end

function Wilds:optional(category, read)
    if self.feature_failures[category] then
        return nil
    end
    local ok, result = pcall(read)
    if not ok then
        self.feature_failures[category] = true
        self.report(category, tostring(result) .. ". Lectura opcional suspendida; HP sigue activo.")
        return nil
    end
    return result
end

function Wilds:retry_features()
    self.feature_failures = {}
    self.scar_states = nil
    self.collector_names = nil
    self.collector_ids = nil
    self.portrait_ids = nil
    self.activities_due = 0
    self:reset_buffs()
    self:reset_stats()
    self.stat_elements = nil
    self.stat_resists = nil
end

function Wilds:install_mission_board()
    self.mission_board_hooks = self.mission_board_hooks or {}
    local definition = self.sdk.find_type_definition("app.GUI050000")
    if not definition then error("Falta app.GUI050000 para la lista de misiones", 0) end
    local function attach(name, callback, owner)
        if self.mission_board_hooks[name] then return end
        local method = required_method(owner or definition, name)
        self.sdk.hook(method, function(args)
            local ok, message = pcall(callback, args)
            if not ok then
                if name ~= "updateQuestDetailWindow" then self.mission_board = nil end
                self.mission_preview = nil
                self.mission_detail = nil
                self.mission_detail_parts = nil
                self.report("lista_misiones", name .. ": " .. tostring(message))
            end
            return self.sdk.PreHookResult.CALL_ORIGINAL
        end, function(retval) return retval end)
        self.mission_board_hooks[name] = true
    end
    local function capture(args)
        self.mission_board = self.sdk.to_managed_object(args[2])
        if not self.mission_board then error("Lista de misiones sin objeto GUI050000", 0) end
        self.report("lista_misiones", nil)
        self.feature_failures.mision_seleccionada = nil
        self.feature_failures.mision_objetivos = nil
    end
    attach("onOpen", function(args)
        self.mission_detail = nil
        self.mission_detail_parts = nil
        capture(args)
    end)
    attach("onClose", function()
        self.mission_board = nil
        self.mission_preview = nil
        self.mission_detail = nil
        self.mission_detail_parts = nil
        self.mission_state = "Lista cerrada"
    end)
    attach("onVisible", capture)
    local parts_type = self.sdk.find_type_definition("app.GUI050000QuestListParts")
    if not parts_type then error("Falta app.GUI050000QuestListParts para los detalles de mision", 0) end
    attach("updateQuestDetailWindow", function(args)
        self.mission_detail = nil
        self.mission_detail_parts = nil
        local parts = self.sdk.to_managed_object(args[2])
        local selected = self.sdk.to_managed_object(args[3])
        if not parts then error("Actualizacion de detalles sin lista de misiones", 0) end
        self.mission_detail_parts = parts
        self.mission_detail = selected
        self.report("lista_misiones", nil)
    end, parts_type)
end

local function call(object, name, ...)
    return required_method(object:get_type_definition(), name):call(object, ...)
end

local consumables = {
    { key = "DashJuice", name = "Zumo de poder", icon = "dash_juice", color = 0xFF70CDE8, flagged = true },
    { key = "Immunizer", name = "Inmunizador", icon = "immunizer", color = 0xFF69BE88, flagged = true },
    { key = "HotDrink", name = "Bebida caliente", icon = "hot_drink", color = 0xFF73AAF2, flagged = true },
    { key = "CoolerDrink", name = "Bebida fria", icon = "cool_drink", color = 0xFFF2C877, flagged = true },
    { key = "Kairiki", name = "Semilla de poder", icon = "might_seed", color = 0xFF788EF2 },
    { key = "Kairiki_G", name = "Pildora de poder", icon = "pill", color = 0xFF788EF2 },
    { key = "KijinPowder", name = "Polvo de demonio", icon = "demon_powder", color = 0xFF788EF2 },
    { key = "KijinAmmo", name = "Municion demonio", icon = "ammo", color = 0xFF788EF2 },
    { key = "Nintai", name = "Semilla armadura", icon = "adamant_seed", color = 0xFFF2C877 },
    { key = "Nintai_G", name = "Pildora armadura", icon = "pill", color = 0xFFF2C877 },
    { key = "KoukaPowder", name = "Polvo de cascara", icon = "hardshell_powder", color = 0xFFF2C877 },
    { key = "KoukaAmmo", name = "Municion armadura", icon = "ammo", color = 0xFFF2C877 },
    { key = "KijinDrink", name = "Droga demoniaca", icon = "demondrug", color = 0xFF788EF2,
        flagged = true, active_label = true },
    { key = "KijinDrink_G", name = "Megadroga demoniaca", icon = "mega_drug", color = 0xFF788EF2,
        flagged = true, active_label = true },
    { key = "KoukaDrink", name = "Piel de armadura", icon = "armorskin", color = 0xFFF2C877,
        flagged = true, active_label = true },
    { key = "KoukaDrink_G", name = "Megapiel de armadura", icon = "mega_drug", color = 0xFFF2C877,
        flagged = true, active_label = true },
    { key = "PickUpStamina", name = "Vigor ambiental", icon = "dash_juice", color = 0xFF70CDE8 },
    { key = "RevivalDrink", name = "Recuperacion (SDK)", icon = "immunizer", color = 0xFFDDA9B8,
        flag = "get_IsActiveRevivalDrink", untimed = true },
}

function Wilds.demo_buffs()
    local rows = {}
    for index, entry in ipairs({ { 13, 0 }, { 14, 1200 }, { 6, 20 }, { 9, 156 }, { 7, 252 }, { 1, 156 } }) do
        local spec = consumables[entry[1]]
        rows[index] = { id = spec.key, name = spec.name, icon = spec.icon,
            color = spec.color, remaining = entry[2] > 0 and entry[2] or nil }
    end
    return rows
end

function Wilds:reset_buffs(reason)
    self.buffs = nil
    self.buffs_owner = nil
    self.buffs_due = 0
    self.buffs_state = reason or "Pendiente de lectura"
end

function Wilds:poll_buffs()
    if not self.settings.enabled or not self.settings.show_buffs then
        self:reset_buffs("Panel desactivado")
        return
    end
    local character = self:optional("buffs", function()
        local players = self.sdk.get_managed_singleton("app.PlayerManager")
        local info = players and call(players, "getMasterPlayer")
        local hunter = info and get(info, "get_Character")
        if not hunter then self.buffs_state = "Sin personaje local cargado"; return end
        local ga = self.sdk.find_type_definition("app.GA")
        if not ga then error("Falta app.GA para verificar la carga de buffs", 0) end
        local save = required_method(ga, "get_Save"):call(nil)
        if not save or boolean(get(save, "get_IsShowLoading"), "Carga de buffs") then
            self.buffs_state = "Carga en curso / sin partida"
            return
        end
        return hunter
    end)
    if not character then
        self:reset_buffs(self.feature_failures.buffs and "Error de lectura: consulta los avisos" or self.buffs_state)
        return
    end
    local owner = tostring(character:get_address())
    if owner ~= self.buffs_owner then
        self:reset_buffs()
        self.buffs_owner = owner
    end
    if self.model.frame < self.buffs_due then return end
    self.buffs_due = self.model.frame + self.settings.sample_frames
    self.buffs = self:optional("buffs", function()
        local status = get(character, "get_HunterStatus")
        local items = status and get(status, "get_ItemBuff")
        if not items then error("HunterStatus.ItemBuff no disponible", 0) end
        local rows = {}
        for _, spec in ipairs(consumables) do
            local row = self:optional("buff_" .. spec.key, function()
                if spec.flag or spec.flagged then
                    if not boolean(get(items, spec.flag or ("get_Is" .. spec.key .. "_On")),
                        spec.key .. " activo") then return end
                end
                local remaining
                if not spec.untimed then
                    remaining = get(items, "get_" .. spec.key .. "_Timer")
                    if not Model.is_finite(remaining) or (spec.flagged and remaining < 0) then
                        error(spec.key .. " con tiempo no valido: " .. tostring(remaining), 0)
                    end
                    if not spec.flagged and remaining <= 0 then return end
                    if spec.active_label and remaining == 0 then remaining = nil end
                end
                return { id = spec.key, name = spec.name, icon = spec.icon,
                    color = spec.color, remaining = remaining }
            end)
            if row then rows[#rows + 1] = row end
        end
        return rows
    end)
    local failed = self.feature_failures.buffs
    for _, spec in ipairs(consumables) do failed = failed or self.feature_failures["buff_" .. spec.key] end
    self.buffs_state = failed and "Lectura incompleta: consulta los avisos"
        or (#self.buffs == 0 and "Sin consumibles activos" or "Leyendo consumibles activos")
end

local stat_elements = {
    { "NONE", "Sin elemento" }, { "FIRE", "Fuego" }, { "WATER", "Agua" },
    { "ELEC", "Rayo" }, { "ICE", "Hielo" }, { "DRAGON", "Dragon" },
    { "POISON", "Veneno" }, { "PARALYSE", "Paralisis" }, { "SLEEP", "Sueno" },
    { "BLAST", "Nitro" },
}

local function stat_enum(sdk_api, name, entries)
    local definition = sdk_api.find_type_definition(name)
    if not definition then error("Falta " .. name, 0) end
    local values = {}
    for _, entry in ipairs(entries) do
        local member = definition:get_field(entry[1])
        if not member then error("Falta " .. name .. "." .. entry[1], 0) end
        values[entry[1]] = integer(member:get_data(nil), name .. "." .. entry[1], -2147483648, 2147483647)
    end
    return values
end

local function stat_number(value, name, signed)
    if not Model.is_finite(value) or (not signed and value < 0) then
        error(name .. " no valido: " .. tostring(value), 0)
    end
    return value
end

function Wilds.demo_stats()
    return { attack = 245, defence = 468, affinity = 25,
        element = { id = "FIRE", name = "Fuego", value = 32 },
        resists = { FIRE = 15, WATER = -5, ELEC = 8, ICE = -10, DRAGON = 3 } }
end

function Wilds:reset_stats(reason)
    self.stats, self.stats_owner, self.stats_due = nil, nil, 0
    self.stats_state = reason or "Pendiente de lectura"
end

function Wilds:poll_stats()
    if not self.settings.enabled or not self.settings.show_stats then
        self:reset_stats("Panel desactivado")
        return
    end
    local character = self:optional("estadisticas", function()
        local players = self.sdk.get_managed_singleton("app.PlayerManager")
        local info = players and call(players, "getMasterPlayer")
        local hunter = info and get(info, "get_Character")
        if not hunter then self.stats_state = "Sin personaje local cargado"; return end
        local ga = self.sdk.find_type_definition("app.GA")
        if not ga then error("Falta app.GA para verificar la carga de estadisticas", 0) end
        local save = required_method(ga, "get_Save"):call(nil)
        if not save or boolean(get(save, "get_IsShowLoading"), "Carga de estadisticas") then
            self.stats_state = "Carga en curso / sin partida"
            return
        end
        return hunter
    end)
    if not character then
        self:reset_stats(self.feature_failures.estadisticas
            and "Error de lectura: consulta los avisos" or self.stats_state)
        return
    end
    local owner = tostring(character:get_address())
    if owner ~= self.stats_owner then
        self:reset_stats()
        self.stats_owner = owner
    end
    if self.model.frame < self.stats_due then return end
    self.stats_due = self.model.frame + self.settings.sample_frames
    self.stats = self:optional("estadisticas", function()
        local status = get(character, "get_HunterStatus")
        if not status then return end
        if not boolean(get(status, "get_IsSetUp"), "HunterStatus preparado") then return end
        local snapshot = { resists = {} }
        local function read(key, component, getter, signed)
            return self:optional("stat_" .. key, function()
                local data = get(status, component)
                if not data then error(component .. " no disponible", 0) end
                return stat_number(get(data, getter), key, signed)
            end)
        end
        snapshot.attack = read("attack", "get_AttackPower", "get_CurrentAttackPower")
        snapshot.defence = read("defence", "get_DefencePower", "get_CurrentDefencePower")
        snapshot.affinity = read("affinity", "get_CriticalRate", "get_CurrentCriticalRate", true)
        snapshot.element = self:optional("stat_element", function()
            local attack = get(status, "get_AttackPower")
            if not attack then error("AttackPower no disponible", 0) end
            self.stat_elements = self.stat_elements or stat_enum(self.sdk, "app.WeaponDef.ATTR", stat_elements)
            local attr = get(attack, "get_AttibuteType")
            local label, id
            for _, spec in ipairs(stat_elements) do
                if self.stat_elements[spec[1]] == attr then label, id = spec[2], spec[1]; break end
            end
            if not label then error("Atributo de arma desconocido: " .. tostring(attr), 0) end
            return { id = id, name = label, value = stat_number(get(attack, "get_CurrentAttrPower"), "Elemento") }
        end)
        for index = 2, 6 do
            local spec = stat_elements[index]
            snapshot.resists[spec[1]] = self:optional("stat_" .. spec[1], function()
                local defence = get(status, "get_DefencePower")
                if not defence then error("DefencePower no disponible", 0) end
                self.stat_resists = self.stat_resists
                    or stat_enum(self.sdk, "app.HitDef.ATTR", { table.unpack(stat_elements, 2, 6) })
                return stat_number(call(defence, "getCurrentElementResist", self.stat_resists[spec[1]]),
                    "Resistencia " .. spec[2], true)
            end)
        end
        return snapshot
    end)
    local partial = self.feature_failures.estadisticas
    for category in pairs(self.feature_failures) do
        if category:match("^stat_") then partial = true end
    end
    self.stats_state = partial and "Lectura incompleta: consulta los avisos"
        or (self.stats and "Leyendo valores actuales" or "Esperando HunterStatus")
    if self.stats then self.stats.partial = partial end
end

function Wilds:collector_name(fixed_id)
    local name = self:optional("nombres_actividades", function()
        self.collector_names = self.collector_names or {}
        if not self.collector_ids then
            local fixed = self.sdk.find_type_definition("app.NpcDef.ID_Fixed")
            local ids = self.sdk.find_type_definition("app.NpcDef.ID")
            local util = self.sdk.find_type_definition("app.NpcUtil")
            if not fixed or not ids or not util then error("Faltan tipos para nombres de recolectores", 0) end
            local resolved = {}
            for _, member in ipairs(fixed:get_fields()) do
                if member:is_static() then
                    local id_field = ids:get_field(member:get_name())
                    if id_field then
                        local value = member:get_data(nil)
                        if Model.is_finite(value) then
                            resolved[value] = integer(id_field:get_data(nil), "ID de NPC", -2147483648, 2147483647)
                        end
                    end
                end
            end
            self.collector_ids = resolved
        end
        local label = self.collector_names[fixed_id]
        if not label then
            local id = self.collector_ids[fixed_id]
            if id == nil then error("Identidad desconocida para recolector #" .. fixed_id, 0) end
            label = required_method(self.sdk.find_type_definition("app.NpcUtil"), "getNpcName"):call(nil, id)
            if type(label) ~= "string" or label == "" then
                error("Nombre no disponible para recolector #" .. fixed_id, 0)
            end
            self.collector_names[fixed_id] = label
        end
        return label
    end)
    return name or Locale.t("Recolector #%s", self.settings.language, fixed_id)
end

function Wilds:read_collection(save)
    local collection = get(save, "get_Collection")
    if not collection then error("Recoleccion de materiales no disponible", 0) end
    local entries = get(collection, "get_CollectionNPC")
    if not entries then error("Lista de recolectores no disponible", 0) end
    local definition = self.sdk.find_type_definition("app.savedata.cCollectionNPCParam")
    local initial = definition and definition:get_field("NPCFixedId_INIT_VALUE")
    if not initial then error("Falta NPCFixedId_INIT_VALUE para filtrar recolectores sin asignar", 0) end
    local unassigned = integer(initial:get_data(nil), "Identidad de recolector sin asignar", -2147483648, 2147483647)
    local collectors, seen = {}, {}
    each_slot(entries, function(npc)
        local id = integer(get(npc, "get_NPCFixedId"), "Identidad de recolector", -2147483648, 2147483647)
        if id == unassigned then return end
        local items = get(npc, "get_CollectionItem")
        if not items then error("Deposito de recoleccion no disponible", 0) end
        local capacity = integer(items:get_size(), "Espacios del deposito", 0, 512)
        local occupied, total = 0, 0
        each_slot(items, function(item)
            local count = integer(get(item, "get_Num"), "Cantidad de material", 0, 32767)
            if count > 0 then
                occupied = occupied + 1
                total = total + count
            end
        end)
        local available = boolean(call(npc, "isEnableAccept"), "Recepcion de materiales disponible")
        if not available and total == 0 then return end
        if seen[id] then error("Recolector repetido: " .. id, 0) end
        seen[id] = true
        if #collectors >= 16 then error("Demasiados recolectores", 0) end
        collectors[#collectors + 1] = { id = id, name = self:collector_name(id),
            count = total, occupied = occupied, capacity = capacity,
            full = boolean(call(npc, "isFullCollectionItems"), "Deposito lleno"),
            available = available }
    end)
    table.sort(collectors, function(a, b) return a.id < b.id end)
    return { collectors = collectors }
end

function Wilds:read_ship(facilities, save)
    local ship = get(facilities, "get_Ship")
    if not ship then error("Barco de suministros no disponible", 0) end
    local opened = boolean(get(ship, "get_IsShipOpened"), "Barco desbloqueado")
    if not opened then return { opened = false } end
    local in_port = boolean(call(ship, "isInPort"), "Barco en puerto")
    local param = get(save, "get_Ship")
    if not param then error("Estado del barco no disponible", 0) end
    return { opened = true, in_port = in_port,
        days = integer(get(param, "get_DayCount"), "Dias del barco", 0, 255) }
end

function Wilds:read_rations(facilities)
    local dining = get(facilities, "get_Dining")
    if not dining then error("Centro de raciones no disponible", 0) end
    local data = get(dining, "get__SettingData")
    if not data then error("Ajustes de raciones no disponibles", 0) end
    local limit = integer(get(data, "get_SupplyFoodMax"), "Capacidad de raciones", 1, 32767)
    local total = integer(call(dining, "getSuppliableFoodNum"), "Raciones totales", 0, 2147483647)
    local extra = integer(call(dining, "getSuppliableFoodNumEx"), "Raciones extra", 0, total)
    -- The runtime total includes extra supplies; SupplyFoodMax only limits ordinary supplies.
    local count = total - extra
    if count > limit then
        error(string.format("Raciones normales fuera de capacidad: total=%d, extra=%d, normales=%d, limite=%d",
            total, extra, count, limit), 0)
    end
    return { count = count, capacity = limit, full = count == limit }
end

-- Keeps overlays hidden across the short gap between an NPC conversation and
-- the facility menu it opens (and back), so they do not flash in between.
local NPC_HOLD_FRAMES = 45

local conversation_category_names = { "TALK", "EVENT_TALK", "SELECT", "EVENT", "DEMO" }

function Wilds:conversation_categories()
    if self.dialogue_categories then return self.dialogue_categories end
    local definition = self.sdk.find_type_definition("app.GUI020400.SUBTITLES_CATEGORY")
    if not definition then error("Falta app.GUI020400.SUBTITLES_CATEGORY", 0) end
    local categories = {}
    for _, name in ipairs(conversation_category_names) do
        local entry = definition:get_field(name)
        if not entry then error("Falta SUBTITLES_CATEGORY." .. name, 0) end
        local value = integer(entry:get_data(nil), "SUBTITLES_CATEGORY." .. name, 0, 2147483647)
        categories[value] = true
    end
    self.dialogue_categories = categories
    return categories
end

-- Temporary per-frame hiding during loading, the map, full-screen menus or a
-- real conversation. Never touches settings or collected data; a
-- detection error disables only that detector, so overlays stay visible.
function Wilds:poll_obstruction()
    self.obstruction = nil
    if not self.settings.enabled then return end
    if self.settings.hide_on_loading then
        local scene = self:optional("ocultar_carga_escena", function()
            local flow = self.sdk.get_managed_singleton("app.GameFlowManager")
            return flow and boolean(get(flow, "get_Loading"), "GameFlowManager.Loading")
        end)
        local travel = self:optional("ocultar_carga_viaje", function()
            local gui = self.sdk.get_managed_singleton("app.GUIManager")
            local loading = gui and get(gui, "get_JanctionLoadingController")
            return loading and boolean(get(loading, "get_IsLoading"), "JanctionLoadingController.IsLoading")
        end)
        if scene or travel then
            self.obstruction = "Carga de escena"
            return
        end
    end
    if self.settings.hide_on_map then
        local screen = self:optional("ocultar_mapa", function()
            local gui = self.sdk.get_managed_singleton("app.GUIManager")
            if not gui then return nil end
            local map = get(gui, "get_MAP3D")
            local front = map and get(map, "get_GUIFront")
            local controller = front and get(front, "get_GUIController")
            local component = controller and get(controller, "get_Component")
            if component and boolean(get(component, "get_Enabled"), "Mapa Enabled") then
                return "Mapa abierto"
            end
            if boolean(call(gui, "isOpenFullScreenUI"), "isOpenFullScreenUI") then
                return "Menu a pantalla completa"
            end
        end)
        if screen then
            if screen == "Menu a pantalla completa" and self.mission_preview then
                self.obstruction = "Vista previa de mision"
            else
                self.obstruction = screen
                return
            end
        end
    end
    if self.settings.hide_on_dialogue then
        local talking = self:optional("ocultar_conversacion", function()
            local dialogue = self.sdk.get_managed_singleton("app.DialogueManager")
            if not dialogue then return false end
            local subtitles = get(dialogue, "get_SubtitleManager")
            if subtitles and boolean(get(subtitles, "get_IsChoiceGUIVisible"), "IsChoiceGUIVisible") then
                return true
            end
            if not boolean(get(dialogue, "get_IsTalking"), "IsTalking") then return false end
            local gui = subtitles and get(subtitles, "get__SubtitlesGUI")
            if not gui then return false end
            local category = integer(field(gui, "_SubtitlesCategory"), "SubtitlesCategory", 0, 2147483647)
            return self:conversation_categories()[category] == true
        end)
        local menu = self:optional("ocultar_menu_npc", function()
            local gui = self.sdk.get_managed_singleton("app.GUIManager")
            if not gui then return false end
            if boolean(call(gui, "isNpcMenuOpen"), "isNpcMenuOpen") then return true end
            local facility = required_method(gui:get_type_definition(), "isActiveFacilityMenu(System.Boolean)")
            return boolean(facility:call(gui, false), "isActiveFacilityMenu")
                or boolean(facility:call(gui, true), "isActiveFacilityMenu")
        end)
        if talking or menu then
            self.npc_hold_until = self.model.frame + NPC_HOLD_FRAMES
            self.npc_reason = menu and "Menu de NPC/instalacion" or "Conversacion"
        end
        -- The quest counter is itself an NPC menu; only its preview is exempt.
        if self.mission_preview and not talking then
            self.obstruction = "Vista previa de mision"
            return
        end
        if self.model.frame < (self.npc_hold_until or 0) then
            self.obstruction = self.npc_reason
        end
    else
        self.npc_hold_until = nil
    end
end

-- After a quest, activities and the quest DPS summary wait until the hunter is
-- back in a village/hub (HunterCharacter.IsInLifeArea) instead of covering the
-- in-game quest result screens.
function Wilds:poll_return()
    if not self.settings.enabled then
        self.awaiting_village = false
        return
    end
    local state = self:optional("regreso_poblado", function()
        local mission = self.sdk.get_managed_singleton("app.MissionManager")
        if not mission then return nil end
        if boolean(get(mission, "get_IsPlayingQuest"), "IsPlayingQuest") then return "quest" end
        local players = self.sdk.get_managed_singleton("app.PlayerManager")
        local info = players and call(players, "getMasterPlayer")
        local character = info and get(info, "get_Character")
        if not character then return nil end
        return boolean(get(character, "get_IsInLifeArea"), "IsInLifeArea") and "village" or "field"
    end)
    if self.feature_failures.regreso_poblado then
        self.awaiting_village = false
    elseif state == "quest" then
        self.awaiting_village = true
    elseif state == "village" then
        self.awaiting_village = false
    end
end

function Wilds:reset_activities()
    self.activities = nil
    self.activities_visible = false
    self.activities_due = 0
end

function Wilds:poll_activities()
    if not self.settings.enabled or not self.settings.show_activities
        or not (self.settings.activities_collection or self.settings.activities_ship
            or self.settings.activities_rations) or self.awaiting_village then
        self:reset_activities()
        return
    end
    local context = self:optional("actividades", function()
        local mission = self.sdk.get_managed_singleton("app.MissionManager")
        if not mission or boolean(get(mission, "get_IsPlayingQuest"), "IsPlayingQuest") then return end
        local players = self.sdk.get_managed_singleton("app.PlayerManager")
        local info = players and call(players, "getMasterPlayer")
        if not info or not get(info, "get_Character") then return end
        local ga = self.sdk.find_type_definition("app.GA")
        if not ga then error("Falta app.GA para actividades del poblado", 0) end
        local save_manager = required_method(ga, "get_Save"):call(nil)
        if not save_manager or boolean(get(save_manager, "get_IsShowLoading"), "Carga de partida") then return end
        local save = save_manager and call(save_manager, "getCurrentUserSaveData")
        if not save then return end
        local facilities = required_method(ga, "get_Facility"):call(nil)
        if not facilities then return end
        return { save = save, facilities = facilities }
    end)
    if not context then self:reset_activities(); return end
    local save_key = tostring(context.save:get_address())
    if self.activities_save ~= save_key then
        self.activities_save = save_key
        self.activities_due = 0
        self.collector_names = nil
    end
    if self.model.frame < (self.activities_due or 0) then return end
    self.activities_due = self.model.frame + self.settings.sample_frames
    local snapshot = {}
    if self.settings.activities_collection then
        snapshot.collection = self:optional("recoleccion", function() return self:read_collection(context.save) end)
    end
    if self.settings.activities_ship then
        snapshot.ship = self:optional("barco", function() return self:read_ship(context.facilities, context.save) end)
    end
    if self.settings.activities_rations then
        snapshot.rations = self:optional("raciones", function() return self:read_rations(context.facilities) end)
    end
    self.activities = snapshot
    self.activities_visible = true
end

function Wilds:reset_damage()
    self.damage:clear()
    self.damage_pending = {}
    self.damage_players = {}
    self.damage_due = 0
    self.unassigned_hits = 0
    self.damage_visible = false
    self.damage_mode = nil
    self.support_unbound = 0
    self.damage_result_until = nil
    self.damage_result_clock = nil
end

function Wilds:retain_damage_result()
    if not self.damage.session then return end
    if self.awaiting_village and self.damage.session:sub(1, 6) == "quest:" then
        self.damage_visible = false
        self.damage_mode = "result"
        return
    end
    self:optional("resultado_dps", function()
        local application = self.sdk.find_type_definition("via.Application")
        if not application then error("Falta via.Application para retener resultados DPS", 0) end
        local now = required_method(application, "get_UpTimeSecond"):call(nil)
        if not Model.is_finite(now) or now < 0 then error("Reloj de resultados DPS no valido", 0) end
        now = math.max(now, self.damage_result_clock or now)
        self.damage_result_clock = now
        self.damage_result_until = self.damage_result_until or (now + 120)
        self.damage_visible = now < self.damage_result_until
        if self.damage_visible then self.damage_mode = "result" end
    end)
end

function Wilds:read_quest_faints(director)
    self.damage.faints = nil
    self.damage.faints = self:optional("muertes", function()
        if not director then
            local manager = self.sdk.get_managed_singleton("app.MissionManager")
            director = manager and get(manager, "get_QuestDirector")
        end
        if not director then error("Sin QuestDirector para leer desmayos", 0) end
        local param = get(director, "get_Param")
        if not param or "quest:" .. tostring(param:get_address()) ~= self.damage.session then
            error("Los desmayos no pertenecen a la mision registrada", 0)
        end
        local encoded = field(director, "QuestPlDieCount")
        if not encoded then error("QuestPlDieCount no disponible", 0) end
        local value, divisor = field(encoded, "v"), field(encoded, "m")
        if not Model.is_finite(value) or not Model.is_finite(divisor) or divisor == 0 then
            error("QuestPlDieCount con valor/divisor no valido", 0)
        end
        local decoded = value / divisor
        if not Model.is_finite(decoded) or decoded < 0 then
            error("Contador de desmayos no valido", 0)
        end
        local count = integer(math.floor(decoded), "Desmayos de mision", 0, 2147483647)
        local data = get(director, "get_QuestData")
        if not data then error("Sin QuestData para leer el limite de desmayos", 0) end
        local limit = integer(call(data, "getQuestLife"), "Limite de desmayos", 0, 2147483647)
        return { count = count, limit = limit }
    end)
end

function Wilds:reset_focus()
    self.focus_owner = nil
    self.focus_combat = false
    self.focus_pending = {}
    self.model.focus_key = nil
    self.focus_due = 0
end

function Wilds:poll_focus()
    if not self.settings.enabled or not self.settings.auto_focus or self.feature_failures.foco then
        self:reset_focus()
        return
    end
    if self.model.frame < (self.focus_due or 0) then return end
    self.focus_due = self.model.frame + self.settings.sample_frames
    self.focus_pending = self.focus_pending or {}
    for key, pending in pairs(self.focus_pending) do
        if self.model.frame - pending.frame > 2 then self.focus_pending[key] = nil end
    end
    local owner = self:optional("combate_foco", function()
        local manager = self.sdk.get_managed_singleton("app.PlayerManager")
        if not manager then return nil end
        local info = call(manager, "getMasterPlayer")
        local character = info and get(info, "get_Character")
        if not character or not boolean(get(character, "get_IsCombat"), "IsCombat") then return nil end
        local game_object = get(character, "get_GameObject")
        if not game_object then return nil end
        local address = game_object:get_address()
        if not address or address == 0 then error("Cazador sin GameObject para foco", 0) end
        return tostring(address)
    end)
    if owner ~= self.focus_owner or not owner then
        self.model.focus_key = nil
        self.focus_pending = {}
    end
    self.focus_owner = owner
    self.focus_combat = owner ~= nil
end

local function hit_enemy(source, hit)
    local target = get(hit, "get_DamageOwner")
    if not target then return end
    local enemy = call(target, "getComponent(System.Type)", source.sdk.typeof("app.EnemyCharacter"))
    if not enemy then return end
    local holder = field(enemy, "_Context")
    local context = holder and field(holder, "_Em")
    if not context or not boolean(get(context, "get_IsBoss"), "IsBoss") then return end
    local health = get(enemy, "get_HealthMgr")
    if not health or boolean(get(health, "get_IsDead"), "IsDead") then return end
    return target, enemy
end

function Wilds:capture_focus(hit)
    if not self.focus_combat or not hit then return end
    local key = tostring(hit:get_address())
    self.focus_pending[key] = nil
    local owner = call(hit, "getActualAttackOwner")
    if not owner or tostring(owner:get_address()) ~= self.focus_owner then return end
    local target, enemy = hit_enemy(self, hit)
    if not target then return end
    local count = 0
    for _ in pairs(self.focus_pending) do count = count + 1 end
    if count >= 256 then error("Demasiados impactos de foco pendientes", 0) end
    self.focus_pending[key] = { frame = self.model.frame,
        target = tostring(target:get_address()), enemy = tostring(enemy:get_address()) }
end

function Wilds:finish_focus(calc, hit)
    if not self.focus_combat or not hit then return end
    local key = tostring(hit:get_address())
    local pending = self.focus_pending[key]
    self.focus_pending[key] = nil
    if not pending or self.model.frame - pending.frame > 2 then return end
    local target = get(hit, "get_DamageOwner")
    if not target or tostring(target:get_address()) ~= pending.target then
        error("Impacto de foco con destino distinto al capturado", 0)
    end
    if not calc then error("Falta calculo de dano para foco", 0) end
    local amount = field(calc, "FinalDamage")
    if not Model.is_finite(amount) or amount < 0 then error("Dano de foco no valido", 0) end
    if amount > 0 then self.model.focus_key = pending.enemy end
end

local function iterator_method(definition, name)
    for _ = 1, 32 do
        if not definition then return nil end
        local method = definition:get_method(name)
        if method then return method end
        if definition.get_methods then
            for _, candidate in ipairs(definition:get_methods()) do
                local candidate_name = candidate:get_name()
                if candidate_name:sub(-#name - 1) == "." .. name then
                    return candidate
                end
            end
        end
        definition = definition.get_parent_type and definition:get_parent_type() or nil
    end
    error("Jerarquia del iterador del grupo demasiado profunda", 0)
end

local function iterate_party(iterator, visit, maximum)
    if not iterator then error("Enumerador del grupo no disponible", 0) end
    local definition = iterator:get_type_definition()
    local move = iterator_method(definition, "MoveNext")
    local current = iterator_method(definition, "get_Current")
    local dispose = iterator_method(definition, "Dispose")
    local ok, message = pcall(function()
        if not move or not current then
            error("Iterador del grupo no compatible: " .. definition:get_full_name()
                .. " (faltan MoveNext/get_Current)", 0)
        end
        local count = 0
        while boolean(move:call(iterator), "MoveNext del grupo") do
            count = integer(count + 1, "Tamano del grupo", 0, maximum)
            visit(current:call(iterator))
        end
    end)
    local disposed, dispose_error = true, nil
    if dispose then disposed, dispose_error = pcall(dispose.call, dispose, iterator) end
    if not ok then
        error(tostring(message) .. (not disposed
            and ("; fallo al cerrar iterador: " .. tostring(dispose_error)) or ""), 0)
    end
    if not disposed then error("Fallo al cerrar iterador: " .. tostring(dispose_error), 0) end
end

local function party_members(list, visit, maximum)
    if not list then return end
    maximum = maximum or 4
    if type(list.get_size) == "function" and type(list.get_element) == "function" then
        local count = integer(list:get_size(), "Tamano del grupo", 0, maximum)
        for index = 0, count - 1 do visit(list:get_element(index)) end
        return
    end
    local definition = list:get_type_definition()
    if definition:get_method("get_Count") and definition:get_method("get_Item") then
        local count = integer(get(list, "get_Count"), "Tamano del grupo", 0, maximum)
        for index = 0, count - 1 do visit(call(list, "get_Item", index)) end
    elseif definition:get_method("get_Length") then
        local count = integer(get(list, "get_Length"), "Tamano del grupo", 0, maximum)
        local element = definition:get_method("GetValue(System.Int32)")
        for index = 0, count - 1 do
            if element then
                visit(element:call(list, index))
            else
                visit(list[index])
            end
        end
    elseif iterator_method(definition, "GetEnumerator") then
        iterate_party(iterator_method(definition, "GetEnumerator"):call(list), visit, maximum)
    elseif iterator_method(definition, "MoveNext") then
        iterate_party(list, visit, maximum)
    else
        error("Coleccion de jugadores no compatible: " .. definition:get_full_name()
            .. " (requiere Count/Item, Length, SystemArray, GetEnumerator o MoveNext)", 0)
    end
end

local function list_values(list, maximum, label)
    if not list then error(label .. " no disponible", 0) end
    local values = { count = 0 }
    party_members(list, function(value)
        values.count = values.count + 1
        values[values.count] = value
    end, maximum)
    return values
end

local function mission_text(value, label)
    if value == nil then return nil end
    if type(value) ~= "string" then
        if (type(value) ~= "userdata" and type(value) ~= "table")
            or type(value.get_type_definition) ~= "function" then
            error(label .. " con tipo Lua no compatible: " .. type(value), 0)
        end
        local definition = value:get_type_definition()
        local type_name = definition:get_full_name()
        if type_name ~= "System.String" then
            error(label .. " con tipo SDK no compatible: " .. type_name, 0)
        end
        value = call(value, "ToString")
        if type(value) ~= "string" then
            error("System.String.ToString no devolvio texto Lua", 0)
        end
    end
    if not utf8.len(value) then error(label .. " con UTF-8 invalido", 0) end
    return value
end

local mission_integer_types = {
    ["System.SByte"] = true, ["System.Byte"] = true,
    ["System.Int16"] = true, ["System.UInt16"] = true,
    ["System.Int32"] = true, ["System.UInt32"] = true,
    ["System.Int64"] = true, ["System.UInt64"] = true,
}

local function mission_scalar(value, label, expected, allow_enum)
    if type(value) == expected then return value end
    if (type(value) ~= "userdata" and type(value) ~= "table")
        or type(value.get_type_definition) ~= "function" then
        error(label .. ": tipo Lua no compatible " .. type(value), 0)
    end
    local definition = value:get_type_definition()
    local type_name = definition:get_full_name()
    local is_enum = allow_enum and definition.is_a and definition:is_a("System.Enum")
    if not (expected == "number" and mission_integer_types[type_name]
        or expected == "boolean" and type_name == "System.Boolean"
        or expected == "number" and is_enum) then
        error(label .. ": tipo SDK no compatible " .. type_name, 0)
    end
    local member = is_enum and "value__" or "m_value"
    local unboxed = field(value, member)
    if type(unboxed) ~= expected then
        error(label .. ": " .. type_name .. "." .. member .. " no devuelve " .. expected, 0)
    end
    return unboxed
end

function Wilds:mission_read(category, read)
    local ok, value = pcall(read)
    if not ok then
        self.report(category, tostring(value) .. ". Se reintentara automaticamente; HP sigue activo.")
        return nil
    end
    self.report(category, nil)
    return value
end

function Wilds:clear_mission_reports()
    for _, category in ipairs({ "mision_nombres", "mision_rangos", "mision_anfitriones",
        "mision_jugadores", "mision_objetivos", "mision_ocupacion", "mision_plazas",
        "mision_desmayos", "mision_tiempo" }) do
        self.report(category, nil)
    end
end

function Wilds:poll_mission_preview()
    local previous_state = self.mission_state
    self.mission_preview = nil
    self.mission_state = "Desactivada"
    if not self.settings.enabled or not self.settings.show_mission_preview then
        self:clear_mission_reports()
        self.report("mision_seleccionada", nil)
        return
    end
    self.mission_state = "Lista no detectada"
    if not self.mission_board then
        if previous_state == "Lista cerrada" then self.mission_state = previous_state end
        self:clear_mission_reports()
        self.report("mision_seleccionada", nil)
        return
    end
    self.mission_state = "Error al leer la lista"
    self.mission_preview = self:mission_read("mision_seleccionada", function()
        local parts = get(self.mission_board, "get__QuestListParts")
        if not parts or not mission_scalar(get(parts, "get_IsActive"),
            "Lista de misiones activa", "boolean") then
            self.mission_state = "Lista inactiva"
            return nil
        end
        -- Use the data sent to the game's detail pane, not a cached/decided quest.
        local selected
        if self.mission_detail_parts
            and self.mission_detail_parts:get_address() == parts:get_address() then
            selected = self.mission_detail
        end
        if not selected then
            self.mission_state = "Esperando detalles de la seleccion"
            return nil
        end
        local session = get(selected, "get_Session")
        if not session then
            self.mission_state = "Seleccion sin anuncio de grupo"
            return nil
        end

        local function read_number(category, object, getter, label, minimum, maximum)
            return self:mission_read(category, function()
                return integer(mission_scalar(get(object, getter), label, "number"),
                    label, minimum, maximum)
            end)
        end
        local member_count = read_number("mision_ocupacion", session, "get_MemberNum",
            "Jugadores de mision", 0, 4)
        local member_max = read_number("mision_plazas", session, "get_MemberMax",
            "Plazas de mision", math.max(member_count or 1, 1), 4)
        local names = self:mission_read("mision_nombres", function()
            return list_values(get(session, "get_HuntersName"), 4, "Nombres del grupo")
        end)
        local ranks = self:mission_read("mision_rangos", function()
            return list_values(get(session, "get_HuntersRank"), 4, "RC del grupo")
        end)
        local hosts = self:mission_read("mision_anfitriones", function()
            return list_values(get(session, "get_IsHost"), 4, "Anfitriones del grupo")
        end)
        local collection_error = not names or not ranks or not hosts
        names, ranks, hosts = names or { count = 0 }, ranks or {}, hosts or {}
        local players = {}
        local missing_rank = false
        local player_errors = {}
        for index = 1, names.count do
            local valid, name = pcall(mission_text, names[index], "Nombre de cazador")
            if not valid then
                player_errors[#player_errors + 1] = string.format("plaza #%d: %s", index, tostring(name))
                name = nil
            end
            if name and name:find("%S") then
                local rank = ranks[index]
                if rank ~= nil then
                    local read, result = pcall(function()
                        return integer(mission_scalar(rank, "RC del cazador", "number"),
                            "RC del cazador", 0, 1000000)
                    end)
                    if read then
                        rank = result
                    else
                        player_errors[#player_errors + 1] = string.format(
                            "plaza #%d: %s", index, tostring(result))
                        rank = nil
                    end
                end
                missing_rank = missing_rank or rank == nil
                local is_host = hosts[index]
                if is_host ~= nil then
                    local read, result = pcall(mission_scalar, is_host, "Anfitrion", "boolean")
                    if read then
                        is_host = result
                    else
                        player_errors[#player_errors + 1] = string.format(
                            "plaza #%d: %s", index, tostring(result))
                        is_host = nil
                    end
                end
                players[#players + 1] = { name = name, rank = rank, host = is_host }
            end
        end
        local roster_status
        if #players ~= member_count or missing_rank or #player_errors > 0 or collection_error then
            roster_status = string.format("Datos de cazadores incompletos: %d/%s nombres",
                #players, member_count and tostring(member_count) or "--")
            self.report("mision_jugadores", roster_status
                .. (#player_errors > 0 and ("; " .. table.concat(player_errors, "; ")) or "")
                .. "; se reintentara automaticamente.")
        else
            self.report("mision_jugadores", nil)
        end
        local quest_life = read_number("mision_desmayos", selected, "get_QuestLife",
            "Limite de desmayos", 0, 255)
        local time_limit = read_number("mision_tiempo", selected, "get_TimeLimit",
            "Limite de tiempo en minutos", 0, 1440)
        if time_limit then time_limit = time_limit * 60 end
        local targets = self:mission_read("mision_objetivos", function()
            local result = {}
            local ids = list_values(get(selected, "get_TargetEmId"), 8, "Objetivos de mision")
            local roles = list_values(get(selected, "get_TargetEmRoleId"), 8, "Roles de objetivos")
            local legendary = list_values(get(selected, "get_TargetEmLegendaryId"), 8,
                "Rangos de objetivos")
            if ids.count ~= roles.count or ids.count ~= legendary.count then
                error("Listas de objetivos de mision desalineadas", 0)
            end
            for index = 1, ids.count do
                local name = mission_text(
                    self.name_method:call(nil,
                        integer(mission_scalar(ids[index], "ID de objetivo", "number", true),
                            "ID de objetivo", -2147483648, 2147483647),
                        integer(mission_scalar(roles[index], "Rol de objetivo", "number", true),
                            "Rol de objetivo", -2147483648, 2147483647),
                        integer(mission_scalar(legendary[index], "Rango de objetivo", "number", true),
                            "Rango de objetivo", -2147483648, 2147483647)),
                    "Nombre de objetivo #" .. index)
                if not name or not name:find("%S") then
                    error("Nombre de objetivo #" .. index .. " vacio", 0)
                end
                result[#result + 1] = name
            end
            return result
        end)
        self.mission_state = "Datos leidos" .. ((roster_status or not targets
            or not member_max or not quest_life or not time_limit) and " (parciales)" or "")
        return {
            players = players,
            member_count = member_count,
            member_max = member_max,
            quest_life = quest_life,
            time_limit = time_limit,
            targets = targets or {},
            target_status = not targets and "Objetivos no disponibles: ver Diagnostico" or nil,
            roster_status = roster_status,
            roster_count = roster_status and #players or nil,
        }
    end)
    if not self.mission_preview then self:clear_mission_reports() end
end

local support_names = {
    [4] = "Fabius", [6] = "Rosso", [9] = "Olivia", [12] = "Nadia",
    [15] = "Griffin", [17] = "Kai", [25] = "Mina", [27] = "Alessa",
    [29] = "Nightmist",
}

local function character_type(definition)
    for _ = 1, 32 do
        if not definition then return false end
        local name = definition:get_full_name()
        if name == "app.CharacterBase" or name == "app.HunterCharacter"
            or name == "app.NpcCharacter" then return true end
        definition = definition.get_parent_type and definition:get_parent_type() or nil
    end
    return false
end

local function support_character(control)
    local definition = control:get_type_definition()
    if definition:get_method("get_Character") then return get(control, "get_Character") end
    -- Partner control layouts vary; only read members declared as characters.
    for _ = 1, 32 do
        if not definition then return nil end
        if definition.get_fields then
            for _, member in ipairs(definition:get_fields()) do
                if not member:is_static() and character_type(member:get_type()) then
                    return control:get_field(member:get_name())
                end
            end
        end
        if definition.get_methods then
            for _, method in ipairs(definition:get_methods()) do
                if method:get_name():match("^get_")
                    and method:get_num_params() == 0
                    and character_type(method:get_return_type()) then
                    return method:call(control)
                end
            end
        end
        definition = definition.get_parent_type and definition:get_parent_type() or nil
    end
    error("Jerarquia de cazador de apoyo demasiado profunda", 0)
end

function Wilds:player_combat(character, id)
    return self:optional("tiempo_combate_" .. id, function()
        if not character then error("Sin personaje para leer tiempo individual de combate", 0) end
        return boolean(get(character, "get_IsCombat"), "IsCombat individual")
    end)
end

function Wilds:read_supports()
    local roster, owners = {}, {}
    self.support_unbound = 0
    local manager = self.sdk.get_managed_singleton("app.NpcManager")
    if not manager then return { roster = roster, owners = owners } end
    local partner = get(manager, "get_PartnerManager")
    if not partner then return { roster = roster, owners = owners } end
    local unbound = 0
    party_members(call(partner, "getQuestMembers"), function(control)
        if not control then return end
        local npc_id, game_object, character
        local definition = control:get_type_definition()
        if definition:get_method("get_NpcCore") then
            -- getQuestMembers can yield cNpcManageInfo rather than partner controls.
            local core = get(control, "get_NpcCore")
            if not core then return end
            character = support_character(core)
            game_object = get(core, "get_GameObject")
            local holder = field(core, "_ContextHolder")
            local context = holder and get(holder, "get_Npc")
            if not context then return end
            npc_id = get(context, "get_NpcID")
        else
            if not boolean(get(control, "get_Valid"), "Valid del apoyo") then return end
            if not boolean(get(control, "get_IsQuestPartner"), "IsQuestPartner") then return end
            npc_id = get(control, "get_NpcID")
            character = support_character(control)
            game_object = character and get(character, "get_GameObject")
        end
        npc_id = integer(npc_id, "NpcID", -1, 100000)
        if npc_id < 0 then return end
        local address = game_object and game_object:get_address()
        local available = address ~= nil and address ~= 0
        local player = { id = "support:" .. tostring(control:get_address()) .. ":" .. npc_id,
            name = support_names[npc_id] or Locale.t("Apoyo #%s", self.settings.language, npc_id),
            is_self = false, is_support = true, damage_available = available }
        player.in_combat = self:player_combat(character, player.id)
        roster[player.id] = player
        if available then owners[tostring(address)] = player else unbound = unbound + 1 end
    end, 16)
    self.support_unbound = unbound
    if unbound > 0 then
        self.report("identidad_apoyos", tostring(unbound)
            .. " apoyos sin Character/GameObject disponible; se muestra --, no dano cero.")
    end
    return { roster = roster, owners = owners }
end

function Wilds:poll_damage()
    if not self.damage then return end
    for key, pending in pairs(self.damage_pending) do
        if self.model.frame - pending.frame > 2 then self.damage_pending[key] = nil end
    end
    if not self.settings.enabled or not self.settings.show_dps then
        if self.damage.session then self:reset_damage() end
        return
    end
    if self.model.frame < self.damage_due then return end
    self.damage_due = self.model.frame + self.settings.sample_frames
    self.damage_visible = false
    local activity = self:optional("actividad", function()
        local manager = self.sdk.get_managed_singleton("app.MissionManager")
        if not manager then return { mode = "unavailable" } end
        if boolean(get(manager, "get_IsPlayingQuest"), "IsPlayingQuest") then
            return { mode = "quest", manager = manager }
        end
        local player_manager = self.sdk.get_managed_singleton("app.PlayerManager")
        if not player_manager then return nil end
        local info = call(player_manager, "getMasterPlayer")
        local character = info and get(info, "get_Character")
        local in_combat = character and self:optional("combate", function()
            return boolean(get(character, "get_IsCombat"), "IsCombat")
        end)
        if in_combat then
            return { mode = "battle", character = character, player_manager = player_manager }
        end
    end)
    if self.feature_failures.actividad then return end
    if activity and activity.mode == "unavailable" then return end
    if not activity then
        if self.feature_failures.combate then return end
        if self.damage.active and self.damage.session:sub(1, 6) == "quest:" then
            self:read_quest_faints()
        end
        self.damage:update(nil)
        self.damage_players = {}
        self.damage_pending = {}
        self.damage_mode = nil
        self:retain_damage_result()
        return
    end
    self.damage_result_until = nil
    self.damage_result_clock = nil
    self.damage_visible = true
    self.damage_mode = activity.mode
    if not self.damage_ready or self.feature_failures.dps then return end
    self:optional("dps", function()
        local session, elapsed, director
        if activity.mode == "quest" then
            director = get(activity.manager, "get_QuestDirector")
            if not director then error("Mision activa sin QuestDirector", 0) end
            local param = get(director, "get_Param")
            if not param then error("Mision activa sin QuestFlowParam", 0) end
            local address = param:get_address()
            if address == nil or address == 0 then error("QuestFlowParam sin direccion valida", 0) end
            session = "quest:" .. tostring(address)
            elapsed = get(director, "get_QuestElapsedTime")
        else
            session = "battle:" .. tostring(activity.character:get_address())
            local application = self.sdk.find_type_definition("via.Application")
            if not application then error("Falta via.Application para reloj de combate", 0) end
            elapsed = required_method(application, "get_UpTimeSecond"):call(nil)
        end
        local previous_session = self.damage.session
        local was_active = self.damage.active
        self.damage:update(session, elapsed)
        if director then self:read_quest_faints(director) end
        if previous_session ~= self.damage.session
            or not was_active then
            self.damage_pending = {}
            self.unassigned_hits = 0
        end
        local players, roster = {}, {}
        local player_manager = activity.player_manager
            or self.sdk.get_managed_singleton("app.PlayerManager")
        if not player_manager then error("Falta app.PlayerManager", 0) end
        local function add(info)
            if not info then return end
            local character = get(info, "get_Character")
            local holder = get(info, "get_ContextHolder")
            local context = holder and get(holder, "get_Pl")
            if not character or not context then return end
            local game_object = get(character, "get_GameObject")
            if not game_object then return end
            local address = game_object:get_address()
            if address == nil or address == 0 then
                error("Cazador sin direccion de GameObject valida", 0)
            end
            local name = get(context, "get_PlayerName")
            local player = { id = tostring(address) .. ":" .. tostring(name), name = name,
                is_self = boolean(get(character, "get_IsMaster"), "IsMaster") }
            player.in_combat = self:player_combat(character, player.id)
            roster[player.id] = player
            players[tostring(address)] = player
        end
        add(call(player_manager, "getMasterPlayer"))
        if activity.mode == "quest" then
            party_members(call(player_manager, "getQuestMembers"), add)
        end
        local supports = self:optional("apoyos", function() return self:read_supports() end)
        if supports then
            for id, player in pairs(supports.roster) do roster[id] = player end
            for address, player in pairs(supports.owners) do
                if players[address] then error("GameObject compartido por cazador y apoyo", 0) end
                players[address] = player
            end
        end
        self.damage:sync(roster)
        for key, pending in pairs(self.damage_pending) do
            local player = roster[pending.player.id]
            if not player or player.damage_available == false then
                self.damage_pending[key] = nil
            end
        end
        self.damage_players = players
    end)
end

function Wilds:capture_damage(hit)
    if not self.damage_visible or not self.damage.active or not hit then return end
    local key = tostring(hit:get_address())
    self.damage_pending[key] = nil
    local owner = call(hit, "getActualAttackOwner")
    if not owner then return end
    local player = self.damage_players[tostring(owner:get_address())]
    if not player then
        self.unassigned_hits = self.unassigned_hits + 1
        return
    end
    local target = hit_enemy(self, hit)
    if not target then return end
    local count = 0
    for _ in pairs(self.damage_pending) do count = count + 1 end
    if count >= 256 then error("Demasiados impactos DPS pendientes", 0) end
    self.damage_pending[key] = { player = player, target = tostring(target:get_address()),
        frame = self.model.frame }
end

function Wilds:finish_damage(calc, hit)
    if not self.damage_visible or not self.damage.active or not hit then return end
    local key = tostring(hit:get_address())
    local pending = self.damage_pending[key]
    self.damage_pending[key] = nil
    if not pending or self.model.frame - pending.frame > 2 then return end
    local target = get(hit, "get_DamageOwner")
    if not target or tostring(target:get_address()) ~= pending.target then
        error("Impacto DPS con destino distinto al capturado", 0)
    end
    if not calc then error("Falta calculo de dano final", 0) end
    self.damage:add(pending.player, field(calc, "FinalDamage"))
end

function Wilds:install_damage(damage)
    self.damage = damage
    self:reset_damage()
    if not self.settings.show_dps and not self.settings.auto_focus then return end
    local stock_type = self.sdk.find_type_definition("app.cEnemyStockDamage")
    local mark_type = self.sdk.find_type_definition("app.cEnemyStockDamage.mcEnemyHitMarkManager")
    if not stock_type or not mark_type then
        error("Faltan tipos de calculo de impactos para DPS", 0)
    end
    local stock = required_method(stock_type, "stockDamageDetail(app.HitInfo)")
    local mark = required_method(mark_type,
        "playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)")
    self.damage_hooks = self.damage_hooks or {}
    local function attach(method, name, callback, focus_callback)
        if self.damage_hooks[name] then return end
        self.sdk.hook(method, function(args)
            if self.settings.enabled and self.settings.auto_focus and self.focus_combat
                and not self.feature_failures.foco then
                self:optional("foco", function() focus_callback(args) end)
            end
            if self.settings.enabled and self.settings.show_dps
                and not self.feature_failures.dps then
                self:optional("dps", function() callback(args) end)
            end
            return self.sdk.PreHookResult.CALL_ORIGINAL
        end, function(retval) return retval end)
        self.damage_hooks[name] = true
    end
    attach(stock, "stock", function(args)
        self:capture_damage(self.sdk.to_managed_object(args[3]))
    end, function(args)
        self:capture_focus(self.sdk.to_managed_object(args[3]))
    end)
    attach(mark, "mark", function(args)
        self:finish_damage(self.sdk.to_managed_object(args[3]),
            self.sdk.to_managed_object(args[4]))
    end, function(args)
        self:finish_focus(self.sdk.to_managed_object(args[3]),
            self.sdk.to_managed_object(args[4]))
    end)
    self.damage_ready = true
end

function Wilds:read(enemy)
    local holder = field(enemy, "_Context")
    if not holder then
        return nil
    end
    local context = field(holder, "_Em")
    if not context then
        return nil
    end
    if get(context, "get_IsBoss") ~= true then
        return nil
    end
    local health_manager = get(enemy, "get_HealthMgr")
    local basic = get(context, "get_Basic")
    if not health_manager or not basic then
        return nil
    end
    -- Wilds protects HP access; this runs only inside EnemyCharacter.doUpdateEnd.
    local health = get(health_manager, "get_Health")
    local max_health = get(health_manager, "get_MaxHealth")
    local enemy_id = get(basic, "get_EmID")
    local name = self.name_method:call(nil,
        enemy_id, get(basic, "get_RoleID"), get(basic, "get_LegendaryID"))
    local sample = { name = name, health = health, max_health = max_health }
    if self.settings.show_monster_icons then
        sample.portrait = self:optional("retratos", function()
            if not self.portrait_ids then self.portrait_ids = Portraits.bind(self.sdk) end
            self.report("retratos", nil)
            return self.portrait_ids[enemy_id] or "unknown"
        end)
    else
        self.report("retratos", nil)
    end
    if self.settings.prioritize_quest then
        sample.quest_target = self:optional("mision", function()
            local manager = self.sdk.get_managed_singleton("app.MissionManager")
            if not manager then return nil end
            local browser = get(context, "get_Browser")
            if not browser then return nil end
            local target_key = get(browser, "get_ThisTargetAccessKey")
            if target_key == nil then return nil end
            local is_target = required_method(manager:get_type_definition(),
                "isQuestTarget(app.TARGET_ACCESS_KEY)"):call(manager, target_key)
            if type(is_target) ~= "boolean" then
                error("MissionManager.isQuestTarget no es booleano", 0)
            end
            return is_target
        end)
    end
    if self.settings.show_pin or self.settings.only_pinned or self.settings.prioritize_pinned then
        sample.pinned = self:optional("objetivo", function()
            local pinned = get(context, "get_IsTargetPinOn")
            if type(pinned) ~= "boolean" then
                error("IsTargetPinOn no es booleano", 0)
            end
            return pinned
        end)
    end
    if self.settings.show_rage then
        sample.rage = self:optional("furia", function()
            local conditions = get(context, "get_Conditions")
            if not conditions then return nil end
            return condition(get(conditions, "get_Angry"), "get_Value", "get_LimitValue")
        end)
    end
    if self.settings.show_stamina then
        sample.stamina = self:optional("resistencia", function()
            local conditions = get(context, "get_Conditions")
            if not conditions then return nil end
            return condition(get(conditions, "get_Tired"), "get_Stamina", "get_DefaultStamina")
        end)
    end
    if self.settings.show_parts then
        sample.parts = self:optional("partes", function()
            local result, issues = read_parts(context)
            if result and result.invalid > 0 then
                local omitted = result.invalid - #issues
                self.report("partes_registros", string.format(
                    "Lectura parcial de partes: %d registro(s) invalido(s): %s%s",
                    result.invalid, table.concat(issues, "; "),
                    omitted > 0 and string.format("; y %d mas", omitted) or ""))
            else
                self.report("partes_registros", nil)
            end
            return result
        end)
    end
    if self.settings.show_wounds then
        sample.wounds = self:optional("heridas", function() return self:read_wounds(context) end)
    end
    if self.settings.auto_focus or self.settings.show_rage then
        for _, entry in ipairs({
            { "paralysis", "paralisis", "app.cEnemyBadConditionParalyse" },
            { "stun", "aturdimiento", "app.cEnemyBadConditionStun" },
        }) do
            sample[entry[1]] = self:optional(entry[2], function()
                local conditions = get(context, "get_Conditions")
                if not conditions then return nil end
                return bad_condition(conditions, entry[3])
            end)
        end
    end
    return sample
end

function Wilds:on_update(args)
    self.hook_calls = self.hook_calls + 1
    if not self.settings.enabled then
        return
    end
    local key
    local ok, err = pcall(function()
        local enemy = self.sdk.to_managed_object(args[2])
        if not enemy then
            error("doUpdateEnd no devolvio un EnemyCharacter valido", 0)
        end
        key = tostring(enemy:get_address())
        if not self.model:should_sample(key, self.settings.sample_frames) then
            return
        end
        local sample = self:read(enemy)
        if sample then
            self.model:set(key, sample)
            self.samples = self.samples + 1
        else
            self.model.monsters[key] = nil
        end
    end)
    if not ok then
        if key then
            self.model.monsters[key] = nil
        end
        self.report("lectura", tostring(err))
    end
end

function Wilds:on_destroy(args)
    local ok, err = pcall(function()
        local enemy = self.sdk.to_managed_object(args[2])
        if enemy then
            local key = tostring(enemy:get_address())
            self.model:remove(key)
            for id, pending in pairs(self.focus_pending or {}) do
                if pending.enemy == key then self.focus_pending[id] = nil end
            end
        end
    end)
    if not ok then
        self.model:clear()
        self.report("destruccion", tostring(err))
    end
end

function Wilds:install()
    local enemy_type = self.sdk.find_type_definition("app.EnemyCharacter")
    local context_type = self.sdk.find_type_definition("app.cEnemyContext")
    local definition = self.sdk.find_type_definition("app.EnemyDef")
    if not enemy_type or not context_type or not definition then
        error("No se encuentran los tipos de Wilds. Revisa juego y version de REFramework.", 0)
    end
    local update = required_method(enemy_type, "doUpdateEnd")
    local destroy = required_method(enemy_type, "doOnDestroy")
    accessor(context_type, "get_IsBoss")
    self.name_method = required_method(definition, "NameString")

    local function preserve_result(retval)
        return retval
    end
    self.sdk.hook(destroy, function(args)
        self:on_destroy(args)
        return self.sdk.PreHookResult.CALL_ORIGINAL
    end, preserve_result)
    self.sdk.hook(update, function(args)
        self:on_update(args)
        return self.sdk.PreHookResult.CALL_ORIGINAL
    end, preserve_result)
    self.ready = true
end

return Wilds
