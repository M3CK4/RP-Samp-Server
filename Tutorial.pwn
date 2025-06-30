#include <a_samp>
#include <YSI\YSI_Coding\y_timers>
#include <a_mysql>
#include <zcmd>
#define SSCANF_NO_NICE_FEATURES
#include <sscanf2>
#include <streamer>

#include "Maps.pwn"

#define SERVER_NAME "Tutorial M3CK4"

#define HOST "localhost"
#define PASS ""
#define USER "root"
#define DB "tutorial-db"

#define dialogRegister 0
#define dialogLogin 1
#define dialogEmail 2
#define dialogGender 3
#define dialogAdminCode 4
#define dialogQuestion 5
#define dialogPlayerInfo 6
#define dialogRentOptions 7

#define MAX_QUESTIONS 50
#define MAX_RENTS 50

new MySQL:SQL;

new bool:registered[MAX_PLAYERS];
new bool:logged[MAX_PLAYERS];

new PlayerText:InfoPTD[MAX_PLAYERS][2];
new Text:ServerTD[5];

new FarmerVeh[2];
new JobStage[MAX_PLAYERS];

enum Rents_Info {
    rID,
    Float:rX,
    Float:rY,
    Float:rZ,
    Float:rAngle,
    bool:rBuilt
};

new RentsInfo[MAX_RENTS][Rents_Info];
new rentObj[MAX_RENTS];
new rentEditID[MAX_PLAYERS];
new numberOfRents;
new Text3D:rentText[MAX_RENTS];
new rentPickup[MAX_RENTS];
new bool:rentExistsInDatabase[MAX_RENTS];
new rentsLoaded;

new renting[MAX_PLAYERS];
new rentTimer[MAX_PLAYERS];
new PlayerText3D:rentTimerTL[MAX_PLAYERS];


// ----------------------------------------------
enum Question_Info {
    qID,
    qFrom[MAX_PLAYER_NAME],
    qFromID,
    qMessage[256],
    bool:qOpened
};
new QuestionInfo[MAX_QUESTIONS][Question_Info];
new askqCooldown[MAX_PLAYERS];
new answeringQuestion[MAX_PLAYERS];
new numberOfQuestions;


// --------------------------------
enum Player_Info {
    sID,
    pPassword,
    pMoney,
    pLevel,
    pSkin,
    pEmail[25],
    bool:pGender,
    pAdmin,
    pAdminCode,
    pInactivity,
    pJob[64],
    pPayDay,
    pXP
};
new PlayerInfo[MAX_PLAYERS][Player_Info];
new RequiredXP[MAX_PLAYERS];

main() {
    print("\n----------------------------------");
    print(" M3CK4 Tutorial RP Server");
    print("----------------------------------\n");
}
// ------------------   TIMERS ----------------------
ptask RentUpdateTimer[1000](playerid)
{
    if(renting[playerid] != -1)
    {
        new text[64];
        format(text, sizeof(text), "{1ac42b}[Rent Timer]\n{ffffff}%d", rentTimer[playerid]);
        DeletePlayer3DTextLabel(playerid, rentTimerTL[playerid]);
        rentTimerTL[playerid] = CreatePlayer3DTextLabel(playerid, text, -1, 0,0,0, 5.0, INVALID_PLAYER_ID, renting[playerid], 0);
        if(rentTimer[playerid] > 0)
        {
            rentTimer[playerid]--;
        } else {
            DestroyVehicle(renting[playerid]);
            DeletePlayer3DTextLabel(playerid, rentTimerTL[playerid]);
            renting[playerid] = -1;
            InfoMessage(playerid, "You rent period has expired.");
        }
    }
}
ptask AskQTimer[1000](playerid) {
    if (askqCooldown[playerid] > 0 && logged[playerid]) {
        askqCooldown[playerid]--;
    }
}
ptask PayDayTimer[60000](playerid) {
    if (PlayerInfo[playerid][pPayDay] > 0 && logged[playerid]) {
        PlayerInfo[playerid][pPayDay]--;
        SavePlayer(playerid);
    }
}
ptask CheckPayDay[1000](playerid) {
    RequiredXP[playerid] = PlayerInfo[playerid][pLevel] * 2 + 4;
    if (PlayerInfo[playerid][pPayDay] == 0 && logged[playerid]) { 
        PlayerInfo[playerid][pXP]++;
        PlayerInfo[playerid][pPayDay] = 60;
        SavePlayer(playerid);
    }
    while (PlayerInfo[playerid][pXP] >= RequiredXP[playerid] && logged[playerid]) {
        PlayerInfo[playerid][pXP] -= RequiredXP[playerid];
        GivePlayerMoney(playerid, 1000);
        PlayerInfo[playerid][pMoney] += 1000;
        PlayerInfo[playerid][pLevel]++;
        GameTextForPlayer(playerid, "~g~You've leveled up!", 3000, 3);
        SetPlayerScore(playerid, PlayerInfo[playerid][pLevel]);
        SavePlayer(playerid);
    }
}
//----------------------------------------------------

public OnGameModeInit() {
    DisableInteriorEnterExits();
    EnableStuntBonusForAll(false);
    ShowPlayerMarkers(false);

    //---------------------------------------------------------

    SQL = mysql_connect(HOST, USER, PASS, DB);
    if (SQL == MYSQL_INVALID_HANDLE || mysql_errno(SQL) != 0) {
        print("Failed to connect with the database");
        SendRconCommand("exit");
        return 0;
    }

    SetGameModeText("Tutorial v0.1 Alpha");
    AddPlayerClass(60, 1731.6658, -1912.0126, 13.5625, 90.0, 0, 0, 0, 0, 0, 0);

    CreateTD();
    //--------------------------------------------------------
    numberOfQuestions = 0;
    numberOfRents = 0;
    rentsLoaded = 0;
    // -------------------------------------------------------
    Create3DTextLabel("[{1ac42b}Farmer{ffffff}]\n'Y'", -1, -401.6756, -1419.5562, 26.0881, 5.0, 0);
    AddStaticPickup(1210, 1, -401.6756, -1419.5562, 26.0881);
    //--------------------------------------------------------
    FarmerVeh[0] = AddStaticVehicle(531, -374.4098, -1452.5555, 25.7266, 0.0, 1, 1);
    FarmerVeh[1] = AddStaticVehicle(531, -379.7271, -1453.6841, 25.7266, 0.0, 1, 1);

    CreateObjects();

    for(new i = 1; i <= MAX_RENTS; i++)
    {
        new str[256];
        mysql_format(SQL, str, sizeof(str), "SELECT * FROM `rents` WHERE `ID` = '%d'", i);
        mysql_tquery(SQL, str, "LoadRent", "d", i);
    }

    return 1;
}

public OnGameModeExit() {
    for (new i = 0; i < MAX_PLAYERS; i++) {
        SavePlayer(i);
        PlayerInfo[i][sID] = -1;
    }
    mysql_close(SQL);
    return 1;
}

public OnPlayerConnect(playerid) {
    SetPlayerColor(playerid, 0xFFFFFFFF);
    TogglePlayerSpectating(playerid, true);
    ResetAccount(playerid);
    DisablePlayerCheckpoint(playerid);
    rentEditID[playerid] = -1;
    renting[playerid] = -1;

    new query[128];
    mysql_format(SQL, query, sizeof(query), "SELECT * FROM `players` WHERE `Username` = '%e'", GetName(playerid));
    mysql_tquery(SQL, query, "CheckAccount", "i", playerid);

    answeringQuestion[playerid] = 0;

    return 1;
}

public OnPlayerDisconnect(playerid, reason) {
    if (!logged[playerid]) return 1;
    SavePlayer(playerid);
    PlayerInfo[playerid][sID] = -1;
    logged[playerid] = false;
    if(renting[playerid] != -1)
    {
        DestroyVehicle(renting[playerid]);
        renting[playerid] = -1;
    }
    return 1;
}

public OnPlayerSpawn(playerid) {
    TogglePlayerControllable(playerid, true);

    SetPlayerSkin(playerid, PlayerInfo[playerid][pSkin]);
    SetPlayerScore(playerid, PlayerInfo[playerid][pLevel]);
    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, PlayerInfo[playerid][pMoney]);

    CreatePTD(playerid);
    ShowEssentialTD(playerid);

    JobStage[playerid] = 0;

    return 1;
}

public OnPlayerDeath(playerid, killerid, reason) {
    SetSpawnInfo(playerid, 0, PlayerInfo[playerid][pSkin], 1731.6658, -1912.0126, 13.5625, 84.0176, 0, 0, 0, 0, 0, 0);
    SpawnPlayer(playerid);
    return 1;
}

public OnVehicleSpawn(vehicleid) {
    return 1;
}

public OnVehicleDeath(vehicleid, killerid) {
    for(new i = 0; i < MAX_PLAYERS; i++)
    {
        if(vehicleid == renting[i])
        {
            DestroyVehicle(vehicleid);
            renting[i] = -1;
            SendClientMessage(i, -1, "{ff000}Your rent vehicle has been destoryed.");
            break;
        }
    }
    return 1;
}

public OnPlayerCommandPerformed(playerid, cmdtext[], success) {
    if (!success) return SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}That command is unknown");
    return 1;
}

public OnPlayerText(playerid, text[]) {
    new Float:X, Float:Y, Float:Z, str[256];
    GetPlayerPos(playerid, X, Y, Z);
    format(str, sizeof(str), "{ffffff}%s says: %s", GetName(playerid), text);
    SendMess(5.0, X, Y, Z, str);

    return 1;
}

public OnPlayerEnterVehicle(playerid, vehicleid, ispassenger) {
    if (vehicleid == FarmerVeh[0] || vehicleid == FarmerVeh[1]) {
        if (strcmp(PlayerInfo[playerid][pJob], "Farmer") != 0) {
            RemovePlayerFromVehicle(playerid);
            ClearAnimations(playerid, 1);
        } else if (JobStage[playerid] == 0) {
            SetPlayerCheckpoint(playerid, -397.0632, -1392.4755, 23.4845, 2.0);
            SendClientMessage(playerid, -1, "{1ac42b}JOB: {ffffff}Go to the marker on the map.");
        }
    }

    for(new i = 0; i < MAX_PLAYERS; i++)
    {
        if(vehicleid == renting[i] && !ispassenger && playerid != i)
        {
            ClearAnimations(playerid);
            RemovePlayerFromVehicle(playerid);
            ErrorMessage(playerid, "You don't rent this vehicle!");
            break;
        }
    }
    return 1;
}

public OnPlayerExitVehicle(playerid, vehicleid) {
    return 1;
}

public OnPlayerStateChange(playerid, newstate, oldstate) {
    return 1;
}

public OnPlayerEnterCheckpoint(playerid) {
    DisablePlayerCheckpoint(playerid);
    if (IsPlayerInRangeOfPoint(playerid, 3.0, -397.0632, -1392.4755, 23.4845)) {
        SetPlayerCheckpoint(playerid, -404.8639, -1393.1588, 23.5116, 2.0);
        JobStage[playerid] = 1;
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -404.8639, -1393.1588, 23.5116)) {
        SetPlayerCheckpoint(playerid, -413.9731, -1394.3230, 23.2529, 2.0);
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -413.9731, -1394.3230, 23.2529)) {
        SetPlayerCheckpoint(playerid, -423.6385, -1395.5577, 22.9466, 2.0);
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -423.6385, -1395.5577, 22.9466)) {
        SetPlayerCheckpoint(playerid, -432.5067, -1396.6907, 22.3170, 2.0);
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -432.5067, -1396.6907, 22.3170)) {
        SetPlayerCheckpoint(playerid, -442.5875, -1397.9780, 22.4039, 2.0);
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -442.5875, -1397.9780, 22.4039)) {
        SetPlayerCheckpoint(playerid, -449.8523, -1398.9059, 21.7560, 2.0);
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -449.8523, -1398.9059, 21.7560)) {
        SetPlayerCheckpoint(playerid, -460.6730, -1400.2883, 19.7509, 2.0);
    } else if (IsPlayerInRangeOfPoint(playerid, 3.0, -460.6730, -1400.2883, 19.7509)) {
        SendClientMessage(playerid, -1, "{1ac42b}JOB: {ffffff}The job is done, here is your pay.");
        GivePlayerMoney(playerid, 300);
        PlayerInfo[playerid][pMoney] += 300;
        SavePlayer(playerid);
        JobStage[playerid] = 0;
        SetVehicleToRespawn(GetPlayerVehicleID(playerid));
    }
    return 1;
}

public OnPlayerLeaveCheckpoint(playerid) {
    return 1;
}

public OnPlayerEnterRaceCheckpoint(playerid) {
    return 1;
}

public OnPlayerLeaveRaceCheckpoint(playerid) {
    return 1;
}

public OnRconCommand(cmd[]) {
    return 1;
}

public OnPlayerRequestSpawn(playerid) {
    return 1;
}

public OnObjectMoved(objectid) {
    return 1;
}

public OnPlayerObjectMoved(playerid, objectid) {
    return 1;
}

public OnPlayerPickUpPickup(playerid, pickupid) {
    return 1;
}

public OnVehicleMod(playerid, vehicleid, componentid) {
    return 1;
}

public OnVehiclePaintjob(playerid, vehicleid, paintjobid) {
    return 1;
}

public OnVehicleRespray(playerid, vehicleid, color1, color2) {
    return 1;
}

public OnPlayerSelectedMenuRow(playerid, row) {
    return 1;
}

public OnPlayerExitedMenu(playerid) {
    return 1;
}

public OnPlayerInteriorChange(playerid, newinteriorid, oldinteriorid) {
    return 1;
}

public OnPlayerKeyStateChange(playerid, newkeys, oldkeys) {
    if (newkeys == KEY_YES) { //Pressed Y
        if (IsPlayerInRangeOfPoint(playerid, 3.0, -401.6756, -1419.5562, 26.0881)) {
            new job[64];
            if (!strcmp(PlayerInfo[playerid][pJob], "None")) {
                strcat(job, "Farmer", sizeof(job));
                PlayerInfo[playerid][pJob] = job;
                SetPlayerSkin(playerid, 161);
                SendClientMessage(playerid, -1, "{1ac4ba}JOB: {ffffff}Your job is now a Farmer.");
                JobStage[playerid] = 0;
            } else {
                SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}You are already hired!");
            }
        }
    } else if(newkeys == KEY_NO) // PRESSED N
    {
        for(new i = 1; i <= MAX_RENTS; i++)
        {
            if(IsPlayerInRangeOfPoint(playerid, 2.0, RentsInfo[i][rX], RentsInfo[i][rY]+2, RentsInfo[i][rZ]-0.7))
            {
                ShowPlayerDialog(playerid, dialogRentOptions, DIALOG_STYLE_TABLIST, "Rent Options", "Mountain Bike\t$10\nFaggio\t$50\nSanchez\t$100\nPremier\t$200", "Choose", "Cancel");
                break;
            }
        }
    }
    return 1;
}

public OnRconLoginAttempt(ip[], password[], success) {
    return 1;
}

public OnPlayerUpdate(playerid) {
    return 1;
}

public OnPlayerStreamIn(playerid, forplayerid) {
    return 1;
}

public OnPlayerStreamOut(playerid, forplayerid) {
    return 1;
}

public OnVehicleStreamIn(vehicleid, forplayerid) {
    return 1;
}

public OnVehicleStreamOut(vehicleid, forplayerid) {
    return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[]) {
    switch (dialogid) {
        case dialogRentOptions:
        {
            if(!response) return 1;
            if(renting[playerid] != -1) return ErrorMessage(playerid, "You are already renting a vehicle! Use /unrent to stop renting the vehicle.");
            new Float:X, Float:Y, Float:Z;
            GetPlayerPos(playerid, X, Y, Z);
            switch(listitem)
            {
                case 0: //Mountain bike
                {
                    if(PlayerInfo[playerid][pMoney] < 10) return ErrorMessage(playerid, "You don't have enough money to rent this vehicle!");
                    renting[playerid] = CreateVehicle(510, X, Y+2, Z+0.5, 0, 1, 1, -1);
                    TakeMoney(playerid, 10);
                }
                case 1: //Faggio
                {
                    if(PlayerInfo[playerid][pMoney] < 50) return ErrorMessage(playerid, "You don't have enough money to rent this vehicle!");
                    renting[playerid] = CreateVehicle(462, X, Y+2, Z+0.5, 0, 1, 1, -1);
                    TakeMoney(playerid, 50);
                }
                case 2: //Sanchez
                {
                    if(PlayerInfo[playerid][pMoney] < 100) return ErrorMessage(playerid, "You don't have enough money to rent this vehicle!");
                    renting[playerid] = CreateVehicle(468, X, Y+2, Z+0.5, 0, 1, 1, -1);
                    TakeMoney(playerid, 100);
                }
                case 3: //Premier
                {
                    if(PlayerInfo[playerid][pMoney] < 200) return ErrorMessage(playerid, "You don't have enough money to rent this vehicle!");
                    renting[playerid] = CreateVehicle(426, X, Y+2, Z+0.5, 0, 1, 1, -1);
                    TakeMoney(playerid, 200);
                }
            }
            InfoMessage(playerid, "Successfully rented a vehicle for 10 minuntes.");
            rentTimer[playerid] = 600;
        }
        case dialogQuestion:  {
            if (!response) {
                QuestionInfo[answeringQuestion[playerid]][qOpened] = false;
                for (new i = 0; i < MAX_PLAYERS; i++) {
                    if (PlayerInfo[i][pAdmin] > 0) {
                        SendClientMessage(i, -1, "{1ac42b}INFO: {ffffff}A new question has been asked. Use /question to answer it.");
                    }
                }
                answeringQuestion[playerid] = 0;
                return 1;
            }
            if (IsPlayerConnected(QuestionInfo[answeringQuestion[playerid]][qFromID]) && !strcmp(QuestionInfo[answeringQuestion[playerid]][qFrom], GetName(QuestionInfo[answeringQuestion[playerid]][qFromID]))) {
                new str[128];
                format(str, sizeof(str), "{1ac42b}ASKQ: {ffffff}You've answered %s's question.", QuestionInfo[answeringQuestion[playerid]][qFrom]);
                SendClientMessage(playerid, -1, str);

                format(str, sizeof(str), "{1ac42b}ASKQ: {ffffff}%s.", inputtext);
                SendClientMessage(QuestionInfo[answeringQuestion[playerid]][qFromID], -1, str);

            } else {
                SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}That player isn't online!");
            }
            QuestionInfo[answeringQuestion[playerid]][qID] = 0;
            QuestionInfo[answeringQuestion[playerid]][qOpened] = false;
            numberOfQuestions--;
            answeringQuestion[playerid] = 0;
        }
        case dialogAdminCode:  {
            if (!response) return Kick(playerid);
            if (PlayerInfo[playerid][pAdminCode] != strval(inputtext)) return ShowPlayerDialog(playerid, dialogAdminCode, DIALOG_STYLE_PASSWORD, "Admin Login", "{ff0000}Admin Code Isn't Correct!\n{ffffff}Type your Admin Code to verify.", "Login", "Quit");
            new query[128];
            mysql_format(SQL, query, sizeof(query), "SELECT * FROM `players` WHERE `Username` = '%e'", GetName(playerid));
            mysql_tquery(SQL, query, "LoadAccount", "i", playerid);
            TogglePlayerSpectating(playerid, false);

            SetSpawnInfo(playerid, 0, PlayerInfo[playerid][pSkin], 1731.6658, -1912.0126, 13.5625, 84.0176, 0, 0, 0, 0, 0, 0);
            SpawnPlayer(playerid);

            SendClientMessage(playerid, -1, "{1ac42b}Welcome to the Server, Have a Great Time!");
            logged[playerid] = true;
        }
        case dialogRegister:  {
            //Register
            if (!response) return Kick(playerid);
            if (strlen(inputtext) < 3) return ShowPlayerDialog(playerid, dialogRegister, DIALOG_STYLE_INPUT, "Register", "{ff0000}The Password Is Too Short!\nType any password to create a new account.", "Next", "Quit");
            PlayerInfo[playerid][pPassword] = udb_hash(inputtext);
            ShowPlayerDialog(playerid, dialogEmail, DIALOG_STYLE_INPUT, "Email", "Type your E-Mail Address.", "Next", "Quit");
        }
        case dialogLogin:  {
            //Login
            if (!response) return Kick(playerid);
            if (udb_hash(inputtext) != PlayerInfo[playerid][pPassword]) return ShowPlayerDialog(playerid, dialogLogin, DIALOG_STYLE_PASSWORD, "Login", "{ff0000}The Password Is Incorrect!\nType your password to login into your account.", "Login", "Quit");
            if (PlayerInfo[playerid][pAdmin] > 0) return ShowPlayerDialog(playerid, dialogAdminCode, DIALOG_STYLE_PASSWORD, "Admin Login", "Type your Admin Code to verify.", "Login", "Quit");
            new query[128];
            mysql_format(SQL, query, sizeof(query), "SELECT * FROM `players` WHERE `Username` = '%e'", GetName(playerid));
            mysql_tquery(SQL, query, "LoadAccount", "i", playerid);
            TogglePlayerSpectating(playerid, false);

            SetSpawnInfo(playerid, 0, PlayerInfo[playerid][pSkin], 1731.6658, -1912.0126, 13.5625, 84.0176, 0, 0, 0, 0, 0, 0);
            SpawnPlayer(playerid);

            SendClientMessage(playerid, -1, "{1ac42b}Welcome to the Server, Have a Great Time!");
            RequiredXP[playerid] = PlayerInfo[playerid][pLevel] * 2 + 4;
            logged[playerid] = true;
        }
        case dialogEmail:  {
            if (!response) return Kick(playerid);
            if (strlen(inputtext) < 12) return ShowPlayerDialog(playerid, dialogEmail, DIALOG_STYLE_INPUT, "Email", "{ff0000}The E-Mail Address Is Invalid!\nType your E-Mail Address.", "Next", "Quit");
            new email[25];
            strcat(email, inputtext, sizeof(email));
            PlayerInfo[playerid][pEmail] = email;
            ShowPlayerDialog(playerid, dialogGender, DIALOG_STYLE_MSGBOX, "Gender", "Choose Your Gender.", "Male", "Female");
        }
        case dialogGender:  {
            if (response) {
                PlayerInfo[playerid][pGender] = true; // Male
                PlayerInfo[playerid][pSkin] = 26;
            } else {
                PlayerInfo[playerid][pGender] = false; // Female
                PlayerInfo[playerid][pSkin] = 12;
            }

            SavePlayer(playerid);
            ShowPlayerDialog(playerid, dialogLogin, DIALOG_STYLE_PASSWORD, "Login", "Type your password to login into your account.", "Login", "Quit");
        }
    }
    return 1;
}

public OnPlayerClickPlayer(playerid, clickedplayerid, source) {
    new str[128];
    format(str, sizeof(str), "{1ac42b}Player:{ffffff} %s\n{1ac42b}PayDay:{ffffff} %dmin\n{1ac42b}XP: {ffffff}%d/%d", GetName(clickedplayerid), PlayerInfo[clickedplayerid][pPayDay], PlayerInfo[clickedplayerid][pXP], RequiredXP[clickedplayerid]);
    ShowPlayerDialog(playerid, dialogPlayerInfo, DIALOG_STYLE_MSGBOX, "Player Info", str, "Ok", "");
    return 1;
}

public OnPlayerEditObject(playerid, playerobject, objectid, response, Float:fX, Float:fY, Float:fZ, Float:fRotX, Float:fRotY, Float:fRotZ)
{
    if(rentEditID[playerid] != -1 && response != EDIT_RESPONSE_UPDATE)
    {
        new id = rentEditID[playerid];
        RentsInfo[id][rX] = fX;
        RentsInfo[id][rY] = fY;
        RentsInfo[id][rZ] = fZ;
        RentsInfo[id][rAngle] = fRotZ;
        RentsInfo[id][rBuilt] = true; 
        rentPickup[id] = CreatePickup(1318, 1, RentsInfo[id][rX], RentsInfo[id][rY]+2, RentsInfo[id][rZ]-0.7, 0);
        rentText[id] = Create3DTextLabel("{1ac42b}[RENT]\n{ffffff}'N'", -1, RentsInfo[id][rX], RentsInfo[id][rY]+2, RentsInfo[id][rZ]-0.7, 10.0, 0, 0);
        SaveRent(id);
        rentEditID[playerid] = -1;
    }
    return 1;
}

// ------ Commands -------
CMD:unrent(playerid)
{
    if(renting[playerid] == -1) return ErrorMessage(playerid, "You don't rent a vehicle!");
    DestroyVehicle(renting[playerid]);
    DeletePlayer3DTextLabel(playerid, rentTimerTL[playerid]);
    rentTimer[playerid] = 0;
    renting[playerid] = -1;
    InfoMessage(playerid, "You stopped renting the vehicle.");
    return 1;
}
CMD:createrent(playerid)
{
    if(PlayerInfo[playerid][pAdmin] < 250) return 0;
    if(numberOfRents == MAX_RENTS) return ErrorMessage(playerid, "The maximum amount of rents is reached, you can't create anymore rents!");
    if(IsPlayerInAnyVehicle(playerid)) return ErrorMessage(playerid, "You can't be in a vehicle!");

    new Float:X, Float:Y, Float:Z, id;
    GetPlayerPos(playerid, X, Y, Z);
    id = getUnusedRentID();
    if(id == -1) return ErrorMessage(playerid, "The maximum amount of rents is reached, you can't create anymore rents!");

    rentObj[id] = CreateObject(4642, X+2, Y, Z, 0.0, 0.0, 0.0);
    rentEditID[playerid] = id;
    RentsInfo[id][rX] = X+2;
    RentsInfo[id][rY] = Y;
    RentsInfo[id][rZ] = Z;
    RentsInfo[id][rBuilt] = false;
    EditObject(playerid, rentObj[id]);
    InfoMessage(playerid, "You are creating a rent.");
    return 1;
}
CMD:kill(playerid, params[])
{
    if(PlayerInfo[playerid][pAdmin] < 2) return 0;
    new player;
    if(sscanf(params, "u", player)) return UsageMessage(playerid, "/kill [Player ID]");
    if(!logged[player]) return ErrorMessage(playerid, "That player isn't online!");
    SetPlayerHealth(player, 0);
    new str[128];
    SendClientMessage(player, -1, "{8788ff}Admin has set your health to 0");
    format(str, sizeof(str), "%s's health set to 0.", GetName(player));
    SendClientMessage(playerid, -1, str);
    return 1;
}
CMD:b(playerid, params[])
{
    new Float:X, Float:Y, Float:Z, msg[256];
    GetPlayerPos(playerid, X, Y, Z);
    if(sscanf(params,  "s[256]", msg)) return UsageMessage(playerid, "/b [Message]");
    new text[256];
    format(text, sizeof(text), "{7DDA58}(( %s )) %s", GetName(playerid), msg);
    SendMess(8.0, X, Y, Z, text);
    return 1;
}
CMD:msg(playerid, params[])
{
    if(PlayerInfo[playerid][pAdmin] == 0) return 0;
    new player, msg[128], str[256];
    if(sscanf(params, "us[128]", player, msg)) return UsageMessage(playerid, "/msg [Player ID] [Message]");
    if(!logged[player]) return ErrorMessage(playerid, "That player isn't online!");
    if(strlen(msg) > 128) return ErrorMessage(playerid, "The message is too long!");
    format(str, sizeof(str), "{1ac42b}MSG: {ffffff}%s", msg);
    SendClientMessage(player, -1, str);
    SendClientMessage(playerid, -1, str);
    return 1;
}
CMD:jetpack(playerid, params[])
{
    if(PlayerInfo[playerid][pAdmin] < 2) return 0;
    if(GetPlayerSpecialAction(playerid) == SPECIAL_ACTION_USEJETPACK)
    {
        new Float:X, Float:Y, Float:Z;
        GetPlayerPos(playerid, X, Y, Z);
        SetPlayerPos(playerid, X, Y, Z);
        SendClientMessage(playerid, -1, "{8788ff}You've unequiped the jetpack");
    } else {
        SetPlayerSpecialAction(playerid, SPECIAL_ACTION_USEJETPACK);
        SendClientMessage(playerid, -1, "{8788ff}You've equiped a jetpack");
    }
    return 1;
}
CMD:setskin(playerid, params[])
{
    if(PlayerInfo[playerid][pAdmin] < 250) return 0;
    new player, skin;
    if(sscanf(params, "ud", player, skin)) return UsageMessage(playerid, "/setskin [Player ID] [Skin ID]");
    if(!logged[player]) return ErrorMessage(playerid, "That player isn't online!");
    if(skin < 0 || skin > 311) return ErrorMessage(playerid, "The Skin ID can't be lower than 0 or higher than 311!");
    SetPlayerSkin(player, skin);
    PlayerInfo[player][pSkin] = skin;
    SavePlayer(player);
    new str[128];
    format(str, sizeof(str), "{1ac42b}INFO: {ffffff}Admin %s has chaged your skin.", GetName(playerid));
    SendClientMessage(player, -1, str);
    format(str, sizeof(str), "{1ac42b}INFO: {ffffff}You've sucessfully changed %s's skin.", GetName(player));
    SendClientMessage(playerid, -1, str);
    return 1;
}
CMD:setstat(playerid, params[])
{
    if(PlayerInfo[playerid][pAdmin] < 250) return 0;
    new player, stat, value[128];
    if(sscanf(params, "uds[128]", player, stat, value)) 
    { 
        UsageMessage(playerid, "/setstat [Player ID] [Stat ID] [Value]");
        SendClientMessage(playerid, -1, "{8788ff}Stat IDs: [1] Job | [2] AskqCooldown | [3] E-Mail | [4] Admin Code | [5] PayDay | [6] XP | [7] Gender");
        return 1;
    }
    if(!logged[player]) return ErrorMessage(playerid, "That player isn't online!");
    if(stat < 1 || stat > 7) return ErrorMessage(playerid, "That Stat ID doesn't exist!");
    if(PlayerInfo[playerid][pAdmin] < PlayerInfo[player][pAdmin]) return ErrorMessage(playerid, "You can't change stat level on players with higher admin level than yours!");
    new change[256];
    switch(stat)
    {
        case 1:
        {
            new job[64];
            format(job, 64, value);
            PlayerInfo[player][pJob] = job;
            format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your Job to %s.", GetName(playerid), value);
        }
        case 2:
        {
            if(strval(value) < 0) return ErrorMessage(playerid, "The value can't be less than 0!");
            askqCooldown[player] = strval(value);
            format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your Askq Cooldown to %d seconds.", GetName(playerid), strval(value));
            
        }
        case 3:
        {
            new email[25];
            format(email, 25, value);
            PlayerInfo[player][pEmail] = email;
            format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your Email to %s.", GetName(playerid), value);
        }
        case 4:
        {
            if(strval(value) != 0 && strval(value) < 1000 || strval(value) > 9999) return ErrorMessage(playerid, "Value has to be 0 or between 1000 and 9999!");
            PlayerInfo[player][pAdminCode] = strval(value);
            format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your Admin Code to %d.", GetName(playerid), strval(value));
            
        }
        case 5:
        {
            if(strval(value) < 0) return ErrorMessage(playerid, "The value can't be less than 0");
            PlayerInfo[player][pPayDay] = strval(value);
            format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your PayDay to %d.", GetName(playerid), strval(value));
            
        }
        case 6:
        {
            if(strval(value) < 0) return ErrorMessage(playerid, "The value can't be less than 0");
            PlayerInfo[player][pXP] = strval(value);
            format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your XP to %d.", GetName(playerid), strval(value));
            
        }
        case 7:
        {
            if(strval(value) != 0 && strval(value) != 1) return ErrorMessage(playerid, "The value can only be 0(F) or 1(M)");
            if(strval(value) == 0) {
                PlayerInfo[player][pGender] = false;
                format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your Gender to Female.", GetName(playerid));
            } else {
                PlayerInfo[player][pGender] = true;
                format(change, sizeof(change), "{1ac42b}INFO: {ffffff}Admin %s has changed your Gender to Male.", GetName(playerid));
            }
        }
    }
    SendClientMessage(player, -1, change);
    SendClientMessage(playerid, -1, change);
    SavePlayer(player);
    return 1;
}
CMD:question(playerid, params[]) {
    if (PlayerInfo[playerid][pAdmin] == 0) return 0;
    if (numberOfQuestions == 0) return SendClientMessage(playerid, -1, "{1ac42b}There aren't any questions.");
    new str[512];
    new questions;
    for (new i = 1; i <= MAX_QUESTIONS; i++) {
        if (QuestionInfo[i][qID] != 0) {
            if (!QuestionInfo[i][qOpened]) {
                format(str, sizeof(str), "{1ac42b}From: {ffffff}%s\n{1ac42b}Question: {ffffff}%s\nAnswer their question in the box below", QuestionInfo[i][qFrom], QuestionInfo[i][qMessage]);
                ShowPlayerDialog(playerid, dialogQuestion, DIALOG_STYLE_INPUT, "Question", str, "Answer", "Close");
                answeringQuestion[playerid] = i;
                QuestionInfo[i][qOpened] = true;
                break;
            } else {
                questions++;
                if (questions == numberOfQuestions) {
                    SendClientMessage(playerid, -1, "{1ac42b}There aren't any questions.");
                    break;
                }
            }
        }
    }
    return 1;
}
CMD:askq(playerid, params[]) {
    new str[128];
    format(str, sizeof(str), "{ff0000}ERROR: {ffffff}You can't ask a question for {ff0000}%d {ffffff}more seconds.", askqCooldown[playerid]);
    if (askqCooldown[playerid] > 0) return SendClientMessage(playerid, -1, str);
    new msg[256];
    if (sscanf(params, "s[256]", msg)) return SendClientMessage(playerid, -1, "{ffff00}USAGE: {ffffff}/askq [Question]");
    if (strlen(msg) > 256) return SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}Your question is too long!");
    if (strlen(msg) < 4) return SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}Your question can't be empty!");
    for (new i = 1; i <= MAX_QUESTIONS; i++) {
        if (QuestionInfo[i][qID] == 0) {
            QuestionInfo[i][qID] = i;
            QuestionInfo[i][qFrom] = GetName(playerid);
            QuestionInfo[i][qFromID] = playerid;
            QuestionInfo[i][qMessage] = msg;
            QuestionInfo[i][qOpened] = false;
            numberOfQuestions++;
            askqCooldown[playerid] = 300;
            SendClientMessage(playerid, -1, "{1ac42b}INFO: {ffffff}Successfully sent a question to the admins.");
            for (new j = 0; j < MAX_PLAYERS; j++) {
                if (PlayerInfo[j][pAdmin] > 0) {
                    SendClientMessage(j, -1, "{1ac42b}INFO: {ffffff}A new question has been asked. Use /question to answer it.");
                }
            }
            break;
        }
    }
    return 1;
}
CMD:giveadmin(playerid, params[]) {
    if (!IsPlayerAdmin(playerid) && PlayerInfo[playerid][pAdmin] != 255) return 1;
    new level, player;
    if (sscanf(params, "ud", player, level)) return SendClientMessage(playerid, -1, "{ffff00}Usage: {ffffff}/giveadmin [Player] [Level]");
    if (!IsPlayerConnected(playerid)) return SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}That player isn't online!");
    if (level < 0 || level > 255) return SendClientMessage(playerid, -1, "{ff0000}ERROR: {ffffff}Admin Level has to be between 0 and 255");

    if (PlayerInfo[player][pAdmin] == 0)
        PlayerInfo[player][pAdminCode] = RandomInRange(1000, 9999);

    PlayerInfo[player][pAdmin] = level;
    if (level == 0)
        PlayerInfo[playerid][pAdminCode] = 0;
    SavePlayer(playerid);

    new msg[256];
    format(msg, sizeof(msg), "{1ac42b}INFO: {ffffff}Succesffully set Admin Level %d to %s", level, GetName(player));
    SendClientMessage(playerid, -1, msg);
    format(msg, sizeof(msg), "{1ac42b}INFO: {ffffff}Admin %s set your Admin Level to %d, Congratulations!", GetName(playerid), level);
    SendClientMessage(player, -1, msg);
    format(msg, sizeof(msg), "{ff0000}IMPORTANT: {ffffff}Your Admin Code is %d, screenshot it, you will need it when you are logging in!", PlayerInfo[playerid][pAdminCode]);
    SendClientMessage(player, -1, msg);
    return 1;
}

CMD:veh(playerid, params[]) {
    if(PlayerInfo[playerid][pAdmin] < 5) return 0;
    new Float:X, Float:Y, Float:Z, vehicle, model, color1, color2;
    if(sscanf(params, "ddd", model, color1, color2)) return UsageMessage(playerid, "/veh [Model ID] [Color 1] [Color 2]");
    GetPlayerPos(playerid, X, Y, Z);
    vehicle = CreateVehicle(model, X + 2, Y, Z, 0.0, color1, color2, -1);
    PutPlayerInVehicle(playerid, vehicle, 0);
    SendClientMessage(playerid, -1, "{8788ff}You've sucessfully spawned a vehicle!");
    return 1;
}

// ------ Forwards ------
forward CheckRent(id);
public CheckRent(id)
{
    if(cache_num_rows())
    {
        rentExistsInDatabase[id] = true;
    } else {
        rentExistsInDatabase[id] = false;
    }
    return 1;
}
forward LoadRent(id);
public LoadRent(id)
{
    rentsLoaded++;
    if(cache_num_rows())
    {
        cache_get_value_int(0, "ID", RentsInfo[id][rID]);
        cache_get_value_float(0, "X", RentsInfo[id][rX]);
        cache_get_value_float(0, "Y", RentsInfo[id][rY]);
        cache_get_value_float(0, "Z", RentsInfo[id][rZ]);
        cache_get_value_float(0, "Angle", RentsInfo[id][rAngle]);
        RentsInfo[id][rBuilt] = true;
        numberOfRents++;
    }

    if(rentsLoaded == MAX_RENTS)
    {
        for(new i = 1; i <=MAX_RENTS; i++)
        {
            if(!RentsInfo[i][rBuilt]) continue;
            rentObj[i] = CreateObject(4642, RentsInfo[i][rX], RentsInfo[i][rY], RentsInfo[i][rZ], 0.0, 0.0, RentsInfo[i][rAngle]);
            rentPickup[i] = CreatePickup(1318, 1, RentsInfo[i][rX], RentsInfo[i][rY]+2, RentsInfo[i][rZ]-0.7, 0);
            rentText[i] = Create3DTextLabel("{1ac42b}[RENT]\n{ffffff}'N'", -1, RentsInfo[i][rX], RentsInfo[i][rY]+2, RentsInfo[i][rZ]-0.7, 10.0, 0, 0);
        }
    }
    return 1;
}

forward CheckAccount(playerid);
public CheckAccount(playerid) {
    if (cache_num_rows() > 0) {
        cache_get_value_int(0, "Password", PlayerInfo[playerid][pPassword]);
        cache_get_value_int(0, "Admin", PlayerInfo[playerid][pAdmin]);
        cache_get_value_int(0, "AdminCode", PlayerInfo[playerid][pAdminCode]);
        ShowPlayerDialog(playerid, dialogLogin, DIALOG_STYLE_PASSWORD, "Login", "Type your password to login into your account.", "Login", "Quit");
    } else {
        ShowPlayerDialog(playerid, dialogRegister, DIALOG_STYLE_INPUT, "Register", "Type any password to create a new account.", "Next", "Quit");
    }
    return 1;
}

forward LoadAccount(playerid);
public LoadAccount(playerid) {
    cache_get_value_int(0, "ID", PlayerInfo[playerid][sID]);
    cache_get_value_int(0, "Money", PlayerInfo[playerid][pMoney]);
    cache_get_value_int(0, "Level", PlayerInfo[playerid][pLevel]);
    cache_get_value_int(0, "Skin", PlayerInfo[playerid][pSkin]);
    cache_get_value_int(0, "Inactivity", PlayerInfo[playerid][pInactivity]);
    cache_get_value_int(0, "PayDay", PlayerInfo[playerid][pPayDay]);
    cache_get_value_int(0, "XP", PlayerInfo[playerid][pXP]);
    cache_get_value_bool(0, "Gender", PlayerInfo[playerid][pGender]);
    cache_get_value_name(0, "Email", PlayerInfo[playerid][pEmail], 25);
    cache_get_value_name(0, "Job", PlayerInfo[playerid][pJob], 64);
    return 1;
}
// ----- Functions ------
getUnusedRentID()
{
    new id = -1, bool:token = false;

    for(new i = 1; i <= MAX_RENTS; i++)
    {
        if(!RentsInfo[i][rBuilt])
        {
            for(new p = 0; p < MAX_PLAYERS; p++)
            {
                if(rentEditID[p] == i)
                {
                    token = true;
                    break;
                }
            }
            if(token == false)
            {
                id = i;
                break;
            }
            token = false;
        }
    }
    return id;
}
// ----- Stock -------
stock SaveRent(id)
{
    new query[256], checkQuery[128];
    mysql_format(SQL, checkQuery, sizeof(checkQuery), "SELECT * FROM `rents` WHERE `ID` = '%d'", id);
    mysql_tquery(SQL, checkQuery, "CheckRent","d", id);
    if(!rentExistsInDatabase[id])
    {
        mysql_format(SQL, query, sizeof(query), "INSERT INTO `rents` (`X`, `Y`, `Z`, `Angle`) VALUES ('%f','%f','%f','%f')",\
        RentsInfo[id][rX],RentsInfo[id][rY],RentsInfo[id][rZ],RentsInfo[id][rAngle]);
    } else {
        mysql_format(SQL, query, sizeof(query), "UPDATE `rents` SET `X` = '%f', `Y` = '%f', `Z` = '%f', `Angle` = '%f' WHERE `ID` = '%d'",\
        RentsInfo[id][rX],RentsInfo[id][rY],RentsInfo[id][rZ],RentsInfo[id][rAngle], RentsInfo[id][rID]);
    }
    mysql_query(SQL, query);
}
stock SendMess(Float:range, Float:X, Float:Y, Float:Z, text[])
{
    for(new playerid = 0; playerid < MAX_PLAYERS; playerid++)
    {
        if(IsPlayerInRangeOfPoint(playerid, range, X, Y, Z))
        {
            SendClientMessage(playerid, -1, text);
        }
    }
}
stock ErrorMessage(playerid, message[])
{
    new str[128];
    format(str, sizeof(str), "{ff0000}ERROR: {ffffff}%s", message);
    SendClientMessage(playerid, -1, str);
    return 1;
}
stock UsageMessage(playerid, message[])
{
    new str[128];
    format(str, sizeof(str), "{ffff00}USAGE: {ffffff}%s", message);
    SendClientMessage(playerid, -1, str);
    return 1;
}
stock InfoMessage(playerid, message[])
{
    new str[128];
    format(str, sizeof(str), "{1ac42b}INFO: {ffffff}%s", message);
    SendClientMessage(playerid, -1, str);
    return 1;
}

stock GiveMoney(playerid, amount)
{
    GivePlayerMoney(playerid, amount);
    PlayerInfo[playerid][pMoney] += amount;
    SavePlayer(playerid);
}
stock TakeMoney(playerid, amount)
{
    GivePlayerMoney(playerid, -amount);
    PlayerInfo[playerid][pMoney] -= amount;
    SavePlayer(playerid);
}
stock ResetMoney(playerid, amount)
{
    ResetPlayerMoney(playerid);
    GivePlayerMoney(playerid, amount);
    PlayerInfo[playerid][pMoney] = amount;
    SavePlayer(playerid);
}

stock ShowEssentialTD(playerid) {
    TextDrawShowForPlayer(playerid, ServerTD[0]);
    TextDrawShowForPlayer(playerid, ServerTD[1]);
    TextDrawShowForPlayer(playerid, ServerTD[2]);
    TextDrawShowForPlayer(playerid, ServerTD[3]);
    TextDrawShowForPlayer(playerid, ServerTD[4]);

    PlayerTextDrawShow(playerid, InfoPTD[playerid][0]);
    PlayerTextDrawShow(playerid, InfoPTD[playerid][1]);
}

stock CreatePTD(playerid) {

    InfoPTD[playerid][0] = CreatePlayerTextDraw(playerid, 548.333496, 122.385147, "Gold:_0g");
    PlayerTextDrawLetterSize(playerid, InfoPTD[playerid][0], 0.262666, 1.670518);
    PlayerTextDrawAlignment(playerid, InfoPTD[playerid][0], 1);
    PlayerTextDrawColor(playerid, InfoPTD[playerid][0], 255);
    PlayerTextDrawSetShadow(playerid, InfoPTD[playerid][0], 0);
    PlayerTextDrawBackgroundColor(playerid, InfoPTD[playerid][0], 255);
    PlayerTextDrawFont(playerid, InfoPTD[playerid][0], 2);
    PlayerTextDrawSetProportional(playerid, InfoPTD[playerid][0], 1);

    InfoPTD[playerid][1] = CreatePlayerTextDraw(playerid, 548.333496, 137.585647, "Bank:_$100");
    PlayerTextDrawLetterSize(playerid, InfoPTD[playerid][1], 0.262666, 1.670518);
    PlayerTextDrawAlignment(playerid, InfoPTD[playerid][1], 1);
    PlayerTextDrawColor(playerid, InfoPTD[playerid][1], 255);
    PlayerTextDrawSetShadow(playerid, InfoPTD[playerid][1], 0);
    PlayerTextDrawBackgroundColor(playerid, InfoPTD[playerid][1], 255);
    PlayerTextDrawFont(playerid, InfoPTD[playerid][1], 2);
}

stock CreateTD() {

    ServerTD[0] = TextDrawCreate(-0.000038, 447.859375, "LD_SPAC:white");
    TextDrawTextSize(ServerTD[0], 642.000000, -17.000000);
    TextDrawAlignment(ServerTD[0], 1);
    TextDrawColor(ServerTD[0], -106);
    TextDrawSetShadow(ServerTD[0], 0);
    TextDrawBackgroundColor(ServerTD[0], 255);
    TextDrawFont(ServerTD[0], 4);
    TextDrawSetProportional(ServerTD[0], 0);

    ServerTD[1] = TextDrawCreate(3.000002, 431.007629, "M3CK4_Tutorial");
    TextDrawLetterSize(ServerTD[1], 0.292333, 1.691259);
    TextDrawAlignment(ServerTD[1], 1);
    TextDrawColor(ServerTD[1], 255);
    TextDrawSetShadow(ServerTD[1], 0);
    TextDrawBackgroundColor(ServerTD[1], 255);
    TextDrawFont(ServerTD[1], 3);
    TextDrawSetProportional(ServerTD[1], 1);

    ServerTD[2] = TextDrawCreate(612.999755, 431.422088, "00:00");
    TextDrawLetterSize(ServerTD[2], 0.400000, 1.600000);
    TextDrawAlignment(ServerTD[2], 2);
    TextDrawColor(ServerTD[2], 255);
    TextDrawSetShadow(ServerTD[2], 0);
    TextDrawBackgroundColor(ServerTD[2], 255);
    TextDrawFont(ServerTD[2], 2);
    TextDrawSetProportional(ServerTD[2], 1);

    ServerTD[3] = TextDrawCreate(317.999969, 430.592620, "Random_Text");
    TextDrawLetterSize(ServerTD[3], 0.400000, 1.600000);
    TextDrawAlignment(ServerTD[3], 2);
    TextDrawColor(ServerTD[3], 255);
    TextDrawSetShadow(ServerTD[3], 0);
    TextDrawBackgroundColor(ServerTD[3], 255);
    TextDrawFont(ServerTD[3], 1);
    TextDrawSetProportional(ServerTD[3], 1);

    ServerTD[4] = TextDrawCreate(545.666503, 118.081489, "LD_SPAC:white");
    TextDrawTextSize(ServerTD[4], 91.000000, 38.000000);
    TextDrawAlignment(ServerTD[4], 1);
    TextDrawColor(ServerTD[4], -1);
    TextDrawSetShadow(ServerTD[4], 0);
    TextDrawBackgroundColor(ServerTD[4], 255);
    TextDrawFont(ServerTD[4], 4);
    TextDrawSetProportional(ServerTD[4], 0);
}

stock RandomInRange(min, max) {
    new number;
    do {
        number = random(max);
    } while (number < min || number > max);
    return number;
}

stock udb_hash(const buf[]) {
    new length = strlen(buf);
    new s1 = 1;
    new s2 = 0;
    new n;
    for (n = 0; n < length; n++) {
        s1 = (s1 + buf[n]) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) + s1;
}

stock GetName(playerid) {
    new name[MAX_PLAYER_NAME];
    GetPlayerName(playerid, name, sizeof(name));
    return name;
}

stock SavePlayer(playerid) {
    new query[256], dest[1024];
    if (!registered[playerid] && !logged[playerid])
        mysql_format(SQL, dest, sizeof(dest), "INSERT INTO `players` (`Username`, `Password`, `Skin`, `Money`, `Level`, `Email`, `Gender`, `Job`, `PayDay`) VALUES ('%e','%d','%d','3600','1','%s','%d', 'None', '60')", \
            GetName(playerid), PlayerInfo[playerid][pPassword], PlayerInfo[playerid][pSkin], PlayerInfo[playerid][pEmail], PlayerInfo[playerid][pGender]);
    else {
        mysql_format(SQL, query, sizeof(query), "UPDATE `players` SET `Username` = '%e', `Password` = '%d', `Skin` = '%d', `Money` = '%d', `Level` = '%d',", GetName(playerid), PlayerInfo[playerid][pPassword], PlayerInfo[playerid][pSkin], PlayerInfo[playerid][pMoney], PlayerInfo[playerid][pLevel]);
        strcat(dest, query, sizeof(dest));
        mysql_format(SQL, query, sizeof(query), "`Email` = '%e', `Gender` = '%d', `Admin` = '%d', `AdminCode` = '%d', `Inactivity` = '%d', `Job` = '%e', `PayDay` = '%d', `XP` = '%d' WHERE `ID` = '%d' LIMIT 1", PlayerInfo[playerid][pEmail], PlayerInfo[playerid][pGender], PlayerInfo[playerid][pAdmin], PlayerInfo[playerid][pAdminCode], PlayerInfo[playerid][pInactivity], PlayerInfo[playerid][pJob], PlayerInfo[playerid][pPayDay], PlayerInfo[playerid][pXP], PlayerInfo[playerid][sID]);
        strcat(dest, query, sizeof(dest));
    }
    mysql_tquery(SQL, dest);
}

stock ResetAccount(playerid) {
    new example[25], none[64];
    strcat(example, "email@example.com", sizeof(example));
    strcat(none, "None", sizeof(none));
    registered[playerid] = false;
    PlayerInfo[playerid][sID] = -1;
    PlayerInfo[playerid][pSkin] = 1;
    PlayerInfo[playerid][pMoney] = 0;
    PlayerInfo[playerid][pLevel] = 0;
    PlayerInfo[playerid][pGender] = false;
    PlayerInfo[playerid][pEmail] = example;
    PlayerInfo[playerid][pAdmin] = 0;
    PlayerInfo[playerid][pAdminCode] = 0;
    PlayerInfo[playerid][pInactivity] = 0;
    PlayerInfo[playerid][pPayDay] = 0;
    PlayerInfo[playerid][pXP] = 0;
    PlayerInfo[playerid][pJob] = none;
    SetPlayerSkin(playerid, 1);
    SetPlayerScore(playerid, 0);
}
