-- REFramework can rerun autorun scripts while require still holds old modules.
for _, name in ipairs({ "config", "model", "wilds", "view", "damage", "layouts", "icons",
    "artwork", "portraits", "locale" }) do
    package.loaded["mhoverlay/" .. name] = nil
end

local Config = require("mhoverlay/config")
local Model = require("mhoverlay/model")
local Wilds = require("mhoverlay/wilds")
local View = require("mhoverlay/view")
local Damage = require("mhoverlay/damage")
local Layouts = require("mhoverlay/layouts")
local Locale = require("mhoverlay/locale")

local version = "1.0"
local model = Model.new()
local damage = Damage.new()
local errors = {}
local settings
local config_valid = true
local preview = false
local preview_focus = false
local render_failed = false
local damage_render_failed = false
local activities_render_failed = false
local buffs_render_failed = false
local stats_render_failed = false
local mission_render_failed = false
local dirty = false
local function tr(key, ...)
    return Locale.t(key, settings and settings.language or "en", ...)
end

local function report(category, message)
    if message == nil then
        errors[category] = nil
        return
    end
    if errors[category] ~= message then
        log.error("[MHOverlay/" .. category .. "] " .. message)
    end
    errors[category] = message
end

local ok, loaded, load_error = pcall(Config.load, fs, json)
if ok and loaded then
    settings = loaded
else
    settings = Config.defaults()
    config_valid = false
    report("configuracion", tostring(ok and load_error or loaded)
        .. ". Se usan ajustes temporales; el archivo original no se sobrescribira.")
end

local layouts_valid = true
local layouts_ok, loaded_layouts, layouts_error = pcall(Layouts.load, fs, json)
if not layouts_ok or not loaded_layouts then
    layouts_valid = false
    loaded_layouts = {}
    report("posiciones", tostring(layouts_ok and layouts_error or loaded_layouts)
        .. ". No se cargan ni se sobrescriben las posiciones por resolucion.")
end
local layouts = Layouts.tracker(loaded_layouts)
local scaled_positions = {}

local function save_layouts()
    if not layouts_valid or not layouts.dirty then return end
    local saved, save_error = pcall(Layouts.save, layouts.profiles, json)
    if saved then
        layouts.dirty = false
        errors.guardado_posiciones = nil
    else
        report("guardado_posiciones", tostring(save_error))
    end
end

local source = Wilds.new(sdk, model, settings, report)
local installed, install_error = pcall(function()
    source:install()
end)
if not installed then
    report("inicio", tostring(install_error))
end
local function install_damage()
    local success, message = pcall(source.install_damage, source, damage)
    if not success then
        if settings.show_dps then report("dps", tostring(message)) end
        if settings.auto_focus then report("foco", tostring(message)) end
    end
end
install_damage()
local function install_mission_board()
    local success, message = pcall(source.install_mission_board, source)
    if not success then report("lista_misiones", tostring(message)) end
end
install_mission_board()

local function save()
    if not config_valid then
        return
    end
    local saved, save_error = pcall(Config.save, settings, json)
    if not saved then
        report("guardado", tostring(save_error))
    else
        dirty = false
        errors.guardado = nil
    end
end

re.on_config_save(function()
    if dirty then
        save()
    end
    save_layouts()
end)

re.on_frame(function()
    model:advance()
    if layouts_valid then
        local resolution = Layouts.resolution(imgui.get_display_size())
        if layouts:update(resolution, settings) then
            scaled_positions = {}
            dirty = true
        end
    end
    source:poll_return()
    source:poll_focus()
    source:poll_damage()
    source:poll_activities()
    source:poll_buffs()
    source:poll_stats()
    source:poll_mission_preview()
    source:poll_obstruction()
    if source.support_unbound == 0 then errors.identidad_apoyos = nil end
    if not settings.enabled then return end
    if source.mission_preview then
        if (not source.obstruction or source.obstruction == "Vista previa de mision")
            and not mission_render_failed then
            local drawn, draw_error = pcall(View.render_mission_preview, draw, imgui,
                settings, source.mission_preview)
            if not drawn then
                mission_render_failed = true
                report("dibujo_lista_misiones", tostring(draw_error))
            end
        end
        return
    end
    if source.obstruction then return end
    local rows = model:rows(settings.max_monsters, settings.show_dead, settings)
    local status
    if preview then
        rows = { { name = tr("DEMO - No son datos del juego"), portrait = "rey_dau", health = 12500,
            max_health = 20000, ratio = 0.625, pinned = true, quest_target = true,
            rage = { active = true, remaining = 42, ratio = 0.7 },
            stamina = { active = false, current = 180, maximum = 300, ratio = 0.6 },
            parts = { broken = 1, total = 3, entries = {
                { index = 0, broken = true }, { index = 2, broken = false },
                { index = 3, broken = false },
            } },
            wounds = { total = 4, states = { NORMAL = 2, RAW = 1, OLD = 1 } } },
            { name = tr("DEMO - Monstruo secundario"), portrait = "rathalos", health = 18000,
                max_health = 24000, ratio = 0.75 } }
        status = tr("MHOverlay: vista previa DEMO")
    elseif next(errors) then
        status = tr("MHOverlay: error; abre Script Generated UI")
    end
    if not render_failed then
        local focused = not preview and settings.auto_focus and source.focus_combat and model:focused()
        if preview and preview_focus then
            focused = rows[1]
            focused.rage.observed_count = 2
            focused.paralysis = { active = false, ratio = 0.35, observed_count = 1 }
            focused.stun = { active = true, remaining = 8, ratio = 0.5, observed_count = 1 }
        end
        local drawn, draw_error
        if focused then
            drawn, draw_error = pcall(View.render_focus, draw, imgui, settings, focused, preview, status)
        else
            drawn, draw_error = pcall(View.render, draw, imgui, settings, rows, status, preview)
        end
        if not drawn then
            render_failed = true
            report("dibujo", tostring(draw_error))
        end
    end
    if not buffs_render_failed then
        local buffs = preview and Wilds.demo_buffs() or source.buffs
        local drawn, draw_error = pcall(View.render_buffs, draw, imgui, settings, buffs, preview)
        if not drawn then
            buffs_render_failed = true
            report("dibujo_buffs", tostring(draw_error))
        end
    end
    if not stats_render_failed then
        local drawn, draw_error = pcall(View.render_stats, draw, imgui, settings,
            preview and Wilds.demo_stats() or source.stats, preview)
        if not drawn then
            stats_render_failed = true
            report("dibujo_estadisticas", tostring(draw_error))
        end
    end
    if not activities_render_failed and source.activities_visible then
        local activities = source.activities
        if preview then
            activities = { collection = { collectors = {
                { name = "DEMO - Apar", count = 11, occupied = 2, capacity = 16,
                    full = false, available = true },
                { name = tr("DEMO - Deposito lleno"), count = 80, occupied = 16, capacity = 16,
                    full = true, available = true },
            } }, ship = { opened = true, in_port = true, days = 2 },
                rations = { count = 7, capacity = 10, full = false } }
        end
        local drawn, draw_error = pcall(View.render_activities, draw, imgui, settings, activities, preview)
        if not drawn then
            activities_render_failed = true
            report("dibujo_actividades", tostring(draw_error))
        end
    end
    if not damage_render_failed and (preview or source.damage_visible) then
        local meter, meter_status = damage, errors.dps and tr("DPS suspendido: abre Diagnostico")
        if preview then
            meter = Damage.new()
            meter:update("demo", 0)
            meter.faints = { count = 1, limit = 3 }
            local roster = {}
            for index, player in ipairs({
                { name = "Tu cazador", amount = 18400 },
                { name = "Cazador 2", amount = 12500 },
                { name = "Cazador 3", amount = 9300 },
                { name = "Olivia", amount = 5800, is_support = true },
            }) do
                local identity = { id = tostring(index), name = tr(player.name),
                    is_self = index == 1, is_support = player.is_support, in_combat = true }
                roster[#roster + 1] = identity
                meter:add(identity, player.amount)
            end
            meter:sync(roster)
            meter:update("demo", 120)
            meter_status = nil
        end
        local drawn, draw_error = pcall(View.render_damage, draw, imgui, settings,
            meter, meter_status, preview, source.damage_mode == "result")
        if not drawn then
            damage_render_failed = true
            report("dibujo_dps", tostring(draw_error))
        end
    end
end)

local function checkbox(label, key)
    local changed, value = imgui.checkbox(tr(label), settings[key])
    if changed then
        settings[key] = value
        dirty = true
        if key == "enabled" then
            model:clear()
        end
        if key == "enabled" or key == "show_dps" then source:reset_damage() end
        if key == "enabled" or key == "auto_focus" then source:reset_focus() end
        if key == "enabled" or key == "show_buffs" then source:reset_buffs() end
        if key == "enabled" or key == "show_stats" then source:reset_stats() end
        if key == "enabled" or key == "show_activities" or key:match("^activities_") then
            source:reset_activities()
        end
        if key == "auto_focus" and value and not source.damage_ready then install_damage() end
        if key == "show_dps" then
            errors.dps = nil
            errors.dibujo_dps = nil
            source.feature_failures.dps = nil
            damage_render_failed = false
            if value and not source.damage_ready then install_damage() end
        end
    end
end

local function slider(label, key, min, max, floating)
    local changed, value
    if floating then
        changed, value = imgui.slider_float(tr(label), settings[key], min, max, "%.2f")
    else
        changed, value = imgui.slider_int(tr(label), settings[key], min, max, "%d")
    end
    if changed then
        if key == "scale" then
            local ratio = value / settings.scale
            for _, position in ipairs({ "x", "y", "focus_x", "focus_y", "dps_x", "dps_y",
                "activities_x", "activities_y", "buffs_x", "buffs_y", "mission_x", "mission_y",
                "stats_x", "stats_y" }) do
                local precise = scaled_positions[position]
                if not precise or math.floor(precise + 0.5) ~= settings[position] then
                    precise = settings[position]
                end
                precise = math.min(16384, precise * ratio)
                scaled_positions[position] = precise
                settings[position] = math.floor(precise + 0.5)
            end
        end
        settings[key] = value
        dirty = true
    end
end

local ui = {}
for _, method in ipairs({ "text", "tree_node", "button" }) do
    ui[method] = function(key, ...) return imgui[method](tr(key, ...)) end
end
ui.tree_pop = function() imgui.tree_pop() end

re.on_draw_ui(function()
    if not imgui.tree_node("MHOverlay " .. version .. " - Wilds") then
        return
    end
    local changed, language = imgui.combo("Language / Idioma", settings.language == "en" and 1 or 2,
        { "English", "Español" })
    if changed then
        settings.language = language == 1 and "en" or "es"
        dirty = true
    end
    checkbox("Activar overlay", "enabled")
    if config_valid then
        if ui.button("Guardar ajustes") then
            save()
            save_layouts()
        end
    else
        ui.text("Configuracion invalida: conserva el archivo original hasta revisarlo.")
        if ui.button("Permitir reemplazar configuracion con los ajustes actuales") then
            config_valid = true
            errors.configuracion = nil
            save()
        end
    end
    slider("Escala global - todas las ventanas", "scale", 0.5, 2.5, true)
    slider("Opacidad del fondo (%)", "opacity", 0, 100)
    if ui.tree_node("Visibilidad") then
        checkbox("Ocultar con mapa y menus a pantalla completa", "hide_on_map")
        checkbox("Ocultar en conversaciones y menus de NPC (forja, tienda...)", "hide_on_dialogue")
        checkbox("Ocultar durante pantallas de carga", "hide_on_loading")
        ui.tree_pop()
    end
    if ui.tree_node("Posiciones por resolucion") then
        local current = Layouts.resolution(imgui.get_display_size())
        ui.text("Resolucion actual: %s", current or tr("desconocida"))
        checkbox("Recordar y cargar automaticamente al cambiar de resolucion", "auto_layout")
        if not layouts_valid then
            ui.text("Archivo de posiciones invalido: no se modifica. Revisa Diagnostico.")
        elseif current then
            if ui.button("Guardar posiciones para %s", current) then
                if layouts:remember(current, settings) then
                    save_layouts()
                else
                    report("posiciones", tr("Maximo de %d resoluciones; borra alguna", Layouts.max_profiles))
                end
            end
        end
        for _, resolution in ipairs(Layouts.sorted(layouts.profiles)) do
            local stored = layouts.profiles[resolution]
            ui.text("%s - escala %.2f%s", resolution, stored.scale, resolution == current and tr(" (actual)") or "")
            if ui.button("Cargar %s", resolution) then
                Layouts.apply(settings, stored)
                scaled_positions = {}
                dirty = true
            end
            if ui.button("Borrar %s", resolution) then
                layouts.profiles[resolution] = nil
                layouts.dirty = true
                save_layouts()
            end
        end
        if not next(layouts.profiles) then ui.text("Aun no hay resoluciones guardadas.") end
        ui.tree_pop()
    end
    if ui.tree_node("Vista previa de mision") then
        checkbox("Mostrar jugadores de la mision seleccionada", "show_mission_preview")
        slider("Mision - Posicion X", "mission_x", 0, 16384)
        slider("Mision - Posicion Y", "mission_y", 0, 16384)
        slider("Mision - Ancho", "mission_width", 300, 800)
        slider("Mision - Escala (%)", "mission_size", 50, 150)
        ui.tree_pop()
    end
    if not imgui.push_font_size or not imgui.pop_font_size then
        ui.text("Tu REFramework no permite escalar fuentes: el texto conserva su tamano.")
    end
    if ui.tree_node("Monstruos") then
        slider("Monstruos - Escala (%)", "monsters_size", 50, 150)
        checkbox("Mostrar icono de cada monstruo junto a su vida", "show_monster_icons")
        checkbox("Mostrar monstruos muertos", "show_dead")
        checkbox("Mostrar enfurecimiento y temporizador", "show_rage")
        checkbox("Mostrar resistencia y agotamiento", "show_stamina")
        checkbox("Mostrar contador de roturas", "show_parts")
        checkbox("Mostrar contadores de heridas", "show_wounds")
        checkbox("Identificar monstruo marcado [*]", "show_pin")
        checkbox("Mostrar solo monstruo marcado en el mapa", "only_pinned")
        checkbox("Priorizar monstruo marcado", "prioritize_pinned")
        checkbox("Objetivos de mision primero [M]", "prioritize_quest")
        checkbox("Distribucion horizontal", "horizontal")
        checkbox("Ordenar primero los de menor porcentaje HP", "damaged_first")
        checkbox("Modo compacto", "compact")
        slider("Posicion X", "x", 0, 16384)
        slider("Posicion Y", "y", 0, 16384)
        slider("Ancho", "width", 200, 800)
        slider("Maximo de monstruos", "max_monsters", 1, 10)
        ui.tree_pop()
    end
    if ui.tree_node("Barra de monstruo en combate") then
        slider("Combate - Escala (%)", "focus_size", 50, 150)
        checkbox("Ampliar al golpear un monstruo (desmarcado: siempre pequenas)", "auto_focus")
        ui.text(settings.auto_focus and "Modo: pequenas al explorar, grande al golpear en combate."
            or "Modo: siempre ventanitas pequenas, tambien durante el combate.")
        slider("Combate - Posicion X", "focus_x", 0, 16384)
        slider("Combate - Posicion Y", "focus_y", 0, 16384)
        slider("Combate - Ancho", "focus_width", 420, 1600)
        ui.tree_pop()
    end
    if ui.tree_node("Buffs del cazador") then
        checkbox("Mostrar buffs de consumibles", "show_buffs")
        slider("Buffs - Posicion X", "buffs_x", 0, 16384)
        slider("Buffs - Posicion Y", "buffs_y", 0, 16384)
        slider("Buffs - Ancho", "buffs_width", 120, 1200)
        slider("Buffs - Escala (%)", "buffs_size", 50, 150)
        checkbox("Buffs - Mostrar nombres", "buffs_names")
        if ui.button("Colocar buffs compactos junto al DPS") then
            settings.buffs_width, settings.buffs_size, settings.buffs_names = 240, 100, false
            local display = imgui.get_display_size()
            local dps_scale = settings.scale * settings.dps_size / 100
            local dps_width = math.min(settings.dps_width * dps_scale, display.x)
            local dps_x = math.max(0, math.min(settings.dps_x, display.x - dps_width))
            settings.buffs_x = math.min(16384, dps_x + dps_width + 12)
            settings.buffs_x = math.floor(settings.buffs_x)
            settings.buffs_y = settings.dps_y
            dirty = true
        end
        if ui.tree_node("Consumibles activos: nombres y tiempos") then
            for _, row in ipairs(source.buffs or {}) do
                imgui.text(tr(row.name) .. ": " .. (row.remaining == nil and "ACT" or View.timer(row.remaining)))
            end
            ui.tree_pop()
        end
        ui.tree_pop()
    end
    if ui.tree_node("Estadisticas del cazador") then
        checkbox("Mostrar estadisticas en tiempo real", "show_stats")
        slider("Stats - Posicion X", "stats_x", 0, 16384)
        slider("Stats - Posicion Y", "stats_y", 0, 16384)
        slider("Stats - Ancho", "stats_width", 260, 1600)
        slider("Stats - Escala (%)", "stats_size", 50, 150)
        ui.text("Ataque/elemento: valores internos, no dano por golpe ni maximo teorico.")
        ui.tree_pop()
    end
    if ui.tree_node("Actividades del poblado") then
        slider("Actividades - Escala (%)", "activities_size", 50, 150)
        checkbox("Mostrar actividades fuera de mision", "show_activities")
        checkbox("Recoleccion de materiales", "activities_collection")
        checkbox("Barco de suministros", "activities_ship")
        checkbox("Raciones disponibles", "activities_rations")
        slider("Actividades - Posicion X", "activities_x", 0, 16384)
        slider("Actividades - Posicion Y", "activities_y", 0, 16384)
        slider("Actividades - Ancho", "activities_width", 300, 800)
        ui.tree_pop()
    end
    if ui.tree_node("Medidor de dano / DPS") then
        slider("DPS - Escala (%)", "dps_size", 50, 150)
        checkbox("Mostrar medidor DPS", "show_dps")
        slider("DPS - Posicion X", "dps_x", 0, 16384)
        slider("DPS - Posicion Y", "dps_y", 0, 16384)
        slider("DPS - Ancho", "dps_width", 300, 800)
        if ui.button("Reiniciar contadores DPS") then source:reset_damage() end
        ui.tree_pop()
    end
    if ui.tree_node("Vista previa y ayuda") then
        local _, value = imgui.checkbox(tr("Vista previa DEMO (datos ficticios)"), preview)
        preview = value
        local _, focus_value = imgui.checkbox(tr("DEMO: mostrar barra de combate"), preview_focus)
        preview_focus = focus_value
        if ui.tree_node("Leyenda de iconos") then
            for _, key in ipairs({
                "Roturas / heridas: roturas completas, NORMAL, TEAR, RAW.",
                "NORMAL, TEAR y RAW son estados del SDK, no dano ni golpes restantes.",
                "Estadisticas: espada, escudo, diana, atributo del arma, cinco resistencias.",
                "Resistencias: fuego, agua, rayo, hielo, dragon.",
                "Arma: calavera = veneno; chispas = paralisis; Z = sueno; bomba = nitro.",
                "Circulo tachado = sin elemento; ? = atributo no disponible.",
                "-- = no disponible. Linea ambar en stats = lectura parcial.",
                "Buffs: tiempo real del juego; ACT = activo sin cuenta atras disponible.",
                "No incluye melodias, comida, habilidades ni estados negativos.",
                "DPS: incluye cazadores y apoyos identificados, no palico ni entorno.",
                "El resumen de la ultima caza dura 2 minutos al volver al poblado.",
                "Actividades: espacios ocupados y raciones pendientes; no inventario.",
            }) do ui.text(key) end
            ui.tree_pop()
        end
        ui.tree_pop()
    end
    if next(errors) then
        ui.text("No se pudo completar esta lectura. Consulta el detalle tecnico.")
        if ui.button("Limpiar avisos y reintentar dibujo") then
            for category in pairs(errors) do
                if category ~= "configuracion" and category ~= "posiciones"
                    and category ~= "inicio" and not category:match("^guardado") then
                    errors[category] = nil
                end
            end
            source:retry_features()
            install_mission_board()
            source:reset_focus()
            source:reset_damage()
            source:reset_activities()
            if not source.damage_ready then install_damage() end
            render_failed, damage_render_failed, activities_render_failed = false, false, false
            buffs_render_failed, stats_render_failed, mission_render_failed = false, false, false
        end
    end
    if ui.tree_node("Diagnostico avanzado") then
        slider("Actualizar cada N fotogramas", "sample_frames", 1, 60)
        checkbox("Detalle de partes en diagnostico (no en overlay)", "parts_details")
        slider("Maximo de partes en detalle", "max_parts", 1, 12)
        ui.text("Version: %s | lector: %s", version, Wilds.version)
        ui.text("Hooks: %s | llamadas: %d | muestras HP: %d",
            tr(source.ready and "si" or "no"), source.hook_calls, source.samples)
        ui.text("DPS: impactos contados: %d | sin propietario: %d", damage.hits, source.unassigned_hits)
        ui.text("Vista previa de mision: %s", tr(source.mission_state or "Pendiente de lectura"))
        ui.text("Ocultacion temporal: %s", tr(source.obstruction or "no"))
        ui.text("Estado de buffs: %s", tr(source.buffs_state or "Pendiente de lectura"))
        ui.text("Estado de estadisticas: %s", tr(source.stats_state or "Pendiente de lectura"))
        if source.activities and source.activities.collection
            and ui.tree_node("Detalle de objetos por recolector") then
            for _, npc in ipairs(source.activities.collection.collectors) do
                ui.text("%s: %d objetos | %d/%d espacios%s", npc.name, npc.count,
                    npc.occupied, npc.capacity, npc.full and tr(" | LLENO") or "")
            end
            ui.tree_pop()
        end
        if ui.tree_node("Detalle de partes y todos los estados de heridas") then
            for _, row in ipairs(model:rows(settings.max_monsters, settings.show_dead, settings)) do
                imgui.text(row.name)
                for _, line in ipairs(View.detail_lines(row, settings)) do
                    imgui.text(line)
                end
            end
            ui.tree_pop()
        end
        ui.text("Revisa re2_framework_log.txt si una lectura falla.")
        for category, message in pairs(errors) do
            ui.text("Aviso [%s]: %s", category,
                Locale.known(message) and tr(message) or tr("No se pudo completar esta lectura. Consulta el detalle tecnico."))
            if ui.tree_node("Detalle tecnico: %s", category) then
                imgui.text(message)
                ui.tree_pop()
            end
        end
        ui.tree_pop()
    end
    imgui.tree_pop()
end)

log.info("[MHOverlay] " .. version .. " loaded.")
