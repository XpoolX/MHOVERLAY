package.path = "./reframework/autorun/?.lua;" .. package.path

local Model = require("mhoverlay/model")
local Config = require("mhoverlay/config")
local Wilds = require("mhoverlay/wilds")
local View = require("mhoverlay/view")
local Damage = require("mhoverlay/damage")
local Icons = require("mhoverlay/icons")
local Portraits = require("mhoverlay/portraits")
local Locale = require("mhoverlay/locale")

local function spanish_defaults()
    local settings = Config.defaults()
    settings.language = "es"
    return settings
end

local passed = 0
local function test(name, run)
    local ok, err = pcall(run)
    if not ok then
        io.stderr:write("FAIL: " .. name .. "\n" .. tostring(err) .. "\n")
        os.exit(1)
    end
    passed = passed + 1
    print("PASS: " .. name)
end

local function equal(actual, expected)
    assert(actual == expected,
        "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function raises(run, pattern)
    local ok, err = pcall(run)
    assert(not ok, "expected an error")
    assert(tostring(err):find(pattern), tostring(err))
end

local function object(name, fields, methods, address)
    local definition = {}
    function definition:get_full_name()
        return name
    end
    function definition:get_field(key)
        return fields[key] ~= nil and {} or nil
    end
    function definition:get_method(key)
        local callback = methods[key]
        if callback then
            return { call = function(_, instance, ...)
                return callback(instance, ...)
            end }
        end
    end
    return {
        get_type_definition = function() return definition end,
        get_field = function(_, key) return fields[key] end,
        get_address = function() return address or 100 end,
    }, definition
end

local function array(entries, size)
    return {
        get_size = function() return size or #entries end,
        get_element = function(_, index) return entries[index + 1] end,
    }
end

local function fixture(access, initial)
    local values = {
        health = 12500, maximum = 20000, boss = true, name = "Rey Dau",
        pinned = false, conditions_present = true,
        quest_target = false, mission_present = true, browser_present = true,
        rage_valid = true, rage_active = false, rage_current = 30, rage_max = 100,
        rage_timer = 20, rage_duration = 60,
        stamina_valid = true, stamina_active = false, stamina_current = 180, stamina_max = 300,
        stamina_timer = 5, stamina_duration = 30,
        paralysis_valid = true, paralysis_active = false, paralysis_current = 20, paralysis_max = 100,
        paralysis_timer = 5, paralysis_duration = 15,
        stun_valid = true, stun_active = false, stun_current = 10, stun_max = 100,
        stun_timer = 2, stun_duration = 10,
        parts_present = true, scar_present = true,
        parts_data = { { max = 1, broken = false }, { max = 2, broken = true } },
        wounds_data = { 0, 2, 2, 3 },
    }
    for key, value in pairs(initial or {}) do
        values[key] = value
    end
    local function sdk_object(name, fields, methods)
        for key, callback in pairs(methods) do
            local property = key:match("^get_(.+)$")
            if property and access and access[property] then
                local field_name = access[property] == "backing"
                    and "<" .. property .. ">k__BackingField" or property
                fields[field_name] = callback()
                methods[key] = nil
            end
        end
        return object(name, fields, methods)
    end
    local hp = sdk_object("app.EnemyHealth", {}, {
        get_Health = function() return values.health end,
        get_MaxHealth = function() return values.maximum end,
    })
    local basic = sdk_object("app.cEmModuleBasic", {}, {
        get_EmID = function() return 1 end,
        get_RoleID = function() return 2 end,
        get_LegendaryID = function() return 3 end,
    })
    local function make_condition(name, prefix, current_name, max_name)
        return sdk_object(name, {}, {
            get_IsValid = function() return values[prefix .. "_valid"] end,
            get_IsActive = function() return values[prefix .. "_active"] end,
            get_CurrentTimer = function() return values[prefix .. "_timer"] end,
            get_ActivateTime = function() return values[prefix .. "_duration"] end,
            [current_name] = function() return values[prefix .. "_current"] end,
            [max_name] = function() return values[prefix .. "_max"] end,
        })
    end
    local angry, angry_type = make_condition("app.cEmConditionAngry",
        "rage", "get_Value", "get_LimitValue")
    local tired, tired_type = make_condition("app.cEmConditionTired",
        "stamina", "get_Stamina", "get_DefaultStamina")
    local paralysis = make_condition("app.cEnemyBadConditionParalyse",
        "paralysis", "get_Value", "get_LimitValue")
    local stun = make_condition("app.cEnemyBadConditionStun",
        "stun", "get_Value", "get_LimitValue")
    local conditions, conditions_type = sdk_object("app.cEmModuleConditions", {}, {
        get_Angry = function() return angry end,
        get_Tired = function() return tired end,
        get__Conditions = function()
            return array(values.bad_conditions or { paralysis, stun })
        end,
    })
    local browser = sdk_object("app.cEnemyBrowser", {}, {
        get_ThisTargetAccessKey = function() return "target_access_key" end,
    })
    local mission, mission_type = object("app.MissionManager", {}, {
        ["isQuestTarget(app.TARGET_ACCESS_KEY)"] = function(instance, key)
            assert(instance)
            equal(key, "target_access_key")
            return values.quest_target
        end,
    })
    local parts_module, parts_type = sdk_object("app.cEmModuleParts", {}, {
        get_BreakParts = function()
            local entries = {}
            for index, part in ipairs(values.parts_data) do
                entries[index] = sdk_object("app.cEmModuleParts.cBreakParts", {}, {
                    get_MaxBreakCount = function() return part.max end,
                    get_IsBreakAll = function() return part.broken end,
                })
            end
            return array(entries, values.parts_size)
        end,
    })
    local scar_module, scar_type = sdk_object("app.cEmModuleScar", {}, {
        get_ScarParts = function()
            local entries = {}
            for index, state in ipairs(values.wounds_data) do
                entries[index] = sdk_object("app.cEmModuleScar.cScarParts", {}, {
                    get_State = function() return state end,
                })
            end
            return array(entries)
        end,
    })
    local scar_enum = {
        get_fields = function()
            local fields = {}
            for value, name in pairs({ [-1] = "NONE", [0] = "NORMAL", [1] = "TEAR",
                [2] = "RAW", [3] = "OLD", [4] = "HEAL" }) do
                fields[#fields + 1] = {
                    is_static = function() return true end,
                    get_data = function(_, instance) equal(instance, nil); return value end,
                    get_name = function() return name end,
                }
            end
            fields[#fields + 1] = { is_static = function() return false end }
            return fields
        end,
    }
    local context, context_type = sdk_object("app.cEnemyContext", {}, {
        get_IsBoss = function() return values.boss end,
        get_Basic = function() return basic end,
        get_IsTargetPinOn = function() return values.pinned end,
        get_Browser = function()
            if values.browser_present then return browser end
        end,
        get_Conditions = function()
            if values.conditions_present then return conditions end
        end,
        get_Parts = function() if values.parts_present then return parts_module end end,
        get_Scar = function() if values.scar_present then return scar_module end end,
    })
    local holder = object("app.ContextHolder", { _Em = context }, {})
    local enemy, enemy_type = sdk_object("app.EnemyCharacter", { _Context = holder }, {
        get_HealthMgr = function() return hp end,
        doUpdateEnd = function() end,
        doOnDestroy = function() end,
    })
    local _, names_type = object("app.EnemyDef", {}, {
        NameString = function(instance, id, role, legendary)
            equal(instance, nil)
            equal(id, 1)
            equal(role, 2)
            equal(legendary, 3)
            return values.name
        end,
    })
    local _, mission_board_type = object("app.GUI050000", {}, {
        onOpen = function() end,
        onClose = function() end,
        onVisible = function() end,
    })
    local _, mission_parts_type = object("app.GUI050000QuestListParts", {}, {
        updateQuestDetailWindow = function() end,
    })
    local portrait_fields, portrait_index = {}, 1000
    for enum in pairs(Portraits.ids) do
        portrait_index = portrait_index + 1
        local id = enum == "EM0156_00_0" and 1 or portrait_index
        portrait_fields[enum] = { get_data = function() return id end }
    end
    local portrait_type = { get_field = function(_, name) return portrait_fields[name] end }
    local types = {
        ["app.EnemyCharacter"] = enemy_type,
        ["app.cEnemyContext"] = context_type,
        ["app.EnemyDef"] = names_type,
        ["app.cEmModuleConditions"] = conditions_type,
        ["app.cEmConditionAngry"] = angry_type,
        ["app.cEmConditionTired"] = tired_type,
        ["app.MissionManager"] = mission_type,
        ["app.cEmModuleParts"] = parts_type,
        ["app.cEmModuleScar"] = scar_type,
        ["app.cEmModuleScar.cScarParts.STATE"] = scar_enum,
        ["app.GUI050000"] = mission_board_type,
        ["app.GUI050000QuestListParts"] = mission_parts_type,
        ["app.EnemyDef.ID"] = portrait_type,
    }
    local hooks = {}
    local sdk_api = {
        PreHookResult = { CALL_ORIGINAL = 0 },
        find_type_definition = function(name) return types[name] end,
        get_managed_singleton = function(name)
            if name == "app.PlayerManager" then return nil end
            equal(name, "app.MissionManager")
            if values.mission_present then return mission end
        end,
        to_managed_object = function(ptr)
            if ptr == "enemy_pointer" then return enemy end
            if ptr == "board_pointer" then return values.mission_board end
            error("unexpected managed pointer: " .. tostring(ptr))
        end,
        hook = function(method, pre, post)
            hooks[#hooks + 1] = { method = method, pre = pre, post = post }
        end,
    }
    local model = Model.new()
    local settings = spanish_defaults()
    local reports = {}
    local source = Wilds.new(sdk_api, model, settings, function(category, message)
        reports[category] = message
    end)
    source:install()
    return source, model, settings, values, hooks, reports, types
end

local function mission_preview_fixture()
    local source, model, settings, values, hooks, reports, types = fixture()
    local function sdk_object(name, methods)
        return object(name, {}, methods)
    end
    local target_ids = array({ 1 })
    local target_roles = array({ 2 })
    local target_legendary = array({ 3 })
    local session
    local selected = sdk_object("app.cGUIQuestViewData", {
        get_Session = function() if not values.preview_no_session then return session end end,
        get_QuestLife = function()
            if values.preview_limits_error then error("Limites aun no recibidos") end
            return values.preview_life or 3
        end,
        get_TimeLimit = function()
            if values.preview_limits_error then error("Limites aun no recibidos") end
            return values.preview_time or 30
        end,
        get_TargetEmId = function() return values.preview_target_ids or target_ids end,
        get_TargetEmRoleId = function() return values.preview_target_roles or target_roles end,
        get_TargetEmLegendaryId = function() return values.preview_target_legendary or target_legendary end,
    })
    values.preview_names = { "Dome", "Hunter B" }
    values.preview_ranks = { 512, 234 }
    values.preview_hosts = { true, false }
    session = sdk_object("app.cGUISessionData", {
        get_MemberNum = function() return values.preview_count or 2 end,
        get_MemberMax = function() return values.preview_max or 4 end,
        get_HuntersName = function() return array(values.preview_names, values.preview_slots) end,
        get_HuntersRank = function()
            if values.preview_rank_error then error("RC temporalmente no disponible") end
            return array(values.preview_ranks, values.preview_slots)
        end,
        get_IsHost = function() return array(values.preview_hosts, values.preview_slots) end,
    })
    local parts = sdk_object("app.GUI050000QuestListParts", {
        get_IsActive = function()
            if values.preview_active_error then error("Lista temporalmente no disponible") end
            return not values.preview_inactive
        end,
        get_SelectViewQuestData = function()
            if not values.preview_no_selection then return selected end
        end,
    })
    local board = sdk_object("app.GUI050000", {
        get__QuestListParts = function() return parts end,
    })
    values.mission_board = board
    source.mission_board = board
    source.mission_detail_parts = parts
    source.mission_detail = selected
    local managed = source.sdk.to_managed_object
    source.sdk.to_managed_object = function(ptr)
        if ptr == "parts_pointer" then return parts end
        if ptr == "selected_pointer" then
            if not values.preview_no_selection then return values.highlighted_quest or selected end
            return nil
        end
        if ptr == nil then return nil end
        return managed(ptr)
    end
    return {
        source = source,
        model = model,
        settings = settings,
        values = values,
        hooks = hooks,
        reports = reports,
        types = types,
        board = board,
        selected = selected,
        parts = parts,
    }
end

test("mission board hooks capture and clear the board without changing damage hook slots", function()
    local f = mission_preview_fixture()
    f.source:install_mission_board()
    equal(#f.hooks, 6)
    equal(f.hooks[3].pre({ nil, "board_pointer" }), 0)
    equal(f.source.mission_board, f.board)
    equal(f.hooks[4].pre({ nil, "board_pointer" }), 0)
    equal(f.source.mission_board, nil)
    equal(f.source.mission_preview, nil)
    f.source.feature_failures.mision_seleccionada = true
    equal(f.hooks[5].pre({ nil, "board_pointer" }), 0)
    equal(f.source.mission_board, f.board)
    equal(f.source.feature_failures.mision_seleccionada, nil)
    equal(f.hooks[5].post("original"), "original")
    f.source:install_mission_board()
    equal(#f.hooks, 6)
end)

test("selected mission preview validates and exposes only roster and advertised quest limits", function()
    local f = mission_preview_fixture()
    f.source:poll_mission_preview()
    local preview = f.source.mission_preview
    assert(preview)
    equal(preview.member_count, 2)
    equal(preview.member_max, 4)
    equal(preview.players[1].name, "Dome")
    equal(preview.players[1].rank, 512)
    equal(preview.players[1].host, true)
    equal(preview.players[2].name, "Hunter B")
    equal(preview.players[2].rank, 234)
    equal(preview.quest_life, 3)
    equal(preview.time_limit, 1800)
    equal(preview.targets[1], "Rey Dau")
    equal(next(f.reports), nil)
end)

test("mission board hook failures report without interrupting the original game method", function()
    local f = mission_preview_fixture()
    f.source:install_mission_board()
    equal(f.hooks[3].pre({ nil, "invalid_pointer" }), 0)
    equal(f.source.mission_board, nil)
    assert(f.reports.lista_misiones:find("onOpen", 1, true))
    equal(f.hooks[3].post("original"), "original")
end)

test("mission roster keeps slot alignment across empty whitespace and null names", function()
    for _, empty in ipairs({ "", "   ", false }) do
        local f = mission_preview_fixture()
        f.values.preview_slots = 4
        f.values.preview_names = { [2] = "Dome", [4] = "Hunter B" }
        if empty ~= false then f.values.preview_names[1] = empty end
        f.values.preview_ranks = { 0, 512, 0, 234 }
        f.values.preview_hosts = { false, true, false, false }
        f.source:poll_mission_preview()
        local preview = assert(f.source.mission_preview)
        equal(#preview.players, 2)
        equal(preview.players[1].name, "Dome")
        equal(preview.players[1].rank, 512)
        equal(preview.players[1].host, true)
        equal(preview.players[2].rank, 234)
        equal(preview.roster_status, nil)
        equal(next(f.reports), nil)
    end
end)

test("incomplete advertised names remain visible and recover without manual retry", function()
    local f = mission_preview_fixture()
    f.values.preview_names = { "", "", "", "" }
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(#preview.players, 0)
    equal(preview.member_count, 2)
    assert(preview.roster_status)
    assert(f.reports.mision_jugadores)
    equal(f.source.feature_failures.mision_seleccionada, nil)
    f.values.preview_names = { "", "Dome", "", "Hunter B" }
    f.values.preview_ranks = { 0, 512, 0, 234 }
    f.values.preview_hosts = { false, true, false, false }
    f.source:poll_mission_preview()
    equal(#f.source.mission_preview.players, 2)
    equal(f.source.mission_preview.roster_status, nil)
    equal(f.reports.mision_jugadores, nil)
end)

test("missing rank does not borrow the rank of the next occupied slot", function()
    local f = mission_preview_fixture()
    f.values.preview_slots = 2
    f.values.preview_ranks = { [2] = 234 }
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(preview.players[1].rank, nil)
    equal(preview.players[2].rank, 234)
    assert(preview.roster_status)
end)

test("mission names decode managed System.String values without losing slot identity", function()
    local f = mission_preview_fixture()
    local managed = object("System.String", {}, {
        ToString = function() return "Cazador \195\145" end,
    })
    f.values.preview_names = { managed, "Hunter B" }
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(preview.players[1].name, "Cazador \195\145")
    equal(preview.players[1].rank, 512)
    equal(preview.players[1].host, true)
    equal(preview.players[2].rank, 234)
    equal(next(f.reports), nil)
end)

test("mission objectives decode managed text without disabling roster or limits", function()
    local f = mission_preview_fixture()
    f.values.name = object("System.String", {}, {
        ToString = function() return "Rey Dau" end,
    })
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(preview.targets[1], "Rey Dau")
    equal(preview.players[1].name, "Dome")
    equal(preview.players[1].rank, 512)
    equal(preview.quest_life, 3)
    equal(next(f.reports), nil)
end)

test("invalid objective text reports its index and type while roster remains drawable", function()
    local f = mission_preview_fixture()
    f.values.name = object("app.UnexpectedTargetName", {}, {})
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(#preview.targets, 0)
    equal(#preview.players, 2)
    equal(preview.time_limit, 1800)
    assert(f.reports.mision_objetivos:find("objetivo #1", 1, true))
    assert(f.reports.mision_objetivos:find("app.UnexpectedTargetName", 1, true))
    equal(f.source.feature_failures.mision_seleccionada, nil)
    assert(preview.target_status)
    f.values.name = "Rey Dau"
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.targets[1], "Rey Dau")
    equal(f.reports.mision_objetivos, nil)
    equal(f.source.mission_preview.target_status, nil)
end)

test("objective IDs decode boxed integers and typed enums before calling EnemyDef", function()
    local f = mission_preview_fixture()
    local id = object("app.EnemyDef.ID", { value__ = 1 }, {})
    id:get_type_definition().is_a = function(_, name) return name == "System.Enum" end
    f.values.preview_target_ids = array({ id })
    f.values.preview_target_roles = array({ (object("System.Int32", { m_value = 2 }, {})) })
    f.values.preview_target_legendary = array({ (object("System.Int32", { m_value = 3 }, {})) })
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.targets[1], "Rey Dau")
    equal(next(f.reports), nil)
end)

test("mission diagnostics distinguish gates from errors and failed reads recover automatically", function()
    local f = mission_preview_fixture()
    for _, case in ipairs({
        { "preview_inactive", "Lista inactiva" },
        { "preview_no_selection", "Esperando detalles de la seleccion" },
        { "preview_no_session", "Seleccion sin anuncio de grupo" },
        { "preview_active_error", "Error al leer la lista" },
    }) do
        f.values[case[1]] = true
        if case[1] == "preview_no_selection" then f.source.mission_detail = nil end
        f.source:poll_mission_preview()
        equal(f.source.mission_preview, nil)
        equal(f.source.mission_state, case[2])
        equal(f.source.feature_failures.mision_seleccionada, nil)
        f.values[case[1]] = false
        f.source.mission_detail = f.selected
        f.source:poll_mission_preview()
        assert(f.source.mission_preview)
        equal(f.source.mission_state, "Datos leidos")
        equal(next(f.reports), nil)
    end
    f.settings.show_mission_preview = false
    f.source:poll_mission_preview()
    equal(f.source.mission_state, "Desactivada")
    f.settings.show_mission_preview = true
    f.source.mission_board = nil
    f.source:poll_mission_preview()
    equal(f.source.mission_state, "Lista no detectada")
end)

test("an unavailable rank collection leaves names and limits visible and clears old warnings", function()
    local f = mission_preview_fixture()
    f.values.preview_rank_error = true
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(#preview.players, 2)
    equal(preview.players[1].rank, nil)
    equal(preview.quest_life, 3)
    assert(f.reports.mision_rangos)
    equal(f.source.mission_state, "Datos leidos (parciales)")
    f.values.preview_rank_error = false
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.players[1].rank, 512)
    equal(next(f.reports), nil)
    f.values.name = nil
    f.source:poll_mission_preview()
    assert(f.reports.mision_objetivos)
    f.values.preview_no_selection = true
    f.source.mission_detail = nil
    f.source:poll_mission_preview()
    equal(next(f.reports), nil)
end)

test("managed array enumeration preserves a returned false without indexing a different value", function()
    local f = mission_preview_fixture()
    local hosts = object("System.Boolean[]", {}, {
        get_Length = function() return 2 end,
        ["GetValue(System.Int32)"] = function(_, index) return index == 0 end,
    })
    local session = f.selected:get_type_definition():get_method("get_Session"):call(f.selected)
    local original = session:get_type_definition().get_method
    session:get_type_definition().get_method = function(self, name)
        if name == "get_IsHost" then return { call = function() return hosts end } end
        return original(self, name)
    end
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.players[1].host, true)
    equal(f.source.mission_preview.players[2].host, false)
    equal(next(f.reports), nil)
end)

test("mission scalars and arrays decode boxed SDK values together", function()
    local f = mission_preview_fixture()
    f.values.preview_count = object("System.Byte", { m_value = 2 }, {})
    f.values.preview_max = object("System.Byte", { m_value = 4 }, {})
    f.values.preview_life = object("System.Int32", { m_value = 3 }, {})
    f.values.preview_time = object("System.Int32", { m_value = 30 }, {})
    f.values.preview_names = {
        (object("System.String", {}, { ToString = function() return "Dome" end })),
        (object("System.String", {}, { ToString = function() return "Hunter B" end })),
    }
    f.values.preview_ranks = {
        (object("System.Int32", { m_value = 512 }, {})),
        (object("System.UInt32", { m_value = 234 }, {})),
    }
    f.values.preview_hosts = {
        (object("System.Boolean", { m_value = true }, {})),
        (object("System.Boolean", { m_value = false }, {})),
    }
    f.values.preview_target_ids = array({ (object("System.Int32", { m_value = 1 }, {})) })
    f.values.preview_target_roles = array({ (object("System.Int32", { m_value = 2 }, {})) })
    f.values.preview_target_legendary = array({ (object("System.Int32", { m_value = 3 }, {})) })
    f.values.name = object("System.String", {}, { ToString = function() return "Rey Dau" end })
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(preview.member_count, 2)
    equal(preview.member_max, 4)
    equal(preview.quest_life, 3)
    equal(preview.time_limit, 1800)
    equal(preview.players[2].name, "Hunter B")
    equal(preview.players[2].rank, 234)
    equal(preview.players[2].host, false)
    equal(preview.targets[1], "Rey Dau")
    equal(next(f.reports), nil)
end)

test("unavailable mission limits preserve the roster and recover without a manual retry", function()
    local f = mission_preview_fixture()
    f.values.preview_limits_error = true
    f.values.preview_count = "invalid"
    f.source:poll_mission_preview()
    local preview = assert(f.source.mission_preview)
    equal(preview.quest_life, nil)
    equal(preview.time_limit, nil)
    equal(preview.member_count, nil)
    equal(preview.member_max, 4)
    equal(#preview.players, 2)
    equal(preview.targets[1], "Rey Dau")
    assert(f.reports.mision_desmayos and f.reports.mision_tiempo and f.reports.mision_ocupacion)
    f.values.preview_limits_error = false
    f.values.preview_count = nil
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.quest_life, 3)
    equal(f.source.mission_preview.time_limit, 1800)
    equal(next(f.reports), nil)
end)

test("mission ranks decode boxed integer values and boxed host flags by their declared types", function()
    for _, type_name in ipairs({ "System.SByte", "System.Byte", "System.Int16", "System.UInt16",
        "System.Int32", "System.UInt32", "System.Int64", "System.UInt64" }) do
        local f = mission_preview_fixture()
        f.values.preview_ranks[1] = object(type_name, { m_value = 120 }, {})
        f.values.preview_hosts[1] = object("System.Boolean", { m_value = true }, {})
        f.values.preview_hosts[2] = object("System.Boolean", { m_value = false }, {})
        f.source:poll_mission_preview()
        local preview = assert(f.source.mission_preview)
        equal(preview.players[1].rank, 120)
        equal(preview.players[1].host, true)
        equal(preview.players[2].rank, 234)
        equal(preview.players[2].host, false)
        equal(next(f.reports), nil)
    end
end)

test("unreadable mission ranks remain unknown without suspending names and recover on the next poll", function()
    for _, invalid in ipairs({
        -1, 0 / 0, math.huge, 75.5, "512", false,
        object("System.Int32", { m_value = -1 }, {}),
        object("System.Int32", {}, {}),
        object("System.Int32", { m_value = "512" }, {}),
        object("app.UnexpectedRank", { m_value = 512 }, {}),
    }) do
        local f = mission_preview_fixture()
        f.values.preview_ranks[1] = invalid
        f.source:poll_mission_preview()
        local preview = assert(f.source.mission_preview)
        equal(#preview.players, 2)
        equal(preview.players[1].name, "Dome")
        equal(preview.players[1].rank, nil)
        equal(preview.players[2].rank, 234)
        equal(preview.quest_life, 3)
        assert(f.reports.mision_jugadores:find("plaza #1", 1, true))
        equal(f.source.feature_failures.mision_seleccionada, nil)
        f.values.preview_ranks[1] = 512
        f.source:poll_mission_preview()
        equal(f.source.mission_preview.players[1].rank, 512)
        equal(f.reports.mision_jugadores, nil)
    end
end)

test("invalid mission host flags cannot hide roster or invent a host", function()
    local f = mission_preview_fixture()
    f.values.preview_hosts[1] = object("System.Int32", { m_value = 1 }, {})
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.players[1].host, nil)
    equal(f.source.mission_preview.players[1].rank, 512)
    assert(f.reports.mision_jugadores:find("System.Int32", 1, true))
    equal(f.source.feature_failures.mision_seleccionada, nil)
    f.values.preview_hosts[1] = true
    f.source:poll_mission_preview()
    equal(f.source.mission_preview.players[1].host, true)
    equal(f.reports.mision_jugadores, nil)
end)

test("unsupported mission name types never hide the panel or fabricate object addresses as names", function()
    for _, invalid in ipairs({
        123, false, "\255",
        object("app.UnexpectedName", {}, { ToString = function() return "fake" end }),
        object("System.String", {}, { ToString = function() error("String unavailable") end }),
        object("System.String", {}, { ToString = function() return {} end }),
    }) do
        local f = mission_preview_fixture()
        f.values.preview_names = { invalid, "Hunter B" }
        f.source:poll_mission_preview()
        local preview = assert(f.source.mission_preview)
        equal(#preview.players, 1)
        equal(preview.players[1].name, "Hunter B")
        equal(preview.players[1].rank, 234)
        assert(f.reports.mision_jugadores:find("plaza #1", 1, true))
        equal(f.source.feature_failures.mision_seleccionada, nil)
        f.values.preview_names[1] = "Dome"
        f.source:poll_mission_preview()
        equal(#f.source.mission_preview.players, 2)
        equal(f.reports.mision_jugadores, nil)
    end
end)

test("HP ratio is exact and bounded; real numeric HP is preserved", function()
    local model = Model.new()
    model:set("a", { name = "Rey Dau", health = 12500, max_health = 20000 })
    equal(model:rows(3, false)[1].ratio, 0.625)
    model:set("a", { name = "Rey Dau", health = 21000, max_health = 20000 })
    equal(model.monsters.a.ratio, 1)
    equal(model.monsters.a.health, 21000)
    model:set("a", { name = "Rey Dau", health = -10, max_health = 20000 })
    equal(model.monsters.a.ratio, 0)
    equal(#model:rows(3, false), 0)
    equal(#model:rows(3, true), 1)
end)

test("invalid HP and names raise errors and remove previous values", function()
    local model = Model.new()
    for _, invalid in ipairs({ 0, -1, math.huge, 0 / 0, "20000" }) do
        model:set("a", { name = "A", health = 5, max_health = 10 })
        raises(function()
            model:set("a", { name = "A", health = 5, max_health = invalid })
        end, "Vida invalida")
        equal(model.monsters.a, nil)
    end
    raises(function()
        model:set("a", { name = "A", health = 0 / 0, max_health = 10 })
    end, "Vida invalida")
    raises(function()
        model:set("a", { name = "", health = 5, max_health = 10 })
    end, "Nombre")
end)

test("sampling interval and expiry use render frames, not CPU time", function()
    local model = Model.new()
    equal(model:should_sample("a", 6), true)
    model:set("a", { name = "A", health = 5, max_health = 10 })
    for _ = 1, 5 do
        model:advance()
        equal(model:should_sample("a", 6), false)
    end
    model:advance()
    equal(model:should_sample("a", 6), true)
    for _ = 1, 120 do model:advance() end
    assert(model.monsters.a)
    model:advance()
    equal(model.monsters.a, nil)
    equal(model.next_sample.a, nil)
end)

test("rows sort deterministically, limit results and clear completely", function()
    local model = Model.new()
    for key, name in pairs({ c = "Z", b = "A", a = "A" }) do
        model:should_sample(key, 6)
        model:set(key, { name = name, health = 5, max_health = 10 })
    end
    local rows = model:rows(2, false)
    equal(#rows, 2)
    equal(rows[1].key, "a")
    equal(rows[2].key, "b")
    model:remove("a")
    equal(model.next_sample.a, nil)
    model:clear()
    equal(next(model.monsters), nil)
    equal(next(model.next_sample), nil)
end)

test("configuration defaults are fresh and older partial configs are accepted", function()
    local a = spanish_defaults()
    a.scale = 2
    equal(spanish_defaults().scale, 1)
    local loaded = assert(Config.validate({ x = 120 }))
    equal(loaded.x, 120)
    equal(loaded.width, 340)
    equal(loaded.enabled, true)
end)

test("configuration rejects corrupt types, nonfinite values and invalid ranges", function()
    for _, value in ipairs({ false, 1, "bad" }) do
        local result, err = Config.validate(value)
        equal(result, nil)
        assert(err)
    end
    for _, raw in ipairs({
        { enabled = 1 }, { scale = 0 / 0 }, { x = -1 }, { x = 1.5 },
        { scale = math.huge }, { width = 100 }, { sample_frames = 0 },
        { max_monsters = 100 }, { show_dead = "false" },
    }) do
        local result, err = Config.validate(raw)
        equal(result, nil)
        assert(err)
    end
end)

test("config load distinguishes missing from corrupt and save failures are explicit", function()
    local loaded = Config.load({ glob = function(pattern)
        equal(pattern, [[^mhoverlay\.json$]])
        return {}
    end }, {})
    equal(loaded.scale, 1)
    local invalid, err = Config.load({ glob = function() return { Config.path } end },
        { load_file = function() return nil end })
    equal(invalid, nil)
    assert(err)
    local captured
    Config.save(spanish_defaults(), { dump_file = function(path, settings)
        equal(path, "mhoverlay.json")
        captured = settings
        return true
    end })
    equal(captured.sample_frames, 6)
    raises(function()
        Config.save(spanish_defaults(), { dump_file = function() return false end })
    end, "No se pudo guardar")
end)

test("Wilds hooks read real HP from args[2] and always preserve game behavior", function()
    local source, model, _, _, hooks = fixture()
    equal(source.ready, true)
    equal(#hooks, 2)
    equal(source.samples, 0)
    local update = hooks[2]
    equal(update.pre({ nil, "enemy_pointer" }), 0)
    equal(model:rows(3, false)[1].name, "Rey Dau")
    equal(model:rows(3, false)[1].ratio, 0.625)
    equal(source.samples, 1)
    local retval = {}
    equal(update.post(retval), retval)
    equal(hooks[1].post(retval), retval)
    equal(hooks[1].pre({ nil, "enemy_pointer" }), 0)
    equal(#model:rows(3, false), 0)
end)

test("Wilds reads Basic as a field when get_Basic is absent", function()
    local source, model, _, _, hooks, reports = fixture({ Basic = "field" })
    equal(hooks[2].pre({ nil, "enemy_pointer" }), 0)
    equal(source.samples, 1)
    equal(model:rows(3, false)[1].name, "Rey Dau")
    equal(model:rows(3, false)[1].health, 12500)
    equal(next(reports), nil)
end)

test("Wilds supports mixed SDK properties, fields and backing fields", function()
    local source, model, _, _, hooks, reports = fixture({
        IsBoss = "field", Basic = "field", HealthMgr = "backing",
        EmID = "field", RoleID = "field", LegendaryID = "backing",
        Health = "field", MaxHealth = "backing",
    })
    equal(hooks[2].pre({ nil, "enemy_pointer" }), 0)
    equal(source.samples, 1)
    equal(model:rows(3, false)[1].ratio, 0.625)
    equal(next(reports), nil)
end)

test("false IsBoss fields exclude small enemies without missing-field errors", function()
    local _, model, _, _, hooks, reports = fixture({ IsBoss = "field" }, { boss = false })
    equal(hooks[2].pre({ nil, "enemy_pointer" }), 0)
    equal(#model:rows(3, false), 0)
    equal(next(reports), nil)
end)

test("optional monster states use SDK values and preserve real HP", function()
    local _, model, _, _, hooks, reports = fixture(nil, { pinned = true })
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model:rows(3, false)[1]
    equal(row.health, 12500)
    equal(row.pinned, true)
    equal(row.rage.active, false)
    equal(row.rage.current, 30)
    equal(row.rage.ratio, 0.3)
    equal(row.stamina.current, 180)
    equal(row.stamina.ratio, 0.6)
    equal(next(reports), nil)
end)

test("active rage and exhaustion timers are remaining seconds, never negative", function()
    local _, model, _, values, hooks = fixture(nil, { rage_active = true, stamina_active = true })
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model:rows(3, false)[1]
    equal(row.rage.remaining, 40)
    equal(row.rage.ratio, 40 / 60)
    equal(row.stamina.remaining, 25)
    values.rage_timer = 90
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].rage.remaining, 0)
    equal(model:rows(3, false)[1].rage.ratio, 0)
end)

test("new SDK states support direct fields and backing fields", function()
    local _, model, _, _, hooks, reports = fixture({
        Conditions = "field", Angry = "field", Tired = "backing",
        IsValid = "field", IsActive = "backing", IsTargetPinOn = "field",
        Value = "field", LimitValue = "backing", Stamina = "field", DefaultStamina = "backing",
    })
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model:rows(3, false)[1]
    equal(row.rage.ratio, 0.3)
    equal(row.stamina.ratio, 0.6)
    equal(row.pinned, false)
    equal(next(reports), nil)
end)

test("unavailable conditions are not invented and can appear on later updates", function()
    local _, model, _, values, hooks, reports = fixture(nil, { conditions_present = false })
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].rage, nil)
    equal(next(reports), nil)
    values.conditions_present = true
    values.rage_valid = false
    values.stamina_valid = false
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].rage, nil)
    equal(model:rows(3, false)[1].stamina, nil)
    equal(next(reports), nil)
end)

test("optional errors suspend only failing feature; HP and other states survive", function()
    local source, model, _, values, hooks, reports = fixture()
    values.rage_max = 0
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model:rows(3, false)[1]
    equal(row.health, 12500)
    equal(row.rage, nil)
    equal(row.stamina.current, 180)
    assert(reports.furia:find("HP sigue activo"))
    equal(reports.lectura, nil)
    values.rage_max = 100
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].rage, nil)
    source:retry_features()
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].rage.current, 30)
end)

test("disabled state widgets do not call incompatible optional SDK members", function()
    local _, model, settings, _, hooks, reports, types = fixture()
    settings.show_rage = false
    settings.auto_focus = false
    settings.show_stamina = false
    settings.show_pin = false
    settings.prioritize_pinned = false
    types["app.cEmModuleConditions"].get_method = function()
        error("optional module must not be accessed")
    end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].rage, nil)
    equal(model:rows(3, false)[1].stamina, nil)
    equal(model:rows(3, false)[1].pinned, nil)
    equal(next(reports), nil)
end)

test("nonfinite timers or nonboolean states report optional failures", function()
    for _, initial in ipairs({
        { rage_valid = 1 }, { rage_active = 1 }, { rage_current = math.huge },
        { rage_active = true, rage_timer = 0 / 0 }, { pinned = 1 },
    }) do
        local _, model, _, _, hooks, reports = fixture(nil, initial)
        hooks[2].pre({ nil, "enemy_pointer" })
        equal(model:rows(3, false)[1].health, 12500)
        assert(next(reports))
        equal(reports.lectura, nil)
    end
end)

test("pin filtering happens before row limits and prioritizes marked monsters", function()
    local model = Model.new()
    model:set("a", { name = "A", health = 50, max_health = 100 })
    model:set("b", { name = "B", health = 75, max_health = 100, pinned = false })
    model:set("z", { name = "Z", health = 90, max_health = 100, pinned = true })
    equal(model:rows(1, false, { prioritize_pinned = true })[1].name, "Z")
    local filtered = model:rows(1, false, { only_pinned = true })
    equal(#filtered, 1)
    equal(filtered[1].name, "Z")
    equal(model:rows(3, false, { damaged_first = true })[1].name, "A")
    equal(model:rows(1, false, {
        prioritize_pinned = true, damaged_first = true,
    })[1].name, "Z")
end)

test("mission objectives precede marked monsters and HP ordering before limits", function()
    local model = Model.new()
    model:set("a", { name = "A", health = 5, max_health = 100, pinned = true })
    model:set("z", { name = "Z", health = 90, max_health = 100, quest_target = true })
    model:set("y", { name = "Y", health = 80, max_health = 100, quest_target = true })
    local settings = spanish_defaults()
    settings.damaged_first = true
    local rows = model:rows(2, false, settings)
    equal(rows[1].name, "Y")
    equal(rows[2].name, "Z")
    settings.prioritize_quest = false
    equal(model:rows(1, false, settings)[1].name, "A")
end)

test("mission priority uses MissionManager target access key, not map pin or species", function()
    local _, model, _, values, hooks, reports = fixture(nil, {
        quest_target = true, pinned = false,
    })
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].quest_target, true)
    equal(next(reports), nil)
    values.quest_target = false
    values.pinned = true
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].quest_target, false)
    equal(model:rows(3, false)[1].pinned, true)
end)

test("missing mission or browser does not invent objectives and can recover", function()
    for _, absent in ipairs({ "mission_present", "browser_present" }) do
        local _, model, _, values, hooks, reports = fixture(nil, { [absent] = false })
        hooks[2].pre({ nil, "enemy_pointer" })
        equal(model:rows(3, false)[1].quest_target, nil)
        equal(next(reports), nil)
        values[absent] = true
        values.quest_target = true
        for _ = 1, 6 do model:advance() end
        hooks[2].pre({ nil, "enemy_pointer" })
        equal(model:rows(3, false)[1].quest_target, true)
    end
end)

test("incompatible mission SDK suspends only mission priority", function()
    local source, model, _, _, hooks, reports, types = fixture()
    types["app.MissionManager"].get_method = function() return nil end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].health, 12500)
    equal(model:rows(3, false)[1].quest_target, nil)
    assert(reports.mision:find("isQuestTarget", 1, true))
    equal(source.feature_failures.mision, true)
end)

test("Wilds samples are throttled, and disabling avoids SDK reads", function()
    local source, model, settings, values, hooks = fixture()
    local update = hooks[2]
    update.pre({ nil, "enemy_pointer" })
    values.health = 10000
    update.pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].health, 12500)
    for _ = 1, 6 do model:advance() end
    update.pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].health, 10000)
    settings.enabled = false
    equal(update.pre({ nil, "invalid_pointer" }), 0)
    equal(source.samples, 2)
end)

test("small enemies are excluded; read failures remove stale HP and report", function()
    local _, model, _, values, hooks, reports = fixture()
    hooks[2].pre({ nil, "enemy_pointer" })
    for _ = 1, 6 do model:advance() end
    values.boss = false
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(#model:rows(3, false), 0)
    for _ = 1, 6 do model:advance() end
    values.boss = true
    values.health = 0 / 0
    equal(hooks[2].pre({ nil, "enemy_pointer" }), 0)
    equal(#model:rows(3, false), 0)
    assert(reports.lectura:find("Vida invalida"))
end)

test("missing reflected members report the exact SDK member", function()
    local _, model, _, _, hooks, reports, types = fixture()
    types["app.cEnemyContext"].get_method = function() return nil end
    equal(hooks[2].pre({ nil, "enemy_pointer" }), 0)
    equal(#model:rows(3, false), 0)
    assert(reports.lectura:find("app.cEnemyContext.get_IsBoss", 1, true))
    local sdk_api = { find_type_definition = function() return nil end }
    raises(function()
        Wilds.new(sdk_api, Model.new(), spanish_defaults(), function() end):install()
    end, "No se encuentran los tipos")
end)

local function render_fixture()
    local rects, texts = {}, {}
    local stack = 0
    local draw_api = {
        filled_rect = function(x, y, w, h, color)
            rects[#rects + 1] = { x = x, y = y, w = w, h = h, color = color }
        end,
        text = function(value)
            texts[#texts + 1] = value
        end,
    }
    local imgui_api = {
        get_display_size = function() return { x = 1920, y = 1080 } end,
        push_font_size = function() stack = stack + 1 end,
        pop_font_size = function() stack = stack - 1 end,
    }
    return draw_api, imgui_api, rects, texts, function() return stack end
end

test("mission preview renderer draws selected roster and advertised mission limits", function()
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    local settings = spanish_defaults()
    View.render_mission_preview(draw_api, imgui_api, settings, {
        players = {
            { name = "Dome", rank = 512, host = true },
            { name = "Hunter B", rank = 234, host = false },
        },
        targets = { "Rey Dau" },
        member_count = 2,
        member_max = 4,
        quest_life = 3,
        time_limit = 1800,
    })
    local labels = table.concat(texts, "\n")
    for _, label in ipairs({ "MISION SELECCIONADA", "2/4 cazadores", "Rey Dau",
        "Dome", "RC 512", "ANFITRION", "Hunter B", "RC 234", "3 desmayos",
        "30:00", "HP y desmayos actuales: al entrar a la mision" }) do
        assert(labels:find(label, 1, true), label)
    end
    assert(#rects > 1)
    equal(rects[1].x, settings.mission_x)
    equal(rects[1].y, settings.mission_y)
    equal(stack(), 0)
    settings.show_mission_preview = false
    View.render_mission_preview(draw_api, imgui_api, settings, {})
    equal(#rects, 2)
end)

test("mission preview draws incomplete roster warning and unknown ranks explicitly", function()
    local f = mission_preview_fixture()
    f.values.preview_slots = 2
    f.values.preview_ranks = { [2] = 234 }
    f.source:poll_mission_preview()
    local d, i, _, texts, stack = render_fixture()
    View.render_mission_preview(d, i, f.settings, f.source.mission_preview)
    local labels = table.concat(texts, "\n")
    assert(labels:find("RC --", 1, true))
    assert(labels:find("Datos de cazadores incompletos", 1, true))
    equal(stack(), 0)
end)

test("mission renderer shows missing limits explicitly without inventing occupancy", function()
    local f = mission_preview_fixture()
    f.values.preview_limits_error = true
    f.values.preview_count = "invalid"
    f.values.name = nil
    f.source:poll_mission_preview()
    local d, i, rects, texts, stack = render_fixture()
    View.render_mission_preview(d, i, f.settings, f.source.mission_preview)
    local content = table.concat(texts, "\n")
    assert(content:find("--/4 cazadores", 1, true))
    assert(content:find("Limite: -- desmayos  |  Tiempo: --", 1, true))
    assert(content:find("Objetivos no disponibles", 1, true))
    assert(content:find("Dome", 1, true))
    assert(rects[1].y + rects[1].h <= 1080)
    equal(stack(), 0)
end)

test("mission preview header and fixed fonts retain nonoverlapping lines at small scales", function()
    local f = mission_preview_fixture()
    f.source:poll_mission_preview()
    f.settings.scale = 0.5
    f.settings.mission_size = 50
    f.settings.mission_width = 300
    local d, i, rects = render_fixture()
    i.push_font_size, i.pop_font_size = nil, nil
    local lines = {}
    d.text = function(_, x, y, color)
        if color ~= 0xFF000000 then lines[#lines + 1] = { x = x, y = y } end
    end
    View.render_mission_preview(d, i, f.settings, f.source.mission_preview)
    assert(#lines > 5)
    for index, line in ipairs(lines) do
        if index > 1 then assert(line.y - lines[index - 1].y >= 19) end
        assert(line.y >= rects[1].y)
        assert(line.y + 15 <= rects[1].y + rects[1].h)
    end
end)

test("built-in renderer draws exact HP fill and percentage without D2D", function()
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    local settings = spanish_defaults()
    settings.show_monster_icons = false
    View.render(draw_api, imgui_api, settings,
        { { name = "Rey Dau", health = 12500, max_health = 20000, ratio = 0.625 } })
    assert(#rects > 100)
    local fill_right = 0
    for _, rect in ipairs(rects) do
        if rect.y >= settings.y + 62 and rect.y < settings.y + 74
            and (rect.color >> 24) == 255 and (rect.color & 255) <= 65 then
            fill_right = math.max(fill_right, rect.x + rect.w)
        end
    end
    assert(fill_right <= settings.x + 12 + (340 - 24) * 0.625)
    assert(fill_right >= settings.x + 12 + (340 - 24) * 0.625 - 1)
    equal(texts[3], "12500 / 20000 HP  (62.5%)")
    equal(stack(), 0)
end)

test("renderer respects disable, clamps position and supports older REFramework", function()
    local draw_api, imgui_api, rects = render_fixture()
    local settings = spanish_defaults()
    settings.enabled = false
    View.render(draw_api, imgui_api, settings, {}, "Waiting")
    equal(#rects, 0)
    settings.enabled = true
    settings.x = 16384
    settings.y = 16384
    imgui_api.push_font_size = nil
    imgui_api.pop_font_size = nil
    View.render(draw_api, imgui_api, settings, {}, "Waiting")
    assert(rects[1].x + rects[1].w <= 1920)
    assert(rects[1].y + rects[1].h <= 1080)
end)

test("render errors unwind the font stack and remain visible to caller", function()
    local draw_api, imgui_api, _, _, stack = render_fixture()
    draw_api.text = function() error("render test failure") end
    raises(function()
        View.render(draw_api, imgui_api, spanish_defaults(), {}, "Waiting")
    end, "render test failure")
    equal(stack(), 0)
end)

test("timer formatting rounds up seconds and handles minute boundaries", function()
    equal(View.timer(0), "0:00")
    equal(View.timer(-2), "0:00")
    equal(View.timer(0.1), "0:01")
    equal(View.timer(59.1), "1:00")
    equal(View.timer(125), "2:05")
end)

test("state widgets draw active timers and bars and mark pinned monster", function()
    local draw_api, imgui_api, rects, texts = render_fixture()
    View.render(draw_api, imgui_api, spanish_defaults(), {
        { name = "Rey Dau", health = 12500, max_health = 20000, ratio = 0.625,
            pinned = true,
            rage = { active = true, remaining = 42, ratio = 0.7 },
            stamina = { active = false, current = 180, maximum = 300, ratio = 0.6 } },
    })
    equal(rects[1].h, 144)
    equal(texts[1], "[*] Rey Dau")
    local rendered = table.concat(texts, "\n")
    assert(rendered:find("0:42", 1, true))
    assert(rendered:find("Furia", 1, true))
    assert(rendered:find("Paralisis", 1, true))
    local stamina_fill
    for _, rect in ipairs(rects) do
        if rect.h == 3 and rect.color == 0xFF70CDE8 then stamina_fill = rect end
    end
    equal(stamina_fill.w, 316 * 0.6)
end)

test("compact and opacity controls affect layout without hiding numeric HP", function()
    local draw_api, imgui_api, rects, texts = render_fixture()
    local settings = spanish_defaults()
    settings.compact = true
    settings.opacity = 0
    View.render(draw_api, imgui_api, settings,
        { { name = "A", health = 50, max_health = 100, ratio = 0.5 } })
    equal(rects[1].h, 66)
    equal(rects[1].color >> 24, 0)
    local last_bar_y = 0
    for _, rect in ipairs(rects) do
        if rect.y >= settings.y + 55 then last_bar_y = math.max(last_bar_y, rect.y + rect.h) end
    end
    equal(last_bar_y, settings.y + 60)
    assert(table.concat(texts, "\n"):find("50 / 100 HP", 1, true))
end)

test("variable-height panels never draw rows below bottom of screen", function()
    local draw_api, imgui_api, rects = render_fixture()
    imgui_api.get_display_size = function() return { x = 640, y = 400 } end
    local settings = spanish_defaults()
    settings.scale = 2
    settings.horizontal = false
    local rows = {}
    for _ = 1, 10 do
        rows[#rows + 1] = {
            name = "A", health = 50, max_health = 100, ratio = 0.5,
            rage = { active = true, remaining = 42, ratio = 0.7 },
            stamina = { active = true, remaining = 10, ratio = 0.5 },
        }
    end
    View.render(draw_api, imgui_api, settings, rows, "Estado")
    assert(#rects > 100)
    for _, rect in ipairs(rects) do
        assert(rect.x >= 0 and rect.x + rect.w <= 640)
        assert(rect.y >= 0 and rect.y + rect.h <= 400)
    end
end)

test("horizontal cards align at the top and wrap using the tallest card", function()
    local settings = spanish_defaults()
    settings.x, settings.y = 0, 0
    local tall = { name = "A", rage = {}, stamina = {} }
    local short = { name = "B" }
    local layout = View.layout(settings, { tall, short, short }, { x = 700, y = 600 }, false)
    equal(#layout.panels, 3)
    equal(layout.panels[1].x, 0)
    equal(layout.panels[2].x, 348)
    equal(layout.panels[2].y, 0)
    equal(layout.panels[3].x, 0)
    equal(layout.panels[3].y, 152)
end)

test("horizontal group clamps as a unit, preserving order and status placement", function()
    local settings = spanish_defaults()
    settings.x, settings.y = 16384, 16384
    local layout = View.layout(settings, { { name = "A" }, { name = "B" } },
        { x = 1000, y = 400 }, true)
    equal(layout.x, 1000 - 688)
    equal(layout.panels[1].y, layout.panels[2].y)
    equal(layout.status_y, 96)
    equal(layout.y + layout.status_y + 30, 400)
end)

test("layout reserves full status height and retains vertical option", function()
    local settings = spanish_defaults()
    settings.horizontal = false
    local layout = View.layout(settings, { {}, {} }, { x = 1920, y = 216 }, true)
    equal(#layout.panels, 1)
    equal(layout.status_y, 96)
    layout = View.layout(settings, { {}, {} }, { x = 1920, y = 1080 }, false)
    equal(layout.panels[1].x, layout.panels[2].x)
    equal(layout.panels[2].y, 96)
end)

test("renderer distinguishes mission objective from marked monster", function()
    local draw_api, imgui_api, _, texts = render_fixture()
    View.render(draw_api, imgui_api, spanish_defaults(), {
        { name = "Objetivo", health = 50, max_health = 100, ratio = 0.5,
            quest_target = true, pinned = false },
    })
    equal(texts[1], "[M] Objetivo")
end)

test("part summary counts only breakable slots and complete breaks, not break events", function()
    local _, model, _, _, hooks, reports = fixture(nil, { parts_data = {
        { max = 0, broken = false }, { max = 2, broken = true },
        { max = 3, broken = false },
    } })
    hooks[2].pre({ nil, "enemy_pointer" })
    local parts = model:rows(3, false)[1].parts
    equal(parts.total, 2)
    equal(parts.broken, 1)
    equal(parts.entries[1].index, 1)
    equal(parts.entries[2].index, 2)
    equal(parts.entries[2].broken, false)
    equal(next(reports), nil)
end)

test("part snapshots refresh, contain no SDK references and remove destroyed monsters", function()
    local _, model, _, values, hooks = fixture()
    hooks[2].pre({ nil, "enemy_pointer" })
    local old = model:rows(3, false)[1].parts
    values.parts_data[1].broken = true
    equal(old.broken, 1)
    equal(old.entries[1].broken, false)
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].parts.broken, 2)
    equal(getmetatable(model:rows(3, false)[1].parts.entries[1]), nil)
    hooks[1].pre({ nil, "enemy_pointer" })
    equal(#model:rows(3, false), 0)
end)

test("wounds group all slots by reflected enum names without hardcoded numeric values", function()
    local _, model, _, _, hooks, reports, types = fixture(nil, { wounds_data = { 99, 99, 0 } })
    types["app.cEmModuleScar.cScarParts.STATE"].get_fields = function()
        return {
            { is_static = function() return true end,
                get_data = function() return 99 end, get_name = function() return "RAW" end },
            { is_static = function() return true end,
                get_data = function() return 0 end, get_name = function() return "NORMAL" end },
        }
    end
    hooks[2].pre({ nil, "enemy_pointer" })
    local wounds = model:rows(3, false)[1].wounds
    equal(wounds.total, 3)
    equal(wounds.states.RAW, 2)
    equal(wounds.states.NORMAL, 1)
    equal(next(reports), nil)
end)

test("unknown wounds never become fake zeros and do not interrupt HP or parts", function()
    local _, model, _, _, hooks, reports = fixture(nil, { wounds_data = { 999 } })
    equal(hooks[2].pre({ nil, "enemy_pointer" }), 0)
    local row = model:rows(3, false)[1]
    equal(row.health, 12500)
    equal(row.parts.total, 2)
    equal(row.wounds, nil)
    assert(reports.heridas:find("desconocido"))
    equal(reports.lectura, nil)
end)

test("missing optional modules are absent rather than zero-filled summaries", function()
    local _, model, _, _, hooks, reports = fixture(nil, {
        parts_present = false, scar_present = false,
    })
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].parts, nil)
    equal(model:rows(3, false)[1].wounds, nil)
    equal(next(reports), nil)
end)

test("invalid part records are isolated while oversized arrays suspend only the parts feature", function()
    for _, initial in ipairs({
        { parts_data = { { max = 1, broken = 1 } } },
        { parts_data = { { max = -1, broken = false } } },
    }) do
        local _, model, _, _, hooks, reports = fixture(nil, initial)
        hooks[2].pre({ nil, "enemy_pointer" })
        local row = model:rows(3, false)[1]
        equal(row.health, 12500)
        equal(row.parts.total, 0)
        equal(row.parts.invalid, 1)
        assert(row.wounds)
        assert(reports.partes_registros)
        equal(reports.partes, nil)
        equal(reports.lectura, nil)
    end
    for _, initial in ipairs({ { parts_size = 513 }, { parts_size = 0 / 0 } }) do
        local _, model, _, _, hooks, reports = fixture(nil, initial)
        hooks[2].pre({ nil, "enemy_pointer" })
        local row = model:rows(3, false)[1]
        equal(row.health, 12500)
        equal(row.parts, nil)
        assert(row.wounds)
        assert(reports.partes)
        equal(reports.lectura, nil)
    end
end)

test("part summaries retain good records and mark incomplete badges and diagnostics", function()
    local _, model, settings, values, hooks, reports = fixture(nil, {
        parts_data = {
            { max = 1, broken = true },
            { max = -1, broken = false },
            { max = 2, broken = false },
        },
    })
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model:rows(3, false)[1]
    equal(row.parts.total, 2)
    equal(row.parts.broken, 1)
    equal(row.parts.invalid, 1)
    assert(reports.partes_registros:find("parte #1", 1, true))
    equal(View.badges(row, settings)[1].count, "1/2?")
    settings.parts_details = true
    assert(View.detail_lines(row, settings)[2]:find("Partes no leidas: 1", 1, true))
    values.parts_data[2].max = 1
    for _ = 1, settings.sample_frames do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].parts.total, 3)
    equal(reports.partes_registros, nil)
end)

test("parts and wounds switches skip unavailable SDK APIs", function()
    local _, model, settings, _, hooks, reports, types = fixture()
    settings.show_parts = false
    settings.show_wounds = false
    types["app.cEmModuleParts"].get_method = function() error("must not read parts") end
    types["app.cEmModuleScar"].get_method = function() error("must not read scars") end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].parts, nil)
    equal(model:rows(3, false)[1].wounds, nil)
    equal(next(reports), nil)
end)

test("parts and wounds work with direct SDK fields and backing fields", function()
    local _, model, _, _, hooks, reports = fixture({
        Parts = "field", Scar = "field", BreakParts = "backing", ScarParts = "field",
        MaxBreakCount = "field", IsBreakAll = "backing", State = "field",
    })
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].parts.broken, 1)
    equal(model:rows(3, false)[1].wounds.states.RAW, 2)
    equal(next(reports), nil)
end)

test("details use real SDK indices, explicit truncation and deterministic wound order", function()
    local settings = spanish_defaults()
    settings.parts_details = true
    settings.max_parts = 1
    local row = { parts = { broken = 1, total = 2, entries = {
        { index = 2, broken = false }, { index = 7, broken = true },
    } }, wounds = { states = { RAW = 2, NORMAL = 1 } } }
    local lines = View.detail_lines(row, settings)
    equal(lines[1], "Roturas completas: 1 / 2")
    equal(lines[2], "Parte #2: pendiente")
    equal(lines[3], "+ 1 partes sin mostrar")
    equal(lines[4], "Heridas: estados SDK")
    equal(lines[5], "NORMAL: 1")
    equal(lines[6], "RAW: 2")
    settings.show_parts = false
    settings.show_wounds = false
    equal(#View.detail_lines(row, settings), 0)
end)

test("empty arrays display genuine zero counts and no wounds rather than failures", function()
    local _, model, settings, _, hooks, reports = fixture(nil, { parts_data = {}, wounds_data = {} })
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model:rows(3, false)[1]
    equal(row.parts.total, 0)
    equal(row.wounds.total, 0)
    local lines = View.detail_lines(row, settings)
    equal(lines[1], "Roturas completas: 0 / 0")
    equal(lines[3], "Sin entradas de heridas")
    equal(next(reports), nil)
end)

test("four badges replace long text lists and add only 44 pixels to panel height", function()
    local draw_api, imgui_api, rects, texts = render_fixture()
    local row = { name = "A", health = 50, max_health = 100, ratio = 0.5,
        parts = { broken = 1, total = 2, entries = {} },
        wounds = { states = { RAW = 2 } } }
    local settings = spanish_defaults()
    View.render(draw_api, imgui_api, settings, { row })
    equal(rects[1].h, 88 + 44)
    local rendered = table.concat(texts, "\n")
    assert(rendered:find("1/2", 1, true))
    assert(not rendered:find("Roturas completas", 1, true))
    assert(not rendered:find("Heridas:", 1, true))
    assert(not rendered:find("RAW:", 1, true))
    local layout = View.layout(settings, { row }, { x = 640, y = 100 }, false)
    equal(#layout.panels, 0)
end)

test("badges use fixed order and distinguish unavailable data from genuine zeros", function()
    local settings = spanish_defaults()
    local badges = View.badges({ parts = { broken = 1, total = 3 },
        wounds = { states = { NORMAL = 15, TEAR = 1, OLD = 5, HEAL = 2 } } }, settings)
    equal(#badges, 4)
    equal(badges[1].kind, "parts")
    equal(badges[1].count, "1/3")
    equal(badges[2].kind, "NORMAL")
    equal(badges[2].count, "15")
    equal(badges[3].kind, "TEAR")
    equal(badges[3].count, "1")
    equal(badges[4].kind, "RAW")
    equal(badges[4].count, "0")
    settings.show_parts = false
    equal(View.badges({}, settings)[1].count, "--")
    equal(View.badges({}, settings)[2].count, "--")
end)

test("part detail and old wound states cannot enlarge the badge row", function()
    local settings = spanish_defaults()
    settings.parts_details = true
    local row = { parts = { broken = 1, total = 12, entries = {} },
        wounds = { states = { NORMAL = 5, OLD = 20, HEAL = 2 } } }
    for index = 1, 12 do
        row.parts.entries[index] = { index = index, broken = false }
    end
    local layout = View.layout(settings, { row }, { x = 1920, y = 1080 }, false)
    equal(layout.panels[1].height, 132)
    settings.show_parts = false
    settings.show_wounds = false
    equal(View.layout(settings, { row }, { x = 1920, y = 1080 }, false).panels[1].height, 88)
end)

test("badges appear below stamina in a single row", function()
    local draw_api, imgui_api, rects, texts = render_fixture()
    local settings = spanish_defaults()
    local row = { name = "A", health = 50, max_health = 100, ratio = 0.5,
        stamina = { active = false, current = 10, maximum = 20, ratio = 0.5 },
        parts = { broken = 1, total = 3, entries = {} },
        wounds = { states = { NORMAL = 15, TEAR = 1, RAW = 2 } } }
    local positions = {}
    draw_api.text = function(value, x, y)
        positions[value] = { x = x, y = y }
    end
    View.render(draw_api, imgui_api, settings, { row })
    local a, b, c, d = positions["1/3"], positions["15"], positions["1"], positions["2"]
    assert(a.x < b.x and b.x < c.x and c.x < d.x)
    equal(a.y, b.y)
    equal(b.y, c.y)
    equal(c.y, d.y)
    assert(a.y > rects[4].y + rects[4].h)
    assert(a.y + 18 <= rects[1].y + rects[1].h)
end)
test("retry clears wound enum cache as well as suspended optional reads", function()
    local source, model, _, values, hooks, reports = fixture(nil, { wounds_data = { 999 } })
    hooks[2].pre({ nil, "enemy_pointer" })
    assert(reports.heridas)
    assert(source.scar_states)
    source:retry_features()
    equal(source.scar_states, nil)
    values.wounds_data = { 2 }
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(3, false)[1].wounds.states.RAW, 1)
end)

test("old configuration gains new controls without losing placement", function()
    local settings = assert(Config.validate({ x = 250, y = 50, scale = 1.5 }))
    equal(settings.x, 250)
    equal(settings.y, 50)
    equal(settings.scale, 1.5)
    equal(settings.show_rage, true)
    equal(settings.opacity, 85)
    equal(settings.only_pinned, false)
    equal(settings.horizontal, true)
    equal(settings.prioritize_quest, true)
    equal(settings.show_parts, true)
    equal(settings.show_wounds, true)
    equal(settings.parts_details, false)
    equal(settings.max_parts, 4)
    equal(Config.validate({ max_parts = 0 }), nil)
    equal(Config.validate({ max_parts = 1.5 }), nil)
    equal(Config.validate({ opacity = 101 }), nil)
    equal(Config.validate({ opacity = 0.5 }), nil)
    equal(Config.validate({ only_pinned = 1 }), nil)
end)

test("damage meter uses individual combat time, exact totals and leader-relative bars", function()
    local damage = Damage.new()
    damage:update("hunt", 300)
    local a = { id = "a", name = "Tu cazador", is_self = true }
    local b = { id = "b", name = "Segundo", is_self = false }
    a.in_combat, b.in_combat = true, true
    damage:sync({ a, b })
    damage:add(a, 750.5)
    damage:add(b, 249.5)
    local rows, total = damage:rows()
    equal(total, 1000)
    equal(rows[1].dps, nil)
    damage:update("hunt", 310)
    rows = damage:rows()
    equal(rows[1].damage, 750.5)
    equal(rows[1].dps, 75.05)
    equal(rows[1].share, 0.7505)
    equal(rows[1].ratio, 1)
    equal(rows[2].ratio, 249.5 / 750.5)
    damage:update("hunt", 310)
    equal(damage:rows()[1].dps, 75.05)
    equal(damage.hits, 2)
end)

test("each hunter pauses and resumes their own combat timer without counting mission travel or late joins", function()
    local damage = Damage.new()
    local a = { id = "a", name = "A", is_self = true, in_combat = false }
    local b = { id = "b", name = "B", is_self = false, in_combat = false }
    damage:update("quest:hunt", 0)
    damage:sync({ a, b })
    damage:update("quest:hunt", 1500)
    equal(damage:rows()[1].elapsed, 0)
    a.in_combat = true
    damage:sync({ a, b })
    damage:add(a, 1000)
    damage:update("quest:hunt", 1510)
    b.in_combat = true
    damage:sync({ a, b })
    damage:add(b, 600)
    damage:update("quest:hunt", 1520)
    a.in_combat = false
    damage:sync({ a, b })
    damage:update("quest:hunt", 1530)
    b.in_combat = false
    damage:sync({ a, b })
    damage:update("quest:hunt", 1800)
    local rows = damage:rows()
    equal(rows[1].elapsed, 20)
    equal(rows[1].dps, 50)
    equal(rows[2].elapsed, 20)
    equal(rows[2].dps, 30)
    a.in_combat = true
    damage:sync({ a, b })
    damage:update("quest:hunt", 1810)
    equal(damage:rows()[1].elapsed, 30)
    equal(damage:rows()[2].elapsed, 20)
    local late = { id = "late", name = "Late", is_self = false, in_combat = true }
    damage:sync({ a, b, late })
    damage:add(late, 200)
    damage:update("quest:hunt", 1820)
    equal(damage.players.late.elapsed, 10)
    damage:sync({ b, late })
    damage:update("quest:hunt", 1900)
    equal(damage.players.a.elapsed, 40)
    damage:update(nil)
    equal(damage:rows()[1].dps, 30)
end)

test("expedition resumes accumulated combat time but excludes the whole inactive gap", function()
    local damage = Damage.new()
    local player = { id = "a", name = "A", is_self = true, in_combat = true }
    damage:update("battle:a", 0)
    damage:sync({ player })
    damage:add(player, 100)
    damage:update("battle:a", 10)
    damage:update(nil)
    damage:update("battle:a", 1000)
    damage:sync({ player })
    damage:update("battle:a", 1010)
    equal(damage:rows()[1].elapsed, 20)
    equal(damage:rows()[1].dps, 5)
end)

test("damage lifecycle freezes results and resets new hunts but never resets on clock jitter", function()
    local damage = Damage.new()
    local player = { id = "a", name = "Cazador", is_self = true }
    damage:add(player, 100)
    equal(#damage:rows(), 0)
    damage:update("one", 120)
    player.in_combat = true
    damage:sync({ player })
    damage:add(player, 50)
    damage:update("one", 125)
    damage:update(nil)
    damage:add(player, 900)
    equal(damage:rows()[1].damage, 50)
    equal(damage:rows()[1].dps, 10)
    equal(damage.active, false)
    damage:update("two", 30)
    equal(#damage:rows(), 0)
    equal(damage.elapsed, 0)
    damage:add(player, 25)
    damage:update("two", 1)
    equal(damage:rows()[1].damage, 25)
    equal(damage.elapsed, 0)
    damage:update("two", 31)
    equal(damage.elapsed, 1)
    damage:update(nil)
    damage:update("two", 0)
    equal(#damage:rows(), 0)
    damage:add(player, 10)
    damage:clear()
    equal(damage.session, nil)
    equal(damage.hits, 0)
    equal(damage.elapsed, 0)
end)

test("damage rejects corrupt identity, time and amounts without inventing plausible DPS", function()
    local damage = Damage.new()
    local player = { id = "a", name = "A", is_self = true }
    damage:update("hunt", 0)
    for _, amount in ipairs({ -1, math.huge, 0 / 0, "10" }) do
        raises(function() damage:add(player, amount) end, "Dano final")
    end
    raises(function() damage:update("hunt", -1) end, "Tiempo")
    raises(function() damage:update("hunt", math.huge) end, "Tiempo")
    raises(function() damage:add({ id = "a", name = "", is_self = true }, 10) end, "Identidad")
    equal(damage.hits, 0)
    damage:player(player)
    damage:add(player, 0)
    equal(damage:rows()[1].share, 0)
    equal(damage:rows()[1].dps, nil)
end)

test("damage sorting is deterministic and percentages include departed players", function()
    local damage = Damage.new()
    damage:update("hunt", 0)
    local roster = {}
    for _, id in ipairs({ "b", "a" }) do
        local player = { id = id, name = "Same", is_self = false, in_combat = true }
        roster[#roster + 1] = player
        damage:add(player, 100)
    end
    damage:sync(roster)
    damage:update("hunt", 20)
    local rows = damage:rows()
    equal(rows[1].id, "a")
    equal(rows[2].share, 0.5)
    equal(rows[2].dps, 5)
end)

local function damage_fixture()
    local source, model, settings, _, hooks, reports, types = fixture()
    local f = { source = source, model = model, settings = settings,
        hooks = hooks, reports = reports, types = types,
        playing = true, started = 1000, time = 100, boss = true, dead = false,
        faint_limit = 3 }
    local inactive_methods = {
        get_IsDashJuice_On = function() return false end,
        get_IsImmunizer_On = function() return false end,
        get_IsHotDrink_On = function() return false end,
        get_IsCoolerDrink_On = function() return false end,
        get_IsKijinDrink_On = function() return false end,
        get_IsKijinDrink_G_On = function() return false end,
        get_IsKoukaDrink_On = function() return false end,
        get_IsKoukaDrink_G_On = function() return false end,
        get_IsActiveRevivalDrink = function() return false end,
    }
    for _, key in ipairs({ "Kairiki", "Kairiki_G", "KijinPowder", "KijinAmmo",
        "Nintai", "Nintai_G", "KoukaPowder", "KoukaAmmo", "PickUpStamina" }) do
        inactive_methods["get_" .. key .. "_Timer"] = function() return 0 end
    end
    local inactive_buffs = object("app.cHunterItemBuff", {}, inactive_methods)
    f.buff_status = object("app.cHunterStatus", {}, {
        get_ItemBuff = function() return inactive_buffs end,
    })
    local function info(index, name, address, is_self)
        local go = object("via.GameObject", {}, {}, address)
        local character = object("app.HunterCharacter", {}, {
            get_HunterStatus = function() return f.buff_status end,
            get_GameObject = function() return go end,
            get_IsMaster = function() return is_self end,
            get_IsCombat = function()
                if f.combat_error or (f.combat_errors and f.combat_errors[index + 1]) then
                    error("IsCombat unavailable")
                end
                if f.combat_states then return f.combat_states[index + 1] == true end
                return f.combat ~= false and (f.playing or f.combat == true)
            end,
            get_IsInLifeArea = function()
                if f.village_error then error("IsInLifeArea unavailable") end
                return f.village ~= false
            end,
        })
        local context = object("app.cPlayerContext", {}, {
            get_StableMemberIndex = function()
                f.index_reads = (f.index_reads or 0) + 1
                if f.index_error then error("StableMemberIndex unavailable") end
                if f.member_indices then return f.member_indices[index + 1] end
                return index
            end,
            get_PlayerName = function() return f.same_name and "Same hunter" or name end,
        })
        local holder = object("app.cHunterContextHolder", {}, {
            get_Pl = function() return context end,
        })
        local result = object("app.cPlayerManageInfo", {}, {
            get_Character = function() return character end,
            get_ContextHolder = function() return holder end,
        })
        return result, go
    end
    f.master, f.owner = info(0, "Tu cazador", 1000, true)
    f.remote, f.remote_owner = info(1, "Cazador remoto", 2000, false)
    f.members = { f.master, f.remote }
    f.manager = object("app.PlayerManager", {}, {
        getMasterPlayer = function() return f.master end,
        getQuestMembers = function()
            if f.collection == "managed_array" or f.collection == "indexed_array" then
                local methods = { get_Length = function() return f.size or #f.members end }
                if f.collection == "managed_array" then
                    methods["GetValue(System.Int32)"] = function(_, index)
                        return f.members[index + 1]
                    end
                end
                local result = object("app.cPlayerManageInfo[]", {}, methods)
                for index, member in ipairs(f.members) do result[index - 1] = member end
                return result
            elseif f.collection == "iterator" or f.collection == "explicit_iterator"
                or f.collection == "inherited_iterator" then
                local index = 0
                local methods = {
                    MoveNext = function()
                        if f.move_error then error("MoveNext failed") end
                        if f.move_invalid then return 1 end
                        index = index + 1
                        return index <= (f.size or #f.members)
                    end,
                    get_Current = function()
                        if f.current_error then error("Current failed") end
                        return f.members[index]
                    end,
                    Dispose = function()
                        f.disposals = (f.disposals or 0) + 1
                        if f.dispose_error then error("Dispose failed") end
                    end,
                }
                if f.missing_current then methods.get_Current = nil end
                local result, definition = object("app.PlayerManager.<getQuestMembers>d__111",
                    {}, f.collection == "iterator" and methods or {})
                if f.collection == "explicit_iterator" then
                    function definition:get_methods()
                        local result = {}
                        for name, callback in pairs(methods) do
                            result[#result + 1] = {
                                get_name = function() return "System.Collections.IEnumerator." .. name end,
                                call = function(_, instance, ...)
                                    return callback(instance, ...)
                                end,
                            }
                        end
                        return result
                    end
                elseif f.collection == "inherited_iterator" then
                    local _, parent = object("IteratorBase", {}, methods)
                    function definition:get_parent_type() return parent end
                end
                return result
            elseif f.collection == "enumerable" then
                return object("System.Collections.Generic.IEnumerable", {}, {
                    GetEnumerator = function()
                        local index = 0
                        return object("Enumerator", {}, {
                            MoveNext = function()
                                index = index + 1
                                return index <= (f.size or #f.members)
                            end,
                            get_Current = function() return f.members[index] end,
                        })
                    end,
                })
            elseif f.collection == "unsupported" then
                return object("app.UnknownPartyCollection", {}, {})
            end
            if f.list then
                return object("System.Collections.Generic.List", {}, {
                    get_Count = function() return #f.members end,
                    get_Item = function(_, index) return f.members[index + 1] end,
                })
            end
            local result = array(f.members, f.size)
            result.get_type_definition = function()
                return { get_method = function() return nil end }
            end
            return result
        end,
    })
    f.param_address = 12345
    local param = object("app.cQuestFlowParam", {}, {})
    param.get_address = function() return f.param_address end
    f.faint_fields = { v = 0, m = 7 }
    local encoded_faints = object("ace.Mandrake", f.faint_fields, {})
    local quest_data = object("app.cActiveQuestData", {}, {
        getQuestLife = function()
            if f.faint_error then error("Quest life unavailable") end
            return f.faint_limit
        end,
    })
    f.director_fields = { QuestPlDieCount = encoded_faints }
    f.director = object("app.cQuestDirector", f.director_fields, {
        get_Param = function() if not f.no_param then return param end end,
        get_QuestStartedTime = function() return f.started end,
        get_QuestElapsedTime = function() return f.time end,
        get_QuestData = function() return quest_data end,
    })
    f.mission = object("app.MissionManager", {}, {
        get_IsPlayingQuest = function() return f.playing end,
        get_QuestDirector = function() return f.director end,
        ["isQuestTarget(app.TARGET_ACCESS_KEY)"] = function() return false end,
    })
    local original_convert = source.sdk.to_managed_object
    source.sdk.to_managed_object = function(value)
        if value == "enemy_pointer" then return original_convert(value) end
        return value
    end
    source.sdk.get_managed_singleton = function(name)
        if name == "app.MissionManager" then return f.mission end
        if name == "app.NpcManager" then return f.npc_manager end
        if name == "app.GUIManager" then return f.gui_manager end
        if name == "app.GameFlowManager" then return f.flow_manager end
        if name == "app.DialogueManager" then return f.dialogue_manager end
        equal(name, "app.PlayerManager")
        return f.manager
    end
    source.sdk.typeof = function(name) equal(name, "app.EnemyCharacter"); return name end
    local context = object("app.cEnemyContext", {}, {
        get_IsBoss = function() return f.boss end,
    })
    local holder = object("app.cEnemyContextHolder", { _Em = context }, {})
    local hp = object("app.cHealthManager", {}, {
        get_IsDead = function() return f.dead end,
    })
    f.enemy = object("app.EnemyCharacter", { _Context = holder }, {
        get_HealthMgr = function() return hp end,
    })
    f.target = object("via.GameObject", {}, {
        ["getComponent(System.Type)"] = function(_, name)
            equal(name, "app.EnemyCharacter")
            return f.enemy
        end,
    }, 5000)
    f.hit_owner = f.owner
    f.hit = object("app.HitInfo", {}, {
        getActualAttackOwner = function() return f.hit_owner end,
        get_DamageOwner = function() return f.target end,
    }, 6000)
    f.calc_fields = { FinalDamage = 125.5 }
    f.calc = object("app.cEnemyStockDamage.cCalcDamage", f.calc_fields, {})
    local _, stock_type = object("app.cEnemyStockDamage", {}, {
        ["stockDamageDetail(app.HitInfo)"] = function() end,
    })
    local _, mark_type = object("app.cEnemyStockDamage.mcEnemyHitMarkManager", {}, {
        ["playHitMarkEffect(app.cEnemyStockDamage.cCalcDamage, app.HitInfo)"] = function() end,
    })
    types["app.cEnemyStockDamage"] = stock_type
    types["app.cEnemyStockDamage.mcEnemyHitMarkManager"] = mark_type
    local _, application_type = object("via.Application", {}, {
        get_UpTimeSecond = function() return f.uptime or 1000 end,
    })
    types["via.Application"] = application_type
    f.damage = Damage.new()
    source:install_damage(f.damage)
    function f:poll()
        model.frame = model.frame + settings.sample_frames
        source:poll_damage()
    end
    function f:stock() return hooks[3].pre({ nil, nil, self.hit }) end
    function f:mark() return hooks[4].pre({ nil, nil, self.calc, self.hit }) end
    f:poll()
    return f
end

test("DPS reads combat independently for remote hunters and keeps damage when an individual timer fails", function()
    local f = damage_fixture()
    f.combat_states = { false, false }
    f:poll()
    f.time = 1500
    f:poll()
    f.combat_states[1] = true
    f:poll()
    f.hit_owner = f.owner
    f:stock(); f:mark()
    f.time = 1510
    f:poll()
    f.combat_states[2] = true
    f:poll()
    f.hit_owner = f.remote_owner
    f:stock(); f:mark()
    f.time = 1520
    f:poll()
    local rows = f.damage:rows()
    local by_name = {}
    for _, row in ipairs(rows) do by_name[row.name] = row end
    equal(by_name["Tu cazador"].elapsed, 20)
    equal(by_name["Tu cazador"].dps, 125.5 / 20)
    equal(by_name["Cazador remoto"].elapsed, 10)
    equal(by_name["Cazador remoto"].dps, 12.55)
    local draw_api, imgui_api, _, texts = render_fixture()
    View.render_damage(draw_api, imgui_api, f.settings, f.damage)
    local rendered = table.concat(texts, "\n")
    assert(rendered:find("00:00:20", 1, true))
    assert(rendered:find("00:00:10", 1, true))
    assert(rendered:find("18,8/s", 1, true))
    assert(not rendered:find("00:25:", 1, true))
    f.combat_states = { false, false }
    f:poll()
    f.time = 1600
    f:poll()
    equal(f.damage:rows()[1].elapsed, 10)
    f.combat_states = { true, false }
    f:poll()
    f.time = 1610
    f:poll()
    equal(f.damage.players[by_name["Tu cazador"].id].elapsed, 30)
    equal(f.damage.players[by_name["Cazador remoto"].id].elapsed, 10)
    f.combat_errors = { false, true }
    f:poll()
    f.time = 1620
    f:poll()
    for _, row in ipairs(f.damage:rows()) do
        if row.is_self then
            equal(row.dps, 125.5 / 40)
            equal(row.elapsed, 40)
            equal(f.reports["tiempo_combate_" .. row.id], nil)
        else
            equal(row.dps, nil)
            equal(row.elapsed, nil)
            assert(f.reports["tiempo_combate_" .. row.id])
        end
        equal(row.damage, 125.5)
    end
    equal(f.reports.dps, nil)
end)

test("DPS hooks read final attributed hits for self and remote player without changing the game", function()
    local f = damage_fixture()
    equal(f:stock(), 0)
    equal(f:mark(), 0)
    equal(f.hooks[3].post("return"), "return")
    equal(f.hooks[4].post("return"), "return")
    f.hit_owner = f.remote_owner
    f.calc_fields.FinalDamage = 74.5
    f:stock()
    f:mark()
    f.time = 110
    f:poll()
    local rows, total = f.damage:rows()
    equal(total, 200)
    equal(rows[1].damage, 125.5)
    equal(rows[1].is_self, true)
    equal(rows[2].name, "Cazador remoto")
    equal(rows[1].dps, 12.55)
    equal(rows[2].share, 0.3725)
    equal(f.reports.dps, nil)
    for _, player in pairs(f.damage.players) do
        for _, value in pairs(player) do assert(type(value) ~= "table") end
    end
end)

test("DPS does not depend on member indices or merge different hunters with identical names", function()
    local f = damage_fixture()
    equal(f.index_reads, nil)
    for _, indices in ipairs({ { 12, 64 }, { -1, -1 }, { 1.5, math.huge } }) do
        f.member_indices = indices
        f:poll()
        equal(f.source.feature_failures.dps, nil)
        f:stock(); f:mark()
    end
    equal(f.damage.hits, 3)
    equal(f.index_reads, nil)
    f.index_error, f.same_name = true, true
    f.source:reset_damage()
    f:poll()
    f:stock(); f:mark()
    f.hit_owner = f.remote_owner
    f:stock(); f:mark()
    local rows, total = f.damage:rows()
    equal(#rows, 2)
    equal(rows[1].name, rows[2].name)
    assert(rows[1].id ~= rows[2].id)
    equal(rows[1].share, 0.5)
    equal(rows[2].share, 0.5)
    equal(total, 251)
    equal(f.index_reads, nil)
    equal(f.reports.dps, nil)
end)

test("DPS consumes each pending hit once, permits reused hit addresses and includes lethal blows", function()
    local f = damage_fixture()
    f:mark()
    equal(f.damage.hits, 0)
    f:stock()
    f.dead = true
    f:mark()
    f:mark()
    equal(f.damage.hits, 1)
    f.dead = false
    f:stock()
    f:mark()
    equal(f.damage.hits, 2)
    equal(select(2, f.damage:rows()), 251)
end)

test("DPS ignores small enemies, corpses, NPC and environment rather than assigning them to self", function()
    local f = damage_fixture()
    f.boss = false
    f:stock(); f:mark()
    f.boss = true
    f.dead = true
    f:stock(); f:mark()
    f.dead = false
    f.hit_owner = object("via.GameObject", {}, {}, 9999)
    f:stock(); f:mark()
    f.hit_owner = nil
    f:stock(); f:mark()
    equal(f.damage.hits, 0)
    equal(f.source.unassigned_hits, 1)
end)

test("reused unknown-owner hit cannot inherit a previous player's pending attribution", function()
    local f = damage_fixture()
    f:stock()
    f.hit_owner = object("via.GameObject", {}, {}, 9999)
    f:stock()
    f:mark()
    equal(f.damage.hits, 0)
end)

test("DPS pending hits expire, cannot cross quests, and cleared counters use a new time window", function()
    local f = damage_fixture()
    f:stock()
    f.model.frame = f.model.frame + 3
    f:mark()
    equal(f.damage.hits, 0)
    f:stock()
    f.param_address = 54321
    f.time = 0
    f:poll()
    f:mark()
    equal(f.damage.hits, 0)
    f:stock(); f:mark()
    f.time = 10
    f:poll()
    equal(f.damage.elapsed, 10)
    f.playing = false
    f:poll()
    equal(f.damage.active, false)
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
    f.source:reset_damage()
    equal(f.damage.hits, 0)
    f.playing = true
    f:poll()
    equal(f.damage.elapsed, 0)
end)

test("changing computed start timestamps and backwards time corrections never erase quest damage", function()
    local f = damage_fixture()
    f.collection = "explicit_iterator"
    for step = 1, 20 do
        f.started = 1000 + step * 0.01
        f.time = 100 + step
        f:poll()
        f:stock(); f:mark()
        equal(f.damage.hits, step)
        equal(select(2, f.damage:rows()), 125.5 * step)
        f.time = f.time - 0.05
        f:poll()
        equal(f.damage.hits, step)
        equal(f.damage.elapsed, step)
    end
    equal(f.damage.elapsed, 20)
    equal(f.reports.dps, nil)
    f:stock()
    f.time = 119.9
    f.source.damage_due = 0
    f.source:poll_damage()
    f:mark()
    equal(f.damage.hits, 21)
    equal(f.damage.elapsed, 20)
end)

test("a transient missing mission manager preserves counters and an explicit next hunt clears them", function()
    local f = damage_fixture()
    f:stock(); f:mark()
    f.time = 110
    f:poll()
    local mission = f.mission
    f.mission = nil
    f:poll()
    equal(f.damage.hits, 1)
    equal(f.damage.elapsed, 10)
    f.mission = mission
    f.time = 111
    f:poll()
    equal(f.damage.hits, 1)
    equal(f.damage.elapsed, 11)
    f.playing = false
    f:poll()
    equal(f.damage.hits, 1)
    f.playing = true
    f.time = 0
    f:poll()
    equal(f.damage.hits, 0)
    equal(f.damage.elapsed, 0)
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
    f.param_address = 98765
    f:poll()
    equal(f.damage.hits, 0)
end)

test("DPS visibility follows mission or real combat, never nearby monsters or drawn weapon", function()
    local f = damage_fixture()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "quest")
    f:stock(); f:mark()
    f.playing = false
    f:poll()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "result")
    equal(f.damage.active, false)
    equal(f.damage.hits, 1)
    f.combat = true
    f.uptime = 2000
    f:poll()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "battle")
    equal(f.damage.hits, 0)
    f:stock(); f:mark()
    f.uptime = 2010
    f:poll()
    equal(f.damage.elapsed, 10)
    equal(f.damage:rows()[1].dps, 12.55)
    f.combat = false
    f:poll()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "result")
    equal(f.damage.hits, 1)
    f.combat = true
    f:poll()
    equal(f.damage.hits, 1)
    f.playing = true
    f:poll()
    equal(f.source.damage_mode, "quest")
    equal(f.damage.elapsed, 0)
end)

test("expedition DPS only attributes self and never enumerates quest members", function()
    local f = damage_fixture()
    f.playing, f.combat = false, true
    f.collection = "unsupported"
    f:poll()
    equal(f.reports.dps, nil)
    f:stock(); f:mark()
    f.hit_owner = f.remote_owner
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
    equal(f.source.unassigned_hits, 1)
    equal(#f.damage:rows(), 1)
    f.combat = false
    f:poll()
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
end)

test("unsupported expedition battle-state detection stays hidden but cannot block mission DPS", function()
    local f = damage_fixture()
    f.playing, f.combat_error = false, true
    f:poll()
    equal(f.source.damage_visible, false)
    assert(f.reports.combate:find("IsCombat unavailable", 1, true))
    equal(f.source.feature_failures.dps, nil)
    f.playing = true
    f:poll()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "quest")
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
end)

test("DPS removes departed players and recalculates percentages using the present roster", function()
    local f = damage_fixture()
    f.hit_owner = f.remote_owner
    f:stock(); f:mark()
    f.members = { f.master }
    f.list = true
    f:poll()
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
    equal(f.damage:rows()[1].name, "Tu cazador")
    equal(#f.damage:rows(), 1)
    f.hit_owner = f.owner
    f:stock(); f:mark()
    equal(f.damage:rows()[1].share, 1)
    equal(f.reports.dps, nil)
end)

local function install_support_fixture(f, options)
    options = options or {}
    local owner = object("via.GameObject", {}, {}, 8000)
    local character, character_definition = object("app.NpcCharacter", {}, {
        get_GameObject = function() return owner end,
        get_IsCombat = function()
            if options.combat_error then error("Support IsCombat unavailable") end
            return options.combat ~= false
        end,
    })
    local methods = {
        get_Valid = function() return options.valid ~= false end,
        get_IsQuestPartner = function() return options.quest_partner ~= false end,
        get_NpcID = function() return options.npc_id or 9 end,
    }
    if not options.unbound and not options.reflected then
        methods.get_Character = function() return character end
    end
    local control, definition = object("app.cNpcPartnerManageControl", {}, methods, 8100)
    if options.reflected then
        function definition:get_fields()
            return { {
                is_static = function() return false end,
                get_type = function() return character_definition end,
                get_name = function() return "_Npc" end,
            } }
        end
        control.get_field = function(_, name) equal(name, "_Npc"); return character end
    elseif options.reflected_getter then
        methods.get_Character = nil
        function definition:get_methods()
            return { {
                get_name = function() return "get_NpcCharacter" end,
                get_num_params = function() return 0 end,
                get_return_type = function() return character_definition end,
                call = function(_, instance) equal(instance, control); return character end,
            } }
        end
    end
    if options.manage_info then
        local context = object("app.cNpcContext", { NpcID = options.npc_id or 9 }, {})
        local holder = object("app.cNpcContextHolder", {}, {
            get_Npc = function() if not options.no_context then return context end end,
        })
        local core = object("app.NpcCharacterCore", { _ContextHolder = holder }, {
            get_GameObject = function() if not options.unbound then return owner end end,
        })
        control = object("app.cNpcManageInfo", {}, {
            get_NpcCore = function() if not options.no_core then return core end end,
        }, 8100)
    end
    f.support_entries = { control }
    local partner = object("app.cNpcPartnerManager", {}, {
        getQuestMembers = function()
            if options.error then error("support collection failed") end
            local list = array(f.support_entries, options.size)
            list.get_type_definition = function()
                return { get_method = function() return nil end }
            end
            return list
        end,
    })
    f.npc_manager = object("app.NpcManager", {}, {
        get_PartnerManager = function() return partner end,
    })
    return owner
end

test("support hunters appear and receive only their own observed damage with explicit APOYO label", function()
    local f = damage_fixture()
    local owner = install_support_fixture(f)
    f:poll()
    equal(#f.damage:rows(), 3)
    f.hit_owner = owner
    f:stock(); f:mark()
    f.hit_owner = f.owner
    f:stock(); f:mark()
    f.time = 110
    f:poll()
    local rows, total = f.damage:rows()
    equal(total, 251)
    local support
    for _, row in ipairs(rows) do if row.is_support then support = row end end
    assert(support)
    equal(support.name, "Olivia")
    equal(support.damage, 125.5)
    equal(support.share, 0.5)
    equal(support.dps, 12.55)
    equal(support.damage_available, true)
    local draw_api, imgui_api, _, texts = render_fixture()
    View.render_damage(draw_api, imgui_api, f.settings, f.damage)
    assert(table.concat(texts, "\n"):find("[APOYO] Olivia", 1, true))
    equal(f.reports.apoyos, nil)
end)

test("real cNpcManageInfo quest members resolve core, NPC context and attack owner without Valid", function()
    local f = damage_fixture()
    local owner = install_support_fixture(f, { manage_info = true })
    f:poll()
    equal(f.reports.apoyos, nil)
    equal(#f.damage:rows(), 3)
    f.hit_owner = owner
    f:stock(); f:mark()
    f.time = 110
    f:poll()
    local row = f.damage:rows()[1]
    equal(row.name, "Olivia")
    equal(row.is_support, true)
    equal(row.damage, 125.5)
    equal(row.dps, nil)
    equal(row.elapsed, nil)
    assert(f.reports["tiempo_combate_" .. row.id])
    f.support_entries = {}
    f:poll()
    equal(#f.damage:rows(), 2)
    equal(select(2, f.damage:rows()), 0)
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
end)

test("NPC info unloaded cores and contexts are skipped and unavailable GameObjects remain explicit", function()
    for _, options in ipairs({
        { manage_info = true, no_core = true },
        { manage_info = true, no_context = true },
        { manage_info = true, npc_id = -1 },
    }) do
        local f = damage_fixture()
        install_support_fixture(f, options)
        f:poll()
        equal(f.reports.apoyos, nil)
        equal(#f.damage:rows(), 2)
    end
    local f = damage_fixture()
    install_support_fixture(f, { manage_info = true, unbound = true })
    f:poll()
    equal(f.reports.apoyos, nil)
    equal(f.source.support_unbound, 1)
    equal(#f.damage:rows(), 3)
end)

test("support discovery accepts reflected character fields and also runs during expedition combat", function()
    for _, options in ipairs({ { reflected = true }, { reflected_getter = true } }) do
        local f = damage_fixture()
        local owner = install_support_fixture(f, options)
        f.playing, f.combat = false, true
        f:poll()
        equal(#f.damage:rows(), 2)
        f.hit_owner = owner
        f:stock(); f:mark()
        equal(f.damage.hits, 1)
        equal(f.damage:rows()[1].name, "Olivia")
        equal(f.reports.apoyos, nil)
    end
end)

test("support slots exclude invalid entries and non quest partners and unknown identities stay explicit", function()
    for _, options in ipairs({
        { valid = false }, { quest_partner = false }, { npc_id = -1 },
    }) do
        local f = damage_fixture()
        install_support_fixture(f, options)
        f:poll()
        equal(#f.damage:rows(), 2)
        equal(f.reports.apoyos, nil)
    end
    local f = damage_fixture()
    install_support_fixture(f, { npc_id = 999 })
    f:poll()
    local found = false
    for _, row in ipairs(f.damage:rows()) do
        if row.is_support then equal(row.name, "Apoyo #999"); found = true end
    end
    assert(found)
end)

test("unbound support hunters show missing data instead of fabricated zero DPS and can later bind", function()
    local f = damage_fixture()
    install_support_fixture(f, { unbound = true })
    f:poll()
    equal(f.source.support_unbound, 1)
    assert(f.reports.identidad_apoyos:find("sin Character/GameObject", 1, true))
    local rows = f.damage:rows()
    for _, row in ipairs(rows) do
        if row.is_support then
            equal(row.damage_available, false)
            equal(row.dps, nil)
            equal(row.ratio, 0)
        end
    end
    local draw_api, imgui_api, _, texts = render_fixture()
    View.render_damage(draw_api, imgui_api, f.settings, f.damage)
    assert(table.concat(texts, "\n"):find("--/s", 1, true))
    local owner = install_support_fixture(f)
    f:poll()
    equal(f.source.support_unbound, 0)
    f.hit_owner = owner
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
end)

test("NPC collection failures suspend only support discovery and keep player DPS updating", function()
    local f = damage_fixture()
    install_support_fixture(f, { error = true })
    f:poll()
    assert(f.reports.apoyos:find("support collection failed", 1, true))
    equal(f.source.feature_failures.dps, nil)
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
    equal(#f.damage:rows(), 2)
    equal(f.reports.dps, nil)
    f.source:retry_features()
    local owner = install_support_fixture(f)
    f:poll()
    f.hit_owner = owner
    f:stock(); f:mark()
    equal(f.damage.hits, 2)
end)

test("support collections allow reserved NPC slots but bound oversized arrays independently", function()
    local f = damage_fixture()
    install_support_fixture(f, { size = 10 })
    f:poll()
    equal(#f.damage:rows(), 3)
    equal(f.reports.apoyos, nil)
    install_support_fixture(f, { size = 17 })
    f:poll()
    assert(f.reports.apoyos:find("Tamano del grupo", 1, true))
    equal(f.source.feature_failures.dps, nil)
    equal(#f.damage:rows(), 2)
end)

test("departure removes rows, pending hits and totals without losing remaining players or rejoin history", function()
    local f = damage_fixture()
    local support_owner = install_support_fixture(f)
    f:poll()
    f:stock(); f:mark()
    f.hit_owner = support_owner
    f:stock(); f:mark()
    f.hit_owner = f.remote_owner
    f:stock(); f:mark()
    equal(select(2, f.damage:rows()), 376.5)
    f:stock()
    f.members = { f.master }
    f.support_entries = {}
    f:poll()
    f:mark()
    equal(#f.damage:rows(), 1)
    equal(f.damage:rows()[1].share, 1)
    equal(select(2, f.damage:rows()), 125.5)
    equal(f.damage.hits, 3)
    f.members = { f.master, f.remote }
    f:poll()
    equal(#f.damage:rows(), 2)
    equal(select(2, f.damage:rows()), 251)
    f.hit_owner = f.owner
    f:stock(); f:mark()
    equal(select(2, f.damage:rows()), 376.5)
    equal(f.reports.dps, nil)
end)

test("DPS supports managed arrays and C# iterator state machines without array helpers", function()
    for _, collection in ipairs({ "managed_array", "indexed_array", "enumerable",
        "iterator", "explicit_iterator", "inherited_iterator" }) do
        local f = damage_fixture()
        f.collection = collection
        f:poll()
        equal(f.reports.dps, nil)
        f.hit_owner = f.remote_owner
        f:stock(); f:mark()
        equal(f.damage.hits, 1)
        if collection:find("iterator") then equal(f.disposals, 1) end
        equal(f.damage:rows()[1].name, "Cazador remoto")
        f.members = {}
        f:poll()
        equal(f.reports.dps, nil)
        if collection:find("iterator") then equal(f.disposals, 2) end
        f:stock(); f:mark()
        equal(f.damage.hits, 1)
    end
end)

test("all managed party collection shapes enforce size limits and identify unsupported types", function()
    for _, collection in ipairs({ "managed_array", "indexed_array", "enumerable",
        "iterator", "explicit_iterator", "inherited_iterator" }) do
        local f = damage_fixture()
        f.collection, f.size = collection, 5
        f:poll()
        assert(f.reports.dps:find("Tamano del grupo"))
        equal(f.source.feature_failures.dps, true)
        if collection:find("iterator") then equal(f.disposals, 1) end
    end
    local f = damage_fixture()
    f.collection = "unsupported"
    f:poll()
    assert(f.reports.dps:find("app.UnknownPartyCollection"))
    assert(not f.reports.dps:find("nil value", 1, true))
    f.source:retry_features()
    f.source:reset_damage()
    f.collection = "managed_array"
    f:poll()
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
end)

test("party iterators close on read failures and report malformed contracts without hiding errors", function()
    for _, scenario in ipairs({
        { field = "move_error", message = "MoveNext failed" },
        { field = "current_error", message = "Current failed" },
        { field = "move_invalid", message = "MoveNext del grupo no es booleano" },
        { field = "dispose_error", message = "Dispose failed" },
        { field = "missing_current", message = "faltan MoveNext/get_Current" },
    }) do
        local f = damage_fixture()
        f.collection = "explicit_iterator"
        f[scenario.field] = true
        f:poll()
        assert(f.reports.dps:find(scenario.message, 1, true), f.reports.dps)
        equal(f.disposals, 1)
        equal(f.source.feature_failures.dps, true)
        f.hooks[2].pre({ nil, "enemy_pointer" })
        equal(f.model:rows(3, false)[1].health, 12500)
    end
    local f = damage_fixture()
    f.collection, f.move_error, f.dispose_error = "iterator", true, true
    f:poll()
    assert(f.reports.dps:find("MoveNext failed", 1, true))
    assert(f.reports.dps:find("Dispose failed", 1, true))
end)

test("invalid final damage suspends only DPS and retry clears pending attribution", function()
    local f = damage_fixture()
    f.calc_fields.FinalDamage = math.huge
    f:stock()
    equal(f:mark(), 0)
    assert(f.reports.dps:find("Dano final"))
    equal(f.source.feature_failures.dps, true)
    equal(f.damage.hits, 0)
    f.hooks[2].pre({ nil, "enemy_pointer" })
    equal(f.model:rows(3, false)[1].health, 12500)
    f.source:retry_features()
    f.source:reset_damage()
    f:poll()
    f.calc_fields.FinalDamage = 20
    f:mark()
    equal(f.damage.hits, 0)
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
end)

test("disabled DPS makes no capture or clock calls and re-enabling starts empty", function()
    local f = damage_fixture()
    f:stock(); f:mark()
    f.settings.show_dps = false
    f.source.sdk.get_managed_singleton = function() error("disabled SDK read") end
    f:poll()
    f:stock(); f:mark()
    equal(f.damage.hits, 0)
    equal(f.reports.dps, nil)
end)

test("invalid party sizes, clocks and mismatched targets report explicitly without HP interruption", function()
    for _, change in ipairs({
        function(f) f.size = 1000 end,
        function(f) f.time = -1 end,
        function(f) f.no_param = true end,
    }) do
        local f = damage_fixture()
        change(f)
        f:poll()
        assert(f.reports.dps)
        equal(f.source.feature_failures.dps, true)
    end
    local f = damage_fixture()
    f:stock()
    f.target = object("via.GameObject", {}, {}, 7000)
    f:mark()
    assert(f.reports.dps:find("destino distinto"))
    equal(f.damage.hits, 0)
end)

test("DPS panel draws exact shares, totals, combat DPS, sorted bars and self marker", function()
    local f = damage_fixture()
    f:stock(); f:mark()
    f.time = 110
    f:poll()
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    View.render_damage(draw_api, imgui_api, f.settings, f.damage)
    local text = table.concat(texts, "\n")
    assert(text:find("DPS / COMB.", 1, true))
    assert(text:find("%[TU%] Tu cazador"))
    assert(text:find("100,00%%"))
    assert(text:find("12,6/s", 1, true))
    assert(text:find("DMG", 1, true))
    assert(text:find("126", 1, true))
    local fills = {}
    for _, rect in ipairs(rects) do
        if rect.h == 57 and rect.w ~= 3 then fills[#fills + 1] = rect end
    end
    equal(fills[1].w, rects[1].w)
    equal(fills[2].w, 0)
    equal(stack(), 0)
    equal(View.damage_number(12345), "12.3k")
    equal(View.damage_number(1000000), "1.0M")
end)

test("DPS panel clamps all primitives, truncates Unicode safely and marks missing timing", function()
    local damage = Damage.new()
    damage:update("hunt", 0)
    for index = 1, 8 do
        damage:add({ id = tostring(index), name = string.rep("狩", 40),
            is_self = false }, 100)
    end
    local settings = spanish_defaults()
    settings.dps_x, settings.dps_y = 16000, 16000
    local draw_api, imgui_api, rects, texts = render_fixture()
    imgui_api.get_display_size = function() return { x = 320, y = 220 } end
    View.render_damage(draw_api, imgui_api, settings, damage)
    for _, rect in ipairs(rects) do
        assert(rect.x >= 0 and rect.x + rect.w <= 320)
        assert(rect.y >= 0 and rect.y + rect.h <= 220)
    end
    local text = table.concat(texts, "\n")
    assert(text:find("--/s", 1, true))
    assert(text:find("+ 6 sin mostrar", 1, true))
    for _, value in ipairs(texts) do assert(utf8.len(value)) end
end)

test("DPS unavailable data is not rendered as zero damage and errors unwind its font stack", function()
    local f = damage_fixture()
    local draw_api, imgui_api, _, texts, stack = render_fixture()
    View.render_damage(draw_api, imgui_api, f.settings, f.damage, "DPS suspendido")
    assert(table.concat(texts, "\n"):find("DPS suspendido"))
    assert(not table.concat(texts, "\n"):find("Grupo:"))
    draw_api.text = function() error("damage draw failure") end
    raises(function()
        View.render_damage(draw_api, imgui_api, f.settings, f.damage)
    end, "damage draw failure")
    equal(stack(), 0)
end)

test("compact DPS formatting retains tenths, damage K and full hours without graph or fake stats", function()
    equal(View.damage_dps(27.6), "27,6/s")
    equal(View.damage_dps(0), "0,0/s")
    equal(View.damage_dps(nil), "--/s")
    equal(View.damage_dps(12500), "12,5K/s")
    equal(View.damage_total(14000), "14,0K")
    equal(View.damage_total(7500), "7,5K")
    equal(View.damage_total(999), "999")
    equal(View.damage_timer(508), "00:08:28")
    equal(View.damage_timer(3661.9), "01:01:01")
    local damage = Damage.new()
    damage:update("hunt", 0)
    damage:sync({ { id = "one", name = "Cazador", is_self = true, in_combat = true } })
    damage:update("hunt", 508)
    damage:add({ id = "one", name = "Cazador", is_self = true }, 14020.8)
    local draw_api, imgui_api, rects, texts = render_fixture()
    View.render_damage(draw_api, imgui_api, spanish_defaults(), damage)
    local content = table.concat(texts, "\n")
    assert(content:find("00:08:28", 1, true))
    assert(content:find("27,6/s", 1, true))
    assert(content:find("14,0K", 1, true))
    assert(not content:find("Lv.", 1, true))
    assert(not content:find("0/3", 1, true))
    local rows = 0
    for _, rect in ipairs(rects) do if rect.h == 57 then rows = rows + 1 end end
    equal(rows, 2)
    equal(rects[1].h, 120)
end)

test("compact DPS rows align numeric right edges and fit names without column overlap", function()
    local damage = Damage.new()
    damage:update("hunt", 0)
    damage:update("hunt", 508)
    for index, amount in ipairs({ 14020.8, 10200, 8300, 7500 }) do
        damage:add({ id = tostring(index), name = "Nombre largo del cazador " .. index,
            is_self = index == 1 }, amount)
    end
    for _, width in ipairs({ 300, 440, 800 }) do
        local draw_api, imgui_api, rects = render_fixture()
        local labels = {}
        local function measured(value)
            return { x = utf8.len(value) * 8, y = 16 }
        end
        imgui_api.calc_text_size = measured
        draw_api.text = function(value, x, y, color)
            if color ~= 0xFF000000 then
                labels[#labels + 1] = { value = value, x = x, y = y }
            end
        end
        local settings = spanish_defaults()
        settings.dps_width = width
        View.render_damage(draw_api, imgui_api, settings, damage)
        equal(rects[1].h, 294)
        local edges, dps_labels, dmg_labels = 0, 0, 0
        for _, label in ipairs(labels) do
            assert(label.x >= settings.dps_x)
            assert(label.x + measured(label.value).x <= settings.dps_x + width)
            if label.value:match("/s$") and not label.value:find("Grupo:", 1, true) then
                equal(label.x + measured(label.value).x, settings.dps_x + width - 8)
                edges = edges + 1
            elseif label.value == "DPS" then
                equal(label.x, settings.dps_x + width - 113)
                dps_labels = dps_labels + 1
            elseif label.value == "DMG" then
                equal(label.x, settings.dps_x + width - 113)
                dmg_labels = dmg_labels + 1
            elseif label.value:find("Nombre", 1, true) or label.value:find("[TU]", 1, true) then
                assert(label.x + measured(label.value).x <= settings.dps_x + width - 198)
            end
        end
        equal(edges, 4)
        equal(dps_labels, 4)
        equal(dmg_labels, 4)
    end
end)

test("DPS tinted fills retain player colors across ranking changes and obey opacity and disable", function()
    local damage = Damage.new()
    damage:update("hunt", 0)
    local a = { id = "a", name = "A", is_self = true }
    local b = { id = "b", name = "B", is_self = false }
    damage:add(a, 100)
    damage:add(b, 50)
    local settings = spanish_defaults()
    local function render()
        local draw_api, imgui_api, rects = render_fixture()
        View.render_damage(draw_api, imgui_api, settings, damage)
        return rects
    end
    local first = render()
    local function fills(rects)
        local result = {}
        for _, rect in ipairs(rects) do
            if rect.h == 57 and rect.w ~= 3 then result[#result + 1] = rect end
        end
        return result
    end
    first = fills(first)
    equal(first[2].w, settings.dps_width * 0.5)
    damage:add(b, 150)
    local second = fills(render())
    equal(first[1].color, second[2].color)
    equal(first[2].color, second[1].color)
    equal(second[1].w, settings.dps_width)
    equal(second[2].w, settings.dps_width * 0.5)
    settings.opacity = 0
    for _, rect in ipairs(render()) do equal(rect.color >> 24, 0) end
    settings.show_dps = false
    equal(#render(), 0)
end)

test("DPS config migrates placement without resetting existing orientation and validates all controls", function()
    local settings = assert(Config.validate({ horizontal = false, x = 600, y = 150 }))
    equal(settings.horizontal, false)
    equal(settings.x, 600)
    equal(settings.show_dps, true)
    equal(settings.dps_width, 440)
    equal(Config.validate({ show_dps = 1 }), nil)
    equal(Config.validate({ dps_width = 299 }), nil)
    equal(Config.validate({ dps_x = math.huge }), nil)
    equal(Config.validate({ dps_y = 1.5 }), nil)
end)

local function activities_fixture()
    local f = damage_fixture()
    f.playing, f.opened, f.in_port, f.days = false, true, true, 2
    f.rations, f.capacity = 7, 10
    f.collectors = {
        { id = 205, counts = { 4, 6, 8 }, available = true, full = true },
        { id = 101, counts = { 10, 15, 0 }, available = true, full = false },
        { id = 309, counts = { 0, 0, 0 }, available = false, full = false },
        { id = -1 },
    }
    local collection = object("app.savedata.cCollectionParam", {}, {
        get_CollectionNPC = function()
            if f.collection_error then error("CollectionNPC unavailable") end
            local entries = {}
            for _, row in ipairs(f.collectors) do
                local items = {}
                for _, count in ipairs(row.counts or {}) do
                    items[#items + 1] = (object("app.savedata.cItemWork", {}, {
                        get_Num = function() return count end,
                    }))
                end
                entries[#entries + 1] = (object("app.savedata.cCollectionNPCParam", {}, {
                    get_NPCFixedId = function() return row.id end,
                    get_CollectionItem = function() return array(items) end,
                    isEnableAccept = function() return row.available end,
                    isFullCollectionItems = function() return row.full end,
                }))
            end
            return array(entries)
        end,
    })
    local ship_param = object("app.savedata.cShipParam", {}, {
        get_DayCount = function() return f.days end,
    })
    f.save = object("app.savedata.cUserSaveParam", {}, {
        get_Collection = function() return collection end,
        get_Ship = function() return ship_param end,
    }, 700)
    local save_manager = object("app.SaveDataManager", {}, {
        get_IsShowLoading = function() return f.loading == true end,
        getCurrentUserSaveData = function() if not f.no_save then return f.save end end,
    })
    local ship = object("app.FacilityShip", {}, {
        get_IsShipOpened = function() return f.opened end,
        isInPort = function() return f.in_port end,
    })
    local setting = object("app.user_data.FacilityDiningSetting", {}, {
        get_SupplyFoodMax = function() return f.capacity end,
    })
    local dining = object("app.FacilityDining", {}, {
        get__SettingData = function() return setting end,
        getSuppliableFoodNum = function()
            if f.rations_error then error("rations unavailable") end
            return f.rations + (f.extra_rations or 0)
        end,
        getSuppliableFoodNumEx = function() return f.extra_rations or 0 end,
        isSuppliableFoodMax = function() return f.rations == f.capacity end,
    })
    local facilities = object("app.FacilityManager", {}, {
        get_Ship = function()
            f.ship_reads = (f.ship_reads or 0) + 1
            if not f.no_ship then return ship end
        end,
        get_Dining = function()
            f.rations_reads = (f.rations_reads or 0) + 1
            return dining
        end,
    })
    local _, ga = object("app.GA", {}, {
        get_Save = function(instance)
            equal(instance, nil)
            f.root_reads = (f.root_reads or 0) + 1
            return save_manager
        end,
        get_Facility = function(instance) equal(instance, nil); return facilities end,
    })
    f.types["app.GA"] = ga
    local function member(name, value)
        return { get_name = function() return name end, is_static = function() return true end,
            get_data = function(_, instance) equal(instance, nil); return value end }
    end
    f.types["app.savedata.cCollectionNPCParam"] = {
        get_field = function(_, name)
            equal(name, "NPCFixedId_INIT_VALUE")
            return member(name, -1)
        end,
    }
    f.types["app.NpcDef.ID_Fixed"] = {
        get_fields = function() return { member("R", 101), member("A", 205), member("L", 309) } end,
    }
    f.types["app.NpcDef.ID"] = {
        get_field = function(_, name) return member(name, ({ R = 11, A = 22, L = 33 })[name]) end,
    }
    local _, util = object("app.NpcUtil", {}, {
        getNpcName = function(instance, id)
            equal(instance, nil)
            f.name_reads = (f.name_reads or 0) + 1
            return ({ [11] = "Rysher", [22] = "Apar", [33] = "Locked" })[id]
        end,
    })
    f.types["app.NpcUtil"] = util
    f.poll = function()
        for _ = 1, f.settings.sample_frames do f.model:advance() end
        f.source:poll_activities()
    end
    return f
end

local function bootstrap(options)
    options = options or {}
    local source, _, _, _, hooks, _, types = fixture()
    local supplied = options.activities_fixture or options.damage_fixture
    if supplied then
        source = supplied.source
        hooks = supplied.hooks
        types = supplied.types
    end
    for index = #hooks, 1, -1 do hooks[index] = nil end
    source.sdk.find_type_definition = function(name)
        if not options.missing_sdk then return types[name] end
    end
    local callbacks, messages, saves = {}, {}, {}
    local draw_api, imgui_api, rects, texts = render_fixture()
    if options.display then
        imgui_api.get_display_size = function() return options.display end
    end
    local ui_path = {}
    imgui_api.tree_node = function(label)
        if options.closed_tree == label then return false end
        ui_path[#ui_path + 1] = label
        return true
    end
    imgui_api.tree_pop = function()
        assert(#ui_path > 0, "unbalanced UI tree")
        table.remove(ui_path)
    end
    imgui_api.text = function(value) messages[#messages + 1] = value end
    imgui_api.checkbox = function(label, current)
        if options.controls then options.controls[label] = table.concat(ui_path, "/") end
        if options.click == label then return true, not current end
        return false, current
    end
    imgui_api.combo = function(label, current, items)
        equal(label, "Language / Idioma")
        equal(#items, 2)
        equal(items[1], "English")
        equal(items[2], "Español")
        if options.language_index then
            local next_index = options.language_index
            options.language_index = nil
            return true, next_index
        end
        return false, current
    end
    imgui_api.slider_int = function(label, current, min, max, format)
        equal(format, "%d")
        assert(current >= min and current <= max)
        if options.controls then options.controls[label] = table.concat(ui_path, "/") end
        if options.slider_label == label then
            assert(options.slider_value >= min and options.slider_value <= max)
            return true, options.slider_value
        end
        return false, current
    end
    imgui_api.slider_float = function(label, current, min, max, format)
        equal(format, "%.2f")
        assert(current >= min and current <= max)
        if options.slider_label == label then
            assert(options.slider_value >= min and options.slider_value <= max)
            return true, options.slider_value
        end
        return false, current
    end
    imgui_api.button = function(label) return options.click == label end
    imgui_api.separator = function() end
    local env = setmetatable({
        fs = { glob = function(pattern)
            if pattern:find("layouts", 1, true) then
                return options.layouts_file ~= nil and { "mhoverlay_layouts.json" } or {}
            end
            return { Config.path }
        end },
        json = {
            load_file = function(path)
                if path == "mhoverlay_layouts.json" then return options.layouts_file end
                if options.corrupt_config then return nil end
                return { show_stats = options.stats == true, language = options.language or "es" }
            end,
            dump_file = function(path, config)
                if path == "mhoverlay_layouts.json" then
                    options.layout_saves = options.layout_saves or {}
                    options.layout_saves[#options.layout_saves + 1] = config
                    return options.layouts_write ~= false
                end
                saves[#saves + 1] = { path = path, config = config }
                return true
            end,
        },
        sdk = source.sdk,
        draw = draw_api,
        imgui = imgui_api,
        log = { error = function(message) messages[#messages + 1] = message end,
            info = function() end },
        re = {
            on_frame = function(fn) callbacks.frame = fn end,
            on_draw_ui = function(fn) callbacks.ui = fn end,
            on_config_save = function(fn) callbacks.save = fn end,
        },
    }, { __index = _G })
    assert(loadfile("reframework/autorun/mhoverlay.lua", "t", env))()
    return callbacks, hooks, messages, saves, texts, options, rects
end

local Layouts = require("mhoverlay/layouts")

test("legacy resolution profiles migrate only missing mission keys and retain existing geometry", function()
    local old = Layouts.capture(spanish_defaults())
    old.dps_x, old.buffs_size, old.scale = 1730, 85, 1.5
    for _, key in ipairs({ "mission_x", "mission_y", "mission_width", "mission_size" }) do
        old[key] = nil
    end
    local profiles = assert(Layouts.validate({ profiles = { ["2560x1440"] = old } }))
    local migrated = profiles["2560x1440"]
    equal(migrated.dps_x, 1730)
    equal(migrated.buffs_size, 85)
    equal(migrated.scale, 1.5)
    equal(migrated.mission_x, spanish_defaults().mission_x)
    equal(old.mission_x, nil)
    old.mission_size = "invalid"
    equal(Layouts.validate({ profiles = { ["2560x1440"] = old } }), nil)
    old.mission_size, old.dps_x = nil, nil
    equal(Layouts.validate({ profiles = { ["2560x1440"] = old } }), nil)
end)

test("autorun replaces stale owned modules before loading and reports the active reader version", function()
    local stale = {}
    for _, name in ipairs({ "config", "model", "wilds", "view", "damage", "layouts", "icons",
        "artwork", "portraits", "locale" }) do
        local key = "mhoverlay/" .. name
        stale[key] = { stale = true }
        package.loaded[key] = stale[key]
    end
    local callbacks, _, messages = bootstrap()
    callbacks.frame()
    callbacks.ui()
    for key, value in pairs(stale) do
        assert(package.loaded[key] ~= value, key)
        equal(package.loaded[key].stale, nil)
    end
    assert(table.concat(messages, "\n"):find("Version: 1.0 | lector: 1.0", 1, true))
end)

test("layouts validate every stored key and reject malformed or excessive profiles", function()
    local layout = Layouts.capture(spanish_defaults())
    local profiles = Layouts.validate({ profiles = { ["1920x1080"] = layout } })
    equal(profiles["1920x1080"].dps_x, spanish_defaults().dps_x)
    equal(profiles["1920x1080"].mission_x, spanish_defaults().mission_x)
    equal(profiles["1920x1080"].mission_size, spanish_defaults().mission_size)
    assert(profiles["1920x1080"] ~= layout)
    for _, raw in ipairs({ nil, {}, { profiles = { bad = layout } },
        { profiles = { ["1x1"] = { scale = 1 } } } }) do
        equal(Layouts.validate(raw), nil)
    end
    local broken = Layouts.capture(spanish_defaults())
    broken.dps_x = 1.5
    equal(Layouts.validate({ profiles = { ["800x600"] = broken } }), nil)
    broken.dps_x, broken.scale = 10, 3
    equal(Layouts.validate({ profiles = { ["800x600"] = broken } }), nil)
    local many = {}
    for index = 1, Layouts.max_profiles + 1 do many[index .. "x1"] = layout end
    equal(Layouts.validate({ profiles = many }), nil)
    equal(Layouts.resolution({ x = 2559.6, y = 1440 }), "2560x1440")
    equal(Layouts.resolution({ x = 0, y = 1440 }), nil)
    equal(table.concat(Layouts.sorted({ ["1280x800"] = 1, ["2560x1440"] = 1, ["1920x1200"] = 1,
        ["1920x1080"] = 1 }), ","), "2560x1440,1920x1200,1920x1080,1280x800")
end)

test("switching resolution stores the previous layout and restores each one after it settles", function()
    local display = { x = 2560, y = 1440 }
    local callbacks, _, messages, saves, _, options = bootstrap({ display = display })
    local function frames(count) for _ = 1, count do callbacks.frame() end end
    local function ui_slider(label, value)
        options.slider_label, options.slider_value = label, value
        callbacks.ui()
        options.slider_label = nil
    end
    frames(2)
    ui_slider("DPS - Posicion X", 1700)
    ui_slider("Escala global - todas las ventanas", 1.5)
    local monitor_dps = nil
    callbacks.save()
    equal(options.layout_saves, nil)
    display.x, display.y = 1512, 982
    frames(29)
    callbacks.save()
    equal(options.layout_saves, nil)
    frames(1)
    callbacks.save()
    local stored = options.layout_saves[#options.layout_saves].profiles["2560x1440"]
    equal(stored.scale, 1.5)
    monitor_dps = stored.dps_x
    ui_slider("Escala global - todas las ventanas", 0.75)
    ui_slider("DPS - Posicion X", 900)
    frames(1)
    display.x, display.y = 2560, 1440
    frames(30)
    callbacks.save()
    local last = options.layout_saves[#options.layout_saves]
    equal(last.profiles["1512x982"].scale, 0.75)
    equal(last.profiles["1512x982"].dps_x, 900)
    equal(saves[#saves].config.scale, 1.5)
    equal(saves[#saves].config.dps_x, monitor_dps)
    display.x, display.y = 1512, 982
    frames(30)
    callbacks.save()
    equal(saves[#saves].config.scale, 0.75)
    equal(saves[#saves].config.dps_x, 900)
    for _, message in ipairs(messages) do assert(not message:find("posiciones]", 1, true), message) end
end)

test("brief resize sizes never swap layouts and auto mode off keeps manual control", function()
    local display = { x = 1920, y = 1080 }
    local stored = Layouts.capture(spanish_defaults())
    stored.scale, stored.dps_x = 2, 50
    local callbacks, _, _, saves, _, options = bootstrap({ display = display,
        layouts_file = { profiles = { ["1280x720"] = stored } } })
    callbacks.frame()
    for size = 1000, 1028 do display.x = size; callbacks.frame() end
    display.x, display.y = 1280, 720
    for _ = 1, 29 do callbacks.frame() end
    callbacks.save()
    equal(#saves, 0)
    options.click = "Recordar y cargar automaticamente al cambiar de resolucion"
    callbacks.ui()
    options.click = nil
    for _ = 1, 40 do callbacks.frame() end
    callbacks.save()
    equal(saves[#saves].config.auto_layout, false)
    equal(saves[#saves].config.scale, 1)
    equal(options.layout_saves, nil)
    options.click = "Cargar 1280x720"
    callbacks.ui()
    callbacks.save()
    equal(saves[#saves].config.scale, 2)
    equal(saves[#saves].config.dps_x, 50)
    options.click = "Borrar 1280x720"
    callbacks.ui()
    equal(next(options.layout_saves[#options.layout_saves].profiles), nil)
    options.click = "Guardar posiciones para 1280x720"
    callbacks.ui()
    equal(options.layout_saves[#options.layout_saves].profiles["1280x720"].scale, 2)
end)

test("startup refreshes the current profile from the saved config and invalid files are never overwritten", function()
    local stored = Layouts.capture(spanish_defaults())
    stored.dps_x = 5
    local callbacks, _, _, _, _, options = bootstrap({ display = { x = 1920, y = 1080 },
        layouts_file = { profiles = { ["1920x1080"] = stored } } })
    callbacks.frame()
    callbacks.save()
    equal(options.layout_saves[1].profiles["1920x1080"].dps_x, spanish_defaults().dps_x)
    local bad, _, messages, _, _, bad_options = bootstrap({ display = { x = 1920, y = 1080 },
        layouts_file = { profiles = { ["1920x1080"] = { scale = 9 } } } })
    bad.frame()
    bad_options.click = "Guardar ajustes"
    bad.ui()
    bad.save()
    equal(bad_options.layout_saves, nil)
    assert(table.concat(messages, "\n"):find("MHOverlay/posiciones", 1, true))
    local failing, _, failing_messages, _, _, failing_options = bootstrap({
        display = { x = 1920, y = 1080 }, layouts_write = false })
    failing.frame()
    failing_options.click = "Guardar posiciones para 1920x1080"
    failing.ui()
    assert(table.concat(failing_messages, "\n"):find("MHOverlay/guardado_posiciones", 1, true))
end)

test("entrypoint renders live hook values with preview disabled by default", function()
    local callbacks, hooks, _, _, texts = bootstrap()
    hooks[2].pre({ nil, "enemy_pointer" })
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("Rey Dau"))
    assert(not table.concat(texts, "\n"):find("DEMO"))
    callbacks.ui()
end)

test("entrypoint shows only the selected mission preview and clears it when the board closes", function()
    local f = mission_preview_fixture()
    local callbacks, hooks, _, _, texts = bootstrap({ activities_fixture = f })
    equal(#hooks, 6)
    hooks[3].pre({ nil, "board_pointer" })
    hooks[6].pre({ nil, "parts_pointer", "selected_pointer" })
    callbacks.frame()
    local content = table.concat(texts, "\n")
    assert(content:find("MISION SELECCIONADA", 1, true))
    assert(content:find("Dome", 1, true))
    assert(not content:find("BUFFS", 1, true))
    hooks[4].pre({ nil, "board_pointer" })
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts, "\n"):find("MISION SELECCIONADA", 1, true))
end)

test("cursor detail events replace the entire mission while the old selection getter stays unchanged", function()
    local f = mission_preview_fixture()
    local other = mission_preview_fixture()
    other.values.preview_names = { "Rathalos host", "Rathalos guest" }
    other.values.preview_ranks = { 901, 72 }
    other.values.preview_time = 50
    other.values.preview_life = 2
    other.values.preview_target_ids = array({ 10 })
    local names_type = f.types["app.EnemyDef"]
    local get_method = names_type.get_method
    names_type.get_method = function(self, name)
        if name == "NameString" then
            return { call = function(_, _, id)
                return id == 10 and "Rathalos" or "Rey Dau"
            end }
        end
        return get_method(self, name)
    end
    local callbacks, hooks, _, _, texts = bootstrap({ activities_fixture = f })
    hooks[3].pre({ nil, "board_pointer" })
    local function draw_selection(quest)
        f.values.highlighted_quest = quest
        equal(hooks[6].pre({ nil, "parts_pointer", "selected_pointer" }), 0)
        equal(hooks[6].post("unchanged"), "unchanged")
        for index = #texts, 1, -1 do texts[index] = nil end
        callbacks.frame()
        return table.concat(texts, "\n")
    end
    local first = draw_selection(f.selected)
    assert(first:find("Rey Dau", 1, true))
    assert(first:find("Dome", 1, true))
    local second = draw_selection(other.selected)
    assert(second:find("Rathalos", 1, true))
    assert(second:find("RC 901", 1, true))
    assert(second:find("50:00", 1, true))
    assert(second:find("2 desmayos", 1, true))
    assert(not second:find("Rey Dau", 1, true))
    assert(not second:find("Dome", 1, true))
    equal(f.parts:get_type_definition():get_method("get_SelectViewQuestData"):call(f.parts), f.selected)
    assert(draw_selection(f.selected):find("Dome", 1, true))
    hooks[6].pre({ nil, "parts_pointer", nil })
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts):find("MISION SELECCIONADA", 1, true))
    hooks[4].pre({ nil, "board_pointer" })
    hooks[3].pre({ nil, "board_pointer" })
    callbacks.frame()
    assert(not table.concat(texts):find("MISION SELECCIONADA", 1, true))
    assert(draw_selection(other.selected):find("Rathalos", 1, true))
end)

test("detail capture errors do not poison the board and mismatched lists cannot reuse old details", function()
    local f = mission_preview_fixture()
    f.source:install_mission_board()
    f.hooks[3].pre({ nil, "board_pointer" })
    f.hooks[6].pre({ nil, "invalid_parts", "selected_pointer" })
    equal(f.source.mission_board, f.board)
    assert(f.reports.lista_misiones)
    equal(f.source.mission_detail, nil)
    f.hooks[6].pre({ nil, "parts_pointer", "selected_pointer" })
    equal(f.reports.lista_misiones, nil)
    f.source:poll_mission_preview()
    assert(f.source.mission_preview)
    f.source.mission_detail_parts = object("app.GUI050000QuestListParts", {}, {}, 9999)
    f.source:poll_mission_preview()
    equal(f.source.mission_preview, nil)
    equal(f.source.mission_state, "Esperando detalles de la seleccion")
end)

test("entrypoint keeps partial missions visible and updates selection without stale data or warnings", function()
    local f = mission_preview_fixture()
    f.values.preview_limits_error = true
    f.values.name = nil
    local callbacks, hooks, messages, _, texts = bootstrap({ activities_fixture = f })
    hooks[3].pre({ nil, "board_pointer" })
    hooks[6].pre({ nil, "parts_pointer", "selected_pointer" })
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("MISION SELECCIONADA", 1, true))
    assert(table.concat(texts, "\n"):find("Dome", 1, true))
    callbacks.ui()
    assert(table.concat(messages, "\n"):find("Datos leidos (parciales)", 1, true))
    f.values.preview_names = { "Nuevo anfitrion", "Nuevo cazador" }
    f.values.preview_ranks = { 11, 12 }
    f.values.preview_limits_error = false
    f.values.name = "Rey Dau"
    for index = #texts, 1, -1 do texts[index] = nil end
    for index = #messages, 1, -1 do messages[index] = nil end
    callbacks.frame()
    callbacks.ui()
    local content = table.concat(texts, "\n")
    assert(content:find("Nuevo anfitrion", 1, true))
    assert(not content:find("Dome", 1, true))
    assert(content:find("Rey Dau", 1, true))
    assert(not table.concat(messages, "\n"):find("mision_objetivos", 1, true))
    hooks[4].pre({ nil, "board_pointer" })
    for index = #messages, 1, -1 do messages[index] = nil end
    callbacks.frame()
    callbacks.ui()
    assert(table.concat(messages, "\n"):find("Vista previa de mision: Lista cerrada", 1, true))
end)

test("no monster waiting text is drawn even with the legacy status setting enabled", function()
    local settings = spanish_defaults()
    settings.show_status = true
    local draw_api, imgui_api, rects, texts = render_fixture()
    View.render(draw_api, imgui_api, settings, {})
    equal(#rects, 0)
    equal(#texts, 0)
    local f = damage_fixture()
    local callbacks, _, _, _, rendered, options = bootstrap({ damage_fixture = f })
    callbacks.frame()
    local function no_waiting()
        local content = table.concat(rendered, "\n")
        assert(not content:find("esperando monstruos grandes", 1, true))
        assert(not content:find("marca un monstruo", 1, true))
    end
    no_waiting()
    options.click = "Mostrar solo monstruo marcado en el mapa"
    callbacks.ui()
    callbacks.frame()
    no_waiting()
end)

test("preview is opt-in, clearly labeled and not saved", function()
    local callbacks, _, _, saves, texts = bootstrap({
        click = "Vista previa DEMO (datos ficticios)",
    })
    callbacks.ui()
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("DEMO"))
    callbacks.save()
    equal(#saves, 0)
end)

test("invalid config is visible and never overwritten by automatic saves", function()
    local callbacks, _, messages, saves = bootstrap({ corrupt_config = true })
    callbacks.ui()
    callbacks.save()
    equal(#saves, 0)
    assert(table.concat(messages, "\n"):find("no se sobrescribira"))
end)

test("settings persist only after a change and use the built-in JSON API", function()
    local callbacks, _, _, saves = bootstrap({ click = "Mostrar monstruos muertos" })
    callbacks.save()
    equal(#saves, 0)
    callbacks.ui()
    callbacks.save()
    equal(#saves, 1)
    equal(saves[1].config.show_dead, true)
    callbacks.save()
    equal(#saves, 1)
end)

test("initialization errors remain visible after clearing transient diagnostics", function()
    local callbacks, _, messages = bootstrap({
        missing_sdk = true, click = "Limpiar avisos y reintentar dibujo",
    })
    callbacks.ui()
    callbacks.ui()
    local count = 0
    for _, message in ipairs(messages) do
        if message:find("^Aviso %[inicio%]:") then count = count + 1 end
    end
    equal(count, 2)
end)

test("entrypoint wires real DPS hooks, frozen game time and manual reset without saving damage", function()
    local f = damage_fixture()
    local callbacks, hooks, messages, saves, texts, options = bootstrap({ damage_fixture = f })
    callbacks.frame()
    hooks[3].pre({ nil, nil, f.hit })
    hooks[4].pre({ nil, nil, f.calc, f.hit })
    f.time = 110
    for _ = 1, 6 do callbacks.frame() end
    local text = table.concat(texts, "\n")
    assert(text:find("100,00%%"))
    assert(text:find("12,6/s", 1, true))
    callbacks.ui()
    assert(table.concat(messages, "\n"):find("impactos contados: 1"))
    equal(#saves, 0)
    options.click = "Reiniciar contadores DPS"
    callbacks.ui()
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts, "\n"):find("100,00%%"))
    callbacks.save()
    equal(#saves, 0)
end)

test("entrypoint disables unsupported DPS without disabling HP or keeping a stale DPS error", function()
    local callbacks, hooks, messages, saves, texts, options = bootstrap()
    options.click = "Mostrar medidor DPS"
    callbacks.ui()
    hooks[2].pre({ nil, "enemy_pointer" })
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("Rey Dau"))
    assert(not table.concat(texts, "\n"):find("DPS suspendido"))
    for index = #messages, 1, -1 do messages[index] = nil end
    options.click = nil
    callbacks.ui()
    assert(not table.concat(messages, "\n"):find("dps:"))
    callbacks.save()
    equal(saves[1].config.show_dps, false)
    equal(saves[1].config.dps_width, 440)
end)

test("entrypoint hides meter in town, retains finished results and allows explicit DEMO preview", function()
    local f = damage_fixture()
    f.playing = false
    local callbacks, _, _, _, texts, options = bootstrap({ damage_fixture = f })
    callbacks.frame()
    assert(not table.concat(texts, "\n"):find("DPS / COMB.", 1, true))
    assert(not table.concat(texts, "\n"):find("SIN MISION", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("DMG", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    f.playing = true
    for _ = 1, 6 do callbacks.frame() end
    assert(table.concat(texts, "\n"):find("DPS / COMB.", 1, true))
    for index = #texts, 1, -1 do texts[index] = nil end
    f.playing = false
    f.source.model.frame = f.source.model.frame + 6
    for _ = 1, 6 do callbacks.frame() end
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("ULTIMA CAZA", 1, true))
    f.uptime = 1120
    for _ = 1, 6 do callbacks.frame() end
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts, "\n"):find("DMG", 1, true))
end)

test("finished DPS remains frozen for exactly 120 application seconds and cannot reopen after expiry", function()
    local f = damage_fixture()
    f:stock(); f:mark()
    f.time = 110
    f:poll()
    local support_owner = install_support_fixture(f)
    f:poll()
    f.hit_owner = support_owner
    f:stock(); f:mark()
    f.playing, f.uptime = false, 2000
    f:poll()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "result")
    equal(f.damage.active, false)
    equal(f.source.damage_result_until, 2120)
    local rows, total = f.damage:rows()
    equal(#rows, 3)
    equal(total, 251)
    equal(f.damage.elapsed, 10)
    f.members, f.support_entries = {}, {}
    f:stock(); f:mark()
    equal(f.damage.hits, 2)
    f.time, f.uptime = 10000, 2119.9
    f:poll()
    equal(f.source.damage_visible, true)
    equal(select(2, f.damage:rows()), total)
    equal(f.damage.elapsed, 10)
    equal(#f.damage:rows(), #rows)
    local draw_api, imgui_api, _, texts = render_fixture()
    View.render_damage(draw_api, imgui_api, f.settings, f.damage, nil, false, true)
    assert(table.concat(texts, "\n"):find("ULTIMA CAZA", 1, true))
    f.uptime = 2120
    f:poll()
    equal(f.source.damage_visible, false)
    f.uptime = 2200
    f:poll()
    equal(f.source.damage_visible, false)
    equal(f.source.damage_result_until, 2120)
    f.uptime = 2001
    f:poll()
    equal(f.source.damage_visible, false)
end)

test("quest DPS result waits through the field summary and starts its 120 seconds back in the village", function()
    local f = damage_fixture()
    f.source:poll_return()
    equal(f.source.awaiting_village, true)
    f:stock(); f:mark()
    f.time = 110
    f:poll()
    f.playing, f.village, f.uptime = false, false, 2000
    f.source:poll_return()
    f:poll()
    equal(f.source.awaiting_village, true)
    equal(f.source.damage_visible, false)
    equal(f.source.damage_result_until, nil)
    equal(f.damage.active, false)
    local _, total = f.damage:rows()
    f.uptime = 2500
    f:poll()
    equal(f.source.damage_visible, false)
    f.village = true
    f.source:poll_return()
    equal(f.source.awaiting_village, false)
    f:poll()
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "result")
    equal(f.source.damage_result_until, 2620)
    equal(select(2, f.damage:rows()), total)
    f.village = false
    f.source:poll_return()
    f.uptime = 2619
    f:poll()
    equal(f.source.damage_visible, true)
    f.uptime = 2620
    f:poll()
    equal(f.source.damage_visible, false)
end)

test("village return detection failure reports once and falls back to immediate results", function()
    local f = damage_fixture()
    local reports = {}
    f.source.report = function(category, message) reports[#reports + 1] = category .. ":" .. message end
    f.source:poll_return()
    f:stock(); f:mark()
    f:poll()
    f.playing, f.village_error = false, true
    f.source:poll_return()
    f.source:poll_return()
    equal(#reports, 1)
    assert(reports[1]:find("IsInLifeArea", 1, true))
    equal(f.source.awaiting_village, false)
    f:poll()
    equal(f.source.damage_visible, true)
    f.source.settings.enabled = false
    f.source:poll_return()
    equal(f.source.awaiting_village, false)
end)

test("expedition combat results still appear immediately outside the village", function()
    local f = damage_fixture()
    f.playing, f.village, f.combat = false, false, true
    f.source:poll_return()
    f:poll()
    f:stock(); f:mark()
    f.combat = false
    f.source:poll_return()
    f:poll()
    equal(f.source.awaiting_village, nil)
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "result")
end)

test("new activity and manual reset cancel retained results; idle town never creates a result", function()
    local f = damage_fixture()
    f:stock(); f:mark()
    f.playing = false
    f:poll()
    assert(f.source.damage_result_until)
    f.combat = true
    f:poll()
    equal(f.source.damage_result_until, nil)
    equal(f.source.damage_mode, "battle")
    equal(f.damage.hits, 0)
    f:stock(); f:mark()
    f.combat = false
    f:poll()
    assert(f.source.damage_result_until)
    f.source:reset_damage()
    f:poll()
    equal(f.source.damage_visible, false)
    equal(f.source.damage_result_until, nil)
    equal(f.damage.session, nil)
    f.playing = true
    f:poll()
    equal(f.source.damage_mode, "quest")
    equal(f.damage.hits, 0)
end)

test("invalid post-combat clock reports explicitly without altering the retained damage", function()
    local f = damage_fixture()
    f:stock(); f:mark()
    f.playing, f.uptime = false, math.huge
    f:poll()
    assert(f.reports.resultado_dps:find("Reloj de resultados DPS no valido", 1, true))
    equal(f.source.damage_visible, false)
    equal(f.damage.hits, 1)
    equal(f.source.feature_failures.dps, nil)
end)

test("quest faint counter decodes real group total and nonstandard limits independently of DPS", function()
    local f = damage_fixture()
    equal(f.damage.faints.count, 0)
    equal(f.damage.faints.limit, 3)
    f.faint_fields.v, f.faint_fields.m, f.faint_limit = 22, 7, 5
    f:poll()
    equal(f.damage.faints.count, 3)
    equal(f.damage.faints.limit, 5)
    f:stock(); f:mark()
    equal(f.damage.hits, 1)
    f.source:reset_damage()
    equal(f.damage.faints, nil)
    f:poll()
    equal(f.damage.faints.count, 3)
    equal(f.damage.hits, 0)
    f.param_address, f.faint_fields.v, f.faint_limit = 999, 0, 1
    f:poll()
    equal(f.damage.faints.count, 0)
    equal(f.damage.faints.limit, 1)
    f.playing, f.combat = false, true
    f:poll()
    equal(f.damage.faints, nil)
    equal(f.source.damage_mode, "battle")
end)

test("quest-ending faint is sampled once then frozen with results until the next quest", function()
    local f = damage_fixture()
    f.faint_fields.v = 14
    f:poll()
    equal(f.damage.faints.count, 2)
    f.faint_fields.v, f.playing = 21, false
    f:poll()
    equal(f.damage.faints.count, 3)
    equal(f.damage.faints.limit, 3)
    equal(f.source.damage_mode, "result")
    f.director_fields.QuestPlDieCount = nil
    f.uptime = 1119
    f:poll()
    equal(f.damage.faints.count, 3)
    equal(f.source.feature_failures.muertes, nil)
    f.uptime = 1120
    f:poll()
    equal(f.source.damage_visible, false)
    equal(f.damage.faints.count, 3)
end)

test("invalid faint data only disables its counter, never HP or hit attribution, and can retry", function()
    for _, change in ipairs({
        function(f) f.faint_fields.m = 0 end,
        function(f) f.faint_fields.m = math.huge end,
        function(f) f.faint_fields.v = 0 / 0 end,
        function(f) f.faint_fields.v = -7 end,
        function(f) f.faint_fields.v = nil end,
        function(f) f.faint_limit = -1 end,
        function(f) f.faint_limit = 1.5 end,
        function(f) f.faint_limit = math.huge end,
        function(f) f.faint_error = true end,
        function(f) f.director_fields.QuestPlDieCount = nil end,
    }) do
        local f = damage_fixture()
        change(f)
        f:poll()
        assert(f.reports.muertes)
        equal(f.damage.faints, nil)
        equal(f.source.feature_failures.muertes, true)
        equal(f.source.feature_failures.dps, nil)
        f:stock(); f:mark()
        equal(f.damage.hits, 1)
        f.hooks[2].pre({ nil, "enemy_pointer" })
        equal(f.model:rows(3, false)[1].health, 12500)
    end
    local f = damage_fixture()
    f.faint_error = true
    f:poll()
    f.faint_error = false
    f.source:retry_features()
    f:poll()
    equal(f.damage.faints.count, 0)
    equal(f.source.feature_failures.muertes, nil)
end)

test("retained faints cannot be taken from a different quest director", function()
    local f = damage_fixture()
    f.param_address, f.playing = 99999, false
    f:poll()
    equal(f.damage.faints, nil)
    assert(f.reports.muertes:find("no pertenecen", 1, true))
    equal(f.source.damage_visible, true)
    equal(f.source.damage_mode, "result")
end)

test("faint header draws a skull and correct counts, keeps labels apart and fits compact widths", function()
    for _, width in ipairs({ 300, 440, 800 }) do
        for _, scale in ipairs({ 0.5, 1, 2.5 }) do
            local f = damage_fixture()
            f.settings.dps_width, f.settings.scale = width, scale
            f.damage.faints = { count = 2, limit = 5 }
            local draw_api, imgui_api, rects = render_fixture()
            local labels = {}
            imgui_api.calc_text_size = function(value)
                return { x = #value * 8 * scale, y = 16 * scale }
            end
            draw_api.text = function(value, x, y, color)
                if color ~= 0xFF000000 and y == f.settings.dps_y + 9 * scale then
                    labels[#labels + 1] = { value = value, x = x, right = x + #value * 8 * scale }
                end
            end
            View.render_damage(draw_api, imgui_api, f.settings, f.damage)
            equal(labels[1].value, "00:00:00")
            equal(labels[2].value, "2/5")
            table.sort(labels, function(a, b) return a.x < b.x end)
            for index, label in ipairs(labels) do
                assert(label.x >= rects[1].x)
                assert(label.right <= rects[1].x + rects[1].w)
                if index > 1 then assert(labels[index - 1].right < label.x) end
            end
            local skull_blocks = 0
            for _, rect in ipairs(rects) do
                if rect.h == 2 * scale then
                    skull_blocks = skull_blocks + 1
                    assert(rect.x >= rects[1].x)
                    assert(rect.x + rect.w <= rects[1].x + rects[1].w)
                end
            end
            assert(skull_blocks >= 8)
        end
    end
    for _, scenario in ipairs({
        { faints = { count = 0, limit = 3 }, text = "0/3" },
        { faints = { count = 2, limit = 0 }, text = "2/--" },
        { text = "--/--" },
    }) do
        local f = damage_fixture()
        f.damage.faints = scenario.faints
        local draw_api, imgui_api, _, texts = render_fixture()
        View.render_damage(draw_api, imgui_api, f.settings, f.damage)
        assert(table.concat(texts, "\n"):find(scenario.text, 1, true))
    end
end)

test("entrypoint displays live quest faints, frozen final faints and isolated DEMO data", function()
    local f = damage_fixture()
    local callbacks, _, _, _, texts, options = bootstrap({ damage_fixture = f })
    local function next_sample()
        for _ = 1, 6 do callbacks.frame() end
        for index = #texts, 1, -1 do texts[index] = nil end
        callbacks.frame()
        return table.concat(texts, "\n")
    end
    assert(next_sample():find("0/3", 1, true))
    f.faint_fields.v, f.faint_limit = 14, 5
    assert(next_sample():find("2/5", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    assert(next_sample():find("1/3", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    assert(next_sample():find("2/5", 1, true))
    f.faint_fields.v, f.playing = 21, false
    local result = next_sample()
    assert(result:find("3/5", 1, true))
    assert(result:find("ULTIMA CAZA", 1, true))
    f.faint_fields.v = 0
    assert(next_sample():find("3/5", 1, true))
end)

test("combat focus follows only confirmed local hits and ignores list priority and filters", function()
    local f = damage_fixture()
    f.combat = true
    f.source:poll_focus()
    f.model:set("100", { name = "A", health = 50, max_health = 100 })
    f.model:set("200", { name = "B", health = 90, max_health = 100, quest_target = true, pinned = true })
    equal(f.model:focused(), nil)
    f:stock()
    equal(f.model:focused(), nil)
    f:mark()
    equal(f.model:focused().name, "A")
    f.settings.only_pinned, f.settings.max_monsters = true, 1
    equal(f.model:rows(1, false, f.settings)[1].name, "B")
    equal(f.model:focused().name, "A")
    f.enemy.get_address = function() return 200 end
    f.hit_owner = f.remote_owner
    f:stock(); f:mark()
    equal(f.model:focused().name, "A")
    f.hit_owner = f.owner
    f:stock(); f:mark()
    equal(f.model:focused().name, "B")
    f.combat = false
    f.model.frame = f.model.frame + 6
    f.source:poll_focus()
    equal(f.model:focused(), nil)
    equal(f.source.focus_combat, false)
    equal(f.settings.only_pinned, true)
    equal(f.settings.horizontal, true)
end)

test("combat focus works without DPS in expeditions and never selects nearby, dead or small enemies", function()
    local f = damage_fixture()
    f.settings.show_dps = false
    f.playing, f.combat = false, true
    f.source:poll_focus()
    f:poll()
    f.model:set("100", { name = "A", health = 100, max_health = 100 })
    equal(f.model:focused(), nil)
    for _, change in ipairs({
        function() f.dead = true end,
        function() f.dead = false; f.boss = false end,
        function() f.boss = true; f.hit_owner = f.remote_owner end,
        function() f.hit_owner = f.owner; f.calc_fields.FinalDamage = 0 end,
    }) do
        change()
        f:stock(); f:mark()
        equal(f.model:focused(), nil)
    end
    f.calc_fields.FinalDamage = 10
    f:stock(); f:mark()
    equal(f.model:focused().name, "A")
    equal(f.damage.hits, 0)
    equal(f.source.feature_failures.dps, nil)
    f.model:remove("100")
    equal(f.model:focused(), nil)
    equal(f.model.focus_key, nil)
end)

test("focus hits expire, cannot leak across combat, and optional errors preserve damage capture", function()
    local f = damage_fixture()
    f.combat = true
    f.source:poll_focus()
    f:stock()
    f.model.frame = f.model.frame + 3
    f:mark()
    equal(f.model.focus_key, nil)
    f:stock()
    f.combat = false
    f.model.frame = f.model.frame + 6
    f.source:poll_focus()
    f:mark()
    equal(f.model.focus_key, nil)
    f.combat = true
    f.source.focus_due = 0
    f.source:poll_focus()
    f:stock()
    f.calc_fields.FinalDamage = math.huge
    f:mark()
    assert(f.reports.foco)
    f.source:poll_focus()
    equal(f.source.focus_combat, false)
    f.source:retry_features()
    f.calc_fields.FinalDamage = 20
    f.source:poll_focus()
    f:stock(); f:mark()
    equal(f.model.focus_key, "100")
    f.settings.auto_focus = false
    f.source:poll_focus()
    equal(f.model.focus_key, nil)
    equal(next(f.source.focus_pending), nil)
end)

test("model expires and clears combat focus, and counts only observed condition activations", function()
    local model = Model.new()
    local function sample(active)
        model:should_sample("a", 6)
        model:set("a", { name = "A", health = 50, max_health = 100,
            rage = { active = active, remaining = 10, ratio = 0.5 } })
    end
    sample(false)
    equal(model.monsters.a.rage.observed_count, 0)
    sample(true)
    equal(model.monsters.a.rage.observed_count, 1)
    sample(true)
    equal(model.monsters.a.rage.observed_count, 1)
    sample(false)
    sample(true)
    equal(model.monsters.a.rage.observed_count, 2)
    model.focus_key = "a"
    for _ = 1, 121 do model:advance() end
    equal(model:focused(), nil)
    equal(model.focus_key, nil)
    sample(true)
    equal(model.monsters.a.rage.observed_count, 1)
    model.focus_key = "a"
    model:clear()
    equal(model.focus_key, nil)
end)

test("focused combat HUD uses real values, geometric icons and blue beveled HP without changing cards", function()
    local source, model, settings, values, hooks = fixture()
    values.rage_active, values.rage_timer = true, 20
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model.monsters["100"]
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    View.render_focus(draw_api, imgui_api, settings, row)
    local content = table.concat(texts, "\n")
    assert(content:find("Rey Dau", 1, true))
    assert(content:find("12500 / 20000", 1, true))
    assert(content:find("62,50%", 1, true))
    assert(content:find("Furia", 1, true))
    assert(content:find("Paralisis", 1, true))
    assert(content:find("Aturdim.", 1, true))
    assert(content:find("+1", 1, true))
    assert(content:find("0:40", 1, true))
    assert(not content:find("activaciones observadas", 1, true))
    assert(not content:find("OBJETIVO DE MISION", 1, true))
    assert(#rects > 300)
    equal(stack(), 0)
    row.paralysis, row.stun, row.rage = nil, nil, nil
    View.render_focus(draw_api, imgui_api, settings, row)
    assert(table.concat(texts, "\n"):find("--:--", 1, true))
    draw_api.filled_rect = function() error("focus draw error") end
    raises(function() View.render_focus(draw_api, imgui_api, settings, row) end, "focus draw error")
    equal(stack(), 0)
end)

test("combat HUD omits auxiliary captions for quest and other monsters but preserves demo and errors", function()
    for _, target in ipairs({ true, false }) do
        local d, i, _, texts = render_fixture()
        local row = { name = "Gravios", health = 50, max_health = 100, ratio = 0.5,
            quest_target = target, rage = { active = true, remaining = 103, ratio = 0.5,
                observed_count = 2 } }
        View.render_focus(d, i, spanish_defaults(), row)
        local content = table.concat(texts, "\n")
        for _, caption in ipairs({ "OBJETIVO DE MISION", "EN COMBATE", "activaciones observadas" }) do
            assert(not content:find(caption, 1, true))
        end
        assert(content:find("Gravios", 1, true))
        assert(content:find("+2", 1, true))
        assert(content:find("1:43", 1, true))
        View.render_focus(d, i, spanish_defaults(), row, true, "Error de lectura")
        content = table.concat(texts, "\n")
        assert(content:find("DEMO - COMBATE", 1, true))
        assert(content:find("Error de lectura", 1, true))
    end
end)

test("combat HUD clamps every primitive and label across widths, scale, viewport and font APIs", function()
    for _, viewport in ipairs({ { x = 1920, y = 1080 }, { x = 420, y = 236 }, { x = 320, y = 200 } }) do
        for _, scale in ipairs({ 0.5, 1, 2.5 }) do
            for _, font in ipairs({ true, false }) do
                local settings = spanish_defaults()
                settings.scale, settings.focus_x, settings.focus_y = scale, 16000, 16000
                local draw_api, imgui_api, rects, _, stack = render_fixture()
                imgui_api.get_display_size = function() return viewport end
                local font_size = 18
                if font then
                    imgui_api.push_font_size = function(size) font_size = size end
                    imgui_api.pop_font_size = function() font_size = 18 end
                else
                    imgui_api.push_font_size, imgui_api.pop_font_size = nil, nil
                end
                imgui_api.calc_text_size = function(value)
                    return { x = utf8.len(value) * font_size / 2, y = font_size }
                end
                draw_api.text = function(value, x, y, color)
                    if color == 0xFF000000 then return end
                    assert(x >= 0, value .. " left")
                    assert(y >= 0, value .. " top")
                    assert(x + imgui_api.calc_text_size(value).x <= viewport.x + 0.01, value .. " right")
                    assert(y + font_size <= viewport.y + 0.01, value .. " bottom")
                end
                View.render_focus(draw_api, imgui_api, settings, {
                    name = string.rep("狩", 100), health = 200000, max_health = 200000,
                    ratio = 1, rage = { active = false, ratio = 1, observed_count = 100 },
                })
                for _, rect in ipairs(rects) do
                    assert(rect.x >= 0 and rect.y >= 0 and rect.w >= 0 and rect.h >= 0)
                    assert(rect.x + rect.w <= viewport.x + 0.01)
                    assert(rect.y + rect.h <= viewport.y + 0.01)
                end
                equal(stack(), 0)
            end
        end
    end
end)

test("combat settings migrate existing files without changing ordinary layout or DPS placement", function()
    local settings = assert(Config.validate({ horizontal = false, x = 123, y = 45, dps_y = 600 }))
    equal(settings.auto_focus, true)
    equal(settings.focus_width, 980)
    equal(settings.horizontal, false)
    equal(settings.x, 123)
    equal(settings.dps_y, 600)
    for _, invalid in ipairs({
        { auto_focus = 1 }, { focus_width = 419 }, { focus_width = 1601 },
        { focus_x = -1 }, { focus_y = 0 / 0 },
    }) do equal(Config.validate(invalid), nil) end
end)

test("missing combat statuses report explicitly without blocking HP or supported conditions", function()
    local _, model, _, values, hooks, reports, types = fixture()
    local original_method = types["app.cEmModuleConditions"].get_method
    types["app.cEmModuleConditions"].get_method = function(self, name)
        if name ~= "get__Conditions" then return original_method(self, name) end
    end
    values.stun_active, values.stun_timer = true, 4
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model.monsters["100"]
    equal(row.health, 12500)
    equal(row.paralysis, nil)
    equal(row.stun, nil)
    equal(row.rage.current, 30)
    assert(reports.paralisis:find("get__Conditions", 1, true))
    assert(reports.aturdimiento:find("get__Conditions", 1, true))
    equal(reports.lectura, nil)
end)

test("DPS capture errors do not disable focus, and destroyed or dead monsters cannot resume old focus", function()
    local f = damage_fixture()
    f.combat = true
    f.source:poll_focus()
    f.source.feature_failures.dps = true
    f.model:set("100", { name = "A", health = 100, max_health = 100 })
    f:stock(); f:mark()
    equal(f.model:focused().name, "A")
    equal(f.damage.hits, 0)
    f:stock()
    f.source:on_destroy({ nil, f.enemy })
    f:mark()
    equal(f.model.focus_key, nil)
    f.model:set("100", { name = "Replacement", health = 100, max_health = 100 })
    equal(f.model:focused(), nil)
    f:stock(); f:mark()
    equal(f.model:focused().name, "Replacement")
    f.model:set("100", { name = "Replacement", health = 0, max_health = 100 })
    equal(f.model:focused(), nil)
    equal(f.model.focus_key, nil)
end)

test("entrypoint automatically switches to one struck monster and restores overview after combat", function()
    local f = damage_fixture()
    f.combat = true
    local callbacks, hooks, _, _, texts, options = bootstrap({ damage_fixture = f })
    hooks[2].pre({ nil, "enemy_pointer" })
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("HP  (", 1, true))
    hooks[3].pre({ nil, nil, f.hit })
    hooks[4].pre({ nil, nil, f.calc, f.hit })
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("62,50%", 1, true))
    assert(not table.concat(texts, "\n"):find("HP  (", 1, true))
    f.combat = false
    for _ = 1, 6 do callbacks.frame() end
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("HP  (", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    options.click = "DEMO: mostrar barra de combate"
    callbacks.ui()
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("DEMO - COMBATE", 1, true))
end)

test("bad conditions are selected by runtime type from the SDK collection, never guessed getters or indices", function()
    local _, model, _, values, hooks, reports = fixture()
    local unrelated = object("app.cEnemyBadConditionPoison", {}, {})
    local trap = object("app.cEnemyBadConditionFieldPitfall", {}, {})
    local function state(name, current, limit, active, timer, duration)
        return object(name, {}, {
            get_IsValid = function() return true end,
            get_IsActive = function() return active end,
            get_Value = function() return current end,
            get_LimitValue = function() return limit end,
            get_CurrentTimer = function() return timer end,
            get_ActivateTime = function() return duration end,
        })
    end
    local paralysis = state("app.cEnemyBadConditionParalyse", 35, 100, false, 0, 20)
    local stun = state("app.cEnemyBadConditionStun", 0, 100, true, 4, 12)
    values.bad_conditions = { unrelated, stun, trap, paralysis }
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model.monsters["100"].paralysis.ratio, 0.35)
    equal(model.monsters["100"].stun.remaining, 8)
    equal(model.monsters["100"].stun.observed_count, 1)
    equal(next(reports), nil)
    values.bad_conditions = { paralysis, unrelated, stun }
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model.monsters["100"].stun.observed_count, 1)
    equal(model.monsters["100"].paralysis.current, 35)
end)

test("missing, invalid and malformed bad conditions never fabricate values or interrupt other widgets", function()
    for _, scenario in ipairs({ "absent", "invalid", "duplicate", "bad-value" }) do
        local _, model, _, values, hooks, reports = fixture()
        local entry = object("app.cEnemyBadConditionParalyse", {}, {
            get_IsValid = function() return scenario ~= "invalid" end,
            get_IsActive = function() return false end,
            get_Value = function() return scenario == "bad-value" and math.huge or 30 end,
            get_LimitValue = function() return 100 end,
        })
        values.bad_conditions = scenario == "absent" and {}
            or (scenario == "duplicate" and { entry, entry } or { entry })
        hooks[2].pre({ nil, "enemy_pointer" })
        local row = model.monsters["100"]
        equal(row.health, 12500)
        equal(row.rage.current, 30)
        equal(row.stamina.current, 180)
        if scenario == "duplicate" then
            equal(row.paralysis.current, 30)
            equal(row.paralysis.ratio, 0.3)
        else
            equal(row.paralysis, nil)
        end
        equal(row.stun, nil)
        equal(reports.lectura, nil)
        if scenario == "bad-value" then
            assert(reports.paralisis)
        else
            equal(reports.paralisis, nil)
        end
    end
end)

test("mini cards retain every previous panel dimension while sharing the large HUD style", function()
    for _, compact in ipairs({ false, true }) do
        for _, horizontal in ipairs({ false, true }) do
            local settings = spanish_defaults()
            settings.compact, settings.horizontal = compact, horizontal
            local row = { name = "Nerscylla curtido", health = 32763, max_health = 32947,
                ratio = 32763 / 32947, rage = { active = false, ratio = 0.2, observed_count = 2 },
                stamina = { active = false, ratio = 0.9 },
                paralysis = { active = true, ratio = 0.5, remaining = 8, observed_count = 1 },
                stun = { active = false, ratio = 0.1, observed_count = 0 },
                parts = { broken = 1, total = 4 }, wounds = { states = { NORMAL = 20, TEAR = 3, RAW = 1 } } }
            local draw_api, imgui_api, rects, texts, stack = render_fixture()
            local layout = View.layout(settings, { row, row }, { x = 1920, y = 1080 }, false)
            equal(layout.width, 340)
            equal(layout.panels[1].height, (compact and 66 or 88) + 56 + 44)
            View.render(draw_api, imgui_api, settings, { row, row })
            local content = table.concat(texts, "\n")
            for _, value in ipairs({ "Nerscylla curtido", "1/4", "20", "3", "1", "+2", "+1", "+0", "0:08" }) do
                assert(content:find(value, 1, true), value)
            end
            for _, rect in ipairs(rects) do
                local in_card = false
                for _, panel in ipairs(layout.panels) do
                    local x, y = layout.x + panel.x, layout.y + panel.y
                    if rect.x >= x and rect.y >= y and rect.x + rect.w <= x + layout.width + 0.001
                        and rect.y + rect.h <= y + panel.height + 0.001 then in_card = true end
                end
                assert(in_card, "drawing outside original card bounds")
            end
            equal(stack(), 0)
        end
    end
end)

test("mini ring draw failures unwind both fonts and disabling enlargement keeps live statuses", function()
    local _, model, settings, values, hooks = fixture()
    settings.auto_focus = false
    values.stun_active, values.stun_timer = true, 4
    hooks[2].pre({ nil, "enemy_pointer" })
    local row = model.monsters["100"]
    equal(row.stun.remaining, 6)
    equal(row.paralysis.current, 20)
    local draw_api, imgui_api, _, _, stack = render_fixture()
    draw_api.text = function(value)
        if value == "Paralisis" then error("mini ring draw failed") end
    end
    raises(function()
        View.render(draw_api, imgui_api, settings, { row })
    end, "mini ring draw failed")
    equal(stack(), 0)
end)

test("REFramework enlargement option saves the choice, restores small cards and requires a fresh hit", function()
    local f = damage_fixture()
    f.combat = true
    local callbacks, hooks, messages, saves, texts, options = bootstrap({ damage_fixture = f })
    hooks[2].pre({ nil, "enemy_pointer" })
    callbacks.frame()
    hooks[3].pre({ nil, nil, f.hit })
    hooks[4].pre({ nil, nil, f.calc, f.hit })
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("62,50%", 1, true))
    options.click = "Ampliar al golpear un monstruo (desmarcado: siempre pequenas)"
    callbacks.ui()
    callbacks.save()
    equal(saves[#saves].config.auto_focus, false)
    assert(table.concat(messages, "\n"):find("siempre ventanitas pequenas", 1, true))
    hooks[3].pre({ nil, nil, f.hit })
    hooks[4].pre({ nil, nil, f.calc, f.hit })
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("HP  (", 1, true))
    assert(not table.concat(texts, "\n"):find("62,50%", 1, true))
    callbacks.ui()
    callbacks.save()
    equal(saves[#saves].config.auto_focus, true)
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts, "\n"):find("62,50%", 1, true))
    hooks[3].pre({ nil, nil, f.hit })
    hooks[4].pre({ nil, nil, f.calc, f.hit })
    callbacks.frame()
    assert(table.concat(texts, "\n"):find("62,50%", 1, true))
    equal(Config.validate({ auto_focus = false }).auto_focus, false)
end)

test("multiple paralysis and stun sources select a coherent snapshot independently of array order", function()
    for _, type_name in ipairs({ "app.cEnemyBadConditionParalyse", "app.cEnemyBadConditionStun" }) do
        local key = type_name:find("Paralyse", 1, true) and "paralysis" or "stun"
        local function state(active, current, maximum, valid)
            local result = object(type_name, {}, {
                get_IsValid = function() return valid ~= false end,
                get_IsActive = function() return active end,
                get_Value = function() return current end,
                get_LimitValue = function() return maximum end,
                get_CurrentTimer = function() return current end,
                get_ActivateTime = function() return maximum end,
            })
            return result
        end
        local scenarios = {
            { entries = { state(false, 90, 100), state(true, 4, 12), state(true, 10, 30) },
                current = 10, maximum = 30, remaining = 20, active = true },
            { entries = { state(false, 50, 200), state(false, 40, 50), state(false, 70, 100) },
                current = 40, maximum = 50, active = false },
            { entries = { state(false, 20, 100, false), state(false, 30, 100) },
                current = 30, maximum = 100, active = false },
            { entries = { state(true, 2, 12), state(true, 20, 30) },
                current = 20, maximum = 30, remaining = 10, active = true },
        }
        for _, scenario in ipairs(scenarios) do
            local _, model, _, values, hooks, reports = fixture()
            values.bad_conditions = scenario.entries
            hooks[2].pre({ nil, "enemy_pointer" })
            local result = model.monsters["100"][key]
            assert(result, key .. ": " .. tostring(reports.paralisis or reports.aturdimiento))
            equal(result.current, scenario.current)
            equal(result.maximum, scenario.maximum)
            equal(result.remaining, scenario.remaining)
            equal(result.active, scenario.active)
            equal(result.observed_count, scenario.active and 1 or 0)
            equal(next(reports), nil)
            local reversed = {}
            for index = #scenario.entries, 1, -1 do
                reversed[#reversed + 1] = scenario.entries[index]
            end
            values.bad_conditions = reversed
            for _ = 1, 6 do model:advance() end
            hooks[2].pre({ nil, "enemy_pointer" })
            local reordered = model.monsters["100"][key]
            for _, field in ipairs({ "active", "current", "maximum", "ratio", "remaining", "observed_count" }) do
                equal(reordered[field], result[field])
            end
        end
    end
end)

test("repeated active references do not inflate counts and malformed secondary states remain explicit", function()
    local _, model, _, values, hooks, reports = fixture()
    local active = object("app.cEnemyBadConditionParalyse", {}, {
        get_IsValid = function() return true end,
        get_IsActive = function() return true end,
        get_CurrentTimer = function() return 5 end,
        get_ActivateTime = function() return 20 end,
    })
    values.bad_conditions = { active, active }
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model.monsters["100"].paralysis.remaining, 15)
    equal(model.monsters["100"].paralysis.observed_count, 1)
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model.monsters["100"].paralysis.observed_count, 1)
    equal(next(reports), nil)
    values.bad_conditions[3] = object("app.cEnemyBadConditionParalyse", {}, {
        get_IsValid = function() return true end,
        get_IsActive = function() return false end,
        get_Value = function() return math.huge end,
        get_LimitValue = function() return 100 end,
    })
    for _ = 1, 6 do model:advance() end
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model.monsters["100"].paralysis, nil)
    assert(reports.paralisis)
    equal(model.monsters["100"].health, 12500)
end)

test("activities read real quantities, slot capacities, local names, ship and rations independently", function()
    local f = activities_fixture()
    f.poll()
    equal(f.source.activities_visible, true)
    local snapshot = f.source.activities
    equal(#snapshot.collection.collectors, 2)
    local row = snapshot.collection.collectors[1]
    equal(row.id, 101)
    equal(row.name, "Rysher")
    equal(row.count, 25)
    equal(row.occupied, 2)
    equal(row.capacity, 3)
    equal(row.full, false)
    equal(snapshot.collection.collectors[2].name, "Apar")
    equal(snapshot.collection.collectors[2].full, true)
    equal(snapshot.ship.in_port, true)
    equal(snapshot.ship.days, 2)
    equal(snapshot.rations.count, 7)
    equal(snapshot.rations.capacity, 10)
    equal(snapshot.rations.full, false)
    equal(f.name_reads, 2)
    f.poll()
    equal(f.name_reads, 2)
    equal(next(f.reports), nil)
end)

test("activities hide immediately in a mission despite sample throttle and return outside it", function()
    local f = activities_fixture()
    f.poll()
    f.playing = true
    f.source:poll_activities()
    equal(f.source.activities_visible, false)
    equal(f.source.activities, nil)
    f.playing = false
    f.combat = true
    f.source:poll_activities()
    equal(f.source.activities_visible, true)
    equal(next(f.reports), nil)
end)

test("activities hide during loading, without a character or save, and never retain stale snapshots", function()
    for _, absent in ipairs({ "loading", "no_save", "master" }) do
        local f = activities_fixture()
        f.poll()
        if absent == "master" then f.master = nil else f[absent] = true end
        f.source:poll_activities()
        equal(f.source.activities_visible, false)
        equal(f.source.activities, nil)
        equal(next(f.reports), nil)
    end
end)

test("activities refresh after collection and save changes without retaining managed objects", function()
    local f = activities_fixture()
    f.poll()
    local previous = f.source.activities
    f.collectors[2].counts = { 0, 0, 0 }
    f.rations, f.days, f.in_port = 10, 1, false
    f.poll()
    equal(previous.collection.collectors[1].count, 25)
    equal(f.source.activities.collection.collectors[1].count, 0)
    equal(f.source.activities.rations.full, true)
    equal(f.source.activities.ship.in_port, false)
    equal(f.source.activities.ship.days, 1)
    local function scalars_only(value)
        for _, item in pairs(value) do
            assert(type(item) ~= "function" and type(item) ~= "userdata")
            if type(item) == "table" then scalars_only(item) end
        end
    end
    scalars_only(f.source.activities)
    f.rations = 2
    f.save.get_address = function() return 800 end
    f.source:poll_activities()
    equal(f.source.activities.rations.count, 2)
end)

test("disabling activities or all their rows clears them without SDK access", function()
    for _, key in ipairs({ "enabled", "show_activities", "all" }) do
        local f = activities_fixture()
        f.poll()
        if key == "all" then
            f.settings.activities_collection, f.settings.activities_ship, f.settings.activities_rations = false, false, false
        else
            f.settings[key] = false
        end
        f.source.sdk.get_managed_singleton = function() error("disabled SDK read") end
        f.source:poll_activities()
        equal(f.source.activities_visible, false)
        equal(f.source.activities, nil)
        equal(next(f.reports), nil)
    end
end)

test("individual activity switches avoid their SDK access and malformed unavailable categories", function()
    local f = activities_fixture()
    f.settings.activities_collection, f.settings.activities_ship = false, false
    f.collection_error, f.no_ship = true, true
    f.poll()
    equal(f.source.activities.collection, nil)
    equal(f.source.activities.ship, nil)
    equal(f.ship_reads, nil)
    equal(f.source.activities.rations.count, 7)
    equal(next(f.reports), nil)
end)

test("activity failures isolate categories, discard partial reads, latch and can be retried", function()
    local f = activities_fixture()
    f.poll()
    f.collectors[2].counts = { -1, 2 }
    f.rations_error = true
    f.poll()
    equal(f.source.activities.collection, nil)
    equal(f.source.activities.rations, nil)
    equal(f.source.activities.ship.in_port, true)
    assert(f.reports.recoleccion:find("Cantidad de material", 1, true))
    assert(f.reports.raciones:find("rations unavailable", 1, true))
    f.collectors[2].counts = { 3 }
    f.rations_error = false
    f.poll()
    equal(f.source.activities.rations, nil)
    f.source:retry_features()
    f.poll()
    equal(f.source.activities.rations.count, 7)
    equal(f.source.activities.collection.collectors[1].count, 3)
    equal(f.source.activities_visible, true)
end)

test("invalid activity data never becomes a fake zero or full deposit", function()
    for _, change in ipairs({
        function(f) f.rations = -1 end,
        function(f) f.rations = math.huge end,
        function(f) f.rations = 11 end,
        function(f) f.capacity = 0 end,
        function(f) f.capacity = 1.5 end,
        function(f) f.days = -1 end,
        function(f) f.in_port = 1 end,
        function(f) f.collectors[2].counts = { 0 / 0 } end,
        function(f) f.collectors[2].full = 1 end,
        function(f) f.collectors[2].available = 1 end,
        function(f) f.collectors[2].id = f.collectors[1].id end,
    }) do
        local f = activities_fixture()
        change(f)
        f.poll()
        assert(next(f.reports))
        equal(f.reports.actividades, nil)
        equal(f.source.activities_visible, true)
    end
end)

test("unknown activity visibility fails closed and missing names do not block real counts", function()
    local f = activities_fixture()
    f.playing = 1
    f.poll()
    equal(f.source.activities_visible, false)
    assert(f.reports.actividades:find("IsPlayingQuest", 1, true))
    local g = activities_fixture()
    g.types["app.NpcUtil"] = nil
    g.poll()
    equal(g.source.activities.collection.collectors[1].name, "Recolector #101")
    equal(g.source.activities.collection.collectors[1].count, 25)
    assert(g.reports.nombres_actividades)
    equal(g.reports.recoleccion, nil)
end)

test("collector filtering uses the real unassigned sentinel, tolerates locked duplicates and keeps negative IDs", function()
    local f = activities_fixture()
    f.collectors = {
        { id = -1 }, { id = -1 },
        { id = 309, counts = {}, available = false, full = false },
        { id = 309, counts = {}, available = false, full = false },
        { id = -1234, counts = { 6 }, available = true, full = false },
    }
    f.source.collector_ids = { [-1234] = 11 }
    f.poll()
    equal(#f.source.activities.collection.collectors, 1)
    equal(f.source.activities.collection.collectors[1].id, -1234)
    equal(f.source.activities.collection.collectors[1].name, "Rysher")
    equal(f.source.activities.collection.collectors[1].count, 6)
    equal(next(f.reports), nil)
end)

test("activity root errors discard snapshots and an explicit retry restores the panel", function()
    local f = activities_fixture()
    f.poll()
    local ga = f.types["app.GA"]
    f.types["app.GA"] = nil
    f.source:poll_activities()
    equal(f.source.activities, nil)
    equal(f.source.activities_visible, false)
    assert(f.reports.actividades:find("app.GA", 1, true))
    f.types["app.GA"] = ga
    f.source:poll_activities()
    equal(f.source.activities_visible, false)
    f.source:retry_features()
    f.source:poll_activities()
    equal(f.source.activities_visible, true)
end)

test("locked ship and empty collections are explicit without inventing a countdown", function()
    local f = activities_fixture()
    f.opened, f.collectors = false, {}
    f.days = -1
    f.poll()
    equal(f.source.activities.ship.opened, false)
    equal(f.source.activities.ship.days, nil)
    local rows = View.activity_rows(f.source.activities, f.settings)
    equal(rows[2].detail, "Sin recogidas disponibles")
    equal(rows[3].detail, "No desbloqueado")
    equal(next(f.reports), nil)
end)

test("activity config migration preserves existing monster and damage settings and validates new values", function()
    local settings = assert(Config.validate({ auto_focus = false, dps_x = 241, horizontal = false }))
    equal(settings.auto_focus, false)
    equal(settings.dps_x, 241)
    equal(settings.horizontal, false)
    equal(settings.show_activities, true)
    equal(settings.activities_width, 380)
    for _, invalid in ipairs({
        { show_activities = 1 }, { activities_ship = "true" }, { activities_rations = 1 },
        { activities_collection = 0 }, { activities_width = 299 },
        { activities_x = math.huge }, { activities_y = 0.5 },
    }) do equal(Config.validate(invalid), nil) end
end)

test("activity rendering shows slot counters, missing data and no invented arrival estimates", function()
    local f = activities_fixture()
    f.poll()
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    View.render_activities(draw_api, imgui_api, f.settings, f.source.activities)
    local labels = table.concat(texts, "\n")
    for _, label in ipairs({ "Rysher", "2/3", "3/3", "EN PUERTO",
        "Dias del ciclo: 2", "7/10" }) do assert(labels:find(label, 1, true), labels) end
    assert(not labels:find("objetos") and not labels:find("espacios"))
    assert(not labels:find("DEMO"))
    equal(stack(), 0)
    assert(#rects > 10)
    local rows = View.activity_rows({}, f.settings)
    equal(rows[2].detail, "-- | Ver Diagnostico")
    equal(rows[3].detail, "-- | Ver Diagnostico")
    equal(rows[4].detail, "-- | Ver Diagnostico")
end)

test("activity panel clamps position and dimensions, reports clipped rows and supports legacy fonts", function()
    local f = activities_fixture()
    f.poll()
    for index = 3, 5 do
        f.source.activities.collection.collectors[index] = { name = "Recolector " .. index,
            count = 5, occupied = 1, capacity = 3, full = false, available = true }
    end
    for _, scale in ipairs({ 0.5, 1, 2.5 }) do
        local draw_api, imgui_api, rects, texts, stack = render_fixture()
        local text_positions = {}
        local record_text = draw_api.text
        draw_api.text = function(value, x, y)
            record_text(value)
            text_positions[#text_positions + 1] = { value = value, x = x, y = y }
        end
        f.settings.scale, f.settings.activities_x, f.settings.activities_y = scale, 16384, 16384
        View.render_activities(draw_api, imgui_api, f.settings, f.source.activities)
        for _, rect in ipairs(rects) do
            assert(rect.x >= 0 and rect.y >= 0 and rect.w > 0 and rect.h > 0)
            assert(rect.x + rect.w <= 1920 and rect.y + rect.h <= 1080)
        end
        equal(stack(), 0)
        if scale == 2.5 then
            assert(table.concat(texts):find("sin mostrar"))
            local footers, last_row_y = 0, 0
            for _, pos in ipairs(text_positions) do
                if pos.value:find("sin mostrar") then
                    footers = footers + 1
                    assert(pos.y > last_row_y)
                    assert(pos.y + 14 * scale <= 1080)
                else
                    last_row_y = math.max(last_row_y, pos.y)
                end
            end
            equal(footers, 2)
        end
    end
    local draw_api, imgui_api, _, _, stack = render_fixture()
    imgui_api.push_font_size, imgui_api.pop_font_size = nil, nil
    View.render_activities(draw_api, imgui_api, f.settings, f.source.activities)
    equal(stack(), 0)
    f.settings.show_activities = false
    local _, _, rects = render_fixture()
    draw_api.filled_rect = function() error("disabled draw") end
    View.render_activities(draw_api, imgui_api, f.settings, f.source.activities)
    equal(#rects, 0)
end)

test("activity renderer restores font stack on draw or malformed UTF8 failure", function()
    local f = activities_fixture()
    f.poll()
    local draw_api, imgui_api, _, _, stack = render_fixture()
    draw_api.text = function() error("drawing failed") end
    raises(function()
        View.render_activities(draw_api, imgui_api, f.settings, f.source.activities)
    end, "drawing failed")
    equal(stack(), 0)
    draw_api.text = function() end
    f.source.activities.collection.collectors[1].name = "\255"
    raises(function()
        View.render_activities(draw_api, imgui_api, f.settings, f.source.activities)
    end, "UTF")
    equal(stack(), 0)
end)

local function obstruction_fixture()
    local f = activities_fixture()
    f.map_open, f.full_screen, f.talking, f.choice, f.category = false, false, false, false, 6
    f.flow_manager = object("app.GameFlowManager", {}, {
        get_Loading = function()
            if f.scene_error then error("Loading unavailable") end
            if f.scene_invalid then return 1 end
            return f.scene_loading == true
        end,
    })
    local loading = object("app.cGUIJanctionLoadingController", {}, {
        get_IsLoading = function()
            if f.travel_error then error("IsLoading unavailable") end
            return f.travel_loading == true
        end,
    })
    local component = object("via.gui.GUI", {}, {
        get_Enabled = function()
            if f.map_error then error("Map component unavailable") end
            return f.map_open
        end,
    })
    local controller = object("via.gui.GUIController", {}, { get_Component = function() return component end })
    local front = object("app.GUI060000", {}, { get_GUIController = function() return controller end })
    local map = object("app.cGUIMapController", {}, { get_GUIFront = function() return front end })
    f.gui_manager = object("app.GUIManager", {}, {
        get_JanctionLoadingController = function()
            if not f.no_loading_controller then return loading end
        end,
        get_MAP3D = function() return map end,
        isOpenFullScreenUI = function() return f.full_screen end,
        isNpcMenuOpen = function()
            if f.npc_menu_error then error("isNpcMenuOpen unavailable") end
            return f.npc_menu == true
        end,
        ["isActiveFacilityMenu(System.Boolean)"] = function(_, flag)
            assert(type(flag) == "boolean")
            return f.facility == flag
        end,
    })
    f.subtitle_fields = { _SubtitlesCategory = 6 }
    local subtitles_gui = object("app.GUI020400", f.subtitle_fields, {})
    local subtitles = object("app.cDialogueSubtitleManager", {}, {
        get_IsChoiceGUIVisible = function() return f.choice end,
        get__SubtitlesGUI = function() return subtitles_gui end,
    })
    f.dialogue_manager = object("app.DialogueManager", {}, {
        get_IsTalking = function()
            if f.dialogue_error then error("IsTalking unavailable") end
            return f.talking
        end,
        get_SubtitleManager = function() return subtitles end,
    })
    local values = { DEMO = 0, EVENT_TALK = 1, SELECT = 2, GOSSIP = 3, NAGARA = 4, EVENT = 5, TALK = 6 }
    local category_type = { get_field = function(_, name)
        local value = values[name]
        if value then return { get_data = function(_, instance) equal(instance, nil); return value end } end
    end }
    f.types["app.GUI020400.SUBTITLES_CATEGORY"] = category_type
    return f
end

test("map, full-screen menus and real conversations hide every overlay only while they are open", function()
    local f = obstruction_fixture()
    local callbacks, _, messages, saves, texts, options = bootstrap({ activities_fixture = f })
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    options.click = nil
    local function shown()
        for index = #texts, 1, -1 do texts[index] = nil end
        callbacks.frame()
        return table.concat(texts, "\n")
    end
    local visible = shown()
    assert(visible:find("ACTIVIDADES - DEMO", 1, true))
    assert(visible:find("DMG", 1, true))
    local function settle()
        for _ = 1, 45 do callbacks.frame() end
        return shown()
    end
    for _, case in ipairs({
        { "scene_loading", true, "Carga de escena", 0 },
        { "travel_loading", true, "Carga de escena", 0 },
        { "map_open", true, "Mapa abierto", 0 }, { "full_screen", true, "Menu a pantalla completa", 0 },
        { "choice", true, "Conversacion", 45 }, { "npc_menu", true, "Menu de NPC/instalacion", 45 },
        { "facility", false, "Menu de NPC/instalacion", 45 },
        { "facility", true, "Menu de NPC/instalacion", 45 },
    }) do
        f[case[1]] = case[2]
        equal(shown(), "")
        local first = #messages + 1
        callbacks.ui()
        assert(table.concat(messages, "\n", first):find("Ocultacion temporal: " .. case[3], 1, true))
        f[case[1]] = nil
        if case[1] ~= "facility" then f[case[1]] = false end
        if case[4] == 0 then
            equal(shown(), visible)
        else
            equal(shown(), "")
            equal(settle(), visible)
        end
    end
    -- forge flow: talk -> brief gap -> facility menu -> close; never flashes back in between
    f.talking = true
    equal(shown(), "")
    f.talking = false
    for _ = 1, 20 do equal(shown(), "") end
    f.facility = true
    for _ = 1, 100 do equal(shown(), "") end
    f.facility = nil
    equal(settle(), visible)
    f.talking = true
    for category, hidden in pairs({ [0] = true, [1] = true, [2] = true, [3] = false,
        [4] = false, [5] = true, [6] = true }) do
        f.subtitle_fields._SubtitlesCategory = category
        equal(settle() == "", hidden)
    end
    f.subtitle_fields._SubtitlesCategory = 6
    f.talking = false
    equal(settle(), visible)
    callbacks.save()
    equal(#saves, 0)
    for _, message in ipairs(messages) do assert(not message:find("ocultar_", 1, true), message) end
end)

test("full-screen mission list allows its preview but map and unrelated menus still hide it", function()
    local f = obstruction_fixture()
    f.source.mission_preview = {}
    f.full_screen = true
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Vista previa de mision")
    f.map_open = true
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Mapa abierto")
    f.map_open, f.source.mission_preview = false, nil
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Menu a pantalla completa")
end)

test("quest preview survives quest-counter NPC menus and holds but not dialogue map or loading", function()
    local f = obstruction_fixture()
    local mission = mission_preview_fixture()
    local board = mission.board
    local original_convert = f.source.sdk.to_managed_object
    f.source.sdk.to_managed_object = function(pointer)
        if pointer == "board_pointer" then return board end
        if pointer == "parts_pointer" then return mission.parts end
        if pointer == "selected_pointer" then return mission.selected end
        return original_convert(pointer)
    end
    local callbacks, hooks, _, _, texts, options = bootstrap({ activities_fixture = f })
    local open, close = hooks[#hooks - 3], hooks[#hooks - 2]
    open.pre({ nil, "board_pointer" })
    hooks[#hooks].pre({ nil, "parts_pointer", "selected_pointer" })
    local function shown()
        for index = #texts, 1, -1 do texts[index] = nil end
        callbacks.frame()
        return table.concat(texts, "\n")
    end
    f.full_screen, f.npc_menu = true, true
    assert(shown():find("MISION SELECCIONADA", 1, true))
    assert(not table.concat(texts):find("ACTIVIDADES", 1, true))
    f.npc_menu, f.facility = false, true
    assert(shown():find("MISION SELECCIONADA", 1, true))
    f.facility = nil
    assert(shown():find("MISION SELECCIONADA", 1, true))
    for _, key in ipairs({ "scene_loading", "travel_loading", "map_open", "talking", "choice" }) do
        f[key] = true
        equal(shown(), "")
        f[key] = false
        assert(shown():find("MISION SELECCIONADA", 1, true), key)
    end
    options.click = "Ocultar con mapa y menus a pantalla completa"
    callbacks.ui()
    options.click = nil
    f.npc_menu = true
    assert(shown():find("MISION SELECCIONADA", 1, true))
    options.click = "Mostrar jugadores de la mision seleccionada"
    callbacks.ui()
    options.click = nil
    equal(shown(), "")
    close.pre({ nil, "board_pointer" })
    equal(shown(), "")
end)

test("loading hides live overlays even with map and dialogue hiding off and restores only eligible panels", function()
    local f = obstruction_fixture()
    local callbacks, _, messages, saves, texts, options = bootstrap({ activities_fixture = f })
    local function toggle(label)
        options.click = label
        callbacks.ui()
        options.click = nil
    end
    toggle("Ocultar con mapa y menus a pantalla completa")
    toggle("Ocultar en conversaciones y menus de NPC (forja, tienda...)")
    local function shown()
        for index = #texts, 1, -1 do texts[index] = nil end
        callbacks.frame()
        return table.concat(texts, "\n")
    end
    assert(shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    f.scene_loading = true
    for _ = 1, 60 do equal(shown(), "") end
    f.travel_loading = true
    f.scene_loading = false
    equal(shown(), "")
    f.travel_loading = false
    assert(shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    f.scene_loading = true
    equal(shown(), "")
    f.playing = true
    f.scene_loading = false
    assert(not shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    f.scene_loading = true
    f.playing, f.village = false, false
    equal(shown(), "")
    f.scene_loading = false
    assert(not shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    f.village = true
    assert(shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    toggle("Mostrar actividades fuera de mision")
    f.scene_loading = true
    equal(shown(), "")
    f.scene_loading = false
    assert(not shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    toggle("Mostrar actividades fuera de mision")
    f.scene_loading = true
    toggle("Ocultar durante pantallas de carga")
    assert(shown():find("ACTIVIDADES DEL POBLADO", 1, true))
    callbacks.save()
    equal(saves[1].config.hide_on_loading, false)
    for _, message in ipairs(messages) do assert(not message:find("ocultar_", 1, true), message) end
end)

test("after loading other obstructions still apply without a loading hold or settings changes", function()
    local f = obstruction_fixture()
    f.scene_loading, f.map_open = true, true
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Carga de escena")
    f.scene_loading = false
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Mapa abierto")
    f.map_open, f.facility = false, true
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Menu de NPC/instalacion")
    f.scene_loading = true
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Carga de escena")
    f.facility, f.scene_loading = nil, false
    for _ = 1, 46 do f.model:advance() end
    f.source:poll_obstruction()
    equal(f.source.obstruction, nil)
    equal(f.settings.enabled, true)
    equal(f.settings.hide_on_loading, true)
end)

test("loading detectors fail independently, report once and tolerate missing singletons or controllers", function()
    for _, invalid in ipairs({ "scene_error", "scene_invalid", "travel_error" }) do
        local f = obstruction_fixture()
        local reports = {}
        f.source.report = function(category) reports[#reports + 1] = category end
        f[invalid] = true
        local scene_failed = invalid ~= "travel_error"
        f.scene_loading, f.travel_loading = not scene_failed, scene_failed
        f.source:poll_obstruction()
        f.source:poll_obstruction()
        equal(f.source.obstruction, "Carga de escena")
        equal(#reports, 1)
        equal(reports[1], scene_failed and "ocultar_carga_escena" or "ocultar_carga_viaje")
        f.scene_loading, f.travel_loading = false, false
        f.source:poll_obstruction()
        equal(f.source.obstruction, nil)
    end
    local f = obstruction_fixture()
    f.flow_manager, f.no_loading_controller = nil, true
    f.source:poll_obstruction()
    equal(f.source.obstruction, nil)
    f.travel_loading, f.no_loading_controller = true, false
    f.source:poll_obstruction()
    equal(f.source.obstruction, "Carga de escena")
    f.gui_manager = nil
    f.source:poll_obstruction()
    equal(f.source.obstruction, nil)
    f.settings.enabled = false
    f.source.sdk.get_managed_singleton = function() error("disabled SDK read") end
    f.source:poll_obstruction()
    equal(f.source.obstruction, nil)
end)

test("obstruction toggles are saved and a broken detector never hides overlays permanently", function()
    local f = obstruction_fixture()
    local reports = {}
    local callbacks, _, _, saves, texts, options = bootstrap({ activities_fixture = f })
    f.map_open = true
    options.click = "Ocultar con mapa y menus a pantalla completa"
    callbacks.ui()
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    f.talking = true
    options.click = "Ocultar en conversaciones y menus de NPC (forja, tienda...)"
    callbacks.ui()
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    callbacks.save()
    equal(saves[1].config.hide_on_map, false)
    equal(saves[1].config.hide_on_dialogue, false)
    local g = obstruction_fixture()
    g.source.report = function(category) reports[#reports + 1] = category end
    g.map_error, g.dialogue_error, g.npc_menu_error = true, true, true
    g.source:poll_obstruction()
    g.source:poll_obstruction()
    equal(g.source.obstruction, nil)
    equal(table.concat(reports, ","), "ocultar_mapa,ocultar_conversacion,ocultar_menu_npc")
end)

test("entrypoint keeps activities hidden after a quest until the hunter is back in the village", function()
    local f = activities_fixture()
    local callbacks, _, messages, _, texts = bootstrap({ activities_fixture = f })
    f.playing = true
    callbacks.frame()
    f.playing, f.village = false, false
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    f.village = true
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    f.village = false
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    equal(#messages, 0)
end)

test("entrypoint renders activities outside missions only, saves controls and keeps preview fictional", function()
    local f = activities_fixture()
    local callbacks, _, messages, saves, texts, options = bootstrap({ activities_fixture = f })
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    equal(#messages, 0)
    for index = #texts, 1, -1 do texts[index] = nil end
    f.playing = true
    callbacks.frame()
    assert(not table.concat(texts):find("ACTIVIDADES DEL POBLADO", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    callbacks.frame()
    assert(not table.concat(texts):find("ACTIVIDADES - DEMO", 1, true))
    f.playing = false
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES - DEMO", 1, true))
    equal(f.rations, 7)
    options.click = "Mostrar actividades fuera de mision"
    callbacks.ui()
    callbacks.save()
    equal(#saves, 1)
    equal(saves[1].config.show_activities, false)
    equal(saves[1].config.activities_rations, true)
    equal(saves[1].config.activities, nil)
    equal(saves[1].config.preview, nil)
end)

test("detailed icons use bounded merged rectangles, transparent margins and distinct original silhouettes", function()
    local signatures = {}
    for _, name in ipairs({ "parts", "NORMAL", "TEAR", "RAW", "rage", "paralysis",
        "stun", "collection", "slot", "ship", "rations",
        "dash_juice", "immunizer",
        "seed", "pill", "powder", "ammo", "drug", "mega_drug" }) do
        local draw_api, _, rects = render_fixture()
        Icons.draw(draw_api, name, 10, 20, 16, 0xFF123456)
        assert(#rects > 10 and #rects <= 90, name .. ": " .. #rects .. " rectangles")
        local pixels, signature = {}, {}
        for _, rect in ipairs(rects) do
            assert(rect.x >= 10 and rect.x + rect.w <= 26)
            assert(rect.y >= 20 and rect.y + rect.h <= 36)
            assert(rect.w > 0 and rect.h > 0)
            assert(rect.color == 0xFF123456 or rect.color == 0xFF171717 or rect.color == 0xFFF2F2F2)
            for x = rect.x, rect.x + rect.w - 1 do
                for y = rect.y, rect.y + rect.h - 1 do
                    local key = x .. ":" .. y
                    equal(pixels[key], nil)
                    pixels[key] = true
                end
            end
            signature[#signature + 1] = table.concat({ rect.x, rect.y, rect.w, rect.h, rect.color }, ":")
        end
        equal(pixels["10:20"], nil)
        local identity = table.concat(signature, ";")
        equal(signatures[identity], nil)
        signatures[identity] = name
    end
end)

test("icon scaling is exact, preserves caller alpha and muted states never gain white highlights", function()
    for _, size in ipairs({ 6, 12, 14, 18, 45 }) do
        local draw_api, _, rects = render_fixture()
        Icons.draw(draw_api, "NORMAL", 5, 7, size, 0x66123456, true)
        for _, rect in ipairs(rects) do
            assert(rect.x >= 5 and rect.x + rect.w <= 5 + size)
            assert(rect.y >= 7 and rect.y + rect.h <= 7 + size)
            equal(rect.color >> 24, 0x66)
            assert(rect.color == 0x66123456 or rect.color == 0x66171717)
        end
    end
    local draw_api, _, rects = render_fixture()
    raises(function() Icons.draw(draw_api, "not_an_icon", 0, 0, 16, 0xFFFFFFFF) end, "Unknown icon")
    equal(#rects, 0)
end)

test("all supplied portraits and consumable sprites are transparent bounded and have a fixed draw budget", function()
    local artwork = require("mhoverlay/artwork")
    local required = { unknown = true, might_seed = true, adamant_seed = true,
        demon_powder = true, hardshell_powder = true, demondrug = true, armorskin = true,
        hot_drink = true, cool_drink = true }
    for _, name in pairs(Portraits.ids) do required[name] = true end
    local count, signatures = 0, {}
    for name in pairs(required) do
        count = count + 1
        assert(artwork[name], name)
        local small = {}
        for _, size in ipairs({ 24, 64, 165 }) do
            local rects = {}
            Icons.draw({ filled_rect = function(x, y, w, h, color)
                assert(x >= 10 and y >= 20 and x + w <= 10 + size and y + h <= 20 + size)
                assert(w > 0 and h > 0)
                equal(color >> 24, 0x66)
                rects[#rects + 1] = { x, y, w, h, color }
            end }, name, 10, 20, size, 0x66123456)
            assert(#rects > 100 and #rects <= 1600, name .. ": " .. #rects)
            if size == 64 then
                local occupied, signature = {}, {}
                for _, r in ipairs(rects) do
                    for x = r[1] - 10, r[1] + r[3] - 11 do
                        for y = r[2] - 20, r[2] + r[4] - 21 do
                            local key = x .. ":" .. y
                            equal(occupied[key], nil)
                            occupied[key] = r[5]
                        end
                    end
                    signature[#signature + 1] = table.concat(r, ":")
                end
                equal(occupied["0:0"], nil)
                equal(occupied["63:63"], nil)
                local identity = table.concat(signature, ";")
                assert(not signatures[identity], name)
                signatures[identity] = name
                small = rects
            elseif size == 165 then
                equal(#rects, #small)
                for index, r in ipairs(rects) do
                    local base = small[index]
                    equal(r[1], 10 + (base[1] - 10) * 165 / 64)
                    equal(r[2], 20 + (base[2] - 20) * 165 / 64)
                    equal(r[3], base[3] * 165 / 64)
                    equal(r[4], base[4] * 165 / 64)
                end
            end
        end
    end
    equal(count, 38)
    for _, name in ipairs({ "might_seed", "adamant_seed", "demon_powder",
        "hardshell_powder", "demondrug", "armorskin", "hot_drink", "cool_drink" }) do
        Icons.draw({ filled_rect = function(_, _, _, _, color)
            equal(color, 0x66123456)
        end }, name, 0, 0, 24, 0x66123456, true)
    end
end)

test("drink flasks preserve narrow necks flat bases and blue or red liquid", function()
    for _, name in ipairs({ "cool_drink", "hot_drink" }) do
        local pixels, last_y, liquid = {}, 0, 0
        Icons.draw({ filled_rect = function(x, y, w, h, color)
            local red, green, blue = color & 0xFF, (color >> 8) & 0xFF, (color >> 16) & 0xFF
            local is_liquid = name == "cool_drink"
                and blue > red + 30 and green > red + 30
                or name == "hot_drink" and red > green + 30 and red > blue + 30
            for py = y, y + h - 1 do
                pixels[py] = pixels[py] or {}
                for px = x, x + w - 1 do
                    pixels[py][px] = true
                    if is_liquid then liquid = liquid + 1 end
                end
                last_y = math.max(last_y, py)
            end
        end }, name, 0, 0, 64, 0xFFFFFFFF)
        local function row_width(row)
            local count, left, right = 0, 64, -1
            for x in pairs(row) do
                count, left, right = count + 1, math.min(left, x), math.max(right, x)
            end
            equal(count, right - left + 1)
            return count
        end
        local neck = row_width(assert(pixels[14]))
        local base = row_width(assert(pixels[last_y]))
        assert(neck <= 14 and base >= 24 and base >= neck * 1.8, name)
        assert(liquid >= 200, name .. ": missing colored liquid")
    end
end)

test("portrait identities use reflected IDs independent of localization or numeric enum ordinals", function()
    equal(Portraits.ids.EM0158_00_0, "nu_udra")
    equal(Portraits.ids.EM0163_00_0, "xu_wu")
    equal(Portraits.ids.EM0160_00_0, "arkveld")
    equal(Portraits.ids.EM0160_50_0, "guardian_arkveld")
    local source, model, _, _, hooks, reports, types = fixture()
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(1, false)[1].portrait, "rey_dau")
    equal(next(reports), nil)
    local ids = Portraits.bind(source.sdk)
    for enum, portrait in pairs(Portraits.ids) do
        local id = types["app.EnemyDef.ID"]:get_field(enum):get_data(nil)
        equal(ids[id], portrait)
    end
    equal(ids[987654], nil)
    local previous = source.read
    source.read = function(self, enemy)
        local sample = previous(self, enemy)
        sample.name = "Un nombre localizado sin el nombre ingles"
        return sample
    end
    model.next_sample = {}
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(1, false)[1].portrait, "rey_dau")
    local unknown_source, unknown_model, _, _, unknown_hooks = fixture()
    unknown_source.portrait_ids = {}
    unknown_hooks[2].pre({ nil, "enemy_pointer" })
    equal(unknown_model:rows(1, false)[1].portrait, "unknown")
end)

test("portrait rendering is wired from live HP hooks to the saved card and combat toggle", function()
    local callbacks, hooks, _, saves, _, options, rects = bootstrap()
    hooks[2].pre({ nil, "enemy_pointer" })
    callbacks.frame()
    local expected = {}
    Icons.monster({ filled_rect = function(x, y, w, h, color)
        expected[#expected + 1] = { x = x, y = y, w = w, h = h, color = color }
    end }, "rey_dau", 48, 188, 64)
    for index, rect in ipairs(expected) do
        local actual = rects[index + 1]
        for key, value in pairs(rect) do equal(actual[key], value) end
    end
    options.click = "Mostrar icono de cada monstruo junto a su vida"
    callbacks.ui()
    callbacks.save()
    equal(saves[#saves].config.show_monster_icons, false)
    for index = #rects, 1, -1 do rects[index] = nil end
    callbacks.frame()
    assert(#rects < #expected)
    equal(Config.validate({ show_monster_icons = "yes" }), nil)
    equal(Config.validate({}).show_monster_icons, true)
end)

test("portrait binding failure reports explicitly without losing HP and retries after SDK recovery", function()
    local source, model, settings, _, hooks, reports, types = fixture()
    local definition = types["app.EnemyDef.ID"]
    types["app.EnemyDef.ID"] = nil
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(1, false)[1].health, 12500)
    equal(model:rows(1, false)[1].portrait, nil)
    assert(reports.retratos:find("EnemyDef.ID", 1, true))
    types["app.EnemyDef.ID"] = definition
    source:retry_features()
    model.next_sample = {}
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(1, false)[1].portrait, "rey_dau")
    equal(reports.retratos, nil)
    settings.show_monster_icons = false
    model.next_sample = {}
    hooks[2].pre({ nil, "enemy_pointer" })
    equal(model:rows(1, false)[1].portrait, nil)
    equal(model:rows(1, false)[1].health, 12500)
end)

test("portrait panels leave the exact health fraction visible at every scale and compact setting", function()
    local settings = spanish_defaults()
    settings.show_rage, settings.show_stamina, settings.show_parts, settings.show_wounds = false, false, false, false
    for _, scale in ipairs({ 0.5, 1, 2.5 }) do
        settings.scale = scale
        for _, compact in ipairs({ false, true }) do
            settings.compact = compact
            local d, i, rects = render_fixture()
            local portraits = {}
            local draw_portrait = Icons.monster
            Icons.monster = function(_, name, x, y, size)
                portraits[#portraits + 1] = { name = name, x = x, y = y, size = size }
            end
            local ok, err = pcall(View.render, d, i, settings, {
                { name = "Rey Dau", portrait = "rey_dau", health = 12500, max_health = 20000, ratio = 0.625 },
            })
            Icons.monster = draw_portrait
            assert(ok, err)
            equal(#portraits, 1)
            equal(portraits[1].name, "rey_dau")
            equal(portraits[1].size, (compact and 48 or 64) * scale)
            local bar_x, bar_y = rects[1].x + 80 * scale, rects[1].y + (compact and 55 or 62) * scale
            assert(portraits[1].x + portraits[1].size < bar_x)
            local right = 0
            for _, r in ipairs(rects) do
                if r.y >= bar_y and r.y < bar_y + (compact and 5 or 12) * scale
                    and r.color >> 24 == 255 and (r.color & 255) <= 65 then
                    right = math.max(right, r.x + r.w)
                end
            end
            local bar_width = (settings.width - 92) * scale
            local lines = math.max(1, math.ceil((compact and 5 or 12) * scale))
            local inset = math.huge
            for line = 0, lines - 1 do
                inset = math.min(inset, math.abs(line / math.max(1, lines - 1) - 0.5)
                    * math.min(12, bar_width / 12))
            end
            local expected = bar_x + bar_width * 0.625 - inset
            assert(math.abs(right - expected) < 0.000001, right .. " vs " .. expected)
        end
    end
end)

test("focused portraits replace only the crest and preserve HP and condition geometry", function()
    local settings = spanish_defaults()
    local row = { name = "Rey Dau", portrait = "rey_dau", health = 100, max_health = 200, ratio = 0.5 }
    local d, i, rects, texts = render_fixture()
    local portraits, original = {}, Icons.monster
    Icons.monster = function(_, name, x, y, size)
        portraits[#portraits + 1] = { name, x, y, size }
    end
    local ok, err = pcall(View.render_focus, d, i, settings, row)
    Icons.monster = original
    assert(ok, err)
    equal(#portraits, 1)
    equal(portraits[1][1], "rey_dau")
    equal(portraits[1][4], 66)
    assert(table.concat(texts, "\n"):find("50,00%%"))
    assert(#rects > 100)
    settings.show_monster_icons = false
    local disabled = false
    Icons.monster = function() disabled = true end
    ok, err = pcall(View.render_focus, d, i, settings, row)
    Icons.monster = original
    assert(ok, err)
    equal(disabled, false)
end)

test("new icon rendering is wired into small and focused states and activities without changing layouts", function()
    local settings = spanish_defaults()
    local draw_api, imgui_api = render_fixture()
    local row = { name = "Rey Dau", health = 100, max_health = 200, ratio = 0.5,
        rage = { ratio = 0.5, active = false, current = 50, maximum = 100 },
        stamina = { ratio = 0.5, active = false, current = 50, maximum = 100 },
        parts = { broken = 1, total = 3 }, wounds = { states = { NORMAL = 1, TEAR = 2, RAW = 3 } } }
    local calls = {}
    local original = Icons.draw
    Icons.draw = function(api, name, x, y, size, color, unavailable)
        calls[#calls + 1] = { name = name, unavailable = unavailable, size = size }
        return original(api, name, x, y, size, color, unavailable)
    end
    local ok, err = pcall(function()
        for _, render in ipairs({ View.render, View.render_focus }) do
            calls = {}
            if render == View.render then render(draw_api, imgui_api, settings, { row })
            else render(draw_api, imgui_api, settings, row) end
            equal(#calls, 7)
            local found = {}
            for _, icon in ipairs(calls) do found[icon.name] = icon end
            for _, name in ipairs({ "parts", "NORMAL", "TEAR", "RAW", "rage", "paralysis", "stun" }) do
                assert(found[name], name)
            end
            equal(found.paralysis.unavailable, true)
            equal(found.stun.unavailable, true)
            assert(not found.rage.unavailable)
        end
        calls = {}
        View.render_activities(draw_api, imgui_api, settings, {
            collection = { collectors = {} }, ship = { opened = false },
            rations = { count = 0, capacity = 10, full = false } })
        equal(#calls, 13)
        equal(calls[1].name, "collection")
        equal(calls[2].name, "ship")
        equal(calls[3].name, "rations")
        for _, icon in ipairs(calls) do equal(icon.unavailable, true) end
    end)
    Icons.draw = original
    if not ok then error(err, 0) end
end)

test("detailed icon failures unwind the owning renderer font stack", function()
    local draw_api, imgui_api, _, _, stack = render_fixture()
    local original = Icons.draw
    Icons.draw = function() error("icon renderer failed") end
    local ok, err = pcall(function()
        raises(function()
            View.render_activities(draw_api, imgui_api, spanish_defaults(), {})
        end, "icon renderer failed")
        equal(stack(), 0)
        raises(function()
            View.render_focus(draw_api, imgui_api, spanish_defaults(),
                { name = "Test", health = 1, max_health = 2, ratio = 0.5 })
        end, "icon renderer failed")
        equal(stack(), 0)
    end)
    Icons.draw = original
    if not ok then error(err, 0) end
end)

test("normal rations exclude extra supplies even when combined total exceeds normal capacity", function()
    local f = activities_fixture()
    f.extra_rations = 10
    f.poll()
    equal(f.source.activities.rations.count, 7)
    equal(f.source.activities.rations.capacity, 10)
    equal(f.source.activities.rations.full, false)
    equal(next(f.reports), nil)
    f.rations = 10
    f.poll()
    equal(f.source.activities.rations.count, 10)
    equal(f.source.activities.rations.full, true)
    f.rations = 0
    f.poll()
    equal(f.source.activities.rations.count, 0)
    equal(f.source.activities.rations.full, false)
    equal(next(f.reports), nil)
end)

test("inconsistent ration breakdown reports actual values rather than clamping a fake success", function()
    local f = activities_fixture()
    f.rations, f.extra_rations = 11, 4
    f.poll()
    equal(f.source.activities.rations, nil)
    assert(f.reports.raciones:find("total=15, extra=4, normales=11, limite=10", 1, true))
    equal(f.source.activities.ship.in_port, true)
    local g = activities_fixture()
    g.extra_rations = -1
    g.poll()
    equal(g.source.activities.rations, nil)
    assert(g.reports.raciones:find("Raciones extra", 1, true))
end)

test("release help explains icon order and uncertainty without changing the overlay or saving", function()
    local callbacks, _, messages, saves, texts, _, rects = bootstrap()
    callbacks.ui()
    local labels = table.concat(messages, "\n")
    for _, label in ipairs({
        "Roturas / heridas: roturas completas, NORMAL, TEAR, RAW.",
        "NORMAL, TEAR y RAW son estados del SDK, no dano ni golpes restantes.",
        "Estadisticas: espada, escudo, diana, atributo del arma, cinco resistencias.",
        "Resistencias: fuego, agua, rayo, hielo, dragon.",
        "-- = no disponible. Linea ambar en stats = lectura parcial.",
    }) do
        assert(labels:find(label, 1, true), label)
    end
    equal(#texts, 0)
    equal(#rects, 0)
    callbacks.save()
    equal(#saves, 0)
end)

test("collector slot icons represent occupied spaces, not material units, with exact capacity and colors", function()
    local settings = spanish_defaults()
    for _, scenario in ipairs({
        { occupied = 2, count = 11, capacity = 16, full = false },
        { occupied = 16, count = 80, capacity = 16, full = true },
        { occupied = 0, count = 0, capacity = 16, full = false },
        { occupied = 1, count = 99, capacity = 5, full = false },
    }) do
        local draw_api, imgui_api, _, texts, stack = render_fixture()
        local slots = {}
        local original = Icons.draw
        Icons.draw = function(api, name, x, y, size, color, unavailable)
            if name == "slot" then
                slots[#slots + 1] = { color = color, unavailable = unavailable }
            end
            return original(api, name, x, y, size, color, unavailable)
        end
        local ok, err = pcall(View.render_activities, draw_api, imgui_api, settings, {
            collection = { collectors = { { name = "Apar", occupied = scenario.occupied,
                capacity = scenario.capacity, count = scenario.count, full = scenario.full, available = true } } },
        })
        Icons.draw = original
        if not ok then error(err, 0) end
        equal(#slots, scenario.capacity)
        local colored = 0
        for index, icon in ipairs(slots) do
            equal(icon.unavailable, index > scenario.occupied)
            if index <= scenario.occupied then
                colored = colored + 1
                equal(icon.color, scenario.full and 0xFF69BE88 or 0xFF55BBFF)
            else
                equal(icon.color, 0xFF686460)
            end
        end
        equal(colored, scenario.occupied)
        assert(table.concat(texts):find(scenario.occupied .. "/" .. scenario.capacity, 1, true))
        assert(not table.concat(texts):find("objetos", 1, true))
        equal(stack(), 0)
    end
end)

test("collector slots wrap at narrow widths and large scales without crossing panel or following rows", function()
    for _, scale in ipairs({ 0.5, 1, 2.5 }) do
        local settings = spanish_defaults()
        settings.scale, settings.activities_width = scale, 300
        local draw_api, imgui_api, rects, texts, stack = render_fixture()
        local icons = {}
        local original = Icons.draw
        Icons.draw = function(api, name, x, y, size, color, unavailable)
            icons[#icons + 1] = { name = name, x = x, y = y, size = size }
            return original(api, name, x, y, size, color, unavailable)
        end
        local ok, err = pcall(View.render_activities, draw_api, imgui_api, settings, {
            collection = { collectors = { { name = string.rep("狩", 50), count = 11,
                occupied = 2, capacity = 16, available = false, full = false } } },
            ship = { opened = false }, rations = { count = 0, capacity = 10, full = false },
        })
        Icons.draw = original
        if not ok then error(err, 0) end
        local background, slots, bottom = rects[1], {}, 0
        for _, icon in ipairs(icons) do
            assert(icon.x >= background.x and icon.x + icon.size <= background.x + background.w)
            assert(icon.y >= background.y and icon.y + icon.size <= background.y + background.h)
            if icon.name == "slot" then
                slots[#slots + 1] = icon
                bottom = math.max(bottom, icon.y + icon.size)
            elseif icon.name == "ship" then
                assert(icon.y > bottom)
            end
        end
        equal(#slots, 16)
        assert(slots[16].y > slots[1].y)
        local labels = table.concat(texts)
        assert(labels:find("Recepcion cerrada", 1, true))
        equal(stack(), 0)
    end
end)

test("zero-capacity and unavailable collectors never fabricate grey slots", function()
    local settings = spanish_defaults()
    local draw_api, imgui_api, _, texts = render_fixture()
    local calls, original = 0, Icons.draw
    Icons.draw = function(api, name, ...)
        if name == "slot" then calls = calls + 1 end
        return original(api, name, ...)
    end
    local ok, err = pcall(function()
        View.render_activities(draw_api, imgui_api, settings, {})
        View.render_activities(draw_api, imgui_api, settings, {
            collection = { collectors = {
                { name = "Apar", occupied = 0, capacity = 0, count = 0, available = true, full = false },
            } },
        })
    end)
    Icons.draw = original
    if not ok then error(err, 0) end
    equal(calls, 0)
    local labels = table.concat(texts)
    assert(labels:find("-- | Ver Diagnostico", 1, true))
    assert(labels:find("Sin espacios", 1, true))
end)

test("collector material totals remain available in REFramework without text-heavy overlay rows", function()
    local f = activities_fixture()
    local callbacks, _, messages = bootstrap({ activities_fixture = f })
    callbacks.frame()
    callbacks.ui()
    local labels = table.concat(messages, "\n")
    assert(labels:find("Rysher: 25 objetos | 2/3 espacios", 1, true))
    assert(labels:find("Apar: 18 objetos | 3/3 espacios | LLENO", 1, true))
    assert(labels:find("Actividades: espacios ocupados y raciones pendientes; no inventario.", 1, true))
end)

test("rations render exact real capacity as food icons with available color and pending grey", function()
    for _, scenario in ipairs({
        { count = 7, capacity = 10 }, { count = 0, capacity = 10 },
        { count = 10, capacity = 10 }, { count = 2, capacity = 16 },
    }) do
        local settings = spanish_defaults()
        settings.activities_collection, settings.activities_ship = false, false
        local draw_api, imgui_api, rects, texts, stack = render_fixture()
        local calls, original = {}, Icons.draw
        Icons.draw = function(api, name, x, y, size, color, unavailable)
            calls[#calls + 1] = { name = name, size = size, color = color, unavailable = unavailable }
            return original(api, name, x, y, size, color, unavailable)
        end
        local ok, err = pcall(View.render_activities, draw_api, imgui_api, settings, {
            rations = { count = scenario.count, capacity = scenario.capacity,
                full = scenario.count == scenario.capacity },
        })
        Icons.draw = original
        if not ok then error(err, 0) end
        equal(#calls, scenario.capacity + 1)
        for index = 2, #calls do
            local icon = calls[index]
            equal(icon.name, "rations")
            equal(icon.size, 14)
            equal(icon.unavailable, index - 1 > scenario.count)
            equal(icon.color, index - 1 > scenario.count and 0xFF686460
                or (scenario.count == scenario.capacity and 0xFF69BE88 or 0xFF55BBFF))
        end
        for _, rect in ipairs(rects) do
            assert(not (rect.h == 3 and rect.w == settings.activities_width - 32),
                "rations must not have a progress bar")
        end
        local labels = table.concat(texts)
        assert(labels:find(scenario.count .. "/" .. scenario.capacity, 1, true))
        assert(not labels:find("para recoger", 1, true))
        equal(stack(), 0)
    end
end)

test("entrypoint always hides activities on mission start even with DEMO and without waiting for sampling", function()
    local f = activities_fixture()
    f.settings.sample_frames = 60
    local callbacks, _, _, _, texts, options = bootstrap({ activities_fixture = f })
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES - DEMO", 1, true))
    for index = #texts, 1, -1 do texts[index] = nil end
    f.playing = true
    callbacks.frame()
    local labels = table.concat(texts)
    assert(not labels:find("ACTIVIDADES", 1, true))
    assert(not labels:find("Raciones", 1, true))
    assert(not labels:find("Barco de suministros", 1, true))
    for index = #texts, 1, -1 do texts[index] = nil end
    f.playing = false
    callbacks.frame()
    assert(table.concat(texts):find("ACTIVIDADES - DEMO", 1, true))
    for index = #texts, 1, -1 do texts[index] = nil end
    f.loading = true
    callbacks.frame()
    assert(not table.concat(texts):find("ACTIVIDADES", 1, true))
end)

local function buffs_fixture()
    local f = activities_fixture()
    f.effects = {
        DashJuice = { active = true, timer = 156 },
        Immunizer = { active = true, timer = 252 },
        HotDrink = { active = false, timer = 408 },
        CoolerDrink = { active = false, timer = 120 },
    }
    for _, key in ipairs({ "Kairiki", "Kairiki_G", "KijinPowder", "KijinAmmo",
        "Nintai", "Nintai_G", "KoukaPowder", "KoukaAmmo", "PickUpStamina",
        "KijinDrink", "KijinDrink_G", "KoukaDrink", "KoukaDrink_G", "RevivalDrink" }) do
        f.effects[key] = { active = false, timer = 0 }
    end
    f.effect_reads = {}
    local methods = {}
    for key, value in pairs(f.effects) do
        methods["get_Is" .. key .. "_On"] = function()
            if value.error then error("missing active flag for " .. key) end
            return value.active
        end
        methods["get_" .. key .. "_Timer"] = function()
            f.effect_reads[key] = (f.effect_reads[key] or 0) + 1
            if value.timer_error then error("missing timer for " .. key) end
            return value.timer
        end
    end
    methods.get_IsActiveRevivalDrink = methods.get_IsRevivalDrink_On
    local items = object("app.cHunterItemBuff", {}, methods)
    f.buff_status = object("app.cHunterStatus", {}, {
        get_ItemBuff = function() if not f.no_item_buffs then return items end end,
    })
    f.poll_buffs = function()
        for _ = 1, f.settings.sample_frames do f.model:advance() end
        f.source:poll_buffs()
    end
    return f
end

local function stats_fixture()
    local f = buffs_fixture()
    f.values = { attack = 220.5, defence = 450, affinity = -10, element = 27.5, attr = 41,
        FIRE = 20, WATER = -15, ELEC = 5, ICE = 0, DRAGON = -3 }
    f.stat_reads = 0
    local function value(key)
        if f.invalid == key then error("Invalid stat " .. key) end
        return f.values[key]
    end
    local attack = object("app.cHunterAttackPower", {}, {
        get_CurrentAttackPower = function()
            f.stat_reads = f.stat_reads + 1
            return value("attack")
        end,
        get_CurrentAttrPower = function() return value("element") end,
        get_AttibuteType = function() return value("attr") end,
    })
    local defence = object("app.cHunterDefencePower", {}, {
        get_CurrentDefencePower = function() return value("defence") end,
        getCurrentElementResist = function(_, id)
            for index, key in ipairs({ "FIRE", "WATER", "ELEC", "ICE", "DRAGON" }) do
                if id == 100 + index * 3 then return value(key) end
            end
            error("Wrong resistance enum: " .. tostring(id))
        end,
    })
    local critical = object("app.cHunterCritical", {}, {
        get_CurrentCriticalRate = function() return value("affinity") end,
    })
    local previous = f.buff_status
    f.buff_status = object("app.cHunterStatus", {}, {
        get_IsSetUp = function() return not f.unset_status end,
        get_ItemBuff = function()
            return previous:get_type_definition():get_method("get_ItemBuff"):call(previous)
        end,
        get_AttackPower = function() return attack end,
        get_DefencePower = function() return defence end,
        get_CriticalRate = function() return critical end,
    })
    for _, spec in ipairs({
        { "app.WeaponDef.ATTR", { "NONE", "FIRE", "WATER", "ELEC", "ICE", "DRAGON",
            "POISON", "PARALYSE", "SLEEP", "BLAST" }, 39, 1 },
        { "app.HitDef.ATTR", { "FIRE", "WATER", "ELEC", "ICE", "DRAGON" }, 100, 3 },
    }) do
        local fields = {}
        for index, key in ipairs(spec[2]) do fields[key] = spec[3] + index * spec[4] end
        f.types[spec[1]] = {
            get_field = function(_, key)
                if fields[key] ~= nil then return { get_data = function() return fields[key] end } end
            end,
        }
    end
    f.poll_stats = function()
        for _ = 1, f.settings.sample_frames do f.model:advance() end
        f.source:poll_stats()
    end
    return f
end

test("live stats read current local hunter values and reflected elemental resistances without arithmetic", function()
    local f = stats_fixture()
    f.poll_stats()
    local stats = f.source.stats
    equal(stats.attack, 220.5)
    equal(stats.defence, 450)
    equal(stats.affinity, -10)
    equal(stats.element.name, "Fuego")
    equal(stats.element.id, "FIRE")
    equal(stats.element.value, 27.5)
    for _, key in ipairs({ "FIRE", "WATER", "ELEC", "ICE", "DRAGON" }) do
        equal(stats.resists[key], f.values[key])
    end
    equal(next(f.reports), nil)
    equal(stats.partial, nil)
    f.values.attack, f.values.defence, f.values.element, f.values.affinity = 260, 510, 34, 30
    f.source:poll_stats()
    equal(f.stat_reads, 1)
    equal(f.source.stats.attack, 220.5)
    f.poll_stats()
    equal(f.source.stats.attack, 260)
    equal(f.source.stats.defence, 510)
    equal(f.source.stats.element.value, 34)
    equal(f.source.stats.affinity, 30)
    equal(stats.attack, 220.5)
    f.values.attack, f.values.defence = 200, 400
    f.poll_stats()
    equal(f.source.stats.attack, 200)
    equal(f.source.stats.defence, 400)
    f.values.attr, f.values.element = 46, 18
    f.poll_stats()
    equal(f.source.stats.element.name, "Veneno")
    equal(f.source.stats.element.id, "POISON")
    f.values.attr, f.values.element = 40, 0
    f.poll_stats()
    equal(f.source.stats.element.name, "Sin elemento")
    equal(f.source.stats.element.id, "NONE")
    equal(f.source.stats.element.value, 0)
end)

test("stats discard stale snapshots on loading lost hunter changed owner disable and missing status", function()
    for _, state in ipairs({ "loading", "master", "owner", "status", "setup", "enabled", "show_stats" }) do
        local f = stats_fixture()
        f.poll_stats()
        if state == "loading" then f.loading = true
        elseif state == "master" then f.master = nil
        elseif state == "status" then f.buff_status = nil
        elseif state == "setup" then f.unset_status = true
        elseif state == "owner" then
            f.master = f.remote
            local hunter = f.master:get_type_definition():get_method("get_Character"):call(f.master)
            hunter.get_address = function() return 1001 end
            f.values.attack = 199
        else
            f.settings[state] = false
            f.source.sdk.get_managed_singleton = function() error("disabled SDK access") end
        end
        if state == "status" or state == "setup" then f.poll_stats() else f.source:poll_stats() end
        if state == "owner" then
            equal(f.source.stats.attack, 199)
            equal(f.source.stats_owner, "1001")
        else equal(f.source.stats, nil) end
        equal(next(f.reports), nil)
    end
end)

test("stats isolate invalid fields show partial data and recover on explicit retry", function()
    for _, key in ipairs({ "attack", "defence", "affinity", "element", "FIRE" }) do
        local f = stats_fixture()
        f.poll_stats()
        f.invalid = key
        f.poll_stats()
        equal(f.source.stats[key] or f.source.stats.resists[key], nil)
        assert(f.reports["stat_" .. key])
        equal(f.source.stats.partial, true)
        if key ~= "defence" then equal(f.source.stats.defence, 450) end
        f.invalid = nil
        f.poll_stats()
        equal(f.source.stats[key] or f.source.stats.resists[key], nil)
        f.source:retry_features()
        f.poll_stats()
        assert(f.source.stats[key] or f.source.stats.resists[key])
    end
    for _, value in ipairs({ 0 / 0, math.huge, -1, "123", false }) do
        local f = stats_fixture()
        f.values.attack = value
        f.poll_stats()
        equal(f.source.stats.attack, nil)
        assert(f.reports.stat_attack)
    end
    local f = stats_fixture()
    f.values.attr = 9999
    f.poll_stats()
    equal(f.source.stats.element, nil)
    assert(f.reports.stat_element:find("desconocido"))
end)

test("stats config and older resolution profiles migrate only the new independent geometry", function()
    local settings = assert(Config.validate({ buffs_x = 732, dps_size = 75 }))
    equal(settings.show_stats, true)
    equal(settings.stats_size, 100)
    equal(settings.buffs_x, 732)
    equal(settings.stats_width, 630)
    equal(Config.validate({ stats_width = 300 }).stats_width, 300)
    equal(Config.validate({ stats_width = 1600 }).stats_width, 1600)
    for _, invalid in ipairs({ { show_stats = 1 }, { stats_width = 259 }, { stats_width = 1601 },
        { stats_size = 49 }, { stats_size = 151 }, { stats_x = -1 }, { stats_y = 0.5 } }) do
        equal(Config.validate(invalid), nil)
    end
    local old = Layouts.capture(settings)
    for _, key in ipairs({ "stats_x", "stats_y", "stats_width", "stats_size" }) do old[key] = nil end
    local profiles = assert(Layouts.validate({ profiles = { ["1920x1080"] = old } }))
    local restored = spanish_defaults()
    Layouts.apply(restored, profiles["1920x1080"])
    equal(restored.stats_x, settings.stats_x)
    equal(restored.stats_size, 100)
    equal(restored.buffs_x, 732)
    equal(restored.dps_size, 75)
    equal(old.stats_x, nil)
end)

test("stats panel displays exact current values and missing fields without fabricated zeroes", function()
    local f = stats_fixture()
    f.poll_stats()
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    View.render_stats(draw_api, imgui_api, f.settings, f.source.stats)
    local labels = table.concat(texts, "\n")
    for _, label in ipairs({ "220.5", "450", "-10%", "27.5", "-15", "0" }) do
        assert(labels:find(label, 1, true), label .. ": " .. labels)
    end
    equal(#texts, 18)
    assert(not labels:find("ESTADISTICAS") and not labels:find("Ataque") and not labels:find("Res."))
    equal(rects[1].w, 630)
    equal(rects[1].h, 56)
    equal(stack(), 0)
    assert(#rects > 0)
    local missing_draw, missing_imgui, missing_rects, missing = render_fixture()
    View.render_stats(missing_draw, missing_imgui, f.settings, { partial = true })
    assert(table.concat(missing):find("--", 1, true))
    equal(#missing, 18)
    equal(missing_rects[2].color, 0xFF55BBFF)
    for _, mode in ipairs({ "nil", "disabled", "hidden" }) do
        local d, i, r = render_fixture()
        local s = spanish_defaults()
        if mode == "disabled" then s.enabled = false elseif mode == "hidden" then s.show_stats = false end
        View.render_stats(d, i, s, mode ~= "nil" and Wilds.demo_stats() or nil)
        equal(#r, 0)
    end
end)

test("stats renderer clamps its panel scales independently and cleans font state after drawing errors", function()
    for _, legacy in ipairs({ false, true }) do
        for _, scale in ipairs({ 0.5, 1, 2.5 }) do
            local d, i, rects, _, stack = render_fixture()
            local settings = spanish_defaults()
            settings.scale, settings.stats_x, settings.stats_y = scale, 16384, 16384
            if legacy then i.push_font_size, i.pop_font_size = nil, nil end
            View.render_stats(d, i, settings, Wilds.demo_stats(), true)
            for _, r in ipairs(rects) do
                assert(r.x >= 0 and r.y >= 0 and r.x + r.w <= 1920 and r.y + r.h <= 1080)
            end
            assert(#rects > 0)
            equal(stack(), 0)
        end
    end
    local d, i, _, _, stack = render_fixture()
    d.text = function() error("stats drawing failed") end
    raises(function() View.render_stats(d, i, spanish_defaults(), Wilds.demo_stats()) end, "stats drawing failed")
    equal(stack(), 0)
end)

test("stat icons have distinct transparent silhouettes bounded spans and preserve alpha", function()
    local signatures = {}
    for _, name in ipairs({ "stat_attack", "stat_defence", "stat_affinity", "stat_fire",
        "stat_water", "stat_thunder", "stat_ice", "stat_dragon", "stat_poison",
        "stat_sleep", "stat_blast", "stat_none", "stat_unknown" }) do
        local d, _, rects = render_fixture()
        Icons.draw(d, name, 5, 9, 32, 0x6655AADD)
        assert(#rects > 10 and #rects <= 160, name .. ": " .. #rects)
        local signature = {}
        for _, r in ipairs(rects) do
            assert(r.x >= 5 and r.y >= 9 and r.x + r.w <= 37 and r.y + r.h <= 41, name)
            assert(r.w > 0 and r.h > 0)
            equal(r.color >> 24, 0x66)
            assert(not (r.x == 5 and r.y == 9), name)
            signature[#signature + 1] = table.concat({ r.x, r.y, r.w, r.h, r.color }, ":")
        end
        local identity = table.concat(signature, ";")
        equal(signatures[identity], nil)
        signatures[identity] = name
    end
end)

test("stat strip keeps nine numbers in one row using localized-independent weapon and resistance icons", function()
    local original, calls = Icons.draw, {}
    Icons.draw = function(_, name, x, y, size, color)
        calls[#calls + 1] = { name = name, x = x, y = y, size = size, color = color }
    end
    local d, i, rects, texts = render_fixture()
    local positions = {}
    d.text = function(value, x, y)
        texts[#texts + 1] = value
        positions[#positions + 1] = { x = x, y = y }
    end
    local s, stats = spanish_defaults(), Wilds.demo_stats()
    stats.element.name = "Un nombre localizado que no identifica al elemento"
    View.render_stats(d, i, s, stats)
    equal(#calls, 9)
    for index, name in ipairs({ "stat_attack", "stat_defence", "stat_affinity", "stat_fire",
        "stat_fire", "stat_water", "stat_thunder", "stat_ice", "stat_dragon" }) do
        equal(calls[index].name, name)
        equal(calls[index].y, s.stats_y + 5)
        if index > 1 then equal(calls[index].x - calls[index - 1].x, 70) end
        equal(positions[index * 2].y, s.stats_y + 33)
        assert(positions[index * 2].x >= s.stats_x + (index - 1) * 70)
        assert(positions[index * 2].x < s.stats_x + index * 70)
    end
    for id, name in pairs({ NONE = "stat_none", FIRE = "stat_fire", WATER = "stat_water",
        ELEC = "stat_thunder", ICE = "stat_ice", DRAGON = "stat_dragon", POISON = "stat_poison",
        PARALYSE = "paralysis", SLEEP = "stat_sleep", BLAST = "stat_blast" }) do
        calls = {}
        stats.element.id = id
        View.render_stats(d, i, s, stats)
        equal(calls[4].name, name)
    end
    calls = {}
    stats.element = nil
    View.render_stats(d, i, s, stats)
    equal(calls[4].name, "stat_unknown")
    equal(rects[1].h, 56)
    Icons.draw = original
end)

test("horizontal stats preserve legacy widths and fit narrow viewports without wrapping or truncating numbers", function()
    for _, viewport in ipairs({ { x = 320, y = 200 }, { x = 800, y = 140 }, { x = 1920, y = 1080 } }) do
        for _, preview in ipairs({ false, true }) do
            local d, i, rects, texts, stack = render_fixture()
            local s = spanish_defaults()
            s.stats_width, s.stats_x, s.stats_y = 300, 16384, 16384
            s.scale, s.stats_size = 2.5, 150
            i.get_display_size = function() return viewport end
            View.render_stats(d, i, s, Wilds.demo_stats(), preview)
            assert(#rects > 0)
            equal(#texts, preview and 20 or 18)
            for _, r in ipairs(rects) do
                assert(r.x >= -0.001 and r.y >= -0.001 and r.x + r.w <= viewport.x + 0.001
                    and r.y + r.h <= viewport.y + 0.001)
            end
            assert(rects[1].w / rects[1].h > (preview and 7 or 9))
            equal(s.stats_width, 300)
            equal(stack(), 0)
        end
    end
    local d, i, _, texts, stack = render_fixture()
    local stats = Wilds.demo_stats()
    stats.attack, stats.defence = 1234567.8, 7654321
    View.render_stats(d, i, spanish_defaults(), stats)
    assert(table.concat(texts):find("1234567.8", 1, true))
    assert(table.concat(texts):find("7654321", 1, true))
    equal(stack(), 0)
    d.text = function() error("numeric draw failed") end
    raises(function() View.render_stats(d, i, spanish_defaults(), stats) end, "numeric draw failed")
    equal(stack(), 0)
end)

test("entrypoint updates live stats hides them during obstructions and persists only panel preferences", function()
    local f = stats_fixture()
    local callbacks, _, messages, saves, texts, options = bootstrap({ activities_fixture = f, stats = true })
    callbacks.frame()
    assert(table.concat(texts):find("220.5", 1, true))
    equal(#messages, 0)
    f.values.attack = 280
    for index = #texts, 1, -1 do texts[index] = nil end
    for _ = 1, f.settings.sample_frames do callbacks.frame() end
    assert(table.concat(texts):find("280", 1, true))
    for index = #texts, 1, -1 do texts[index] = nil end
    f.loading = true
    callbacks.frame()
    equal(#texts, 0)
    f.loading = false
    f.values.attack = 215
    callbacks.frame()
    assert(table.concat(texts):find("215", 1, true))
    options.slider_label, options.slider_value = "Stats - Posicion X", 960
    callbacks.ui()
    options.slider_label = nil
    options.click = "Mostrar estadisticas en tiempo real"
    callbacks.ui()
    callbacks.save()
    equal(saves[#saves].config.stats_x, 960)
    equal(saves[#saves].config.show_stats, false)
    equal(saves[#saves].config.stats, nil)
    equal(saves[#saves].config.attack, nil)
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts):find("ESTADISTICAS", 1, true))
end)

test("stats warnings retry from UI and demo never replaces live readings", function()
    local f = stats_fixture()
    f.invalid = "attack"
    local callbacks, _, messages, _, texts, options = bootstrap({ activities_fixture = f, stats = true })
    callbacks.frame()
    assert(table.concat(messages):find("stat_attack", 1, true))
    assert(table.concat(texts):find("--", 1, true))
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    local labels = table.concat(texts)
    assert(labels:find("ESTADISTICAS - DEMO", 1, true))
    assert(labels:find("245", 1, true))
    f.invalid = nil
    options.click = "Limpiar avisos y reintentar dibujo"
    callbacks.ui()
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(table.concat(texts):find("220.5", 1, true))
    assert(not table.concat(texts):find("ESTADISTICAS - DEMO", 1, true))
end)

test("buff reader uses local HunterStatus.ItemBuff and explicit active flags with game timers only", function()
    local f = buffs_fixture()
    f.poll_buffs()
    local rows = f.source.buffs
    equal(#rows, 2)
    equal(rows[1].id, "DashJuice")
    equal(rows[1].remaining, 156)
    equal(rows[1].name, "Zumo de poder")
    equal(rows[2].id, "Immunizer")
    equal(rows[2].remaining, 252)
    equal(rows[1].maximum, nil)
    equal(rows[1].ratio, nil)
    equal(f.effect_reads.HotDrink, nil)
    equal(f.effect_reads.CoolerDrink, nil)
    equal(next(f.reports), nil)
    for _, row in ipairs(rows) do
        for _, value in pairs(row) do
            assert(type(value) == "string" or type(value) == "number")
        end
    end
end)

test("buff activation, refresh, expiry and reapplication use current snapshots and sampling throttle", function()
    local f = buffs_fixture()
    f.poll_buffs()
    local old = f.source.buffs
    f.effects.DashJuice.timer = 50
    f.source:poll_buffs()
    equal(f.source.buffs[1].remaining, 156)
    f.poll_buffs()
    equal(f.source.buffs[1].remaining, 50)
    equal(old[1].remaining, 156)
    f.effects.DashJuice.timer = 180
    f.effects.HotDrink.active = true
    f.poll_buffs()
    equal(f.source.buffs[1].remaining, 180)
    equal(#f.source.buffs, 3)
    f.effects.DashJuice.active, f.effects.Immunizer.active, f.effects.HotDrink.active = false, false, false
    f.poll_buffs()
    equal(#f.source.buffs, 0)
    equal(next(f.reports), nil)
end)

test("buffs clear immediately on loading, missing character, owner changes and disable without SDK reads", function()
    for _, absent in ipairs({ "loading", "master" }) do
        local f = buffs_fixture()
        f.poll_buffs()
        if absent == "master" then f.master = nil else f.loading = true end
        f.source:poll_buffs()
        equal(f.source.buffs, nil)
        equal(f.source.buffs_owner, nil)
        equal(next(f.reports), nil)
    end
    local f = buffs_fixture()
    f.poll_buffs()
    f.master = f.remote
    f.effects.DashJuice.timer = 77
    local character = f.master:get_type_definition():get_method("get_Character"):call(f.master)
    character.get_address = function() return 1001 end
    f.source:poll_buffs()
    equal(f.source.buffs[1].remaining, 77)
    for _, key in ipairs({ "show_buffs", "enabled" }) do
        local g = buffs_fixture()
        g.poll_buffs()
        g.settings[key] = false
        g.source.sdk.get_managed_singleton = function() error("disabled SDK read") end
        g.source:poll_buffs()
        equal(g.source.buffs, nil)
        equal(next(g.reports), nil)
    end
end)

test("individual buff errors remove stale effects, preserve other effects and recover only on retry", function()
    local f = buffs_fixture()
    f.poll_buffs()
    f.effects.DashJuice.error = true
    f.poll_buffs()
    equal(#f.source.buffs, 1)
    equal(f.source.buffs[1].id, "Immunizer")
    assert(f.reports.buff_DashJuice:find("missing active flag", 1, true))
    equal(f.reports.buffs, nil)
    f.effects.DashJuice.error = false
    f.poll_buffs()
    equal(#f.source.buffs, 1)
    f.source:retry_features()
    f.source:poll_buffs()
    equal(#f.source.buffs, 2)
    f.no_item_buffs = true
    f.poll_buffs()
    equal(f.source.buffs, nil)
    assert(f.reports.buffs:find("ItemBuff", 1, true))
end)

test("buff reader rejects nonboolean flags and invalid timers instead of showing invented durations", function()
    for _, change in ipairs({
        function(v) v.active = 1 end,
        function(v) v.timer = -1 end,
        function(v) v.timer = 0 / 0 end,
        function(v) v.timer = math.huge end,
        function(v) v.timer = "150" end,
        function(v) v.timer_error = true end,
    }) do
        local f = buffs_fixture()
        change(f.effects.DashJuice)
        f.poll_buffs()
        equal(#f.source.buffs, 1)
        equal(f.source.buffs[1].id, "Immunizer")
        assert(f.reports.buff_DashJuice)
        equal(f.reports.buffs, nil)
    end
    local f = buffs_fixture()
    f.effects.DashJuice.timer = 0
    f.poll_buffs()
    equal(f.source.buffs[1].remaining, 0)
    equal(next(f.reports), nil)
end)

test("buff config migrates without affecting existing positions and validates independent panel controls", function()
    local settings = assert(Config.validate({ x = 888, activities_width = 400, auto_focus = false }))
    equal(settings.x, 888)
    equal(settings.activities_width, 400)
    equal(settings.auto_focus, false)
    equal(settings.show_buffs, true)
    equal(settings.buffs_width, 300)
    equal(settings.buffs_size, 100)
    equal(settings.mission_size, 100)
    equal(settings.buffs_names, false)
    for _, invalid in ipairs({
        { show_buffs = 1 }, { buffs_width = 119 }, { buffs_width = 1201 },
        { buffs_x = math.huge }, { buffs_y = 1.5 }, { buffs_size = 49 },
        { buffs_size = 151 }, { buffs_size = 75.5 }, { buffs_names = 1 },
        { mission_x = math.huge }, { mission_y = 1.5 }, { mission_width = 299 },
        { mission_size = 49 }, { mission_size = 151 },
    }) do equal(Config.validate(invalid), nil) end
end)

test("buff panel draws icons, remaining times and names only for supplied active effects", function()
    local f = buffs_fixture()
    f.poll_buffs()
    f.settings.buffs_names, f.settings.buffs_width = true, 400
    local draw_api, imgui_api, rects, texts, stack = render_fixture()
    View.render_buffs(draw_api, imgui_api, f.settings, f.source.buffs)
    local labels = table.concat(texts, "\n")
    for _, label in ipairs({ "BUFFS", "Zumo de poder", "Inmunizador", "2:36", "4:12" }) do
        assert(labels:find(label, 1, true), labels)
    end
    assert(not labels:find("caliente") and not labels:find("DEMO"))
    equal(stack(), 0)
    assert(#rects > 20)
    local draw_empty, imgui_empty, empty = render_fixture()
    View.render_buffs(draw_empty, imgui_empty, f.settings, {})
    View.render_buffs(draw_empty, imgui_empty, f.settings, nil)
    f.settings.show_buffs = false
    View.render_buffs(draw_empty, imgui_empty, f.settings, f.source.buffs)
    equal(#empty, 0)
end)

test("buff panel wraps, clamps and reports clipped effects at supported scales and legacy fonts", function()
    local rows = Wilds.demo_buffs()
    for index = 7, 18 do
        rows[index] = { id = "CoolerDrink", name = "Bebida fria", icon = "cool_drink",
            color = 0xFFF2C877, remaining = 90 }
    end
    for _, scale in ipairs({ 0.5, 1, 2.5 }) do
        for _, legacy in ipairs({ false, true }) do
            local settings = spanish_defaults()
            settings.scale, settings.buffs_width = scale, 240
            settings.buffs_x, settings.buffs_y = 16384, 16384
            local draw_api, imgui_api, rects, texts, stack = render_fixture()
            imgui_api.get_display_size = function() return { x = 800, y = 600 } end
            if legacy then imgui_api.push_font_size, imgui_api.pop_font_size = nil, nil end
            View.render_buffs(draw_api, imgui_api, settings, rows)
            assert(#rects > 0)
            for _, rect in ipairs(rects) do
                assert(rect.w > 0 and rect.h > 0 and rect.x >= 0 and rect.y >= 0)
                assert(rect.x + rect.w <= 800.001 and rect.y + rect.h <= 600.001)
            end
            equal(stack(), 0)
            if scale == 2.5 then assert(table.concat(texts):find("sin mostrar")) end
        end
    end
end)

test("all eighteen consumables map explicit getters to distinct effects without guessed timer flags", function()
    local f = buffs_fixture()
    for _, effect in pairs(f.effects) do effect.active, effect.timer = true, 87 end
    f.poll_buffs()
    equal(#f.source.buffs, 18)
    local expected = {
        DashJuice = { "Zumo de poder", "dash_juice" }, Immunizer = { "Inmunizador", "immunizer" },
        HotDrink = { "Bebida caliente", "hot_drink" }, CoolerDrink = { "Bebida fria", "cool_drink" },
        Kairiki = { "Semilla de poder", "might_seed" }, Kairiki_G = { "Pildora de poder", "pill" },
        KijinPowder = { "Polvo de demonio", "demon_powder" }, KijinAmmo = { "Municion demonio", "ammo" },
        Nintai = { "Semilla armadura", "adamant_seed" }, Nintai_G = { "Pildora armadura", "pill" },
        KoukaPowder = { "Polvo de cascara", "hardshell_powder" }, KoukaAmmo = { "Municion armadura", "ammo" },
        KijinDrink = { "Droga demoniaca", "demondrug" }, KijinDrink_G = { "Megadroga demoniaca", "mega_drug" },
        KoukaDrink = { "Piel de armadura", "armorskin" }, KoukaDrink_G = { "Megapiel de armadura", "mega_drug" },
        PickUpStamina = { "Vigor ambiental", "dash_juice" },
        RevivalDrink = { "Recuperacion (SDK)", "immunizer" },
    }
    for _, row in ipairs(f.source.buffs) do
        equal(row.name, expected[row.id][1])
        equal(row.icon, expected[row.id][2])
        equal(row.remaining, row.id ~= "RevivalDrink" and 87 or nil)
        expected[row.id] = nil
    end
    equal(next(expected), nil)
    equal(f.effect_reads.RevivalDrink, nil)
    equal(next(f.reports), nil)
end)

test("seed pill powder ammunition and environmental vigor expire on their own real timers", function()
    for _, key in ipairs({ "Kairiki", "Kairiki_G", "KijinPowder", "KijinAmmo",
        "Nintai", "Nintai_G", "KoukaPowder", "KoukaAmmo", "PickUpStamina" }) do
        local f = buffs_fixture()
        f.effects.DashJuice.active, f.effects.Immunizer.active = false, false
        f.effects[key].active, f.effects[key].timer = false, 30
        f.poll_buffs()
        equal(#f.source.buffs, 1)
        equal(f.source.buffs[1].id, key)
        equal(f.source.buffs[1].remaining, 30)
        for _, expired in ipairs({ 0, -0.01 }) do
            f.effects[key].timer = expired
            f.poll_buffs()
            equal(#f.source.buffs, 0)
        end
        f.effects[key].timer = math.huge
        f.poll_buffs()
        equal(#f.source.buffs, 0)
        assert(f.reports["buff_" .. key])
        f.effects[key].timer = 60
        f.source:retry_features()
        f.poll_buffs()
        equal(f.source.buffs[1].remaining, 60)
    end
end)

test("drugs and armor show active without inventing a clock and ignore inactive stale timers", function()
    for _, key in ipairs({ "KijinDrink", "KijinDrink_G", "KoukaDrink", "KoukaDrink_G", "RevivalDrink" }) do
        local f = buffs_fixture()
        f.effects.DashJuice.active, f.effects.Immunizer.active = false, false
        f.effects[key].active = true
        f.poll_buffs()
        equal(#f.source.buffs, 1)
        equal(f.source.buffs[1].id, key)
        equal(f.source.buffs[1].remaining, nil)
        local draw_api, imgui_api, _, texts = render_fixture()
        View.render_buffs(draw_api, imgui_api, f.settings, f.source.buffs)
        assert(table.concat(texts):find("ACT", 1, true))
        f.effects[key].active, f.effects[key].timer = false, 9999
        f.poll_buffs()
        equal(#f.source.buffs, 0)
        equal(next(f.reports), nil)
    end
end)

test("buff diagnostic state distinguishes no character loading empty success and partial errors", function()
    local f = buffs_fixture()
    f.poll_buffs()
    equal(f.source.buffs_state, "Leyendo consumibles activos")
    for _, effect in pairs(f.effects) do effect.active, effect.timer = false, 0 end
    f.poll_buffs()
    equal(f.source.buffs_state, "Sin consumibles activos")
    f.loading = true
    f.source:poll_buffs()
    equal(f.source.buffs_state, "Carga en curso / sin partida")
    f.loading, f.master = false, nil
    f.source:poll_buffs()
    equal(f.source.buffs_state, "Sin personaje local cargado")
    f.settings.show_buffs = false
    f.source:poll_buffs()
    equal(f.source.buffs_state, "Panel desactivado")
    local g = buffs_fixture()
    g.effects.RevivalDrink.active = 1
    g.poll_buffs()
    equal(g.source.buffs_state, "Lectura incompleta: consulta los avisos")
    equal(#g.source.buffs, 2)
    assert(g.reports.buff_RevivalDrink)
    g.no_item_buffs = true
    g.poll_buffs()
    equal(g.source.buffs, nil)
    equal(g.source.buffs_state, "Lectura incompleta: consulta los avisos")
    g.source:poll_buffs()
    equal(g.source.buffs_state, "Error de lectura: consulta los avisos")
end)

test("legacy buff fonts retain minimum readable cell geometry when smaller sizes are requested", function()
    local settings = spanish_defaults()
    settings.scale, settings.buffs_size, settings.buffs_width = 0.5, 50, 240
    local draw_api, imgui_api, rects = render_fixture()
    imgui_api.push_font_size, imgui_api.pop_font_size = nil, nil
    View.render_buffs(draw_api, imgui_api, settings, Wilds.demo_buffs())
    equal(rects[1].w, 192)
    equal(rects[1].h, 140)
end)

test("compact buffs use measured small cells and size does not affect the DPS or other panel settings", function()
    local settings = spanish_defaults()
    local dps_width, monster_scale = settings.dps_width, settings.scale
    settings.buffs_width = 240
    for _, size in ipairs({ 50, 100, 150 }) do
        settings.buffs_size = size
        local draw_api, imgui_api, rects, texts, stack = render_fixture()
        View.render_buffs(draw_api, imgui_api, settings, Wilds.demo_buffs())
        equal(rects[1].w, 192 * size / 100)
        equal(rects[1].h, 140 * size / 100)
        assert(not table.concat(texts):find("Droga demoniaca", 1, true))
        equal(settings.dps_width, dps_width)
        equal(settings.scale, monster_scale)
        equal(stack(), 0)
    end
    local migrated = assert(Config.validate({ buffs_width = 660, buffs_x = 850, buffs_y = 400, scale = 1.5 }))
    equal(migrated.buffs_width, 660)
    equal(migrated.buffs_x, 850)
    equal(migrated.buffs_size, 100)
    local demo = Wilds.demo_buffs()
    demo[1].name = "mutated"
    assert(Wilds.demo_buffs()[1].name ~= "mutated")
end)

test("buff drawing failures unwind font stack and live reading is independent of DPS and activities", function()
    local f = buffs_fixture()
    f.settings.show_dps, f.settings.auto_focus, f.settings.show_activities = false, false, false
    f.playing = true
    f.poll_buffs()
    equal(#f.source.buffs, 2)
    local draw_api, imgui_api, _, _, stack = render_fixture()
    draw_api.text = function() error("buff drawing failed") end
    raises(function()
        View.render_buffs(draw_api, imgui_api, f.settings, f.source.buffs)
    end, "buff drawing failed")
    equal(stack(), 0)
    equal(next(f.reports), nil)
end)

test("buff panel handles a viewport with just enough height without clipping its footer or drawing offscreen", function()
    for _, height in ipairs({ 83, 84, 90, 107, 108, 272 }) do
        local settings = spanish_defaults()
        settings.buffs_width = 240
        local draw_api, imgui_api, rects, _, stack = render_fixture()
        imgui_api.get_display_size = function() return { x = 800, y = height } end
        View.render_buffs(draw_api, imgui_api, settings, Wilds.demo_buffs())
        for _, rect in ipairs(rects) do
            assert(rect.y >= 0 and rect.y + rect.h <= height)
        end
        if height < 108 then equal(#rects, 0) else assert(#rects > 0) end
        equal(stack(), 0)
    end
end)

test("entrypoint wires real buffs, isolated demo data and persisted toggle without saving snapshots", function()
    local f = buffs_fixture()
    local callbacks, _, messages, saves, texts, options = bootstrap({ activities_fixture = f })
    callbacks.frame()
    local labels = table.concat(texts)
    assert(labels:find("BUFFS", 1, true))
    assert(labels:find("2:36", 1, true))
    equal(#messages, 0)
    options.click = "Vista previa DEMO (datos ficticios)"
    callbacks.ui()
    callbacks.frame()
    assert(table.concat(texts):find("BUFFS - DEMO", 1, true))
    equal(f.effects.HotDrink.active, false)
    equal(f.effects.DashJuice.timer, 156)
    options.click = "Mostrar buffs de consumibles"
    callbacks.ui()
    callbacks.save()
    equal(saves[1].config.show_buffs, false)
    equal(saves[1].config.buffs, nil)
    for index = #texts, 1, -1 do texts[index] = nil end
    callbacks.frame()
    assert(not table.concat(texts):find("BUFFS - DEMO", 1, true))
    assert(not table.concat(texts):find("BUFFS", 1, true))
end)

test("compact placement button saves independent panel geometry beside the current DPS", function()
    local f = buffs_fixture()
    local callbacks, _, messages, saves, _, options = bootstrap({ activities_fixture = f })
    options.click = "Colocar buffs compactos junto al DPS"
    callbacks.ui()
    callbacks.save()
    local settings = saves[#saves].config
    equal(settings.buffs_x, settings.dps_x + settings.dps_width * settings.scale + 12)
    equal(settings.buffs_y, settings.dps_y)
    equal(settings.buffs_width, 240)
    equal(settings.buffs_size, 100)
    equal(settings.buffs_names, false)
    equal(settings.scale, 1)
    equal(settings.dps_width, 440)
    assert(table.concat(messages):find("Estado de buffs:", 1, true))
end)

test("new effect warnings can be cleared from REFramework and recover without contaminating DEMO", function()
    local f = buffs_fixture()
    f.effects.Kairiki_G.timer = math.huge
    local callbacks, _, messages, _, texts, options = bootstrap({ activities_fixture = f })
    callbacks.frame()
    assert(table.concat(messages):find("buff_Kairiki_G", 1, true))
    callbacks.ui()
    assert(table.concat(messages):find("Lectura incompleta", 1, true))
    f.effects.Kairiki_G.timer = 20
    options.click = "Limpiar avisos y reintentar dibujo"
    callbacks.ui()
    options.click = nil
    for index = #messages, 1, -1 do messages[index] = nil end
    callbacks.frame()
    callbacks.ui()
    assert(not table.concat(messages):find("buff_Kairiki_G", 1, true))
    assert(table.concat(messages):find("Pildora de poder: 0:20", 1, true))
    assert(table.concat(messages):find("Leyendo consumibles activos", 1, true))
    assert(table.concat(texts):find("0:20", 1, true))
end)

test("global scale resizes and repositions every panel together including hidden panels and saves", function()
    local f = buffs_fixture()
    local callbacks, _, _, saves, _, options = bootstrap({ activities_fixture = f })
    callbacks.ui()
    callbacks.save()
    equal(#saves, 0)
    local defaults = spanish_defaults()
    options.slider_label = "Escala global - todas las ventanas"
    for _, scale in ipairs({ 0.5, 2, 2.5, 1 }) do
        options.slider_value = scale
        callbacks.ui()
        callbacks.save()
        local actual = saves[#saves].config
        equal(actual.scale, scale)
        for _, key in ipairs({ "x", "y", "focus_x", "focus_y", "dps_x", "dps_y",
            "activities_x", "activities_y", "buffs_x", "buffs_y", "mission_x", "mission_y",
            "stats_x", "stats_y" }) do
            equal(actual[key], math.floor(defaults[key] * scale + 0.5))
        end
        for _, key in ipairs({ "width", "dps_width", "focus_width", "activities_width",
            "buffs_width", "buffs_size", "mission_width", "mission_size",
            "sample_frames", "opacity" }) do
            equal(actual[key], defaults[key])
        end
        assert(Config.validate(actual))
    end
end)

test("continuous global slider changes retain position precision instead of accumulating rounding drift", function()
    local f = buffs_fixture()
    local callbacks, _, _, saves, _, options = bootstrap({ activities_fixture = f })
    local defaults = spanish_defaults()
    options.slider_label = "Escala global - todas las ventanas"
    for step = 101, 200 do
        options.slider_value = step / 100
        callbacks.ui()
    end
    callbacks.save()
    for _, key in ipairs({ "x", "y", "focus_x", "focus_y", "dps_x", "dps_y",
        "activities_x", "activities_y", "buffs_x", "buffs_y", "mission_x", "mission_y",
        "stats_x", "stats_y" }) do
        equal(saves[#saves].config[key], defaults[key] * 2)
    end
    for step = 199, 50, -1 do
        options.slider_value = step / 100
        callbacks.ui()
    end
    callbacks.save()
    equal(saves[#saves].config.x, defaults.x / 2)
    equal(saves[#saves].config.buffs_x, defaults.buffs_x / 2)
end)

test("global scaling respects positions changed through compact placement and keeps DPS separation", function()
    local f = buffs_fixture()
    local callbacks, _, _, saves, _, options = bootstrap({ activities_fixture = f })
    options.slider_label, options.slider_value = "Escala global - todas las ventanas", 1.5
    callbacks.ui()
    options.slider_label = nil
    options.click = "Colocar buffs compactos junto al DPS"
    callbacks.ui()
    callbacks.save()
    local placed = saves[#saves].config
    options.click = nil
    options.slider_label, options.slider_value = "Escala global - todas las ventanas", 0.5
    callbacks.ui()
    callbacks.save()
    local resized = saves[#saves].config
    equal(resized.buffs_x, math.floor(placed.buffs_x / 3 + 0.5))
    equal(resized.buffs_y, math.floor(placed.buffs_y / 3 + 0.5))
    equal(resized.buffs_x - (resized.dps_x + resized.dps_width * resized.scale), 4)
end)

test("panel scale settings migrate validate and preserve existing buff customization", function()
    local migrated = assert(Config.validate({ scale = 1.25, buffs_size = 70, dps_x = 500 }))
    for _, key in ipairs({ "monsters_size", "focus_size", "dps_size", "activities_size" }) do
        equal(migrated[key], 100)
        for _, invalid in ipairs({ 49, 151, 75.5, math.huge, "100", false }) do
            equal(Config.validate({ [key] = invalid }), nil)
        end
        equal(Config.validate({ [key] = 50 })[key], 50)
        equal(Config.validate({ [key] = 150 })[key], 150)
    end
    equal(migrated.buffs_size, 70)
    equal(migrated.scale, 1.25)
    equal(migrated.dps_x, 500)
end)

test("monster controls are nested and every section exposes and persists an independent scale slider", function()
    local f = buffs_fixture()
    local options = { activities_fixture = f, controls = {} }
    local callbacks, _, _, saves = bootstrap(options)
    callbacks.ui()
    for _, control in ipairs({ "Mostrar contadores de heridas", "Posicion X", "Ancho",
        "Maximo de monstruos", "Mostrar solo monstruo marcado en el mapa" }) do
        assert(options.controls[control]:match("/Monstruos$"), control)
    end
    for _, spec in ipairs({
        { "Monstruos - Escala (%)", "monsters_size", "Monstruos" },
        { "Combate - Escala (%)", "focus_size", "Barra de monstruo en combate" },
        { "DPS - Escala (%)", "dps_size", "Medidor de dano / DPS" },
        { "Actividades - Escala (%)", "activities_size", "Actividades del poblado" },
        { "Buffs - Escala (%)", "buffs_size", "Buffs del cazador" },
        { "Mision - Escala (%)", "mission_size", "Vista previa de mision" },
        { "Stats - Escala (%)", "stats_size", "Estadisticas del cazador" },
    }) do
        equal(options.controls[spec[1]], "MHOverlay 1.0 - Wilds/" .. spec[3])
        options.slider_label, options.slider_value = spec[1], 75
        callbacks.ui()
        callbacks.save()
        equal(saves[#saves].config[spec[2]], 75)
        equal(saves[#saves].config.scale, 1)
        equal(saves[#saves].config.dps_x, spanish_defaults().dps_x)
    end
    options.slider_label, options.slider_value = "Escala global - todas las ventanas", 1.5
    callbacks.ui()
    callbacks.save()
    for _, key in ipairs({ "monsters_size", "focus_size", "dps_size", "activities_size",
        "buffs_size", "mission_size", "stats_size" }) do
        equal(saves[#saves].config[key], 75)
    end
    options.closed_tree, options.controls = "Monstruos", {}
    options.slider_label = nil
    callbacks.ui()
    equal(options.controls["Ancho"], nil)
    assert(options.controls["DPS - Escala (%)"])
    assert(options.controls["Combate - Escala (%)"])
    assert(options.controls["Mision - Escala (%)"])
end)

test("each renderer uses global times its own scale without changing other windows or their anchors", function()
    local row = { name = "Rey Dau", health = 50, max_health = 100, ratio = 0.5 }
    local damage = Damage.new()
    damage:update("demo", 0)
    damage:update("demo", 120)
    damage:add({ id = "self", name = "Hunter", is_self = true }, 100)
    local specs = {
        { "monsters_size", 18, function(d, i, s) View.render(d, i, s, { row }) end },
        { "focus_size", 18, function(d, i, s) View.render_focus(d, i, s, row, true) end },
        { "dps_size", 16, function(d, i, s) View.render_damage(d, i, s, damage) end },
        { "activities_size", 14, function(d, i, s)
            View.render_activities(d, i, s, { rations = { count = 2, capacity = 5, full = false } })
        end },
        { "buffs_size", 14, function(d, i, s) View.render_buffs(d, i, s, Wilds.demo_buffs()) end },
        { "stats_size", 14, function(d, i, s) View.render_stats(d, i, s, Wilds.demo_stats()) end },
    }
    local function render(spec, settings)
        local d, i, rects, _, stack = render_fixture()
        i.get_display_size = function() return { x = 8000, y = 8000 } end
        local fonts = {}
        i.push_font_size = function(size) fonts[#fonts + 1] = size end
        i.pop_font_size = function() end
        spec[3](d, i, settings)
        assert(#rects > 0)
        equal(stack(), 0)
        return rects[1], fonts[1]
    end
    for _, target in ipairs(specs) do
        for _, percent in ipairs({ 50, 75, 150 }) do
            local settings = spanish_defaults()
            settings.scale = 1.2
            local base, base_font = render(target, settings)
            settings[target[1]] = percent
            local resized, font = render(target, settings)
            assert(math.abs(resized.w - base.w * percent / 100) < 0.001)
            assert(math.abs(resized.h - base.h * percent / 100) < 0.001)
            local prefix = ({ monsters_size = "", focus_size = "focus_", dps_size = "dps_",
                activities_size = "activities_", buffs_size = "buffs_", stats_size = "stats_" })[target[1]]
            local x, y = settings[prefix .. "x"], settings[prefix .. "y"]
            assert(math.abs(resized.x - (x + (base.x - x) * percent / 100)) < 0.001)
            assert(math.abs(resized.y - (y + (base.y - y) * percent / 100)) < 0.001)
            assert(math.abs(font - base_font * percent / 100) < 0.001)
            for _, other in ipairs(specs) do
                if other ~= target then
                    local rect, other_font = render(other, settings)
                    local defaults = spanish_defaults()
                    defaults.scale = 1.2
                    local original, original_font = render(other, defaults)
                    equal(rect.w, original.w)
                    equal(rect.h, original.h)
                    equal(other_font, original_font)
                end
            end
        end
    end
end)

test("compact buff placement respects independent DPS scale", function()
    local f = buffs_fixture()
    local callbacks, _, _, saves, _, options = bootstrap({ activities_fixture = f })
    options.slider_label, options.slider_value = "DPS - Escala (%)", 75
    callbacks.ui()
    options.slider_label = nil
    options.click = "Colocar buffs compactos junto al DPS"
    callbacks.ui()
    callbacks.save()
    local actual = saves[#saves].config
    equal(actual.buffs_x, actual.dps_x + actual.dps_width * actual.scale * 0.75 + 12)
    equal(actual.dps_size, 75)
    equal(actual.buffs_size, 100)
end)

test("language defaults to English validates strictly and preserves older settings and layout geometry", function()
    equal(Config.defaults().language, "en")
    local old = assert(Config.validate({ x = 777, stats_width = 300, buffs_names = true }))
    equal(old.language, "en")
    equal(old.x, 777)
    equal(old.stats_width, 300)
    equal(old.buffs_names, true)
    equal(Config.validate({ language = "es" }).language, "es")
    for _, value in ipairs({ "EN", "fr", "", 0, true, {} }) do
        equal(Config.validate({ language = value }), nil)
        equal(Config.valid_value("language", value), false)
    end
    local layout = Layouts.capture(old)
    equal(layout.language, nil)
    old.language = "es"
    Layouts.apply(old, layout)
    equal(old.language, "es")
    equal(old.x, 777)
end)

test("release menu has English controls and collapsible diagnostics without experimental labels", function()
    local options = { language = "en", controls = {}, closed_tree = "Advanced diagnostics" }
    local callbacks, _, messages, _, texts = bootstrap(options)
    callbacks.ui()
    for _, label in ipairs({ "Enable overlay", "Show consumable buffs", "Show live hunter stats",
        "Show damage / DPS meter", "Stats - Width", "Show monster portraits" }) do
        assert(options.controls[label], label)
    end
    equal(options.controls["Update every N frames"], nil)
    local labels = table.concat(messages, "\n")
    assert(not labels:find("HP samples:", 1, true))
    assert(not labels:find("Hooks:", 1, true))
    assert(not labels:find("experimental", 1, true))
    assert(labels:find("Attack/element: internal values", 1, true))
    equal(#texts, 0)
    options.closed_tree, options.controls = nil, {}
    callbacks.ui()
    assert(options.controls["Update every N frames"]:find("/Advanced diagnostics", 1, true))
    assert(table.concat(messages):find("Version: 1.0 | reader: 1.0", 1, true))
end)

test("language selector applies immediately persists and never resets user geometry or live values", function()
    local f = stats_fixture()
    local options = { language = "en", stats = true, activities_fixture = f, controls = {} }
    local callbacks, _, messages, saves, texts = bootstrap(options)
    options.slider_label, options.slider_value = "Stats - Position X", 777
    callbacks.ui()
    options.slider_label = nil
    options.language_index = 2
    options.controls = {}
    callbacks.ui()
    assert(options.controls["Mostrar estadisticas en tiempo real"])
    callbacks.save()
    equal(saves[#saves].config.language, "es")
    equal(saves[#saves].config.stats_x, 777)
    local last = saves[#saves].config
    callbacks.frame()
    options.language_index = 1
    options.controls = {}
    callbacks.ui()
    assert(options.controls["Show live hunter stats"])
    callbacks.save()
    equal(saves[#saves].config.language, "en")
    for _, key in ipairs(Layouts.keys) do equal(saves[#saves].config[key], last[key]) end
    for index = #texts, 1, -1 do texts[index] = nil end
    for _ = 1, 6 do callbacks.frame() end
    assert(table.concat(texts):find("220.5", 1, true))
    equal(saves[#saves].config.stats, nil)
    assert(#messages > 0)
end)

test("English buff names states and warnings change without modifying snapshots or translating proper names", function()
    local f = buffs_fixture()
    f.poll_buffs()
    local rows = f.source.buffs
    local settings = Config.defaults()
    settings.buffs_names, settings.buffs_width = true, 600
    local d, i, _, texts = render_fixture()
    View.render_buffs(d, i, settings, rows)
    local labels = table.concat(texts)
    assert(labels:find("Dash Juice", 1, true))
    assert(labels:find("Immunizer", 1, true))
    equal(rows[1].name, "Zumo de poder")
    equal(rows[1].remaining, 156)
    settings.language = "es"
    local d2, i2, _, texts2 = render_fixture()
    View.render_buffs(d2, i2, settings, rows)
    assert(table.concat(texts2):find("Zumo de poder", 1, true))
    local opts = { language = "en", stats = true, activities_fixture = stats_fixture() }
    opts.activities_fixture.invalid = "attack"
    local callbacks, _, messages = bootstrap(opts)
    callbacks.frame()
    callbacks.ui()
    assert(table.concat(messages):find("Stat reader: Partial reading: check warnings", 1, true))
    local player = { name = "Zumo de poder", rank = 51, host = true }
    local dm, im, _, tm = render_fixture()
    View.render_mission_preview(dm, im, Config.defaults(), { players = { player }, targets = { "Furia" } })
    local mission = table.concat(tm)
    assert(mission:find("Zumo de poder", 1, true))
    assert(mission:find("Furia", 1, true))
    assert(not mission:find("Dash Juice", 1, true))
    equal(player.name, "Zumo de poder")
end)

test("English overlays translate mission combat activities damage and demo labels before fitting", function()
    local settings = Config.defaults()
    local function labels(render)
        local d, i, _, texts, stack = render_fixture()
        render(d, i)
        equal(stack(), 0)
        return table.concat(texts, "\n")
    end
    local mission = labels(function(d, i)
        View.render_mission_preview(d, i, settings, {
            member_count = 1, member_max = 4, quest_life = 3, time_limit = 3000,
            players = { { name = "Hunter", rank = 35, host = true } },
            targets = { "Rey Dau" }, roster_status = "incomplete", roster_count = 1,
        })
    end)
    for _, value in ipairs({ "SELECTED QUEST", "1/4 hunters", "TARGET", "HUNTERS",
        "HR 35", "HOST", "Limit: 3 faints", "Time: 50:00", "Incomplete hunter data" }) do
        assert(mission:find(value, 1, true), value .. ": " .. mission)
    end
    local activity = labels(function(d, i)
        View.render_activities(d, i, settings, { collection = { collectors = {} },
            ship = { opened = true, in_port = true, days = 2 },
            rations = { count = 0, capacity = 0 } })
    end)
    for _, value in ipairs({ "VILLAGE ACTIVITIES", "MATERIAL COLLECTION", "No collections",
        "Supply ship", "IN PORT", "Cycle days", "Rations", "No slots" }) do
        assert(activity:find(value, 1, true), value .. ": " .. activity)
    end
    local focus = labels(function(d, i)
        View.render_focus(d, i, settings, { name = "Furia", health = 50, max_health = 100, ratio = 0.5 }, true)
    end)
    for _, value in ipairs({ "DEMO - COMBAT", "Furia", "Rage", "Paralysis", "Stun", "50.00%" }) do
        assert(focus:find(value, 1, true), value)
    end
    local meter = Damage.new()
    meter:update("quest", 0)
    meter:add({ id = "self", name = "Furia", is_self = true }, 1500)
    meter:update("quest", 10)
    local damage = labels(function(d, i) View.render_damage(d, i, settings, meter) end)
    for _, value in ipairs({ "DPS / COMBAT", "[YOU]", "Furia", "Group:", "1.5K" }) do
        assert(damage:find(value, 1, true), value .. ": " .. damage)
    end
    assert(not damage:find("1,5", 1, true))
    local stats = labels(function(d, i) View.render_stats(d, i, settings, Wilds.demo_stats(), true) end)
    assert(stats:find("STATS - DEMO", 1, true))
    local details = table.concat(View.detail_lines({ parts = { broken = 1, total = 3, entries = {} },
        wounds = { states = {} } }, settings), "\n")
    assert(details:find("Completed breaks:", 1, true))
    assert(details:find("No wound entries", 1, true))
end)

test("release menu text and every consumable name have English translations", function()
    local source = assert(io.open("reframework/autorun/mhoverlay.lua", "r"))
    local content = source:read("*a")
    source:close()
    for _, pattern in ipairs({ '%f[%w]ui%.text%("([^"]+)"', '%f[%w]ui%.button%("([^"]+)"',
        '%f[%w]ui%.tree_node%("([^"]+)"', 'checkbox%("([^"]+)"', 'slider%("([^"]+)"' }) do
        for key in content:gmatch(pattern) do
            assert(Locale.known(key), "Missing menu translation: " .. key)
        end
    end
    local f = buffs_fixture()
    for _, effect in pairs(f.effects) do effect.active, effect.timer = true, 90 end
    f.poll_buffs()
    equal(#f.source.buffs, 18)
    for _, row in ipairs(f.source.buffs) do
        assert(Locale.known(row.name), row.name)
        assert(Locale.t(row.name, "en") ~= row.name, row.name)
        equal(Locale.t(row.name, "es"), row.name)
    end
    equal(Locale.t("Rey Dau", "en"), "Rey Dau")
end)

print(string.format("\n%d tests passed.", passed))
