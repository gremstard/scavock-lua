-- Character customizer (D15 / §23): fixed-option composite, never a skin
-- upload. The player picks a skin tone, face, hair (+ color), and facial
-- hair; layers composite over the base in a fixed order:
--   base ^[multiply:tone -> clothes(shorts) -> face -> hair ^[multiply
--   -> beard ^[multiply
-- Art lives in textures/ as scavock_skin_base / scavock_face_N /
-- scavock_hair_N / scavock_beard_N — replace those PNGs with real art
-- under the same names and this system uses them untouched.

local TONES = {
	{ "Pale",   "#f2d6c0" },
	{ "Fair",   "#e0b090" },
	{ "Tan",    "#c48a5e" },
	{ "Brown",  "#8a5a38" },
	{ "Deep",   "#5c3a24" },
}
local HAIR_COLORS = {
	{ "Black",  "#26221f" },
	{ "Brown",  "#5a4028" },
	{ "Blonde", "#b09050" },
	{ "Grey",   "#9a9a98" },
}
local FACES, HAIRS, BEARDS = 3, 3, 2

local function opts(player)
	local meta = player:get_meta()
	local function geti(key, default, max)
		local v = meta:get_int(key)
		if v < 1 or v > max then return default end
		return v
	end
	return {
		tone = geti("cc_tone", 2, #TONES),
		face = geti("cc_face", 1, FACES),
		hair = meta:get_int("cc_hair"),      -- 0 = none
		hcol = geti("cc_hcol", 2, #HAIR_COLORS),
		beard = meta:get_int("cc_beard"),    -- 0 = none
	}
end

local function composite(o)
	local t = "scavock_skin_base.png^[multiply:" .. TONES[o.tone][2]
	t = t .. "^scavock_skin_clothes.png"
	t = t .. "^scavock_face_" .. o.face .. ".png"
	if o.hair > 0 and o.hair <= HAIRS then
		t = t .. "^(scavock_hair_" .. o.hair .. ".png^[multiply:"
			.. HAIR_COLORS[o.hcol][2] .. ")"
	end
	if o.beard > 0 and o.beard <= BEARDS then
		t = t .. "^(scavock_beard_" .. o.beard .. ".png^[multiply:"
			.. HAIR_COLORS[o.hcol][2] .. ")"
	end
	return t
end

-- what you wear shows on the rig (clothes composite on top of the skin)
local WEAR = {
	["scavock_gear:cap"] = "scavock_wear_cap.png",
	["scavock_gear:shirt"] = "scavock_wear_shirt.png",
	["scavock_gear:vest"] = "scavock_wear_vest.png",
	["scavock_gear:pants"] = "scavock_wear_pants.png",
	["scavock_gear:shoes"] = "scavock_wear_shoes.png",
}

local function wear_layers(player)
	local t = ""
	if not (rawget(_G, "scavock_gear") and scavock_gear.equipped) then
		return t
	end
	for _, slot in ipairs({ "hat", "top", "vest", "bottoms", "shoes" }) do
		local ok, st = pcall(scavock_gear.equipped, player, slot)
		if ok and st and not st:is_empty() then
			local tex = WEAR[st:get_name()]
			if tex then
				t = t .. "^" .. tex
			end
		end
	end
	return t
end

function scavock.apply_character(player)
	local o = opts(player)
	player:set_properties({
		visual = "mesh",
		mesh = "scavock_character.obj",
		textures = { composite(o) .. wear_layers(player) },
		visual_size = { x = 1, y = 1 },
		backface_culling = false,
	})
end

local function show_customizer(name)
	local player = core.get_player_by_name(name)
	if not player then return end
	local o = opts(player)
	local fs = {
		"formspec_version[6]", "size[12.6,9.2]",
		"label[0.4,0.6;CHARACTER]",
		("model[8.2,0.9;4.0,6.6;preview;scavock_character.obj;%s;-10,160;true;true]")
			:format(core.formspec_escape(composite(o))),
		("label[0.4,1.3;Skin tone:  %s]"):format(TONES[o.tone][1]),
		"button[5.2,1.05;1.2,0.7;cc_tone_p;<]",
		"button[6.5,1.05;1.2,0.7;cc_tone_n;>]",
		("label[0.4,2.3;Face:  %d / %d]"):format(o.face, FACES),
		"button[5.2,2.05;1.2,0.7;cc_face_p;<]",
		"button[6.5,2.05;1.2,0.7;cc_face_n;>]",
		("label[0.4,3.3;Hair:  %s]"):format(o.hair == 0 and "None" or o.hair),
		"button[5.2,3.05;1.2,0.7;cc_hair_p;<]",
		"button[6.5,3.05;1.2,0.7;cc_hair_n;>]",
		("label[0.4,4.3;Hair color:  %s]"):format(HAIR_COLORS[o.hcol][1]),
		"button[5.2,4.05;1.2,0.7;cc_hcol_p;<]",
		"button[6.5,4.05;1.2,0.7;cc_hcol_n;>]",
		("label[0.4,5.3;Facial hair:  %s]"):format(o.beard == 0 and "None" or o.beard),
		"button[5.2,5.05;1.2,0.7;cc_beard_p;<]",
		"button[6.5,5.05;1.2,0.7;cc_beard_n;>]",
		"button[0.4,7.6;7.3,0.9;cc_done;DONE]",
	}
	core.show_formspec(name, "scavock_player:character", table.concat(fs))
end

core.register_chatcommand("character", {
	description = "Open the character customizer",
	func = function(name) show_customizer(name) return true end,
})

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "scavock_player:character" then return end
	local meta = player:get_meta()
	local o = opts(player)
	local function cycle(v, max, delta, allow_zero)
		v = v + delta
		local lo = allow_zero and 0 or 1
		if v > max then v = lo end
		if v < lo then v = max end
		return v
	end
	local changed = false
	if fields.cc_tone_n then meta:set_int("cc_tone", cycle(o.tone, #TONES, 1)) changed = true end
	if fields.cc_tone_p then meta:set_int("cc_tone", cycle(o.tone, #TONES, -1)) changed = true end
	if fields.cc_face_n then meta:set_int("cc_face", cycle(o.face, FACES, 1)) changed = true end
	if fields.cc_face_p then meta:set_int("cc_face", cycle(o.face, FACES, -1)) changed = true end
	if fields.cc_hair_n then meta:set_int("cc_hair", cycle(o.hair, HAIRS, 1, true)) changed = true end
	if fields.cc_hair_p then meta:set_int("cc_hair", cycle(o.hair, HAIRS, -1, true)) changed = true end
	if fields.cc_hcol_n then meta:set_int("cc_hcol", cycle(o.hcol, #HAIR_COLORS, 1)) changed = true end
	if fields.cc_hcol_p then meta:set_int("cc_hcol", cycle(o.hcol, #HAIR_COLORS, -1)) changed = true end
	if fields.cc_beard_n then meta:set_int("cc_beard", cycle(o.beard, BEARDS, 1, true)) changed = true end
	if fields.cc_beard_p then meta:set_int("cc_beard", cycle(o.beard, BEARDS, -1, true)) changed = true end
	if changed then
		scavock.apply_character(player)
		show_customizer(player:get_player_name())
	elseif fields.cc_done or fields.quit then
		scavock.apply_character(player)
	end
end)

core.register_on_joinplayer(function(player)
	core.after(0.2, function()
		local p = core.get_player_by_name(player:get_player_name())
		if p then scavock.apply_character(p) end
	end)
end)

core.register_on_newplayer(function(player)
	core.after(1.0, function()
		show_customizer(player:get_player_name())
	end)
end)
