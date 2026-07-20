--[[
basic_eshop by Sharp, rnd and gui design by Jozet (2018)
--]]

modname = "basic_eshop";
basic_eshop = {};
basic_eshop.data = {}; -- {"item name", quantity, price}
basic_eshop.guidata = {}; -- [name] = {idx = idx, filter = filter, sort = sort } (start index on cur. page, filter item name, sort_coloumn)
basic_eshop.bank = {};
basic_eshop.version = "20260720se"

-------------------------
-- CONFIGURATION SETTINGS
-------------------------

-- Starting money for new players (written to bank.csv). Change here to configure.
basic_eshop.starting_money = 30

---------------------
-- END OF SETTINGS
---------------------

-- Admins must declare shops in prices.csv
-- Default starter shop prices (admins can edit these at prices.csv file)
local defaults = {
	"default:dirt;1;-0.1",
	"default:dirt;1;0.3",
	"default:tree;1;-0.35",
	"default:tree;1;1.05",
	"default:cobble;1;-0.15",
	"default:cobble;1;0.45",
	"currency:minegeld;1;-1",
	"currency:minegeld;1;1",
}

-- Code

local filepath = minetest.get_worldpath()..'/' .. modname;
minetest.mkdir(filepath)

-- forward declarations for functions used before their definitions
local normalize_path, safe_open, number_to_string, lua_explode, check_toplist, save_bank
local toplist = {}

local function get_money(player_or_name)
	local name
	if type(player_or_name) == "string" then name = player_or_name
	elseif player_or_name and player_or_name.get_player_name then name = player_or_name:get_player_name() end
	if not name then return 0 end
	local acc = basic_eshop.bank[name] or {0, 0}
	return tonumber(acc[1]) or 0
end

local function save_bank()
	local file,err = io.open(filepath..'/bank.csv', 'wb'); 
	if err then minetest.log("#basic_eshop: error cant save bank data") return end
	-- write CSV lines: name;balance;time (skip _top)
	for k,v in pairs(basic_eshop.bank) do
		if k ~= "_top" and type(v) == "table" then
			local bal = number_to_string(tonumber(v[1]) or 0)
			local tstamp = number_to_string(tonumber(v[2]) or 0)
			file:write(k .. ";" .. bal .. ";" .. tstamp .. "\n")
		end
	end
	file:close()
end

local function check_toplist(name,balance)
	local mink = toplist["_min"];
	local minb = toplist[mink] or 0;
	if balance<minb then 
		if toplist[name] then toplist["_min"] = name; toplist[name] = balance end
		return
	end 	
	
	local n = 0; for k,v in pairs(toplist) do n = n + 1 end
	
	local list = {};
	toplist[name] = balance
	
	if n+1>10 then toplist[mink] = nil end
	
	minb = 10^9; mink = ""
	for k,v in pairs(toplist) do
		if k~="_min" and v<minb then mink = k; minb = v end
	end
	toplist["_min"] = mink
end

local function set_money(player_or_name, amount)
	local name
	if type(player_or_name) == "string" then name = player_or_name
	elseif player_or_name and player_or_name.get_player_name then name = player_or_name:get_player_name() end
	if not name then return end
	basic_eshop.bank[name] = {tonumber(amount) or 0, minetest.get_gametime()}
	check_toplist(name, tonumber(amount) or 0)
	save_bank()
end

local function save_to_log(log_text)
	minetest.mkdir(filepath)
	local file,err = io.open(filepath..'/transactions_log.csv', 'a')
	if not file then
		minetest.log("#basic_eshop: error cant save transaction data: " .. tostring(err))
		return
	end
	file:write(log_text .. "\n")
	file:close()
end

lua_explode = function(s, delimiter)
	local result = {}
	for match in (s..delimiter):gmatch("(.-)"..delimiter) do
		table.insert(result, match)
	end
	return result
end

local function check_mod(mod_item_or_node_name)
	local mod = lua_explode(mod_item_or_node_name, ":")
	if (minetest.get_modpath(mod[1]) ~= nil) then
		return true
	end
	return false
end

number_to_string = function(n)
	if type(n) ~= "number" then return tostring(n) end
	if n == math.floor(n) then
		return string.format("%.0f", n)
	end
	local s = string.format("%.6f", n)
	s = s:gsub("%.?0+$", "")
	return s
end

local load_prices = function()

	local data = {}

	local file,err = io.open(filepath..'/prices.csv', 'rb')
	local raw = ""
	if err then
		minetest.log("#basic_eshop: prices.csv missing; creating default prices.csv")
		local deftext = table.concat(defaults, "\n")
		local wfile, werr = io.open(filepath..'/prices.csv', 'wb')
		if wfile then
			wfile:write(deftext .. "\n")
			wfile:close()
		else
			minetest.log("#basic_eshop: error cant create default prices.csv: " .. tostring(werr))
		end
		raw = deftext
	else
		raw = file:read("*a") or ""; file:close()
	end

	-- CSV format only: item;qty;price
	for line in raw:gmatch("[^\r\n]+") do
		local parts = lua_explode(line, ";")
		if parts[1] and parts[1] ~= "" then
			local it = parts[1]
			local qty = tonumber(parts[2]) or 1
			local price = tonumber(parts[3]) or 0
			data[#data+1] = {it, qty, price}
		end
	end

	local out = {}
	for i = 1,#data do
		if (data[i][1] ~= "" ) and (check_mod(data[i][1])) then
			out[#out+1] = data[i]
		end
	end
	basic_eshop.data = out
end

local toplist = {};
local load_bank = function()
	local file,err = io.open(filepath..'/bank.csv', 'rb')
	if err then
		minetest.log("#basic_eshop: bank file missing or cannot be opened; initializing empty bank")
		basic_eshop.bank = {}
		basic_eshop.bank["_top"] = { ["_min"] = "" }
		toplist = basic_eshop.bank["_top"];
		return
	end
	local raw = file:read("*a") or ""; file:close()
	local out = {};
	for line in raw:gmatch("[^\r\n]+") do
		local parts = lua_explode(line, ";")
		local name = parts[1]
		if name and name ~= "_top" and parts[2] then
			local bal = tonumber(parts[2]) or 0
			local tstamp = tonumber(parts[3]) or 0
			out[name] = {bal, tstamp}
		end
	end

	basic_eshop.bank = out

	local arr = {}
	for k,v in pairs(basic_eshop.bank) do
		if k ~= "_top" and type(v) == "table" then arr[#arr+1] = {k, v[1]} end
	end
	table.sort(arr, function(a,b) return a[2] > b[2] end)

	local top = { ["_min"] = "" }
	for i = 1, math.min(10, #arr) do
		top[arr[i][1]] = arr[i][2]
	end
	
	local mink, minb = "", math.huge
	for k,v in pairs(top) do
		if k ~= "_min" and v < minb then mink, minb = k, v end
	end
	top["_min"] = mink
	basic_eshop.bank["_top"] = top
	toplist = basic_eshop.bank["_top"];
end

local check_toplist = function(name,balance)
	local mink = toplist["_min"];
	local minb = toplist[mink] or 0;
	if balance<minb then 
		if toplist[name] then toplist["_min"] = name; toplist[name] = balance end
		return
	end 
	
	local n = 0; for k,v in pairs(toplist) do n = n + 1 end
	
	local list = {};
	toplist[name] = balance
	
	if n+1>10 then toplist[mink] = nil end --remove minimal
	--more than 10 entries, have to throw out smallest one
	
	minb = 10^9; mink = "" -- find new minimal element
	for k,v in pairs(toplist) do
		if k~="_min" and v<minb then mink = k; minb = v end
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
	minetest.show_formspec(name, "basic_eshop:toplist", form)
end

minetest.after(0, function() -- problem: before this minetest.get_gametime() is nil
	load_prices()
	load_bank()
end)

minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	if not basic_eshop.bank[name] then
		set_money(name, basic_eshop.starting_money)
		minetest.chat_send_player(name, "#basic_eshop: You received starting money: " .. basic_eshop.starting_money .. " $")
	end
end)

minetest.register_on_shutdown(function()
	save_bank()
end)

local init_guidata = function(name)
	basic_eshop.guidata[name] = {idx = 1, filter = "",sort = 0, count = #basic_eshop.data};
end

basic_eshop.show_shop_gui = function(name)
	
	local guidata = basic_eshop.guidata[name];
	if not guidata then init_guidata(name); guidata = basic_eshop.guidata[name]; end
	
	local idx = guidata.idx;
	local sort = guidata.sort;
	local filter = guidata.filter;
	if string.find(filter,"%%") then filter = "" end
	
	local data = basic_eshop.data; -- whole list of items for sale
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
	
	local m = #idxdata;
	local n = #idxdata;
	local pricesort = "";
	if guidata.sort == 1 then pricesort = "+" elseif guidata.sort == 2 then pricesort  = "-" end
	
	local form = "size[10,8]"..	-- width, height
	"bgcolor[#222222cc; true]" ..
	"background[0,0;8,8;gui_formbg.png;true]" ..

	"label[0.4,-0.1;".. minetest.colorize("#6f6e6e", "Basic ") .. minetest.colorize("#6f6e6e", "Online ") .. minetest.colorize("#6f6e6e", "Shop") .. "]" ..
	"label[5,-0.1;" .. minetest.colorize("#aaa", "Your money: ".. get_money(minetest.get_player_by_name(name)) .. " $") .. "]" ..

	"label[0.6,0.7;" .. minetest.colorize("#aaa", "item") .. "]" ..
	"button[4.2,0.7;1.2,0.5;price;" .. minetest.colorize("#aaa", "price"..pricesort) .. "]" ..
	
	"box[0.35,-0.1;9.05,0.65;#111]".."box[5,-0.1;4.4,0.65;#111]"..
	"box[0.35,7.2;9.05,0.15;#111]" ..  -- horizontal lines
	"field[0.65,7.9;2,0.5;search;;".. guidata.filter .."] button[2.5,7.6;1.5,0.5;filter;refresh]"..
	"button[4,7.6;1,0.5;help;help]"..
	"button[6.6,7.6;1,0.5;left;<] button[8.6,7.6;1,0.5;right;>]" ..
	"label[7.6,7.6; " .. math.ceil(idx/(m+1)) .." / " .. math.ceil(n/(m+1)) .."]";
	
	
	local tabdata = {};
	local idxhigh = math.min(idx + m,n);
	
	for i = idx, idxhigh do
		local id = idxdata[i] or 1;
		local y = 1.3+(i-idx)*0.65

		local img_x = 0.6
		local label_x = 1.4
		local price_x = 4.8

		local server_sell_form = ""
		local tooltip_buy = "buy ".. id

		local price = data[id][3]
		local arrow_x = 0.2
		local arrow = price >= 0 and minetest.colorize("#14870c", "▶") or minetest.colorize("#ff4444", "◀")
		if price >= 0 then
			server_sell_form =
				"image_button[7.8," .. y .. ";0.7,0.7;wool_black.png;buy ".. id ..";+1]" ..
				"image_button[8.3," .. y .. ";0.7,0.7;wool_black.png;buy ".. id ..";+10]" ..
				"image_button[8.8," .. y .. ";0.8,0.7;wool_black.png;buy ".. id ..";+100]"
		else
			server_sell_form =
				"image_button[7.8," .. y .. ";0.7,0.7;wool_black.png;sell ".. id ..";-1]" ..
				"image_button[8.3," .. y .. ";0.7,0.7;wool_black.png;sell ".. id ..";-10]" ..
				"image_button[8.8," .. y .. ";0.8,0.7;wool_black.png;sell ".. id ..";-100]"
		end

		if price >= 0 then
			tabdata[i-idx+1] =
				"label["..arrow_x..","..y..";".. arrow .. "]" ..
				"item_image["..(img_x-0.2)..","..(y-0.1)..";0.7,0.7;".. data[id][1] .. "]" ..
				"label["..label_x..","..y..";".. data[id][1] .. " x" .. data[id][2] .."]" ..
				"label["..price_x..","..y..";" .. minetest.colorize("#00ff36", data[id][3].." $") .."]" ..
				server_sell_form ..
				"tooltip[".. tooltip_buy ..";".. data[id][1] .. "]"
		else
			-- price is negative: shop buys item and gives player money
			tabdata[i-idx+1] =
				"label["..arrow_x..","..y..";".. arrow .. "]" ..
				"item_image["..(img_x-0.2)..","..(y-0.1)..";0.7,0.7;".. data[id][1] .. "]" ..
				"label["..label_x..","..y..";".. data[id][1] .. " x" .. data[id][2] .."]" ..
				"label["..price_x..","..y..";" .. minetest.colorize("#00ff36", -data[id][3].." $") .."]" ..
				server_sell_form ..
				"tooltip[".. tooltip_buy ..";".. data[id][1] .. "]"
		end
		server_sell_form = ""
	end
	
	minetest.show_formspec(name, "basic_eshop", form .. table.concat(tabdata,""))	
end

local make_table_copy = function(tab)
	local out = {};
	for i = 1,#tab do out[i] = tab[i] end
	return out
end

minetest.register_on_player_receive_fields(
	function(player, formname, fields)
		if formname~="basic_eshop" then return end
		local name = player:get_player_name()
		if not basic_eshop.guidata[name] then init_guidata(name) end
		
		if fields.help then
			local name = player:get_player_name();
				local text = "Admins can edit prices.csv to set available items and prices.\n\nUse /shop to browse and buy or sell items from the shop."
				local form = "size [6,4] textarea[0,0;6.5,4.5;help;SHOP HELP;".. text.."]"
				minetest.show_formspec(name, "basic_eshop:help", form)
			return
		end
		
		if fields.left then
			local guidata = basic_eshop.guidata[name]
			local idx = guidata.idx;
			local n =  guidata.count;
			local m = n;
			idx = idx - m-1;
			if idx<0 then idx = math.max(n - n%(m+1),0)+1 end
			if idx>n then idx = math.max(n-m,1) end
			guidata.idx = idx;
			basic_eshop.show_shop_gui(name)
			return			
		elseif fields.right then
			local guidata = basic_eshop.guidata[name]
			local idx = guidata.idx;
			local n =  guidata.count;
			local m = n;
			idx = idx + m+1;
			if idx>n then idx = 1 end
			guidata.idx = idx;
			basic_eshop.show_shop_gui(name)
			return
		elseif fields.filter then
			local guidata = basic_eshop.guidata[name]
			guidata.filter = tostring(fields.search or "") or ""
			if guidata.filter == "" then guidata.count = #basic_eshop.data end
			guidata.idx = 1
			basic_eshop.show_shop_gui(name)
		elseif fields.price then -- change sorting
			local guidata = basic_eshop.guidata[name]
			guidata.sort = (guidata.sort+1)%3 --0,1,2
			basic_eshop.show_shop_gui(name)
			return
		end
		
		for k,v in pairs(fields) do
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
				if sell then
					sel = tonumber(string.sub(k,6));
				else
					sel = tonumber(string.sub(k,5));
				end
				
				if not sel then return end
				local shop_item = basic_eshop.data[sel];
				if not shop_item then return end
				local balance = get_money(player);
				local price = shop_item[3] * pcs;

				if price >=0 then -- Buy

					if balance<price then
						minetest.chat_send_player(name,"#basic_eshop : you need " .. price .. " money to buy item " .. sel .. ", you only have " .. balance)
						return
					end
					balance = balance - price; set_money(player,balance)

					local inv = player:get_inventory();
					inv:add_item("main",shop_item[1] .. " " .. shop_item[2] * pcs);
					
					minetest.chat_send_player(name,"#basic_eshop : You bought \"" .. shop_item[1] .."\" " .. pcs .. "x, for " .. price .."$, Your balance is " .. balance .. "$")
					local msg_log = "#basic_eshop : Player: ".. name .." bought \"" .. shop_item[1] .."\" " .. pcs .. "x, for " .. price .."$, Player balance is " .. balance .. "$"
					local msg_log_csv = os.date("%Y-%m-%d %H:%M:%S") .. ";" .. name ..";bought;" .. shop_item[1] ..";" .. pcs .. ";" .. number_to_string(price) .. ";" .. number_to_string(balance)
					minetest.log(msg_log)
					save_to_log(msg_log_csv)
				
				else -- Sell
					
					local balance = get_money(player);
					local inv = player:get_inventory();

					if inv:contains_item("main",ItemStack(shop_item[1] .. " " .. shop_item[2] * pcs)) then
						inv:remove_item("main",ItemStack(shop_item[1] .. " " .. shop_item[2] * pcs));
						balance = balance - price
						set_money(player,balance)

						minetest.chat_send_player(name,"#basic_eshop : You sold \"" .. shop_item[1] .."\" " .. pcs .. "x, for " .. -price .."$, Your balance is " .. balance .. "$")
						local msg_log = "#basic_eshop : Player: ".. name .." sold \"" .. shop_item[1] .."\" " .. pcs .. "x, for " .. -price .."$, Player balance is " .. balance .. "$"
						local msg_log_csv = os.date("%Y-%m-%d %H:%M:%S") .. ";" .. name ..";sold;" .. shop_item[1] ..";" .. pcs .. ";" .. number_to_string(-price) .. ";" .. number_to_string(balance)
						minetest.log(msg_log)
						save_to_log(msg_log_csv)
					end
					
				end
				
				basic_eshop.show_shop_gui(name)
				save_bank()
			end
		end
	end	
)

-- CHATCOMMANDS

minetest.register_chatcommand("shop", {
	description = "Open shop GUI",
	privs = {
		privs = interact
	},
	func = function(name, param)
		basic_eshop.show_shop_gui(name)
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

minetest.register_chatcommand("shop_money", { 
	description = "Show how many money You have",
	privs = {
		privs = interact
	},
	func = function(name, param)
		if not param or param == "" then param = name end
		local bal = get_money(param)
		minetest.chat_send_player(name,"#basic_eshop: " .. param .. " has " .. bal .. " money.")
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
		set_money(pname,amount)
		minetest.chat_send_player(name,"#basic_eshop: " .. param .. " now has " .. amount .. " money.")
	end
})

minetest.register_chatcommand("shop_reload", { 
	description = "Reload shops from prices.csv file",
	privs = {
		privs = kick
	},
	func = function(name, param)
		load_prices()
		load_bank()
		minetest.chat_send_player(name,"#basic_eshop: Shop list loaded from file prices.csv!")
	end
})
