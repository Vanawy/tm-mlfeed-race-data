const string RACESTATSFEED_SCRIPT_TXT = """
// 1 space indent due to openplanet preprocessor
 #Const C_PageUID "RaceStats"
 #Include "TextLib" as TL

declare Text G_PreviousMapUid;

// logging function, should be "MLHook_LogMe_" + PageUID
Void MLHookLog(Text msg) {
    SendCustomEvent("MLHook_LogMe_" ^ C_PageUID, [msg]);
}

Integer SpawnStatusToUint(CSmPlayer::ESpawnStatus status) {
    switch (status) {
        case CSmPlayer::ESpawnStatus::NotSpawned: {
            return 0;
        }
        case CSmPlayer::ESpawnStatus::Spawning: {
            return 1;
        }
        case CSmPlayer::ESpawnStatus::Spawned: {
            return 2;
        }
        default: {}
    }
    return 0;
}

Integer GetBestRaceTime(CSmPlayer Player) {
    if (Player == Null || Player.Score == Null) return -1;
    if (Player.Score.BestRaceTimes.count == 0) return -1;
    return Player.Score.BestRaceTimes[Player.Score.BestRaceTimes.count - 1];
}

// Integer[] GetBestRaceTimes(CSmPlayer Player) {
//     if (Player == Null || Player.Score == Null) return [];
//     return Player.Score.BestRaceTimes;
// }


declare Integer[Text] LastSpawnTime;
declare Text[] LastKnownPlayers;

// send a complete list of players every now and then.
Void SendDepartedPlayers() {
    declare Boolean[Text] CurrentPlayers;
    declare Text[] CurrPlayerNames;
    foreach (Player in Players) {
        CurrentPlayers[Player.User.Name] = True;
        CurrPlayerNames.add(Player.User.Name);
    }
    foreach (PlayerName in LastKnownPlayers) {
        if (CurrentPlayers.existskey(PlayerName)) continue;
        SendCustomEvent("MLHook_Event_RaceStats_PlayerLeft", [PlayerName]);
    }
    LastKnownPlayers = CurrPlayerNames;
}


Text[] CPTimesStr(Integer[] Checkpoints) {
    declare Text[] Ret = [];
    foreach (t in Checkpoints) {
        Ret.add("" ^ t);
    }
    return Ret;
}


// send all players best times
Void _SendPlayerTimes(CSmPlayer Player) {
    if (Player.Score == Null) return;
    declare Name = Player.User.Name;
    declare RaceTimes = Player.RaceWaypointTimes;
    declare BestTimes = TL::Join(",", CPTimesStr(Player.Score.BestRaceTimes));
    SendCustomEvent("MLHook_Event_RaceStats_PlayerRaceTimes", [Name, ""^RaceTimes, BestTimes]);
}

// we only want to send info when a player's CP count changes.
declare Integer[Text] LastCPCounts;
declare CSmPlayer::ESpawnStatus[Text] LastSpawn;

Boolean _SendPlayerStats(CSmPlayer Player, Boolean Force) {
    declare Text Name = Player.User.Name;
    declare CPCount = Player.RaceWaypointTimes.count;
    // check for changes
    declare Boolean SpawnChanged = LastSpawn.existskey(Name) && Player.SpawnStatus != LastSpawn[Name];
    declare Boolean CpsChanged = LastCPCounts.existskey(Name) && CPCount != LastCPCounts[Name];
    // update if there are changes or the update is forced.
    declare Boolean WillSendEvent = Force || SpawnChanged || CpsChanged;
    if (WillSendEvent) {
        declare LatestCPTime = "";
        if (CPCount > 0) {
            LatestCPTime = ""^Player.RaceWaypointTimes[CPCount - 1];
        }
        // events should be prefixed with "MLHook_Event_" + PageUID.
        // Suffixes can be applied if multiple types of events are sent.
        SendCustomEvent("MLHook_Event_RaceStats_PlayerCP", [Name, ""^CPCount, LatestCPTime, ""^GetBestRaceTime(Player), ""^SpawnStatusToUint(Player.SpawnStatus)]);
    }
    if (SpawnChanged || Force) {
        _SendPlayerTimes(Player);
    }
    // update last spawn and cp count always
    LastCPCounts[Name] = CPCount;
    LastSpawn[Name] = Player.SpawnStatus;
    return WillSendEvent;
}

// to start with we want to send all data.
Void InitialSend() {
    foreach (Player in Players) {
        _SendPlayerStats(Player, True);
        _SendPlayerTimes(Player);
    }
    MLHookLog("Completed: InitialSend");
}

Void CheckPlayers() {
    declare Integer c = 0;
    foreach (Player in Players) {
        if (_SendPlayerStats(Player, False)) {
            c += 1;
        }
        // if (c > 4) {
        //     c = 0;
        //     yield;
        // }
    }
}

Void CheckMapChange() {
    if (Map != Null && Map.MapInfo.MapUid != G_PreviousMapUid) {
        G_PreviousMapUid = Map.MapInfo.MapUid;
        LastCPCounts = [];
    }
}

Void CheckIncoming() {
    declare Text[][] MLHook_Inbound_RaceStats for ClientUI;
    foreach (Event in MLHook_Inbound_RaceStats) {
        if (Event[0] == "SendAllPlayerStates") {
            InitialSend();
        } else {
            MLHookLog("Skipped unknown incoming event: " ^ Event);
            continue;
        }
        MLHookLog("Processed Incoming Event: "^Event[0]);
    }
    MLHook_Inbound_RaceStats = [];
}

main() {
    declare Integer LoopCounter = 0;
    MLHookLog("Starting RaceStatsFeed");
    while (Players.count == 0) {
        yield;
    }
    MLHookLog("RaceStatsFeed got init players");
    yield;
    InitialSend();
    MLHookLog("RaceStatsFeed did init send");
    while (True) {
        yield;
        CheckPlayers();
        LoopCounter += 1;
        if (LoopCounter % 60 == 0) {
            SendDepartedPlayers();
            CheckMapChange();
        }
        if (LoopCounter % 60 == 20) {
            CheckIncoming();
        }
    }
}
""";