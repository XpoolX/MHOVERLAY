local Portraits = {}

-- EnemyDef.ID field names, not numeric enum ordinals or translated display names.
Portraits.ids = {
    EM0001_00_0 = "rathian",
    EM0002_00_0 = "rathalos",
    EM0002_50_0 = "guardian_rathalos",
    EM0005_00_0 = "gravios",
    EM0008_00_0 = "yian_kut_ku",
    EM0009_00_0 = "gypceros",
    EM0021_00_0 = "congalala",
    EM0022_00_0 = "blangonga",
    EM0070_00_0 = "nerscylla",
    EM0071_00_0 = "gore_magala",
    EM0100_51_0 = "guardian_fulgur_anjanath",
    EM0113_51_0 = "guardian_ebony_odogaron",
    EM0150_00_0 = "doshaguma",
    EM0150_50_0 = "guardian_doshaguma",
    EM0151_00_0 = "balahara",
    EM0152_00_0 = "chatacabra",
    EM0153_00_0 = "quematrice",
    EM0154_00_0 = "lala_barina",
    EM0155_00_0 = "rompopolo",
    EM0156_00_0 = "rey_dau",
    EM0157_00_0 = "uth_duna",
    EM0158_00_0 = "nu_udra",
    EM0159_00_0 = "ajarakan",
    EM0160_00_0 = "arkveld",
    EM0160_50_0 = "guardian_arkveld",
    EM0161_00_0 = "hirabami",
    EM0162_00_0 = "jin_dahaad",
    EM0163_00_0 = "xu_wu",
    EM0164_50_0 = "zoh_shia",
}

function Portraits.bind(sdk_api)
    local definition = sdk_api.find_type_definition("app.EnemyDef.ID")
    if not definition then error("Falta app.EnemyDef.ID para los retratos", 0) end
    local ids = {}
    for enum, portrait in pairs(Portraits.ids) do
        local field = definition:get_field(enum)
        if not field then error("Falta app.EnemyDef.ID." .. enum, 0) end
        local value = field:get_data(nil)
        if type(value) ~= "number" or value % 1 ~= 0 then
            error("ID de retrato no entero: " .. enum, 0)
        end
        if ids[value] then error("ID de retrato duplicado: " .. enum, 0) end
        ids[value] = portrait
    end
    return ids
end

return Portraits
