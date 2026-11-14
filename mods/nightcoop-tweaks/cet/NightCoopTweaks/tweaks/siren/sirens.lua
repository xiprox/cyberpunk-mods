-- A police car's siren by its audio resource (Vehicle_Record's player_audio_resource,
-- or AudioResourceName): on starts its loop, off stops it.
-- Written by tools/make-sound-tables.py from the game's own audio metadata; don't edit by hand.

return {
    ["v_car_archer_hella_police"] = { off = "v_car_archer_hella_police_siren_stop", on = "v_car_archer_hella_police_siren_start" },
    ["v_car_archer_hella_police_traffic"] = { off = "v_car_archer_hella_police_siren_traffic_stop", on = "v_car_archer_hella_police_siren_traffic_start" },
    ["v_car_chevalier_emperor_police"] = { off = "v_car_chevalier_emperor_police_siren_stop", on = "v_car_chevalier_emperor_police_siren_start" },
    ["v_car_chevalier_emperor_police_traffic"] = { off = "v_car_chevalier_emperor_police_siren_traffic_stop", on = "v_car_chevalier_emperor_police_siren_traffic_start" },
    ["v_car_militech_hellhound_police"] = { off = "v_car_militech_hellhound_police_siren_stop", on = "v_car_militech_hellhound_police_siren_start" },
    ["v_car_militech_hellhound_police_traffic"] = { off = "v_car_militech_hellhound_police_siren_traffic_stop", on = "v_car_militech_hellhound_police_siren_traffic_start" },
    ["v_car_thorton_merrimac_maxtac"] = { off = "v_car_chevalier_emperor_police_siren_stop", on = "v_car_chevalier_emperor_police_siren_start" },
    ["v_car_thorton_merrimac_maxtac_traffic"] = { off = "v_car_chevalier_emperor_police_siren_traffic_stop", on = "v_car_chevalier_emperor_police_siren_traffic_start" },
    ["v_car_thorton_merrimac_police"] = { off = "v_car_thorton_merrimac_police_siren_stop", on = "v_car_thorton_merrimac_police_siren_start" },
    ["v_car_thorton_merrimac_police_traffic"] = { off = "v_car_thorton_merrimac_police_siren_traffic_stop", on = "v_car_thorton_merrimac_police_siren_traffic_start" },
    ["v_car_villefort_cortes_police"] = { off = "v_car_villefort_cortes_police_siren_stop", on = "v_car_villefort_cortes_police_siren_start" },
    ["v_car_villefort_cortes_police_traffic"] = { off = "v_car_villefort_cortes_police_siren_traffic_stop", on = "v_car_villefort_cortes_police_siren_traffic_start" },
}
