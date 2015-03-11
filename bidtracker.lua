-- Hook
local lOriginal_SetItemRef;

-- Status variables
local auction_started = false;
local auction_item = "";
local auction_bids = {};
local auction_os_bids = {};
local auction_min_bid = 0;

-- Variable for scrolling the bidlist.
local scroll = 0

-- Function to print to the chat frame.
function chat_print(text)
	DEFAULT_CHAT_FRAME:AddMessage("BidTracker: " .. text, 0.5, 1, 1);
end

-- Split a string into words.
function split_string(str) 
  local t = {};
  for word in string.gfind(str, "%S+") do
  	table.insert(t, word)
  end
  return t;
end

-- Register events
function bidtracker_OnLoad()
	this:RegisterEvent("CHAT_MSG_WHISPER");
	this:RegisterEvent("VARIABLES_LOADED");
end

-- Initiate all the slash commands.
function bidtracker_Init()
	SlashCmdList["bidtracker"] = bidtracker_OnCommand;
	SLASH_bidtracker1 = "/bidtracker";
	SLASH_bidtracker2 = "/btr";

	-- Hook the shift clicking on an item.
	lOriginal_SetItemRef = SetItemRef;
	SetItemRef = bidtracker_ItemLink;

	chat_print("BidTracker is now loaded! Use the command /bidtracker or /btr to use.");

end

-- Function that puts the link of an item in the item box.
function bidtracker_ItemLink(link, text, button)
	local item_box = getglobal("BidTrackerFrameItemName");

	lOriginal_SetItemRef(link, text, button);

	if (strsub(link, 1, 6) ~= "Player" and not auction_started) then
		item_box:SetText(text);
	end
end

-- Decode and call event handlers.
function bidtracker_OnEvent(event)
	if (event == "VARIABLES_LOADED") then
		if (completed_auctions == nil) then
			completed_auctions = {}
		end

		bidtracker_Init();
	elseif (event == "CHAT_MSG_WHISPER" and auction_started == true) then
		bidtracker_HandleWhisper(arg1, arg2); -- arg1 = message, arg2 = author
	end
end

-- Handle incoming whispers.
function bidtracker_HandleWhisper(msg, author)
	local incoming_words = split_string(msg);

	local bid = tonumber(incoming_words[1]);
	
	if (bid == nil) then
		SendChatMessage("You must only bid a number followed by OS if you're making an alt bid or off-spec bid! For example: -10, -5, 0, 5, 10", "WHISPER", nil, author);
		return;
	end

	if (incoming_words[2] ~= nil) then
		if (bid ~= nil and string.lower(incoming_words[2]) ~= "os") then
			SendChatMessage("You must only bid a number followed by OS if you're making an alt bid or off-spec bid! For example: -10, -5, 0, 5, 10", "WHISPER", nil, author);
			return;
		end
	end

	if (bid - math.floor(bid/5)*5 ~= 0) then
		SendChatMessage("Your bid must be a multiple of 5! Your bid was NOT accepted!", "WHISPER", nil, author);
		return;
	end
	

	if (incoming_words[2] ~= nil and string.lower(incoming_words[2]) == "os") then	
		auction_os_bids[author] = bid;
		SendChatMessage("Your OS bid is: " .. tostring(bid) .. " DKP!", "WHISPER", nil, author);
	else
		auction_bids[author] = bid;
		SendChatMessage("You have bid: " .. tostring(bid) .. " DKP!", "WHISPER", nil, author);
	end

	bidtracker_UpdateInterfaceBidList();
end

-- Updates the list of 10 bids for the interface.
function bidtracker_UpdateInterfaceBidList()
	local bids_to_check = {}

	-- If the main bid table is empty we check off-spec bids.
	if (next(auction_bids) == nil) then
		bids_to_check = auction_os_bids;
		getglobal("BidTrackerFrameBidType"):SetText("Bid type: OS");
	else
		bids_to_check = auction_bids;
		getglobal("BidTrackerFrameBidType"):SetText("Bid type: MS");
	end
	
	-- Put all the bids into an array.
	local keys = {}
	local i = 0;
	for name, value in pairs(bids_to_check) do
		i = i + 1;
		keys[i] = { name, value };
	end
	
	-- Function that compares by dkp and not by name.
	local function compare(first, second)
		return first[2] > second[2];
	end

	-- Sort the array.
	table.sort(keys, compare);
	
	
	-- Output the bids.
	for i = 0, 9 do
		getglobal("BidTrackerFrameBid" .. tostring(i)):SetText("");
		
		if (keys[i + 1 + scroll] ~= nil) then
			getglobal("BidTrackerFrameBid" .. tostring(i)):SetText(i + 1 + scroll .. ". "  .. keys[i + 1 + scroll][1] .. ": " .. keys[i + 1 + scroll][2]);
		end
	end
end

function bidtracker_ScrollUp()
	scroll = scroll - 1;
	bidtracker_UpdateInterfaceBidList();
end

function bidtracker_ScrollDown()
	scroll = scroll + 1;
	bidtracker_UpdateInterfaceBidList();
end

-- Decode and call slash command handlers.
function bidtracker_OnCommand(msg)
	local command_words = split_string(msg);

	if (command_words[1] == "setitem") then
		if (command_words ~= nil and tonumber(command_words[2]) ~= nil) then
			local item_name = "";
			for i, name in pairs(command_words) do
				if (i > 2) then
					item_name = item_name .. " " .. name;
				end
			end

			bidtracker_SetItem(item_name, tonumber(command_words[2]));
		else
			chat_print("Usage: /bidtracker setitem #min_bid $item");
		end
	elseif (command_words[1] == "startauction") then
		bidtracker_StartAuction();
	elseif (command_words[1] == "stopcountdown") then
		bidtracker_StopCountdown();
	elseif (command_words[1] == "announce") then
		if (auction_started == false) then
			bidtracker_HandleAnnounce();
		else
			chat_print("Stop the auction before announcing!");
		end
	elseif (command_words[1] == "listbids") then
		chat_print("Name: bid");
		for name, bid in pairs(auction_bids) do
			chat_print(name .. ": " .. bid);
		end
	elseif (command_words[1] == "listosbids") then
		chat_print("Name: bid");
		for name, bid in pairs(auction_os_bids) do
			chat_print(name .. ": " .. bid);
		end
	elseif (command_words[1] == "removebid") then
		if (auction_bids[command_words[2]] ~= nil) then
			auction_bids[command_words[2]] = nil;
			bidtracker_UpdateInterfaceBidList();
			chat_print("The bid from " .. command_words[2] .. " has been removed!");
		else
			chat_print("Player " .. command_words[2] .. " does not exist in the bid list!");
		end
	elseif (command_words[1] == "removeosbid") then
		if (auction_os_bids[command_words[2]] ~= nil) then
			auction_os_bids[command_words[2]] = nil;
			bidtracker_UpdateInterfaceBidList();
			chat_print("The off-spec bid from " .. command_words[2] .. " has been removed!");
		else
			chat_print("Player " .. command_words[2] .. " does not exist in the off-spec bid list!");
		end
	elseif (command_words[1] == "clearsaves") then
		completed_auctions = {};
		chat_print("Saves cleared!");
	elseif (command_words[1] == "listsaves") then
		chat_print("Saved auctions:");
		for key, val in completed_auctions do
			chat_print(val['name'] .. " - " .. val['item'] .. " - " .. val['price']);
		end
	elseif (command_words[1] == "show") then
		local frame = getglobal("BidTrackerFrame");

		if (frame:IsVisible()) then
			frame:Hide();
		else
			frame:Show();
		end
	else
		chat_print("Usage:");
		chat_print("setitem #min_bid $item_name - Set the minimum bid and the item to be auctioned. Shift-links do work!");
		chat_print("show - Toggles the BidTracker GUI.");
		chat_print("startauction                - Start the auction.");
		chat_print("stopcountdown               - Stop the announcement countdown.");
		chat_print("announce                    - Announce the auction winner.");
		chat_print("listbids                    - Locally list current bids.");
		chat_print("listosbids			- Locally list current off-spec bids.");
		chat_print("removebid $player_name      - Remove the player's bid from the bidlist.");
		chat_print("removeosbid $player_name    - Remove the player's off-spec bid from the bidlist.");
		chat_print("listsaves			- List saved finished auctions.");
		chat_print("clearsaves			- Clear all saved auctions.");
	end
end

function bidtracker_StartAuction()
	if (auction_item ~= "") then
		auction_started = true;
		SendChatMessage("Whisper bids on the " .. auction_item .. " to me! (Minimum bid: " .. auction_min_bid .. " DKP)", "RAID", nil, nil);
		
		scroll = 0;
		getglobal("BidTrackerFrameButtonStartAuction"):SetButtonState("DISABLED");
		getglobal("BidTrackerFrameButtonAnnounce"):SetButtonState("NORMAL");
		getglobal("BidTrackerFrameButtonSetItem"):SetButtonState("DISABLED");
		getglobal("BidTrackerFrameButtonStopCountdown"):SetButtonState("DISABLED");
		
		chat_print("Auction started!");
	else
		chat_print("Must have an item before starting the auction!");
	end
end

function bidtracker_StopCountdown()
	Chronos.unscheduleByName("announcement");
	chat_print("Auction countdown stopped!");
	
	getglobal("BidTrackerFrameButtonStartAuction"):SetButtonState("NORMAL");
	getglobal("BidTrackerFrameButtonAnnounce"):SetButtonState("NORMAL");
	getglobal("BidTrackerFrameButtonSetItem"):SetButtonState("NORMAL");
	getglobal("BidTrackerFrameButtonStopCountdown"):SetButtonState("DISABLED");
end

function bidtracker_HandleAnnounce()
	SendChatMessage("WARNING! The auction for the " .. auction_item .. " will end in 30 seconds! Bid now if you want it!", "RAID", nil, nil);
	Chronos.scheduleByName("announcement", 30, bidtracker_HandleAnnounceCallback);
	
	getglobal("BidTrackerFrameButtonStartAuction"):SetButtonState("DISABLED");
	getglobal("BidTrackerFrameButtonAnnounce"):SetButtonState("DISABLED");
	getglobal("BidTrackerFrameButtonSetItem"):SetButtonState("DISABLED");
	getglobal("BidTrackerFrameButtonStopCountdown"):SetButtonState("NORMAL");
end

-- Announce the winner of the auction.
function bidtracker_HandleAnnounceCallback()
	local current_max = -1000000;
	local max_bidders = {};
	local random_player = 1;
	local bids_to_check;	


	auction_started = false;
	SendChatMessage("The auction for the " .. auction_item .. " has finished. No more bids will be accepted!", "RAID", nil, nil);

	getglobal("BidTrackerFrameButtonStartAuction"):SetButtonState("NORMAL");
	getglobal("BidTrackerFrameButtonAnnounce"):SetButtonState("DISABLED");
	getglobal("BidTrackerFrameButtonSetItem"):SetButtonState("NORMAL");
	getglobal("BidTrackerFrameButtonStopCountdown"):SetButtonState("DISABLED");
	
	chat_print("Auction finished!");


	local prev_max = auction_min_bid; -- The amount you actually pay. (You always pay at least the minimum bid.)
	
	-- If the main bid table is empty we check off-spec bids.
	if (next(auction_bids) == nil) then
		bids_to_check = auction_os_bids;
		SendChatMessage("There were no main spec bids! The item will go to an off-spec or alt!", "RAID", nil, nil);
	else
		bids_to_check = auction_bids;
	end

	-- Find the max bid. (or max bids if several people bid the same amount)
	for name, bid in pairs(bids_to_check) do
		if (bid > current_max) then
			if (current_max > prev_max) then
				prev_max = current_max;
			end
			current_max = bid;
			max_bidders = {};
			max_bidders[name] = bid;
		elseif (bid == current_max) then
			max_bidders[name] = bid;
		elseif (bid > prev_max) then
			prev_max = bid;
		end
	end


	-- Count the number of players in the winner table.
	local count = 0;
	for _ in max_bidders do
		count = count + 1;
	end

	if (count == 0) then
		SendChatMessage("There were no bids for the " .. auction_item .. "!", "RAID", nil, nil);
	end

	if (count > 1) then
		SendChatMessage("There has been a tie for the " .. auction_item .. "!", "RAID", nil, nil);
		SendChatMessage("One player will be chosen at random among the following:", "RAID", nil, nil);
		for name, _ in pairs(max_bidders) do
			SendChatMessage(name, "RAID", nil, nil);
		end
		
		if (current_max > auction_min_bid) then
			prev_max = current_max;
		end

		random_player = math.random(1, count);
	end

	for name, _ in pairs(max_bidders) do
		random_player = random_player - 1;

		if (random_player == 0) then
			SendChatMessage("Congratulations " .. name .. " on the " .. auction_item .. " for " .. prev_max .. " DKP!", "RAID", nil, nil);
			local winner_data = {
				['name'] = name,
				['item'] = auction_item,
				['price'] = prev_max
			}
			table.insert(completed_auctions, winner_data);
			break;
		end
	end

	auction_item = "";
	auction_bids = {}
	auction_os_bids = {}
	
	getglobal("BidTrackerFrameButtonAnnounce"):SetButtonState("DISABLED");
	getglobal("BidTrackerFrameItemName"):SetText("");
	getglobal("BidTrackerFrameMinimumBid"):SetText("0");
	bidtracker_UpdateInterfaceBidList();
end

-- Set the bid item.
function bidtracker_SetItem(item, min_bid)
	auction_item = item;
	auction_min_bid = min_bid;
	chat_print("Auction item set to: " .. auction_item .. " (Min bid: " .. auction_min_bid .. " DKP)");
	
	getglobal("BidTrackerFrameItemName"):SetText(auction_item);
	getglobal("BidTrackerFrameMinimumBid"):SetText(auction_min_bid);
end

function bidtracker_HandleSetItemButton()
	bidtracker_SetItem(getglobal("BidTrackerFrameItemName"):GetText(), tonumber(getglobal("BidTrackerFrameMinimumBid"):GetText()));
end

