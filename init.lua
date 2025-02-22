--[[
basic_shop by rnd, gui design by Jozet, 2018

INSTRUCTIONS:
	use /sell command to sell items (make shop).
	admin can set up shops using negative price to make shop buy item from players - this way players can get money, but only up to 100.
	

TODO:
	- ability to reverse money - item in admin shop OK
		meaning: shop owner(admin) buys item and gives money to players. admin shop has infinite money
		TODO: other players can do this too. problem: need additional storage for items if player not online
	rating of shops: more money player gives for item more his rating is worth
--]]

modname = "basic_shop";
basic_shop = {};
basic_shop.data = {}; -- {"item name", quantity, price, time_left, seller, minimal sell quantity}
basic_shop.guidata = {}; -- [name] = {idx = idx, filter = filter, sort = sort } (start index on cur. page, filter item name, sort_coloumn)
basic_shop.bank = {}; -- bank for offline players, [name] = {balance, deposit_time}, 
basic_shop.version = "20211006se"



-------------------------
-- CONFIGURATION SETTINGS
-------------------------

basic_shop.items_on_page = 8  -- gui setting
basic_shop.maxprice = 1000000 -- maximum price players can set for 1 item
basic_shop.max_noob_money = 100000000 -- after this player no longer allowed to sell his goods to admin shop to prevent inflation

basic_shop.time_left = 60*60*24*7*2; -- 2 week before shop removed/bank account reset

basic_shop.allowances = { -- how much money players need to make more shops and levels
	{5, 1}, -- noob: 5$ allows to make 1 shop
	{100,5}, -- medium
	{3000,25} -- pro
}

-- 2 initial admin shops to get items
basic_shop.admin_shops = { --{"item name", quantity, price, time_left, seller, minimal sell quantity}
	[1] = {"default:dirt",1,-0.1,10^15,"*server*",1},
	[2] = {"default:dirt",1,0.3,10^15,"*server*",1},
	[3] = {"default:tree",1,-0.35,10^15,"*server*",1},
	[4] = {"default:tree",1,1.05,10^15,"*server*",1},
	[5] = {"default:cobble",1,-0.15,10^15,"*server*",1},
	[6] = {"default:cobble",1,0.45,10^15,"*server*",1},
	--ShDebug
	[7] = {"currency:minegeld", 1, -1, 10^15, "*server*", 1},
	[8] = {"currency:minegeld", 1, 1, 10^15, "*server*", 1},
}

---------------------
-- END OF SETTINGS
---------------------



local filepath = minetest.get_worldpath()..'/' .. modname;
minetest.mkdir(filepath) -- create if non existent

save_shops = function()
	local file,err = io.open(filepath..'/shops.txt', 'wb'); 
	if err then minetest.log("#basic_shop: error cant save data") return end
	file:write(minetest.serialize(basic_shop.data));file:close()
end

function lua_explode(s, delimiter)
    result = {}
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match)
    end
    return result
end

function check_mod(mod_item_or_node_name)
	local mod = lua_explode(mod_item_or_node_name, ":")
	if (minetest.get_modpath(mod[1]) ~= nil) then
		return true
	end
	return false
end

local player_shops = {}; --[name] = count
load_shops = function()
	
	local told = minetest.get_gametime()  - basic_shop.time_left; -- time of oldest shop before timeout
	local data = {}
	
	local file,err = io.open(filepath..'/shops.txt', 'rb')

	if err then 
		minetest.log("#basic_shop: error cant load data. creating new shops.") 
	else
		data = minetest.deserialize(file:read("*a")) or {};file:close()
	end
	
	local out = {}	
	if not data[1] then -- no shops yet in file
		for i = 1,#basic_shop.admin_shops do -- add admin shops first
			out[#out+1]= basic_shop.admin_shops[i]
		end
	end
	
	for i = 1,#data do
		if (data[i][1] ~= "" ) and (check_mod(data[i][1])) then --Check if data filled in stores.txt are loaded or skip them
			if data[i][4]>told then -- shop is recent, not too old, otherwise (skip) remove it
				out[#out+1] = data[i]
				player_shops[data[i][5]] = (player_shops[data[i][5]] or 0) + 1 -- how many shops player has
			end
		end
	end
	basic_shop.data = out
end

local toplist = {};
load_bank = function()
	local file,err = io.open(filepath..'/bank.txt', 'rb')
	if err then minetest.log("#basic_shop: error cant load bank data"); return end
	local data = minetest.deserialize(file:read("*a")) or {}; file:close()
	local out = {};
	local told = minetest.get_gametime() - basic_shop.time_left;
	for k,v in pairs(data) do
		if k~="_top" then
			if v[2]>told then out[k] = v end
		else 
			out[k] = v
		end
	end
	basic_shop.bank = out
	if not basic_shop.bank["_top"] then
		basic_shop.bank["_top"] = {["_min"] = ""} -- [name] = balance
	end
	toplist = basic_shop.bank["_top"];
end

local check_toplist = function(name,balance) -- too small to be on toplist -- attempt to insert possible toplist balance
	local mink = toplist["_min"]; -- minimal element on the list
	local minb = toplist[mink] or 0; -- minimal value
	if balance<minb then 
		if toplist[name] then toplist["_min"] = name; toplist[name] = balance end
		return -- too small to be on toplist
	end 
	
	local n = 0; for k,v in pairs(toplist) do n = n + 1 end
	
	local list = {};
	toplist[name] = balance
	
	if n+1>10 then toplist[mink] = nil end --remove minimal
	--more than 10 entries, have to throw out smallest one
	
	
	minb = 10^9; mink = "" -- find new minimal element
	for k,v in pairs(toplist) do
		if k~="_min" and v<minb then mink = k minb = v end
	end
	toplist["_min"] = mink
end

local display_toplist = function(name)
	local out = {};
	for k,v in pairs(toplist) do
		if k ~= "_min" then
			out[#out+1] = {k,v}
		end
	end
	table.sort(out, function(a,b) return a[2]>b[2] end)
	local ret = {};
	for i = 1,#out do
		ret[#ret+1] = i .. ". " .. out[i][1] .. " " .. out[i][2]
	end
	local form = "size [6,7] textarea[0,0.1;6.6,8.5;TOP SHOPS;TOP RICHEST;".. table.concat(ret,"\n").."]"
	minetest.show_formspec(name, "basic_shop:toplist", form)
	
	--minetest.chat_send_all(table.concat(ret,"\n"))
end


save_bank = function()
	local file,err = io.open(filepath..'/bank.txt', 'wb'); 
	if err then minetest.log("#basic_shop: error cant save bank data") return end
	file:write(minetest.serialize(basic_shop.bank)); file:close()
end

minetest.after(0, function() -- problem: before this minetest.get_gametime() is nil
	load_shops()
	load_bank()
end)

minetest.register_on_shutdown(function()
	save_bank()
	save_shops()
end)

get_money = function(player)
	local inv = player:get_inventory();
	local stack = inv:get_stack(modname,1);
	if not stack then return 0 end
	return tonumber(stack:to_string()) or 0
end

set_money = function(player, amount)
	local inv = player:get_inventory();
	if inv:get_size(modname)<1 then inv:set_size(modname, 2) end
	inv:set_stack(modname, 1, ItemStack(amount))
	
	check_toplist(player:get_player_name(),amount)
end


init_guidata = function(name)
	--[name] = {idx = idx, filter = filter, sort = sort } (start index on cur. page, filter item name, sort_coloumn)
	basic_shop.guidata[name] = {idx = 1, filter = "",sort = 0, count = #basic_shop.data};
end

basic_shop.show_shop_gui = function(name)
	
	local guidata = basic_shop.guidata[name];
	if not guidata then init_guidata(name); guidata = basic_shop.guidata[name]; end
	
	local idx = guidata.idx;
	local sort = guidata.sort;
	local filter = guidata.filter;
	if string.find(filter,"%%") then filter = "" end
	
	local data = basic_shop.data; -- whole list of items for sale
	local idxdata = {}; -- list of idx of items for sale
	
	if filter == "" then
		for i = 1,#data do idxdata[i] = i end
		guidata.count = #data
	else
		for i = 1,#data do
			if string.find(data[i][1],filter) then
				idxdata[#idxdata+1] = i
			end
		end
		guidata.count = #idxdata
	end
		
	if guidata.sort>0 then
		if guidata.sort == 1 then -- sort price increasing
			local sortf = function(a,b) return data[a][3]<data[b][3] end
			table.sort(idxdata,sortf)
		elseif guidata.sort == 2 then
			local sortf = function(a,b) return data[a][3]>data[b][3] end
			table.sort(idxdata,sortf)		
		end
	end
	
	local m = basic_shop.items_on_page; -- default 8 items per page
	local n = #idxdata; -- how many items in current selection
	local pricesort = "";
	if guidata.sort == 1 then pricesort = "+" elseif guidata.sort == 2 then pricesort  = "-" end
	
	local form = "size[10,8]"..	-- width, height
	"bgcolor[#222222cc; true]" ..
	"background[0,0;8,8;gui_formbg.png;true]" ..

	"label[0.4,-0.1;".. minetest.colorize("#6f6e6e", "Basic ") .. minetest.colorize("#6f6e6e", "Online ") .. minetest.colorize("#6f6e6e", "Shop") .. "]" ..
	"label[5,-0.1;" .. minetest.colorize("#aaa", "Your money: ".. get_money(minetest.get_player_by_name(name)) .. " $, shops ".. (player_shops[name] or 0)) .. "]" ..

	"label[0.4,0.7;" .. minetest.colorize("#aaa", "item") .. "]" ..
	--"label[3,0.7;" .. minetest.colorize("#aaa", "price") .. "]" ..
	"button[3,0.7;1.2,0.5;price;" .. minetest.colorize("#aaa", "price"..pricesort) .. "]" ..
	"label[5,0.7;" .. minetest.colorize("#aaa", "time left") .. "]" ..
	"label[6.5,0.7;" .. minetest.colorize("#aaa", "seller") .. "]" ..
	
	"box[0.35,-0.1;9.05,0.65;#111]".."box[5,-0.1;4.4,0.65;#111]"..
	"box[0.35,7.2;9.05,0.15;#111]" ..  -- horizontal lines
	"field[0.65,7.9;2,0.5;search;;".. guidata.filter .."] button[2.5,7.6;1.5,0.5;filter;refresh]"..
	"button[4,7.6;1,0.5;help;help]"..
	"button[6.6,7.6;1,0.5;left;<] button[8.6,7.6;1,0.5;right;>]" ..
	"label[7.6,7.6; " .. math.ceil(idx/(m+1)) .." / " .. math.ceil(n/(m+1)) .."]";
	
	
	local tabdata = {};
	local idxhigh = math.min(idx + m,n);
	
	local t = basic_shop.time_left-minetest.get_gametime();
	
	for i = idx, idxhigh do
		local id = idxdata[i] or 1;
		local y = 1.3+(i-idx)*0.65
		local ti = tonumber(data[id][4]) or 0; 
		local time_left = ""
		
		ti = (t+ti); 
		if (ti> basic_shop.time_left) or (data[id][5] == '*server*') then -- shop by pro player or server, no time limit
			time_left = "no limit"
		else
			ti = ti/60; -- time left in minutes: time_left - (t-ti) = time_left-t + ti
			if ti<0 then ti = 0 end
			if ti<60 then 
				time_left = math.floor(ti*10)/10 .. "m"
			elseif ti< 1440 then 
				time_left =  math.floor(ti/60*10)/10 .. "h"
			else
				time_left =  math.floor(ti/1440*10)/10 .. "d"
			end
		end
		
		local server_sell_form = ""
		local tooltip_buy = "buy ".. id
		
		local price = data[id][3]
		if price>=0 then -- shop buys money and sells item
			
			if data[id][5] == "*server*" then
			server_sell_form =			
			"image_button[8.3," .. y .. ";0.7,0.7;wool_black.png;buy ".. id ..";+1]" ..  -- buy button
			"image_button[8.8," .. y .. ";0.7,0.7;wool_black.png;buy ".. id ..";+10]" ..  -- buy button
			"image_button[9.3," .. y .. ";0.8,0.7;wool_black.png;buy ".. id ..";+100]"  -- buy button
			else
			server_sell_form ="image_button[8.3," .. y .. ";1.25,0.7;wool_black.png;buy ".. id ..";buy]"  -- buy button
			end
			
			tabdata[i-idx+1] = 
			"item_image[0.4,".. y-0.1 .. ";0.7,0.7;".. data[id][1] .. "]" .. -- image
			"label[1.1,".. y .. ";x ".. data[id][2] .. "/" .. data[id][6] .. "]" .. -- total_quantity
			"label[3,".. y .. ";" .. minetest.colorize("#00ff36", data[id][3].." $") .."]" .. -- price
			"label[5,".. y ..";" .. time_left .."]" .. -- time left
			"label[6.5," .. y .. ";" .. minetest.colorize("#EE0", data[id][5]) .."]" .. -- seller
			--"image_button[8.5," .. y .. ";1.25,0.7;wool_black.png;buy".. id ..";buy ".. id .."]"  -- buy button
			server_sell_form
			.."tooltip[".. tooltip_buy ..";".. data[id][1] .. "]"
		else -- shop buys item and sells money
			
			tooltip_buy = "sell ".. id
			if data[id][5] == "*server*" then
			server_sell_form =
			"image_button[8.3," .. y .. ";0.7,0.7;wool_black.png;sell ".. id ..";-1]" ..  -- buy button
			"image_button[8.8," .. y .. ";0.7,0.7;wool_black.png;sell ".. id ..";-10]" ..  -- buy button
			"image_button[9.3," .. y .. ";0.8,0.7;wool_black.png;sell ".. id ..";-100]"  -- buy button
			else
			server_sell_form ="image_button[8.3," .. y .. ";1.25,0.7;wool_black.png;sell ".. id ..";sell]"  -- buy button
			end
			
			tabdata[i-idx+1] = 
			"item_image[3.0,".. y-0.1 .. ";0.7,0.7;".. data[id][1] .. "]" .. -- image
			"label[3.7,".. y .. ";x ".. data[id][2] .. "]" .. -- total_quantity
			"label[0.4,".. y .. ";" .. minetest.colorize("#00ff36", -data[id][3].." $") .."]" .. -- price
			"label[5,".. y ..";" .. time_left .."]" .. -- time left
			"label[6.5," .. y .. ";" .. minetest.colorize("#EE0", data[id][5]) .."]" .. -- seller
			--"image_button[8.5," .. y .. ";1.25,0.7;wool_black.png;buy".. id ..";sell ".. id .."]"  -- buy button
			server_sell_form
			.."tooltip[".. tooltip_buy ..";".. data[id][1] .. "]"
		end
		server_sell_form = ""
	end
	
	minetest.show_formspec(name, "basic_shop", form .. table.concat(tabdata,""))	
end

local dout = minetest.chat_send_all;


local make_table_copy = function(tab)
	local out = {};
	for i = 1,#tab do out[i] = tab[i] end
	return out
end

local remove_shop = function(idx)
	local data = {};
	for i = 1,idx-1 do data[i] = make_table_copy(basic_shop.data[i]) end -- expensive, but ok for 'small'<1000 number of shops
	for i = idx+1,#basic_shop.data do data[i-1] = make_table_copy(basic_shop.data[i]) end
	basic_shop.data = data;
end


minetest.register_on_player_receive_fields(
	function(player, formname, fields)
		if formname~="basic_shop" then return end
		local name = player:get_player_name()
		if not basic_shop.guidata[name] then init_guidata(name) end
		
		--[[
		if balance < 5 then -- new player
			minetest.chat_send_player(name,"#basic_shop: you need at least 5$ to sell items")
			return
		elseif balance<100 then -- noob
			if shop_count>1 then allow = false end
		elseif balance<1000 then -- medium
			if shop_count>5 then allow = false end
		else -- pro
			if shop_count>25 then allow = false end
		end
		if not allow then 
			minetest.chat_send_player(name,"#basic_shop: you need more money if you want more shops (100 for 5, 1000+ for 25).")
			return
		end
		--]]
		
		if fields.help then
			local name = player:get_player_name();
				local text = "Make a shop using /sell command while holding item to sell in hands. "..
				"Players get money by selling goods into admin made shops, but only up to ".. basic_shop.allowances[2][1] .. "$.\n\n"..
				"Depending on how much money you have (/shop_money command) you get ability to create " ..
				"more shops with variable life span:\n\n"..
				"    balance 0-" .. basic_shop.allowances[1][1]-1 .. "     : new player, can't create shops yet\n"..
				"    balance ".. basic_shop.allowances[1][1] .."-".. basic_shop.allowances[2][1]-1 .. "    : new trader, " .. basic_shop.allowances[1][2] .. " shop\n"..
				"    balance " .. basic_shop.allowances[2][1] .. "-" .. basic_shop.allowances[3][1]-1 .. ": medium trader, " .. basic_shop.allowances[2][2] .. " shops\n"..
				"    balance " .. basic_shop.allowances[3][1] .. "+   : pro trader, " .. basic_shop.allowances[3][2] .. " shops\n\n"..
				"All trader shop lifetime is one week ( after that shop closes down), for pro traders unlimited lifetime.\n\n"..
				"Admin can set up shop that buys items and gives money by setting negative price when using /sell."
				local form = "size [6,7] textarea[0,0;6.5,8.5;help;SHOP HELP;".. text.."]"
				minetest.show_formspec(name, "basic_shop:help", form)
			return
		end
		
		if fields.left then
			local guidata = basic_shop.guidata[name]
			local idx = guidata.idx;
			local n =  guidata.count;
			local m = basic_shop.items_on_page;
			idx = idx - m-1;
			if idx<0 then idx = math.max(n - n%(m+1),0)+1 end
			if idx>n then idx = math.max(n-m,1) end
			guidata.idx = idx;
			basic_shop.show_shop_gui(name)
			return			
		elseif fields.right then
			local guidata = basic_shop.guidata[name]
			local idx = guidata.idx;
			local n =  guidata.count;
			local m = basic_shop.items_on_page;
			idx = idx + m+1;
			if idx>n then idx = 1 end
			guidata.idx = idx;
			basic_shop.show_shop_gui(name)
			return
		elseif fields.filter then
			local guidata = basic_shop.guidata[name]
			guidata.filter = tostring(fields.search or "") or ""
			if guidata.filter == "" then guidata.count = #basic_shop.data end
			guidata.idx = 1
			basic_shop.show_shop_gui(name)
		elseif fields.price then -- change sorting
			local guidata = basic_shop.guidata[name]
			guidata.sort = (guidata.sort+1)%3 --0,1,2
			basic_shop.show_shop_gui(name)
			return
		end
		
		for k,v in pairs(fields) do
			--minetest.chat_send_player(name,"#basic_shop DEBUG: k: "..k.." v: "..v)
			--minetest.chat_send_player(name,"#basic_shop DEBUG: string.sub(k,1,3): "..string.sub(k,1,3))
			--if string.sub(k,1,3) == "buy" then
			local transfer = false
			local sell = false
			local pcs = 0
			
			if v == "-1" then pcs = 1; transfer = true; sell = true end
			if v == "-10" then pcs = 10; transfer = true; sell = true end
			if v == "-100" then pcs = 100; transfer = true; sell = true end
			if v == "+1" then pcs = 1; transfer = true end
			if v == "+10" then pcs = 10; transfer = true end
			if v == "+100" then pcs = 100; transfer = true end
			if v == "buy" then pcs = 1; transfer = true; end
			if v == "sell" then pcs = 1; transfer = true; sell = true end
			
			
			if transfer then
				local sel = 0
				--local sel = tonumber(string.sub(v,5));
				if sell then
					sel = tonumber(string.sub(k,6));
				else
					sel = tonumber(string.sub(k,5));
				end
				--minetest.chat_send_player(name,"#basic_shop DEBUG - sel: "..sel)
				
				if not sel then return end
				local shop_item = basic_shop.data[sel];
				if not shop_item then return end
				local balance = get_money(player);
				--local price = shop_item[3];
				local price = shop_item[3] * pcs;
				local seller = shop_item[5]
				
				if price >=0 then -- normal mode, sell items, buy money
				
					if seller ~= name then -- owner buys for free
						if balance<price then
							minetest.chat_send_player(name,"#basic_shop : you need " .. price .. " money to buy item " .. sel .. ", you only have " .. balance)
							return
						end
						balance = balance - price;set_money(player,balance) -- change balance for buyer
						local splayer = minetest.get_player_by_name(seller);
						if splayer then
							set_money(splayer, get_money(splayer) + price)
						else
							-- player offline, add to bank instead
							local bank_account = basic_shop.bank[seller] or {}; -- {deposit time, value}
							local bank_balance = bank_account[1] or 0;
							basic_shop.bank[seller] = {bank_balance + price, minetest.get_gametime()} -- balance, time of deposit.
						end
					
					end
					
					local inv = player:get_inventory();
					inv:add_item("main",shop_item[1] .. " " .. shop_item[2] * pcs);
					
					-- ShEdit
					-- remove item from shop
					if (seller ~= "*server*") then
						shop_item[6] = shop_item[6] - (shop_item[2]  * pcs);
						shop_item[4] = minetest.get_gametime() -- time refresh
						if (shop_item[6]<=0) then --remove shop
							player_shops[seller] = (player_shops[seller] or 1) - 1;
							remove_shop(sel)
						end
					end
					minetest.chat_send_player(name,"#basic_shop : you bought " .. shop_item[1] .." x " .. shop_item[2] * pcs .. ", for price " .. price .."$ Your balance is " .. balance .. "$")
					minetest.log("#basic_shop : Player: ".. name .." bought " .. shop_item[1] .." x " .. shop_item[2] * pcs .. ", for price " .. price .."$ Player balance is " .. balance .. "$")
				
				else -- price<0 -> admin shop buys item, gives money to player
					
					-- TODO: if shop owner not admin only allow sell if he online so that he can receive items.
					local balance = get_money(player);
					if balance>=basic_shop.max_noob_money then
						minetest.chat_send_player(name,"#basic_shop: you can no longer get more money by selling goods to admin shop (to prevent inflation) but you can still get money by selling to other players.")
						return
					end
					
					local inv = player:get_inventory(); -- buyer, his name = name
					
					if inv:contains_item("main",ItemStack(shop_item[1] .. " " .. shop_item[2] * pcs)) then
						inv:remove_item("main",ItemStack(shop_item[1] .. " " .. shop_item[2] * pcs));
						balance = math.min(basic_shop.max_noob_money, balance - price)
						set_money(player,balance)
						minetest.chat_send_player(name,"#basic_shop : you sold " .. shop_item[1] .." x " .. shop_item[2] * pcs .. " for price " .. -price .."$ Your balance is " .. balance .. "$")
						minetest.log("#basic_shop : Player: ".. name .." sold " .. shop_item[1] .." x " .. shop_item[2] * pcs .. " for price " .. -price .."$ Player balance is " .. balance .. "$")
						if balance>=basic_shop.max_noob_money then
							minetest.chat_send_player(name,"#basic_shop : CONGRATULATIONS! you are no longer noob merchant. now you can make more shops - look in help in /shop screen.")
						end
						if (seller ~= "*server*") then
							remove_shop(sel)
						end
					end
					
				end
				
				basic_shop.show_shop_gui(name)
				--ShEdit
				save_bank()
				--save_shops()
			end
		end
	end	
)

minetest.register_on_joinplayer( -- if player has money from bank, give him the money
	function(player)
		local name = player:get_player_name();
		local bank_account = basic_shop.bank[name] or {}; -- {deposit time, value}
		local bank_balance = bank_account[1] or 0;
		if bank_balance>0 then
			local balance = get_money(player) + bank_balance;
			set_money(player,balance)
			basic_shop.bank[name] = nil
			minetest.chat_send_player(name,"#basic_shop: you get " .. bank_balance .. "$ from shops, new balance " .. balance .. "$ ")
			minetest.log("#basic_shop: Player: " .. name .. " get " .. bank_balance .. "$ from shops, new balance " .. balance .. "$ ")
		end
	end
)

--[[
local ts = 0
minetest.register_globalstep(function(dtime) -- time based income
	ts = ts + dtime
	if ts<720 then return end-- 720 = 12*60
	ts = 0
	local players = minetest.get_connected_players()
	for i = 1,#players do
		local balance = get_money(players[i]);
		if balance<100 then -- above 100 no pay
			set_money(players[i],balance+1) -- 5 money/hr
		end
	end
	
end)
--]]

-- CHATCOMMANDS

minetest.register_chatcommand("shop", {  -- display shop browser
	description = "Open shop GUI",
	privs = {
		privs = interact
	},
	func = function(name, param)
		basic_shop.show_shop_gui(name)
	end
});

minetest.register_chatcommand("shop_top", {  
	description = "",
	privs = {
		privs = interact
	},
	func = function(name, param)
		display_toplist(name)
	end
});


-- player selling his product - makes new shop
minetest.register_chatcommand("sell", { 
	description = "Sell item in hand for <price>",
	privs = {
		privs = interact
	},
	func = function(name, param)
		local words = {};
		for word in param:gmatch("%S+") do words[#words+1]=word end
		local price, count, total_count
		if #words == 0  then
			minetest.chat_send_player(name,"#basic_shop " .. basic_shop.version .. " : /sell price, where price must be between 0 and " .. basic_shop.maxprice .."\nadvanced: /sell price count total_sell_count.")
			return
		end
		
		price = tonumber(words[1]) or 0; price = (price>=0) and math.floor(price+0.5) or -math.floor(-price+0.5);
		if price>basic_shop.maxprice then
			minetest.chat_send_player(name,"#basic_shop: /sell price, where price must be less than " .. basic_shop.maxprice .."\nadvanced: /sell price count total_sell_count .")
			return
		end
		count = tonumber(words[2])
		total_count = tonumber(words[3])
		
		
		local player = minetest.get_player_by_name(name); if not player then return end
		if price<0 and not minetest.get_player_privs(name).kick then price = - price end -- non admin players can not make shops that give money for items
		
		local stack =  player:get_wielded_item()
		local itemname = stack:get_name();
		
		if not count then count = stack:get_count() else count = tonumber(count) or 1 end
		if count<1 then count = 1 end
		if not total_count then total_count = count else total_count = tonumber(total_count) or count end
		if total_count<count then total_count = count end; 
		
		if itemname == "" then return end
		
		local shop_count = (player_shops[name] or 0)+1;
		local balance = get_money(player);
		
		local allow = true -- do we let player make new shop
		if balance < 0 then -- new player
			minetest.chat_send_player(name,"#basic_shop: you need at least 5$ to sell items")
			return
		elseif balance<100 then -- noob
			if shop_count>1 then allow = false end -- 1 shop for noob
		elseif balance<3000 then -- medium
			if shop_count>5 then allow = false end -- 5 shop for medium
		else -- pro
			if shop_count>25 then allow = false end -- 25 shop for pro
		end
		if not allow then 
			minetest.chat_send_player(name,"#basic_shop: you need more money if you want more shops (100 for 5, 3000+ for 25). Currently " .. shop_count .. " shops and " .. balance .. " money.")
			return
		end
		
		-- check players inventory for worn out items of this type, if found dont allow selling
		local inv = player:get_inventory()
		for i = 1, inv:get_size("main") do
			local stack = inv:get_stack("main", i)
			if itemname == stack:get_name() and stack:get_wear()>0 then 
				minetest.chat_send_player(name,"#basic_shop: found used tool/weapon you are selling in your inventory. Remove it and try again.")
				return
			end
		end
		
		local sstack = ItemStack(itemname.. " " .. total_count);
		if not player:get_inventory():contains_item("main", sstack) then 
			minetest.chat_send_player(name,"#basic_shop: you need at least " .. total_count .. " of " .. itemname)
			return
		end
		
		player_shops[name] = shop_count;
		player:get_inventory():remove_item("main", sstack)
		
		local data = basic_shop.data;
		--{"item name", quantity, price, time_left, seller}
		data[#data+1 ] = { itemname, count, price, minetest.get_gametime(), name, total_count};
		
		if balance>= basic_shop.allowances[3][1] then data[#data][4] = 10^15; end -- if player is 'pro' then remove time limit, shop will never be too old
		
		minetest.chat_send_player(name,"#basic_shop : " .. itemname .. " x " .. count .."/"..total_count .." put on sale for the price " .. price .. ". To remove item simply go /shop and buy it (for free).")
		
	end
})

minetest.register_chatcommand("shop_sell", { 
	description = "Admin shop offer",
	privs = {
		privs = kick
	},
	func = function(name, param)
		local player = minetest.get_player_by_name(name); if not player then return end
		local stack =  player:get_wielded_item()
		local itemname = stack:get_name()
			
		local data = basic_shop.data;
		--{"item name", quantity, price, time_left, seller}
		data[#data+1 ] = { itemname, 1, tonumber(param), 10^15, "*server*", 1};
		save_shops()
		minetest.chat_send_player(name,"#basic_shop: Sell item " .. itemname .. " were added for " .. param .. " to the shop list!")
		minetest.log(name,"#basic_shop: Sell item " .. itemname .. " were added for " .. param .. " to the shop list!")
	end
})

minetest.register_chatcommand("shop_buy", { 
	description = "Admin shop offer",
	privs = {
		privs = kick
	},
	func = function(name, param)
		local player = minetest.get_player_by_name(name); if not player then return end
		local stack =  player:get_wielded_item()
		local itemname = stack:get_name()
			
		local data = basic_shop.data;
		--{"item name", quantity, price, time_left, seller}
		data[#data+1 ] = { itemname, 1, tonumber(param*-1), 10^15, "*server*", 1};
		save_shops()
		minetest.chat_send_player(name,"#basic_shop: Buy item " .. itemname .. " were added for " .. param .. " to the shop list!")
		minetest.log(name,"#basic_shop: Buy item " .. itemname .. " were added for " .. param .. " to the shop list!")
	end
})

minetest.register_chatcommand("shop_money", { 
	description = "Show how many money You have",
	privs = {
		privs = interact
	},
	func = function(name, param)
		if not param or param == "" then param = name end
		local player = minetest.get_player_by_name(param)
		if not player then return end
		minetest.chat_send_player(name,"#basic_shop: " .. param .. " has " .. get_money(player) .. " money.")
	end
})

minetest.register_chatcommand("shop_set_money", { 
	description = "",
	privs = {
		privs = kick
	},
	func = function(name, param)
		local pname, amount
		pname,amount = string.match(param,"^([%w_]+)%s+(.+)");
		if not pname or not amount then minetest.chat_send_player(name,"usage: shop_set_money NAME AMOUNT") return end
		amount = tonumber(amount) or 0;
		local player = minetest.get_player_by_name(pname); if not player then return end
		set_money(player,amount)
		minetest.chat_send_player(name,"#basic_shop: " .. param .. " now has " .. amount .. " money.")
	end
})

minetest.register_chatcommand("shop_save", { 
	description = "Save shops to shops.txt file",
	privs = {
		privs = kick
	},
	func = function(name, param)
		save_bank()
		save_shops()
		minetest.chat_send_player(name,"#basic_shop: Shop list saved to file shops.txt!")
	end
})

minetest.register_chatcommand("shop_load", { 
	description = "Load shops from shops.txt file",
	privs = {
		privs = kick
	},
	func = function(name, param)
		load_shops()
		load_bank()
		minetest.chat_send_player(name,"#basic_shop: Shop list loaded from file shops.txt!")
	end
})