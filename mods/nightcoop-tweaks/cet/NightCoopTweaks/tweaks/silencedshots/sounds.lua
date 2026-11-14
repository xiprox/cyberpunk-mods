-- The shots an NPC makes firing a weapon silenced, by the weapon's audio set
-- (Item_Record.AudioName): the set's npcSilenced settings, or npcSettings
-- (fallback = true) where it has none, through their gun choir to each voice.
-- single: one shot; burst: one burst; loop and loopStop: an automatic loop.
-- Written by tools/make-sound-tables.py from the game's own audio metadata; don't edit by hand.

return {
    ["dev_drone_bombus_wea_set_torch"] = {
        fallback = true,
        settings = "dev_drone_bombus_wea_torch",
        voices = {
            { loop = "w_gun_npc_lexington_fire_voice_01", loopStop = "w_gun_npc_lexington_fire_voice_stop_01", single = "w_gun_npc_lexington_fire_single_voice_01" },
        },
    },
    ["dev_drone_griffin_wea_set_rifle"] = {
        fallback = true,
        settings = "dev_drone_griffin_wea_rifle",
        voices = {
            { burst = "dev_drone_griffin_default_wea_rifle_fire_single_voice_01", loop = "dev_drone_griffin_default_wea_rifle_fire_single_voice_01", single = "dev_drone_griffin_default_wea_rifle_fire_single_voice_01" },
            { burst = "dev_drone_griffin_default_wea_rifle_fire_single_voice_02", loop = "dev_drone_griffin_default_wea_rifle_fire_single_voice_02", single = "dev_drone_griffin_default_wea_rifle_fire_single_voice_02" },
            { burst = "dev_drone_griffin_default_wea_rifle_fire_single_voice_03", loop = "dev_drone_griffin_default_wea_rifle_fire_single_voice_03", single = "dev_drone_griffin_default_wea_rifle_fire_single_voice_03" },
        },
    },
    ["dev_drone_octant_wea_set_autocannon"] = {
        fallback = true,
        settings = "dev_drone_octant_wea_autocannon",
        voices = {
            { burst = "dev_drone_wyvern_wea_rifle_fire_burst_01", loop = "dev_drone_wyvern_wea_rifle_fire_auto_voice_01", loopStop = "dev_drone_wyvern_wea_rifle_fire_auto_voice_01_stop", single = "dev_drone_wyvern_wea_rifle_fire_single_voice_01" },
        },
    },
    ["dev_drone_wyvern_wea_set_rifle"] = {
        fallback = true,
        settings = "dev_drone_wyvern_wea_rifle",
        voices = {
            { burst = "dev_drone_wyvern_wea_rifle_02_fire_burst_01", single = "dev_drone_wyvern_wea_rifle_02_fire_single_voice_01" },
            { burst = "dev_drone_wyvern_wea_rifle_02_fire_burst_02", single = "dev_drone_wyvern_wea_rifle_02_fire_single_voice_02" },
            { burst = "dev_drone_wyvern_wea_rifle_02_fire_burst_03", single = "dev_drone_wyvern_wea_rifle_02_fire_single_voice_03" },
        },
    },
    ["v_av_panzer_wea_set_cannon"] = {
        fallback = true,
        settings = "v_av_panzer_wea_cannon",
        voices = {
            { loop = "v_av_panzer_wea_cannon_fire" },
        },
    },
    ["v_av_panzer_wea_set_countermeasures"] = {
        fallback = true,
        settings = "v_av_panzer_wea_countermeasures",
        voices = {
            { loop = "v_av_panzer_wea_countermeasures_fire" },
        },
    },
    ["v_av_panzer_wea_set_missiles"] = {
        fallback = true,
        settings = "v_av_panzer_wea_missile_launcher",
        voices = {
            { loop = "v_av_panzer_wea_missile_launcher_fire" },
        },
    },
    ["wea_set_achilles"] = {
        fallback = true,
        settings = "wea_npc_achilles",
        voices = {
            { single = "w_gun_npc_achilles_fire_voice_01" },
            { single = "w_gun_npc_achilles_fire_voice_02" },
            { single = "w_gun_npc_achilles_fire_voice_03" },
            { single = "w_gun_npc_achilles_fire_voice_04" },
        },
    },
    ["wea_set_ajax"] = {
        fallback = false,
        settings = "wea_npc_ajax_suppressor",
        voices = {
            { loop = "w_gun_npc_ajax_fire_voice_01_supp", loopStop = "w_gun_npc_ajax_fire_voice_01_supp_stop" },
        },
    },
    ["wea_set_ashura"] = {
        fallback = true,
        settings = "wea_npc_ashura",
        voices = {
            { single = "w_gun_npc_ashura_fire_voice_01" },
            { single = "w_gun_npc_ashura_fire_voice_02" },
            { single = "w_gun_npc_ashura_fire_voice_03" },
            { single = "w_gun_npc_ashura_fire_voice_04" },
        },
    },
    ["wea_set_burya"] = {
        fallback = true,
        settings = "wea_npc_burya",
        voices = {
            { single = "w_gun_npc_revol_tech_burya_fire_voice_01" },
            { single = "w_gun_npc_revol_tech_burya_fire_voice_02" },
            { single = "w_gun_npc_revol_tech_burya_fire_voice_03" },
            { single = "w_gun_npc_revol_tech_burya_fire_voice_04" },
            { single = "w_gun_npc_revol_tech_burya_fire_voice_05" },
        },
    },
    ["wea_set_carnage"] = {
        fallback = true,
        settings = "wea_npc_carnage",
        voices = {
            { single = "w_gun_npc_carnage_fire_voice_01" },
        },
    },
    ["wea_set_chao"] = {
        fallback = true,
        settings = "wea_npc_chao",
        voices = {
            { burst = "w_gun_npc_chao_fire_burst_voice_01", single = "w_gun_npc_chao_fire_single_voice_01" },
            { burst = "w_gun_npc_chao_fire_burst_voice_02", single = "w_gun_npc_chao_fire_single_voice_02" },
            { burst = "w_gun_npc_chao_fire_burst_voice_03", single = "w_gun_npc_chao_fire_single_voice_03" },
            { burst = "w_gun_npc_chao_fire_burst_voice_04", single = "w_gun_npc_chao_fire_single_voice_04" },
        },
    },
    ["wea_set_chao_voodoo"] = {
        fallback = true,
        settings = "wea_npc_chao",
        voices = {
            { burst = "w_gun_npc_chao_fire_burst_voice_01", single = "w_gun_npc_chao_fire_single_voice_01" },
            { burst = "w_gun_npc_chao_fire_burst_voice_02", single = "w_gun_npc_chao_fire_single_voice_02" },
            { burst = "w_gun_npc_chao_fire_burst_voice_03", single = "w_gun_npc_chao_fire_single_voice_03" },
            { burst = "w_gun_npc_chao_fire_burst_voice_04", single = "w_gun_npc_chao_fire_single_voice_04" },
        },
    },
    ["wea_set_copperhead"] = {
        fallback = false,
        settings = "wea_npc_copperhead_suppressor",
        voices = {
            { loop = "w_gun_npc_copperhead_fire_voice_01_supp", loopStop = "w_gun_npc_copperhead_fire_voice_01_supp_stop" },
        },
    },
    ["wea_set_crusher"] = {
        fallback = true,
        settings = "wea_npc_crusher",
        voices = {
            { loop = "w_gun_npc_crusher_fire_voice_01", loopStop = "w_gun_npc_crusher_fire_voice_02" },
        },
    },
    ["wea_set_defender"] = {
        fallback = false,
        settings = "wea_npc_defender_suppressor",
        voices = {
            { loop = "w_gun_npc_defender_fire_voice_01_supp", loopStop = "w_gun_npc_defender_fire_voice_01_supp_stop" },
        },
    },
    ["wea_set_dian"] = {
        fallback = true,
        settings = "wea_npc_dian",
        voices = {
            { loop = "w_gun_npc_dian_fire_voice_01", loopStop = "w_gun_npc_dian_fire_voice_stop_01", single = "w_gun_npc_dian_fire_single_voice_01" },
            { loop = "w_gun_npc_dian_fire_voice_02", loopStop = "w_gun_npc_dian_fire_voice_stop_02", single = "w_gun_npc_dian_fire_single_voice_02" },
            { loop = "w_gun_npc_dian_fire_voice_03", loopStop = "w_gun_npc_dian_fire_voice_stop_03", single = "w_gun_npc_dian_fire_single_voice_03" },
            { loop = "w_gun_npc_dian_fire_voice_04", loopStop = "w_gun_npc_dian_fire_voice_stop_04", single = "w_gun_npc_dian_fire_single_voice_04" },
        },
    },
    ["wea_set_grad"] = {
        fallback = true,
        settings = "wea_npc_grad",
        voices = {
            { single = "w_gun_npc_grad_fire_voice_01" },
        },
    },
    ["wea_set_grad_panam"] = {
        fallback = true,
        settings = "wea_npc_grad_suppressor",
        voices = {
            { single = "w_gun_npc_grad_fire_voice_01_supp" },
        },
    },
    ["wea_set_grit"] = {
        fallback = true,
        settings = "wea_npc_grit",
        voices = {
            { single = "w_gun_npc_grit_fire_voice_01" },
            { single = "w_gun_npc_grit_fire_voice_02" },
        },
    },
    ["wea_set_guillotine"] = {
        fallback = true,
        settings = "wea_npc_guillotine",
        voices = {
            { loop = "w_gun_npc_guillotine_fire_voice_01", loopStop = "w_gun_npc_guillotine_fire_voice_01_stop" },
        },
    },
    ["wea_set_hmg"] = {
        fallback = true,
        settings = "wea_npc_hmg_militech",
        voices = {
            { loop = "w_gun_npc_hmg_fire_voice_01", loopStop = "w_gun_npc_hmg_fire_voice_01_stop" },
        },
    },
    ["wea_set_igla"] = {
        fallback = true,
        settings = "wea_npc_igla",
        voices = {
            { single = "w_gun_npc_igla_fire_voice_01" },
        },
    },
    ["wea_set_kappa"] = {
        fallback = true,
        settings = "wea_npc_kappa",
        voices = {
            { loop = "w_gun_npc_kappa_fire_voice_01" },
            { loop = "w_gun_npc_kappa_fire_voice_02" },
            { loop = "w_gun_npc_kappa_fire_voice_03" },
        },
    },
    ["wea_set_kenshin"] = {
        fallback = true,
        settings = "wea_npc_kenshin",
        voices = {
            { burst = "w_gun_npc_kenshin_fire_burst_voice_01", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_01" },
            { burst = "w_gun_npc_kenshin_fire_burst_voice_02", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_02" },
            { burst = "w_gun_npc_kenshin_fire_burst_voice_03", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_03" },
            { burst = "w_gun_npc_kenshin_fire_burst_voice_04", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_04" },
            { single = "w_gun_npc_pistol_tech_kenshin_fire_voice_05" },
        },
    },
    ["wea_set_kenshin_chaos"] = {
        fallback = true,
        settings = "wea_npc_kenshin",
        voices = {
            { burst = "w_gun_npc_kenshin_fire_burst_voice_01", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_01" },
            { burst = "w_gun_npc_kenshin_fire_burst_voice_02", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_02" },
            { burst = "w_gun_npc_kenshin_fire_burst_voice_03", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_03" },
            { burst = "w_gun_npc_kenshin_fire_burst_voice_04", single = "w_gun_npc_pistol_tech_kenshin_fire_voice_04" },
            { single = "w_gun_npc_pistol_tech_kenshin_fire_voice_05" },
        },
    },
    ["wea_set_kyubi"] = {
        fallback = false,
        settings = "wea_npc_kyubi_suppressor",
        voices = {
            { single = "w_gun_npc_kyubi_fire_suppressed_voice_01" },
            { single = "w_gun_npc_kyubi_fire_suppressed_voice_02" },
            { single = "w_gun_npc_kyubi_fire_suppressed_voice_03" },
        },
    },
    ["wea_set_lexington"] = {
        fallback = false,
        settings = "wea_npc_lexington_suppressor",
        voices = {
            { loop = "w_gun_npc_lexington_fire_voice_01_supp", loopStop = "w_gun_npc_lexington_fire_voice_stop_01_supp" },
        },
    },
    ["wea_set_liberty"] = {
        fallback = false,
        settings = "wea_npc_liberty_suppressor",
        voices = {
            { single = "w_gun_npc_liberty_fire_voice_01_supp" },
        },
    },
    ["wea_set_liberty_dex"] = {
        fallback = false,
        settings = "wea_npc_liberty",
        voices = {
            { single = "w_gun_npc_liberty_fire_voice_01" },
        },
    },
    ["wea_set_ma70"] = {
        fallback = true,
        settings = "wea_npc_ma70",
        voices = {
            { loop = "w_gun_npc_ma70_fire_voice_01", loopStop = "w_gun_npc_ma70_fire_voice_01_stop" },
        },
    },
    ["wea_set_masamune"] = {
        fallback = false,
        settings = "wea_npc_masamune_suppressor",
        voices = {
            { burst = "w_gun_npc_masamune_fire_burst_voice_01_supp" },
        },
    },
    ["wea_set_metel"] = {
        fallback = true,
        settings = "wea_npc_metel",
        voices = {
            { single = "w_gun_npc_metel_fire_voice_01" },
        },
    },
    ["wea_set_missile_vehicle"] = {
        fallback = true,
        settings = "wea_npc_missile_vehicle",
        voices = {
            { loop = "w_missile_vehicle_launcher" },
        },
    },
    ["wea_set_nekomata"] = {
        fallback = true,
        settings = "wea_npc_nekomata",
        voices = {
            { single = "w_gun_npc_nekomata_fire_voice_01" },
            { single = "w_gun_npc_nekomata_fire_voice_02" },
            { single = "w_gun_npc_nekomata_fire_voice_03" },
            { single = "w_gun_npc_nekomata_fire_voice_04" },
        },
    },
    ["wea_set_nova"] = {
        fallback = false,
        settings = "wea_npc_nova_suppressor",
        voices = {
            { single = "w_gun_npc_nova_fire_voice_01_supp" },
        },
    },
    ["wea_set_nue"] = {
        fallback = false,
        settings = "wea_npc_nue_suppressor",
        voices = {
            { single = "w_gun_npc_nue_fire_voice_01_supp" },
        },
    },
    ["wea_set_omaha"] = {
        fallback = true,
        settings = "wea_npc_omaha",
        voices = {
            { single = "w_gun_npc_omaha_fire_voice_01" },
            { single = "w_gun_npc_omaha_fire_voice_02" },
            { single = "w_gun_npc_omaha_fire_voice_03" },
            { single = "w_gun_npc_omaha_fire_voice_04" },
        },
    },
    ["wea_set_overture"] = {
        fallback = false,
        settings = "wea_npc_overture_suppressor",
        voices = {
            { single = "w_gun_npc_overture_fire_voice_01_supp" },
            { single = "w_gun_npc_overture_fire_voice_01_supp" },
            { single = "w_gun_npc_overture_fire_voice_01_supp" },
            { single = "w_gun_npc_overture_fire_voice_01_supp" },
        },
    },
    ["wea_set_palica"] = {
        fallback = true,
        settings = "wea_npc_palica",
        voices = {
            { single = "w_gun_npc_palica_fire_voice_01" },
            { single = "w_gun_npc_palica_fire_voice_02" },
            { single = "w_gun_npc_palica_fire_voice_03" },
            { single = "w_gun_npc_palica_fire_voice_04" },
        },
    },
    ["wea_set_pozhar"] = {
        fallback = true,
        settings = "wea_npc_pozhar",
        voices = {
            { loop = "w_gun_npc_pozhar_fire_voice_01", loopStop = "w_gun_npc_pozhar_fire_voice_stop_01" },
        },
    },
    ["wea_set_pulsar"] = {
        fallback = false,
        settings = "wea_npc_pulsar_suppressor",
        voices = {
            { loop = "w_gun_npc_pulsar_fire_voice_01_supp", loopStop = "w_gun_npc_pulsar_fire_voice_01_supp_stop" },
        },
    },
    ["wea_set_quasar"] = {
        fallback = true,
        settings = "wea_npc_quasar",
        voices = {
            { loop = "w_gun_npc_quasar_fire_voice_01", loopStop = "w_gun_npc_quasar_fire_stop", single = "w_gun_npc_quasar_fire_single_voice_01" },
            { loop = "w_gun_npc_quasar_fire_voice_02", loopStop = "w_gun_npc_quasar_fire_stop", single = "w_gun_npc_quasar_fire_single_voice_02" },
            { loop = "w_gun_npc_quasar_fire_voice_03", loopStop = "w_gun_npc_quasar_fire_stop", single = "w_gun_npc_quasar_fire_single_voice_03" },
            { loop = "w_gun_npc_quasar_fire_voice_04", loopStop = "w_gun_npc_quasar_fire_stop", single = "w_gun_npc_quasar_fire_single_voice_04" },
        },
    },
    ["wea_set_saratoga"] = {
        fallback = false,
        settings = "wea_npc_saratoga_suppressor",
        voices = {
            { loop = "w_gun_npc_saratoga_fire_voice_01_supp", loopStop = "w_gun_npc_saratoga_fire_voice_01_supp_stop" },
        },
    },
    ["wea_set_satara"] = {
        fallback = true,
        settings = "wea_npc_satara",
        voices = {
            { single = "w_gun_npc_satara_fire_voice_01" },
            { single = "w_gun_npc_satara_fire_voice_02" },
            { single = "w_gun_npc_satara_fire_voice_03" },
            { single = "w_gun_npc_satara_fire_voice_04" },
        },
    },
    ["wea_set_senkoh"] = {
        fallback = true,
        settings = "wea_npc_senkoh",
        voices = {
            { burst = "w_gun_npc_senkoh_fire_voice_01" },
        },
    },
    ["wea_set_senkoh_prototype"] = {
        fallback = true,
        settings = "wea_npc_senkoh",
        voices = {
            { burst = "w_gun_npc_senkoh_fire_voice_01" },
        },
    },
    ["wea_set_shingen"] = {
        fallback = true,
        settings = "wea_npc_shingen",
        voices = {
            { burst = "w_gun_npc_shingen_fire_burst_voice_01", single = "w_gun_npc_shingen_fire_single_voice_01" },
            { burst = "w_gun_npc_shingen_fire_burst_voice_02", single = "w_gun_npc_shingen_fire_single_voice_02" },
            { burst = "w_gun_npc_shingen_fire_burst_voice_03", single = "w_gun_npc_shingen_fire_single_voice_03" },
            { burst = "w_gun_npc_shingen_fire_burst_voice_04", single = "w_gun_npc_shingen_fire_single_voice_04" },
        },
    },
    ["wea_set_sidewinder"] = {
        fallback = true,
        settings = "wea_npc_sidewinder",
        voices = {
            { loop = "w_gun_npc_sidewinder_fire_voice_01", loopStop = "w_gun_npc_sidewinder_fire_voice_stop_01", single = "w_gun_npc_sidewinder_fire_single_voice_01" },
            { loop = "w_gun_npc_sidewinder_fire_voice_02", loopStop = "w_gun_npc_sidewinder_fire_voice_stop_02", single = "w_gun_npc_sidewinder_fire_single_voice_02" },
            { loop = "w_gun_npc_sidewinder_fire_voice_03", loopStop = "w_gun_npc_sidewinder_fire_voice_stop_03", single = "w_gun_npc_sidewinder_fire_single_voice_03" },
            { loop = "w_gun_npc_sidewinder_fire_voice_04", loopStop = "w_gun_npc_sidewinder_fire_voice_stop_04", single = "w_gun_npc_sidewinder_fire_single_voice_04" },
        },
    },
    ["wea_set_silverhand"] = {
        fallback = true,
        settings = "wea_npc_overture",
        voices = {
            { single = "w_gun_npc_overture_fire_voice_01" },
            { single = "w_gun_npc_overture_fire_voice_02" },
            { single = "w_gun_npc_overture_fire_voice_03" },
            { single = "w_gun_npc_overture_fire_voice_04" },
        },
    },
    ["wea_set_slaught"] = {
        fallback = true,
        settings = "wea_npc_slaught-o-matic",
        voices = {
            { loop = "w_gun_npc_slaught_fire_voice_01", loopStop = "w_gun_npc_slaught_fire_voice_01_stop" },
        },
    },
    ["wea_set_smasher_hmg"] = {
        fallback = true,
        settings = "wea_npc_smasher_hmg",
        voices = {
            { loop = "w_gun_npc_hmg_smasher_fire_auto", loopStop = "w_gun_npc_hmg_smasher_fire_stop", single = "w_gun_npc_hmg_smasher_fire_single" },
        },
    },
    ["wea_set_smasher_shotgun"] = {
        fallback = true,
        settings = "wea_npc_smasher_shotgun",
        voices = {
            { loop = "w_gun_npc_shotgun_smasher_fire_auto", loopStop = "w_gun_npc_shotgun_smasher_fire_stop", single = "w_gun_npc_shotgun_smasher_fire_single" },
        },
    },
    ["wea_set_sor22"] = {
        fallback = true,
        settings = "wea_npc_sor22",
        voices = {
            { single = "w_gun_npc_sor22_fire_voice_01" },
        },
    },
    ["wea_set_spec_launcher_delamain"] = {
        fallback = false,
        settings = "wea_npc_launcher_delamain",
        voices = {
            { burst = "w_gun_npc_spec_launcher_delamain_fire", loop = "w_gun_npc_spec_launcher_delamain_fire", single = "w_gun_npc_spec_launcher_delamain_fire" },
        },
    },
    ["wea_set_special_flak_cannon"] = {
        fallback = true,
        settings = "wea_npc_hmg_militech",
        voices = {
            { loop = "w_gun_npc_hmg_fire_voice_01", loopStop = "w_gun_npc_hmg_fire_voice_01_stop" },
        },
    },
    ["wea_set_special_plasma_cutter"] = {
        fallback = true,
        settings = "wea_npc_special_plasma_cutter",
        voices = {
            { burst = "w_gun_npc_spec_plasma_fire", loop = "w_gun_npc_spec_plasma_fire", single = "w_gun_npc_spec_plasma_fire" },
        },
    },
    ["wea_set_tactician"] = {
        fallback = true,
        settings = "wea_npc_tactician",
        voices = {
            { single = "w_gun_npc_tactician_fire_voice_01" },
            { single = "w_gun_npc_tactician_fire_voice_02" },
            { single = "w_gun_npc_tactician_fire_voice_03" },
            { single = "w_gun_npc_tactician_fire_voice_04" },
        },
    },
    ["wea_set_testera"] = {
        fallback = true,
        settings = "wea_npc_testera",
        voices = {
            { single = "w_gun_npc_testera_fire_voice_01" },
        },
    },
    ["wea_set_ticon"] = {
        fallback = true,
        settings = "wea_npc_ticon",
        voices = {
            { burst = "w_gun_npc_ticon_fire_voice_02", single = "w_gun_npc_ticon_fire_voice_01" },
        },
    },
    ["wea_set_ticon_reed"] = {
        fallback = true,
        settings = "wea_npc_ticon",
        voices = {
            { burst = "w_gun_npc_ticon_fire_voice_02", single = "w_gun_npc_ticon_fire_voice_01" },
        },
    },
    ["wea_set_toygun"] = {
        fallback = true,
        settings = "wea_npc_toygun",
        voices = {
            { loop = "w_gun_npc_toygun_fire_voice_01", loopStop = "w_gun_npc_toygun_fire_voice_stop_01", single = "w_gun_npc_toygun_fire_single_voice_01" },
            { loop = "w_gun_npc_toygun_fire_voice_02", loopStop = "w_gun_npc_toygun_fire_voice_stop_02", single = "w_gun_npc_toygun_fire_single_voice_02" },
            { loop = "w_gun_npc_toygun_fire_voice_03", loopStop = "w_gun_npc_toygun_fire_voice_stop_03", single = "w_gun_npc_toygun_fire_single_voice_03" },
            { loop = "w_gun_npc_toygun_fire_voice_04", loopStop = "w_gun_npc_toygun_fire_voice_stop_04", single = "w_gun_npc_toygun_fire_single_voice_04" },
        },
    },
    ["wea_set_umbra"] = {
        fallback = false,
        settings = "wea_npc_umbra_suppressor",
        voices = {
            { loop = "w_gun_npc_umbra_fire_supp_voice_01", loopStop = "w_gun_npc_umbra_fire_supp_voice_stop_01", single = "w_gun_npc_umbra_fire_supp_single_voice_01" },
            { loop = "w_gun_npc_umbra_fire_supp_voice_02", loopStop = "w_gun_npc_umbra_fire_supp_voice_stop_02", single = "w_gun_npc_umbra_fire_supp_single_voice_02" },
            { loop = "w_gun_npc_umbra_fire_supp_voice_03", loopStop = "w_gun_npc_umbra_fire_supp_voice_stop_03", single = "w_gun_npc_umbra_fire_supp_single_voice_03" },
        },
    },
    ["wea_set_unity"] = {
        fallback = false,
        settings = "wea_npc_unity_suppressor",
        voices = {
            { single = "w_gun_npc_unity_fire_voice_01_supp" },
        },
    },
    ["wea_set_vehicle"] = {
        fallback = true,
        settings = "wea_npc_vehicle",
        voices = {
            { loop = "w_gun_npc_mounted_vehicle_fire_voice_01", loopStop = "w_gun_npc_mounted_vehicle_fire_voice_01_stop", single = "w_gun_npc_mounted_vehicle_fire_single_voice_01" },
            { loop = "w_gun_npc_mounted_vehicle_fire_voice_02", loopStop = "w_gun_npc_mounted_vehicle_fire_voice_02_stop", single = "w_gun_npc_mounted_vehicle_fire_single_voice_02" },
            { loop = "w_gun_npc_mounted_vehicle_fire_voice_03", loopStop = "w_gun_npc_mounted_vehicle_fire_voice_03_stop", single = "w_gun_npc_mounted_vehicle_fire_single_voice_03" },
        },
    },
    ["wea_set_warden"] = {
        fallback = true,
        settings = "wea_npc_warden",
        voices = {
            { loop = "w_gun_npc_warden_fire_voice_01", loopStop = "w_gun_npc_warden_fire_voice_01_stop", single = "w_gun_npc_warden_fire_single_voice_01" },
            { loop = "w_gun_npc_warden_fire_voice_02", loopStop = "w_gun_npc_warden_fire_voice_02_stop", single = "w_gun_npc_warden_fire_single_voice_02" },
        },
    },
    ["wea_set_yukimura"] = {
        fallback = true,
        settings = "wea_npc_yukimura",
        voices = {
            { loop = "w_gun_npc_yukimura_fire_voice_01", loopStop = "w_gun_npc_yukimura_fire_voice_stop_01", single = "w_gun_npc_yukimura_fire_single_voice_01" },
            { loop = "w_gun_npc_yukimura_fire_voice_02", loopStop = "w_gun_npc_yukimura_fire_voice_stop_02", single = "w_gun_npc_yukimura_fire_single_voice_02" },
            { loop = "w_gun_npc_yukimura_fire_voice_03", loopStop = "w_gun_npc_yukimura_fire_voice_stop_03", single = "w_gun_npc_yukimura_fire_single_voice_03" },
            { loop = "w_gun_npc_yukimura_fire_voice_04", loopStop = "w_gun_npc_yukimura_fire_voice_stop_04", single = "w_gun_npc_yukimura_fire_single_voice_04" },
        },
    },
    ["wea_set_yukimura_preset"] = {
        fallback = true,
        settings = "wea_npc_yukimura",
        voices = {
            { loop = "w_gun_npc_yukimura_fire_voice_01", loopStop = "w_gun_npc_yukimura_fire_voice_stop_01", single = "w_gun_npc_yukimura_fire_single_voice_01" },
            { loop = "w_gun_npc_yukimura_fire_voice_02", loopStop = "w_gun_npc_yukimura_fire_voice_stop_02", single = "w_gun_npc_yukimura_fire_single_voice_02" },
            { loop = "w_gun_npc_yukimura_fire_voice_03", loopStop = "w_gun_npc_yukimura_fire_voice_stop_03", single = "w_gun_npc_yukimura_fire_single_voice_03" },
            { loop = "w_gun_npc_yukimura_fire_voice_04", loopStop = "w_gun_npc_yukimura_fire_voice_stop_04", single = "w_gun_npc_yukimura_fire_single_voice_04" },
        },
    },
    ["wea_set_zhuo"] = {
        fallback = true,
        settings = "wea_npc_zhuo",
        voices = {
            { single = "w_gun_npc_zhuo_fire_voice_01" },
            { single = "w_gun_npc_zhuo_fire_voice_02" },
            { single = "w_gun_npc_zhuo_fire_voice_03" },
            { single = "w_gun_npc_zhuo_fire_voice_04" },
        },
    },
}
