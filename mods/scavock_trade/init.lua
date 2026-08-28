-- Credits & trading (§19).
--
-- Credits: the basic trading currency — earned selling items, spent
-- buying from merchants. Pure in-game loop, no real-money path. Trading
-- posts live in safe zones (§12: the venue for the social half).
--
-- Scavock Tokens / Skill Tokens / mystery packs / season pools are
-- cosmetic-economy live-ops (§19/§20) — out of scope for the Lua slice,
-- which has no cosmetic layer to spend them on. Documented in README.

-- what merchants pay (per item)
local SELL_VALUES = {
	["scavock_core:scrap_ingot"] = 2,
	["scavock_core:leather"] = 3,
	["scavock_core:copper_ingot"] = 4,
	["scavock_core:iron_ingot"] = 5,
	["scavock_core:steel_ingot"] = 9,
	["scavock_core:titanium_ingot"] = 25,
	["scavock_core:graphene_ingot"] = 60,
	["scavock_survival:meat_raw"] = 2,
	["scavock_survival:meat_cooked"] = 4,
	["scavock_vehicles:fish"] = 3,
	["scavock_power:plastic"] = 2,
	["scavock_gear:feather"] = 2,
	["scavock_core:coal_lump"] = 1,
	["scavock_under:advtech"] = 500,
}

-- what merchants stock
local CATALOGUE = {
	{ item = "scavock_survival:bandage", n = 2, price = 6 },
	{ item = "scavock_weapons:arrow", n = 6, price = 10 },
	{ item = "scavock_survival:canteen", n = 1, price = 12 },
	{ item = "scavock_death:medkit", n = 1, price = 22 },
	{ item = "scavock_power:oil", n = 1, price = 16 },
	{ item = "scavock_locks:lockpick", n = 2, price = 9 },
	{ item = "scavock_power:torch", n = 6, price = 5 },
	{ item = "scavock_core:iron_ingot", n = 2, price = 14 },
}

core.register_craftitem("scavock_trade:credit", {
	description = "Credits (merchant currency, §19)",
	inventory_image = "scavock_credit.png",
	stack_max = 999,
})

local function credits_of(player)
	local total = 0
	scavock.p_each(player, function(inv, list, i, st)
		if st:get_name() == "scavock_trade:credit" then
			total = total + st:get_count()
		end
	end)
	return total
end

local function take_credits(player, n)
	if not scavock.p_contains(player, "scavock_trade:credit " .. n) then
		return false
	end
	return scavock.p_take(player, "scavock_trade:credit " .. n)
end

local function give(player, itemstring)
	local leftover = scavock.p_add(player, itemstring)
	if not leftover:is_empty() then
		core.add_item(player:get_pos(), leftover)
	end
end

local function trade_formspec(player)
	local fs = { "formspec_version[6]", "size[11.4,10.4]",
		"label[0.4,0.5;TRADING POST]",
		("label[7.4,0.5;CREDITS  %d]"):format(credits_of(player)),
		"label[0.4,1.1;Buy:]" }
	local y = 1.5
	for i, e in ipairs(CATALOGUE) do
		local def = core.registered_items[e.item]
		local label = def and def.description:gsub("\n.*", "") or e.item
		fs[#fs + 1] = ("item_image[0.4,%f;0.7,0.7;%s]"):format(y, e.item)
		fs[#fs + 1] = ("button[1.3,%f;8.2,0.7;buy_%d;%dx %s — %dc]")
			:format(y, i, e.n, core.formspec_escape(label), e.price)
		y = y + 0.85
	end
	fs[#fs + 1] = ("label[0.4,%f;Sell: hold an item, then —]"):format(y + 0.3)
	fs[#fs + 1] = ("button[0.4,%f;5.2,0.8;sell_one;SELL ONE]"):format(y + 0.7)
	fs[#fs + 1] = ("button[5.8,%f;5.2,0.8;sell_all;SELL STACK]"):format(y + 0.7)
	return table.concat(fs)
end

local function do_sell(player, all)
	local wield = player:get_wielded_item()
	local value = SELL_VALUES[wield:get_name()]
	local name = player:get_player_name()
	if not value then
		core.chat_send_player(name, "The merchant shrugs. No market for that.")
		return
	end
	local n = all and wield:get_count() or 1
	wield:take_item(n)
	player:set_wielded_item(wield)
	give(player, "scavock_trade:credit " .. (value * n))
	core.chat_send_player(name, ("Sold for %d credits."):format(value * n))
end

core.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "scavock_trade:post" then return end
	local name = player:get_player_name()
	if fields.sell_one or fields.sell_all then
		do_sell(player, fields.sell_all ~= nil)
		core.show_formspec(name, "scavock_trade:post", trade_formspec(player))
		return
	end
	for field in pairs(fields) do
		local i = tonumber(field:match("^buy_(%d+)$") or "")
		if i and CATALOGUE[i] then
			local e = CATALOGUE[i]
			if take_credits(player, e.price) then
				give(player, e.item .. " " .. e.n)
				core.chat_send_player(name, "Bought.")
			else
				core.chat_send_player(name, "Not enough credits.")
			end
			core.show_formspec(name, "scavock_trade:post", trade_formspec(player))
			return
		end
	end
end)

core.register_node("scavock_trade:post", {
	description = "Trading Post (found in safe zones)",
	tiles = { "scavock_post.png" },
	light_source = 6,
	groups = { choppy = 1 },
	drop = "",
	on_construct = function(pos)
		core.get_meta(pos):set_string("infotext", "Trading post — buy and sell")
	end,
	on_rightclick = function(pos, node, clicker)
		core.show_formspec(clicker:get_player_name(), "scavock_trade:post",
			trade_formspec(clicker))
	end,
})

-- trading posts appear beside existing and future safe-zone stones
core.register_lbm({
	label = "trading posts in safe zones",
	name = "scavock_trade:posts",
	nodenames = { "scavock_world:safezone_core" },
	run_at_every_load = true,
	action = function(pos)
		local p = { x = pos.x + 2, y = pos.y, z = pos.z }
		if core.get_node(p).name == "air" then
			core.set_node(p, { name = "scavock_trade:post" })
		end
	end,
})
