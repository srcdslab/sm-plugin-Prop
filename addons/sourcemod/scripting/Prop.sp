/****************************************************************

	Credits to original authors: 
	Darkthrone, Greyscale, Twisted|Panda
	Roy (Christian Deacon), Doshik
	
	Remake by ire.
																 
****************************************************************/

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>

#pragma tabsize 0
#define MAXENTITIES 2048

enum struct Props
{
    char PropName[128];
	char PropPath[128];
	int PropPrice;
	int PropHP;
	int PropMaxHP;
}

Props PropData[MAXENTITIES +1];

char PropCommands[][] = {"sm_zprops", "sm_props", "sm_zprop", "sm_prop"};

int g_iPropAmount;
int g_iPropCredits[MAXPLAYERS +1];
int g_iRoundStartDelay;

bool g_bGivenCredits[MAXPLAYERS +1] = {false, ...};

ConVar g_cvPropsEnabled;
ConVar g_cvPropsEnabledRoundStart;
ConVar g_cvPropsEnabledRoundStartTime;
ConVar g_cvNadePropsEnabled;
ConVar g_cvKillCredits;
ConVar g_cvInfectCredits;
ConVar g_cvSpawnCredits;
ConVar g_cvRoundStartCredits;
ConVar g_cvMaxCredits;

StringMap g_smPropHP;
ArrayList g_arClientProps[MAXPLAYERS +1];

public Plugin myinfo =
{
	name = "[ZR] Props",
	author = "Darkthrone, Greyscale, Twisted|Panda, Roy (Christian Deacon), Doshik, ire",
	description  = "Buy props, show their health and more",
	version = "1.2",
};

public void OnPluginStart()
{
	for(int i = 0; i < sizeof(PropCommands); i++)
	{
		RegConsoleCmd(PropCommands[i], OpenPropMenu);
	}
	
	RegAdminCmd("sm_deleteprop", DeleteProp, ADMFLAG_BAN);
	RegAdminCmd("sm_getpropinfo", GetPropInfo, ADMFLAG_BAN);
	RegAdminCmd("sm_resetprop", ResetProp, ADMFLAG_BAN);
	RegAdminCmd("sm_zprop_credits", PropCredits, ADMFLAG_CONVARS);
	
	HookEvent("round_start", Event_RoundStart);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	g_cvPropsEnabled = CreateConVar("props_enabled", "1", "Enable or disable plugin");
	g_cvPropsEnabledRoundStart = CreateConVar("props_enabled_roundstart", "1", "Enable or disable props during round start");
	g_cvPropsEnabledRoundStartTime = CreateConVar("props_roundstarttime", "30", "How many seconds after round start enable props");
	g_cvNadePropsEnabled = CreateConVar("props_nades_enabled", "1", "Enable or disable grenade blast damage on friendly props");
	g_cvKillCredits = CreateConVar("props_credits_kill", "5", "Amount of credits for killing a zombie");
	g_cvInfectCredits = CreateConVar("props_credits_infect", "2", "Amount of credits for infecting a human");
	g_cvSpawnCredits = CreateConVar("props_credits_spawn", "1", "Amount of credits for a spawn");
	g_cvRoundStartCredits = CreateConVar("props_credits_roundstart", "2", "Amount of credits for a new round start");
	g_cvMaxCredits = CreateConVar("props_credits_max", "45", "Maximum amount of credits a player can have");
	AutoExecConfig(true);
	
	LoadTranslations("prop.phrases");
	LoadTranslations("common.phrases");
	
	g_smPropHP = new StringMap();	
}

public void OnMapStart()
{
	SetupPropMenu();
	SetupPropHealth();
}

public void OnMapEnd()
{
	g_smPropHP.Clear();
}

public void OnClientConnected(int client)
{
	g_arClientProps[client] = new ArrayList();
}

public void OnClientDisconnect(int client)
{
	g_iPropCredits[client] = 0;
	g_bGivenCredits[client] = false;
	g_arClientProps[client].Clear();
}

void SetupPropMenu()
{	
	g_iPropAmount = 0;
	
    char FilePath[128];
	BuildPath(Path_SM, FilePath, sizeof(FilePath), "configs/props.cfg");
	if(!FileExists(FilePath))
	{
		SetFailState("[ZP] Missing cfg file %s!", FilePath);
		return;
	}
	
	KeyValues Kv = new KeyValues("Props");
	Kv.ImportFromFile(FilePath);
	Kv.GotoFirstSubKey();
	do
	{
	    Kv.GetSectionName(PropData[g_iPropAmount].PropName, sizeof(PropData[].PropName)); 
		Kv.GetString("path", PropData[g_iPropAmount].PropPath, sizeof(PropData[].PropPath)); 
		PropData[g_iPropAmount].PropPrice = Kv.GetNum("price"); 
		g_iPropAmount++;
	}
	while(Kv.GotoNextKey());
	
	delete Kv;
}

void SetupPropHealth()
{
    char FilePath[128], KvModelPath[128];
	
	BuildPath(Path_SM, FilePath, sizeof(FilePath), "configs/prophp.cfg");
	if(!FileExists(FilePath))
	{
		SetFailState("[ZP] Missing cfg file %s!", FilePath);
		return;
	}
	
	KeyValues Kv = new KeyValues("Props");
	Kv.ImportFromFile(FilePath);
	Kv.GotoFirstSubKey();
	do
	{
	    Kv.GetSectionName(KvModelPath, sizeof(KvModelPath));
		{
			g_smPropHP.SetValue(KvModelPath, Kv.GetNum("health"));
		}
	}
	while Kv.GotoNextKey();
	
	delete Kv;	
}

public Action DeleteProp(int client, int args)
{
    int g_iTarget = GetClientAimTarget(client, false);
	
	if(IsValidEntity(g_iTarget))
	{
		char ClassName[64];
		GetEntityClassname(g_iTarget, ClassName, sizeof(ClassName));
		
		if(StrEqual(ClassName, "prop_physics", false) || StrEqual(ClassName, "prop_physics_multiplayer", false) || StrEqual(ClassName, "prop_physics_override", false))
		{
			RemoveProp(g_iTarget);
			CPrintToChat(client, "%t", "DeletedProp");
			return Plugin_Handled;
		}
		
		else
		{
			CPrintToChat(client, "%t", "FailToDeleteProp");
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;
}

public Action GetPropInfo(int client, int args)
{
    int g_iTarget = GetClientAimTarget(client, false);
	
	if(IsValidEntity(g_iTarget))
	{
	    char PropModel[128], ClassName[64];
        GetEntPropString(g_iTarget, Prop_Data, "m_ModelName", PropModel, sizeof(PropModel));
		GetEntityClassname(g_iTarget, ClassName, sizeof(ClassName));
		
		int g_iPropHealth = PropData[g_iTarget].PropHP;
        int g_iOwner = GetEntPropEnt(g_iTarget, Prop_Send, "m_PredictableID");
		
		if(g_iOwner > 0)
		{
			CPrintToChat(client, "%t", "GetPropInfo", PropModel, ClassName, g_iOwner, g_iPropHealth);
			return Plugin_Handled;
		}
		
		else
		{
		    CPrintToChat(client, "%t", "GetServerPropInfo", PropModel, ClassName, g_iPropHealth);
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;    
}

public Action ResetProp(int client, int args)
{
    int g_iTarget = GetClientAimTarget(client, false);
	
	if(IsValidEntity(g_iTarget))
	{
		char ClassName[64];
		GetEntityClassname(g_iTarget, ClassName, sizeof(ClassName));
		
		if(StrEqual(ClassName, "prop_physics", false) || StrEqual(ClassName, "prop_physics_multiplayer", false) || StrEqual(ClassName, "prop_physics_override", false))
		{
			int g_iOwner = GetEntPropEnt(g_iTarget, Prop_Send, "m_PredictableID");
			
			if(g_iOwner > 0)
			{
				SetEntPropEnt(g_iTarget, Prop_Send, "m_PredictableID", -1);
				CPrintToChat(client, "%t", "ResetedProp", g_iOwner);
				return Plugin_Handled;
			}
			
			else
			{
				CPrintToChat(client, "%t", "AlreadyServerProp");
				return Plugin_Handled;
			}
		}
		
		else
		{
			CPrintToChat(client, "%t", "FailToResetProp");
			return Plugin_Handled;
		}
	}
	
	return Plugin_Handled;
}

public Action PropCredits(int client, int args)
{
	if(args != 2)
	{
		CPrintToChat(client, "%t", "GiveCreditsUsage");
		return Plugin_Handled;
	}
	
	char arg1[64], arg2[16];
	
	GetCmdArg(1, arg1, sizeof(arg1));
	GetCmdArg(2, arg2, sizeof(arg2));
	
	int g_iCredits = StringToInt(arg2);
	
	if(g_iCredits <= 0)
	{
		return Plugin_Handled;
	}
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if((target_count = ProcessTargetString(arg1, client, target_list, MAXPLAYERS, COMMAND_FILTER_NO_BOTS, target_name, sizeof(target_name), tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for(int i = 0; i < target_count; i++)
	{
		g_iPropCredits[target_list[i]] += g_iCredits;
		g_bGivenCredits[target_list[i]] = true;
	}
	
	CPrintToChat(client, "%t", "GaveCredits", g_iCredits, target_name);
	
	return Plugin_Handled;
}

public Action OpenPropMenu(int client, int args)
{
	if(!IsValidClient(client)) 
	{
		return Plugin_Handled;
	}
	
	if(!g_cvPropsEnabled.BoolValue)
	{
		CPrintToChat(client, "%t", "PropsAreDisabled");
		return Plugin_Handled;
	}
	
	if(!g_cvPropsEnabledRoundStart.BoolValue)
	{
		if(g_iRoundStartDelay > GetTime())
		{
			CPrintToChat(client, "%t", "PropsRoundStart", g_iRoundStartDelay - GetTime());
			return Plugin_Handled;
		}
	}
	
    Menu PropMenu = new Menu(MenuHandle);
	char MenuTitle[128];
	Format(MenuTitle, sizeof(MenuTitle), "Available props: \nYour credits: %d", g_iPropCredits[client]);
	PropMenu.SetTitle(MenuTitle);
	char MenuBuffer[8], MenuBuffer2[128];
	for(int i = 0; i < g_iPropAmount; i++)
	{
	    IntToString(i, MenuBuffer, sizeof(MenuBuffer));
	    Format(MenuBuffer2, sizeof(MenuBuffer2), "%s $%d]", PropData[i].PropName, PropData[i].PropPrice);
		PropMenu.AddItem(MenuBuffer, MenuBuffer2, g_iPropCredits[client] >= PropData[i].PropPrice ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	}
	PropMenu.ExitButton = true;
	PropMenu.Display(client, 999);
	
	return Plugin_Handled;
}

public int MenuHandle(Menu menu, MenuAction action, int client, int choice)
{
    if(action == MenuAction_Select)
	{
	    char PropIndex[8];
	    menu.GetItem(choice, PropIndex, sizeof(PropIndex));
		CreateProp(client, StringToInt(PropIndex));
		OpenPropMenu(client, choice);
	}
	
    else if(action == MenuAction_End)
    {
        delete menu;
    }
}

void CreateProp(int client, int PropIndex)
{
    int g_iProp = CreateEntityByName("prop_physics_override");
	
	if(IsValidEntity(g_iProp))
	{
	    DispatchKeyValue(g_iProp, "model", PropData[PropIndex].PropPath);
		SetEntityMoveType(g_iProp, MOVETYPE_VPHYSICS);
		DispatchSpawn(g_iProp);
		
    	float fLocation[3], fAngles[3], fOrigin[3], fTemp[3];
		GetClientAbsOrigin(client, fLocation);
		GetClientAbsAngles(client, fAngles);
		GetClientEyeAngles(client, fTemp);
		fAngles[0] = fTemp[0];
		fLocation[2] += 50;
		AddProp(fLocation, fAngles, 35, fOrigin);
		TeleportEntity(g_iProp, fOrigin, NULL_VECTOR, NULL_VECTOR);
		
		g_iPropCredits[client] -= PropData[PropIndex].PropPrice;
		CPrintToChat(client, "%t", "PurchasedProp", PropData[PropIndex].PropName);
		SetEntPropEnt(g_iProp, Prop_Send, "m_PredictableID", client);
		
		g_arClientProps[client].Push(EntIndexToEntRef(g_iProp));
	}
}

void AddProp(float vecOrigin[3], float vecAngle[3], units, float output[3])
{
	float vecView[3];
	GetViewVector(vecAngle, vecView);
	output[0] = vecView[0] * units + vecOrigin[0];
	output[1] = vecView[1] * units + vecOrigin[1];
	output[2] = vecView[2] * units + vecOrigin[2];
}

void GetViewVector(float vecAngle[3], float output[3])
{
	output[0] = Cosine(vecAngle[1] / (180 / FLOAT_PI));
	output[1] = Sine(vecAngle[1] / (180 / FLOAT_PI));
	output[2] = -Sine(vecAngle[0] / (180 / FLOAT_PI));
}

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    for(int i = 1; i <= MaxClients; i++)
	{
	    if(IsValidClient(i))
		{
		    AddCredits(i, g_cvRoundStartCredits.IntValue);
		}
	}
	
	g_iRoundStartDelay = GetTime() + g_cvPropsEnabledRoundStartTime.IntValue;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
	int victim = GetClientOfUserId(event.GetInt("userid"));
	
	if(IsValidClient(attacker) && attacker != victim && GetClientTeam(attacker) == 3 && GetClientTeam(victim) == 2)
	{
	    AddCredits(attacker, g_cvKillCredits.IntValue);
		ResetProps(victim);
	}
	
	if(IsValidClient(attacker) && attacker != victim && GetClientTeam(attacker) == 2 && GetClientTeam(victim) == 3)
	{
	    AddCredits(attacker, g_cvInfectCredits.IntValue);
		ResetProps(victim);
	}
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
	
	if(IsValidClient(client))
	{
	    AddCredits(client, g_cvSpawnCredits.IntValue);
	}
}

void AddCredits(int client, int amount)
{
	g_iPropCredits[client] += amount;
	
	if(g_iPropCredits[client] < g_cvMaxCredits.IntValue)
	{
		PrintHintText(client, "%t", "CreditsForProps", amount);
	}
	
    else
    {
		if(!g_bGivenCredits[client])
		{
			g_iPropCredits[client] = g_cvMaxCredits.IntValue;
			PrintHintText(client, "%t", "ReachedMaxCredits");
		}
    }	
}

void ResetProps(int client)
{
	if(g_arClientProps[client].Length > 0)
	{
		for(int i = 0; i < g_arClientProps[client].Length; i++)
		{
			int g_iEntity = EntRefToEntIndex(g_arClientProps[client].Get(i));
			
			if(g_iEntity != INVALID_ENT_REFERENCE)
			{
				SetEntPropEnt(g_iEntity, Prop_Send, "m_PredictableID", -1);
			}
		}
		
		g_arClientProps[client].Clear();
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
    SDKHook(entity, SDKHook_SpawnPost, OnSpawnPost);
}

public void OnSpawnPost(int entity)
{
    char ClassName[64], PropModelPath[128];
	GetEntityClassname(entity, ClassName, sizeof(ClassName));
	
    if(StrEqual(ClassName, "prop_physics", false) || StrEqual(ClassName, "prop_physics_multiplayer", false) || StrEqual(ClassName, "prop_physics_override", false))
	{
		GetEntPropString(entity, Prop_Data, "m_ModelName", PropModelPath, sizeof(PropModelPath));
		
		int g_iPropHealth;
		
		if(g_smPropHP.GetValue(PropModelPath, g_iPropHealth))
		{
			PropData[entity].PropHP = g_iPropHealth;
			PropData[entity].PropMaxHP = g_iPropHealth;
		}
		
		else
		{
			PropData[entity].PropHP = 1337;
			PropData[entity].PropMaxHP = 1337;
		}
		
		SDKHook(entity, SDKHook_OnTakeDamage, OnTakeDamage);
	}
}

public Action OnTakeDamage(int entity, int& attacker, int& inflictor, float& damage, int& damagetype)
{
    int g_iOwner = GetEntPropEnt(entity, Prop_Send, "m_PredictableID");
	
	if(!IsValidClient(attacker))
	{
	    return Plugin_Continue;
	}
	
	if(attacker != g_iOwner && g_iOwner > 0)
	{
		if(!g_cvNadePropsEnabled.BoolValue && damagetype == DMG_BLAST)
		{
			if(GetClientTeam(g_iOwner) == 3)
			{
				return Plugin_Handled;
			}
		}
			
		if(GetClientTeam(attacker) == 3 && GetClientTeam(g_iOwner) == 3)
		{	
			PrintCenterText(attacker, "%t", "PlayerPropInfo", PropData[entity].PropHP, g_iOwner, GetClientTeam(g_iOwner) == 1 ? "Spectator" : GetClientTeam(g_iOwner) == 2 ? "Zombie" : "Human");
			return Plugin_Continue;
		}
	}
	
	PropData[entity].PropHP -= RoundToZero(damage);
	
	SetPropColor(entity, PropData[entity].PropHP, PropData[entity].PropMaxHP);
	
	if(PropData[entity].PropHP > 0)
	{
		if(g_iOwner > 0)
		{
			PrintCenterText(attacker, "%t", "PlayerPropInfo", PropData[entity].PropHP, g_iOwner, GetClientTeam(g_iOwner) == 1 ? "Spectator" : GetClientTeam(g_iOwner) == 2 ? "Zombie" : "Human");
		}
		
		else
		{
			PrintCenterText(attacker, "%t", "ServerPropInfo", PropData[entity].PropHP);
		}
	}
	
	else
	{
		RemoveProp(entity);
		PropData[entity].PropHP = 0;
	}
	
	return Plugin_Continue;
}

void SetPropColor(int entity, int health, int maxhealth)
{
	if(health <= maxhealth * 0.75)
	{
		SetEntityRenderColor(entity, 96, 96, 96, 255);
	}
	
	if(health <= maxhealth * 0.5)
	{
		SetEntityRenderColor(entity, 64, 64, 64, 255);
	}
	
	if(health <= maxhealth * 0.25)
	{
		SetEntityRenderColor(entity, 32, 32, 32, 255);
	}
}

void RemoveProp(int entity)
{
	float fPos[3], fDir[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fPos);
	TE_SetupSparks(fPos, fDir, 2, 2);
	TE_SendToAll();
	AcceptEntityInput(entity, "Kill");	
}

bool IsValidClient(int client)
{
    return(0 < client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client) && IsPlayerAlive(client));
}