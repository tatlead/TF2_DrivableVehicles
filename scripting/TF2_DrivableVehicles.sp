#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Battlefield Duck"
#define PLUGIN_VERSION "1.0"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <morecolors>
#include <tf2>
//#include <vphysics>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[TF2] Driveable Vehicles", 
	author = PLUGIN_AUTHOR, 
	description = "Let Vehicles work on Team Fortress 2", 
	version = PLUGIN_VERSION, 
	url = "http://steamcommunity.com/id/battlefieldduck/"
};

 #define COLLISION_GROUP_PLAYER 5
 

#define MAX_HOOK_ENTITIES 2048
#define ENTER_VEHICLE_CD  0.5
#define SOUND_VEHICLE_CD  1.0


static bool iDebug = false;
int g_ModelIndex;
int g_HaloIndex;

static char g_strDebugModel[][] =
{
	"materials/sprites/physbeam.vmt",
	"materials/sprites/halo01.vmt",
};

static char g_strVehicleModel[][] =
{
	"models/props_vehicles/car002a.mdl",
	"models/props_vehicles/car004a.mdl",
	"models/props_vehicles/car005a.mdl",
	//"models/airboat.mdl",
	//"models/buggy.mdl",
};

static char g_strVehicleSound[][] =
{
	//Vehicle moving
	"vehicles/v8/first.wav",
	
	//Beep Beep
	"ambient_mp3/mvm_warehouse/car_horn_01.mp3",
	
	//Brake
	"vehicles/v8/skid_highfriction.wav",
};


/**	I know it wastes a lot of space..
[MAX_HOOK_ENTITIES] <- Vehicle Index
{
	[0]: Vehicle Ref, [1]: Seat 1 Client Userid, [2]: Seat 2 Client Userid, [3]: Seat 3 Client Userid, [4]: Seat 4 Client Userid
}
*/
int g_iVehicleData[MAX_HOOK_ENTITIES][5];

/**
	[0] Is Player in car seat no., [1]: Vehicle Ref, [2]: Info Ref
*/
int g_iPlayerInVehicle[MAXPLAYERS + 1][3];

/**
	[0]: Vehicle Speed, [1]: Enter Vehicle CD, [2][3][4]: Sound CD, [5]: Player Push CD, [6]: Seat height
*/
float g_fPlayerData[MAXPLAYERS + 1][7];


public void OnPluginStart()
{
	RegAdminCmd("sm_veh", 	  Command_SpawnVehicle, 0, "Spawn Vehicle in TF2!");
	RegAdminCmd("sm_vehicle", Command_SpawnVehicle, 0, "Spawn Vehicle in TF2!");
	
	RegAdminCmd("sm_vehmenu", Command_VehicleMenu, 0, "Vehicle Menu!");
	
	RegAdminCmd("sm_delveh", Command_RemoveVehicle, 0, "Remove Aiming Vehicle");
	RegAdminCmd("sm_delvehall", Command_RemoveVehicleAll, 0, "Remove All Vehicle");
	
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
}

public Action Command_SpawnVehicle(int client, int args)
{
	if(args == 1)
	{
		char strCmd[2];
		GetCmdArg(1, strCmd, sizeof(strCmd));
		
		int iVehicleType = StringToInt(strCmd) - 1;
		if (iVehicleType < sizeof(g_strVehicleModel) && iVehicleType != -1)
		{

			int iVehicleIndex = TF2_SpawnVehicle(client, iVehicleType);
			
			// Set Vehicle Ref
			g_iVehicleData[iVehicleIndex][0] = EntIndexToEntRef(iVehicleIndex);
			
			// Reset Vehicle Ref
			for (int i = 1; i <= 4; i++)
			{
				g_iVehicleData[iVehicleIndex][i] = 0;
			}
			
			if(iDebug)
			{
				PrintCenterText(client, "Index: %i, Ref: %i, Seat: %i %i %i %i", iVehicleIndex, EntIndexToEntRef(iVehicleIndex)
				, g_iVehicleData[iVehicleIndex][1], g_iVehicleData[iVehicleIndex][2], g_iVehicleData[iVehicleIndex][3], g_iVehicleData[iVehicleIndex][4]);
			}
			
			return Plugin_Continue;
		}
	}
	
	CPrintToChat(client, "[SM] Usage: sm_vehicle <1-3>");
	
	return Plugin_Continue;
}

public Action Command_RemoveVehicle(int client, int args)
{
	if(IsValidClient(client))
	{
		int iEntity = GetClientAimEntity(client);
		if(TF2_IsEntityVehicle(iEntity))
		{
			AcceptEntityInput(iEntity, "Kill");
			PrintToChat(client, "[Vehicle] Removed Vehicle %i", iEntity);
		}
		else PrintToChat(client, "[Vehicle] Not a Valid Vehicle");
	}
	
	return Plugin_Continue;
}

public Action Command_RemoveVehicleAll(int client, int args)
{
	int iCount;
	int index = -1;
	while ((index = FindEntityByClassname(index, "prop_physics")) != -1)
	{
		if (TF2_IsEntityVehicle(index))
		{	
			AcceptEntityInput(index, "Kill");
			iCount++;
		}
	}
	PrintToChat(client, "[Vehicle] Removed %i Vehicles successfully!", iCount);
	
	return Plugin_Continue;
}

public Action Command_VehicleMenu(int client, int args)
{
	char menuinfo[1024];
	Menu menu = new Menu(Handler_VehicleMenu);
	
	Format(menuinfo, sizeof(menuinfo), "TF2 Vehicle - Seat Config v%s\n \nSeat position: %f", PLUGIN_VERSION, g_fPlayerData[client][6]);
	menu.SetTitle(menuinfo);
	
	Format(menuinfo, sizeof(menuinfo), " Higher", client);
	menu.AddItem("0", menuinfo);
	
	Format(menuinfo, sizeof(menuinfo), " Lower", client);
	menu.AddItem("1", menuinfo);
	
	menu.ExitBackButton = false;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int Handler_VehicleMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		switch(StringToInt(info))
		{
			case (0):g_fPlayerData[client][6] += 0.5;
			case (1):g_fPlayerData[client][6] -= 0.5;
		}
		
		if (g_fPlayerData[client][6] > 25.0) g_fPlayerData[client][6] -= 0.5;
		else if (g_fPlayerData[client][6] < -5.0)g_fPlayerData[client][6] += 0.5;
		
		int iVehicle = EntRefToEntIndex(g_iPlayerInVehicle[client][1]);
		if (iVehicle != INVALID_ENT_REFERENCE)
		{
			int iSeatNum = g_iPlayerInVehicle[client][0];
			
			if (iSeatNum > 0)
			{
				TF2_SetClientLeaveSeat(client);
				TF2_SetClientEnterSeat(client, iVehicle, iSeatNum);
			}
		}
		Command_VehicleMenu(client, -1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack)
		{
			
		}
	}
	else if (action == MenuAction_End)
		delete menu;
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	TF2_SetClientLeaveSeat(client);
}

public void OnMapStart()
{
	if(iDebug)
	{
		g_ModelIndex = PrecacheModel(g_strDebugModel[0]);
		g_HaloIndex  = PrecacheModel(g_strDebugModel[1]);
	}
	
	int iModelSize = sizeof(g_strVehicleModel) - 1;
	for (int i = 0; i <= iModelSize; i++)
	{
		PrecacheModel(g_strVehicleModel[i]);
	}
	
	int iSoundSize = sizeof(g_strVehicleSound) - 1;
	for (int i = 0; i <= iSoundSize; i++)
	{
		PrecacheSound(g_strVehicleSound[i]);
	}
}

public void OnClientPutInServer(int client)
{
	g_iPlayerInVehicle[client][0] = 0;
	g_iPlayerInVehicle[client][1] = -1;
	
	for (int i = 0; i <= 4; i++)
	{
		g_fPlayerData[client][i] = 0.0;
	}
	
}

public void OnEntityDestroyed(int entity)
{
	if(TF2_IsEntityVehicle(entity))
	{
		for (int i = 1; i <= 4; i++)
		{
			TF2_SetClientLeaveSeat(g_iVehicleData[entity][i]);
		}
	}
}

//Set pushing force on entities
public Action Hook_StartTouch(int entity, int client)
{
	int iDriver = GetClientOfUserId(g_iVehicleData[entity][1]);
	int iPassenger2 = GetClientOfUserId(g_iVehicleData[entity][2]);
	int iPassenger3 = GetClientOfUserId(g_iVehicleData[entity][3]);
	int iPassenger4 = GetClientOfUserId(g_iVehicleData[entity][4]);
	
	//Filter the client inside the vehicle
	if(entity != client && client != iDriver && client != iPassenger2 && client != iPassenger3 && client != iPassenger4)
	{
		if(g_fPlayerData[client][5] <= GetGameTime())
		{
			//g_fPlayerData[client][5] = GetGameTime() + 3.0;
			float fVelocity[3];
			GetEntPropVector(entity, Prop_Data, "m_vecVelocity", fVelocity);
			
			//SetEntityMoveType(client, MOVETYPE_PUSH);
			//SetEntProp(client, Prop_Data, "m_CollisionGroup", 3);
			//SetEntProp(entity, Prop_Data, "m_nSolidType", 0);
			//SetEntProp(client, Prop_Data, "m_nSolidType", 0);
			//SetEntProp(client, Prop_Data, "m_CollisionGroup", 17);  
			//SetEntityFlags(entity, GetEntityFlags(entity) | 4);
			//fVelocity[2] = 0.0;
			ScaleVector(fVelocity, 20.0);
			
			
			//float fOrigin[3];
			//GetEntPropVector(client, Prop_Send, "m_vecOrigin", fOrigin);
			//float fAngle[3];		
			//GetEntPropVector(entity, Prop_Send, "m_angRotation", fAngle);
			//GetPointAimPosition(fOrigin, fAngle, 100.0, fOrigin, tracerayfilterrocket, client);
			
			//TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, fVelocity);
			
			if(iDebug)	
				PrintCenterTextAll("Vehicle: %i\n Touched Entity:%i\n Vel: %f %f %f \n Collision: %i", entity, client, fVelocity[0], fVelocity[1], fVelocity[2], GetEntProp(client, Prop_Data, "m_CollisionGroup"));
		}
	}
	
}

public Action Hook_EndTouch(int entity, int client)
{
	int iDriver = GetClientOfUserId(g_iVehicleData[entity][1]);
	int iPassenger2 = GetClientOfUserId(g_iVehicleData[entity][2]);
	int iPassenger3 = GetClientOfUserId(g_iVehicleData[entity][3]);
	int iPassenger4 = GetClientOfUserId(g_iVehicleData[entity][4]);
	
	//Filter the client inside the vehicle
	if(entity != client && client != iDriver && client != iPassenger2 && client != iPassenger3 && client != iPassenger4)
	{
		if(g_fPlayerData[client][5] <= GetGameTime())
		{
			g_fPlayerData[client][5] = GetGameTime() + 1.0;
			//SetEntProp(client, Prop_Data, "m_nSolidType", 6);
		}
		//SetEntityMoveType(other, MOVETYPE_WALK);
		//SetEntProp(entity, Prop_Data, "m_CollisionGroup", 6);
		//SetEntProp(other, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(!IsPlayerAlive(client)) 
		return Plugin_Continue;	
	
	if(g_iPlayerInVehicle[client][0] > 0)
	{
		int iVehicle = EntRefToEntIndex(g_iPlayerInVehicle[client][1]);
		int iSeatNum = g_iPlayerInVehicle[client][0];
		
		if(iVehicle != INVALID_ENT_REFERENCE)
		{
			//Is Client a driver?
			if(GetClientOfUserId(g_iVehicleData[iVehicle][1]) == client && iSeatNum == 1)
			{
				float fVehicleAngle[3];		
				GetEntPropVector(iVehicle, Prop_Send, "m_angRotation", fVehicleAngle);
				
				if((fVehicleAngle[0] < 60 && fVehicleAngle[0] > -60) && (fVehicleAngle[2] < 45 && fVehicleAngle[2] > -45))
				{
					//Move Forward and Back
					if(buttons & IN_FORWARD || buttons & IN_BACK)
					{
						//Move Forward
						if(buttons & IN_FORWARD)
						{
							g_fPlayerData[client][0] += 1.0;
						}
						
						//Move Back
						if(buttons & IN_BACK)
						{
							g_fPlayerData[client][0] -= 1.0;
						}
		
					}
					else
					{
						if(g_fPlayerData[client][0] > 0.0)
						{
							g_fPlayerData[client][0] -= 0.5;
						}
						else	if(g_fPlayerData[client][0] < 0.0)
						{
							g_fPlayerData[client][0] += 0.5;
						}
					}
					
					if(g_fPlayerData[client][2] <= GetGameTime() && g_fPlayerData[client][0] != 0.0)
					{
						float fVolume = SquareRoot(SquareRoot(FloatAbs(g_fPlayerData[client][0])) / 100.0);
						if (fVolume > 1.0)	fVolume = 1.0;
						StopSound(iVehicle, SNDCHAN_AUTO, g_strVehicleSound[0]);
						EmitSoundToAll(g_strVehicleSound[0], iVehicle, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, fVolume);
						g_fPlayerData[client][2] = GetGameTime() + 4.0;
					}
					else if(g_fPlayerData[client][0] == 0.0)
					{
						StopSound(iVehicle, SNDCHAN_AUTO, g_strVehicleSound[0]);
					}
					
					//Left Right
					if(buttons & IN_MOVELEFT)
					{
						if(g_fPlayerData[client][0] > 0.0)	fVehicleAngle[1] += SquareRoot(FloatAbs(g_fPlayerData[client][0]/250.0));
						else fVehicleAngle[1] += -SquareRoot(FloatAbs(g_fPlayerData[client][0]/250.0));
					}
					if(buttons & IN_MOVERIGHT)
					{
						if(g_fPlayerData[client][0] > 0.0)	fVehicleAngle[1] += -SquareRoot(FloatAbs(g_fPlayerData[client][0]/250.0));
						else fVehicleAngle[1] += SquareRoot(FloatAbs(g_fPlayerData[client][0]/250.0));
					}
					
					//Brake
					if(buttons & IN_JUMP)
					{ 
						if(g_fPlayerData[client][0] >= 3.0 || g_fPlayerData[client][0] <= -3.0)
						{
							if(g_fPlayerData[client][0] >= 5.0)
							{
								g_fPlayerData[client][0] -= 5.0;
							}
							else if(g_fPlayerData[client][0] <= -5.0)
							{
								g_fPlayerData[client][0] += 5.0;
							}
							
							if(g_fPlayerData[client][4] <= GetGameTime())
							{
								float fVolume = SquareRoot(SquareRoot(FloatAbs(g_fPlayerData[client][0])) / 50.0);
								if (fVolume > 1.0)	fVolume = 1.0;
								EmitSoundToAll(g_strVehicleSound[2], iVehicle, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, fVolume);
								g_fPlayerData[client][4] = GetGameTime() + 0.05;
							}
						}
						else StopSound(iVehicle, SNDCHAN_AUTO, g_strVehicleSound[2]);
					}
					
					
					//Beep Beep
					if(buttons & IN_RELOAD && g_fPlayerData[client][3] <= GetGameTime())
					{
						EmitSoundToAll(g_strVehicleSound[1], iVehicle, SNDCHAN_AUTO, SNDLEVEL_NORMAL, SND_NOFLAGS, 0.8);
						g_fPlayerData[client][3] = GetGameTime() + 1.0;
					}
					
					TeleportEntity(iVehicle, NULL_VECTOR, fVehicleAngle, TF2_GetVehicleVelocity(fVehicleAngle, g_fPlayerData[client][0]));
					
				}
				else
				{
					g_fPlayerData[client][0] = 0.0;
					
					if(buttons & IN_RELOAD)
					{
						if(fVehicleAngle[0] > 60)
						{
							fVehicleAngle[0] -= 1.0;
						}
						else fVehicleAngle[0] += 1.0;
						
						if(fVehicleAngle[2] > 45)
						{
							fVehicleAngle[2] -= 1.0;
						}
						else fVehicleAngle[2] += 1.0;
						AnglesNormalize(fVehicleAngle);
						TeleportEntity(iVehicle, NULL_VECTOR, fVehicleAngle, NULL_VECTOR);
					}
				}
				
			}
			
			if(buttons & IN_ATTACK3 && g_fPlayerData[client][1] <= GetGameTime())
			{		
				TF2_SetClientLeaveSeat(client);
				
				g_fPlayerData[client][1] = GetGameTime() + ENTER_VEHICLE_CD;
				
				for (int i = 0; i <= 2; i++)	StopSound(iVehicle, SNDCHAN_AUTO, g_strVehicleSound[i]);
			}	
			//
			//TeleportEntity(client, TF2_GetVehicleSeatPosition(iVehicle, iSeatNum), NULL_VECTOR, NULL_VECTOR);
		}
		else
		{
			TF2_SetClientLeaveSeat(client);
		}
	}
	else
	{
		
		if(TF2_IsPlayerStuckInVehicle(client))
		{
			float iPosition[3];
			GetClientAbsOrigin(client, iPosition);
			iPosition[2] += 10.0;
			TeleportEntity(client, iPosition, NULL_VECTOR, NULL_VECTOR);
		}
		
		float fOrigin[3];
		GetClientAbsOrigin(client, fOrigin);
		
		//Find Vehicle
		int index = -1;
		while ((index = FindEntityByClassname(index, "prop_physics")) != -1)
		{
			if (TF2_IsEntityVehicle(index))
			{		
				//Loop Seat ( 1-4 )
				for (int i = 1; i <= 4; i++)
				{
					if (g_iVehicleData[index][i] == 0)
					{
						if(GetVectorDistance(TF2_GetVehicleSeatPosition(index, i), fOrigin) < 65.0)
						{
							if(iDebug)	PrintCenterText(client, "Seat %i", i);
							
							if(buttons & IN_ATTACK3 && GetEntityFlags(client) & FL_DUCKING && g_fPlayerData[client][1] <= GetGameTime() && buttons & IN_DUCK)
							{
								//Set client userid to g_iVehicleData depends on seat no.
								
								TF2_SetClientEnterSeat(client, index, i);
								g_fPlayerData[client][1] = GetGameTime() + ENTER_VEHICLE_CD;
								
								if(iDebug)	PrintCenterText(client, "Seated on %i", i);
							}
						}
					}
				}
	
			}
		}
		
		
	}
	return Plugin_Continue;
}

/**************************

		   Stock
		
***************************/
stock bool IsValidClient(int client)
{
	if (client <= 0)return false;
	if (client > MaxClients)return false;
	if (!IsClientConnected(client))return false;
	return IsClientInGame(client);
}

/**	 	 Vehicle	 */
bool TF2_IsEntityVehicle(int entity)
{
	if(IsValidEntity(entity) && entity > 0)
	{
		char szModel[64];
		GetEntPropString(entity, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
		
		int iModelSize = sizeof(g_strVehicleModel) - 1;
		for (int i = 0; i <= iModelSize; i++)
		{
			if(StrEqual(szModel, g_strVehicleModel[i]))
			{
				return true;
			}
		}
		
	}
	return false;
}

int TF2_SpawnVehicle(int client, int type)
{
	int iVehicle = CreateEntityByName("prop_physics_override");
	if (iVehicle > MaxClients && IsValidEntity(iVehicle))
	{
		SetEntProp(iVehicle, Prop_Send, "m_nSolidType", 6);
		SetEntProp(iVehicle, Prop_Data, "m_nSolidType", 6);
		
		char strName[128];
		Format(strName, sizeof(strName), "TF2Vehicle%i", iVehicle);
		DispatchKeyValue(iVehicle, "targetname", strName);
		
		DispatchKeyValue(iVehicle, "model", g_strVehicleModel[type]);
		
		float fOrigin[3];
		GetClientEyePosition(client, fOrigin);
		DispatchKeyValueVector(iVehicle, "origin", fOrigin);

		DispatchSpawn(iVehicle);
		
		if(iDebug)
		{
			SetEntityRenderMode(iVehicle, RENDER_TRANSCOLOR); 
			SetEntityRenderColor(iVehicle, _, _, _, 180);
		}
	}
	return iVehicle;
}

float[] TF2_GetVehicleSeatPosition(int entity, int seatNum)
{
	float fOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fOrigin);

	fOrigin[2] -= 25.0;
	//fOrigin[2] -= 10.0;
	
	float fAngle[3];		
	GetEntPropVector(entity, Prop_Send, "m_angRotation", fAngle);
	
	switch(seatNum)
	{
		case(1):
		{
			fAngle[0] -= fAngle[0] + fAngle[2];
			fAngle[1] += 90.0; 
		}
		case(2):
		{
			fAngle[0] -= fAngle[0] - fAngle[2];
			fAngle[1] += 270.0;
		}
		case(3):
		{
			fAngle[0] *= -1;
			fAngle[1] += 180.0;
			AnglesNormalize(fAngle);
			
			GetPointAimPosition(fOrigin, fAngle, 38.0, fOrigin, tracerayfilterrocket, entity);

			fAngle[0] -= fAngle[0] + fAngle[2];
			fAngle[1] += 90.0; 
		}
		case(4):
		{
			fAngle[0] *= -1;
			fAngle[1] += 180.0;
			AnglesNormalize(fAngle);

			GetPointAimPosition(fOrigin, fAngle, 38.0, fOrigin, tracerayfilterrocket, entity);

			fAngle[0] -= fAngle[0] - fAngle[2];
			fAngle[1] += 270.0;
		}
	}
	AnglesNormalize(fAngle);
	
	float fout[3];
	GetPointAimPosition(fOrigin, fAngle, 18.0, fout, tracerayfilterrocket, entity);
	SetDEBUGBeamPoints(fOrigin, fout, 255, 0, 0);
	
	return fout;
}

void TF2_SetClientEnterSeat(int client, int entity, int seatNum)
{
	g_iVehicleData[entity][seatNum] = GetClientUserId(client);
								
	g_iPlayerInVehicle[client][0] = seatNum;
	g_iPlayerInVehicle[client][1] = EntIndexToEntRef(entity);
	
	if(seatNum == 1)
	{
		SDKHook(entity, SDKHook_StartTouch, Hook_StartTouch);
		SDKHook(entity, SDKHook_EndTouch, Hook_EndTouch);
		
		AcceptEntityInput(entity, "EnableDamageForces");
	}
	
	float Seatpos[3];
	Seatpos = TF2_GetVehicleSeatPosition(entity, seatNum);
	Seatpos[2] += g_fPlayerData[client][6];
	
	int Seat = CreateEntityByName("info_target");
	if (Seat > MaxClients && IsValidEntity(Seat))
	{
		DispatchSpawn(Seat);
		SetEntPropVector(Seat, Prop_Send, "m_vecOrigin", Seatpos);

		SetVariantString("!activator"); 
		AcceptEntityInput(Seat, "SetParent", entity);
	}
	
	SetEntPropVector(client, Prop_Send, "m_vecOrigin", Seatpos);
	SetVariantString("!activator"); 
	AcceptEntityInput(client, "SetParent", Seat);
	
	g_iPlayerInVehicle[client][2] = EntIndexToEntRef(Seat);
	g_fPlayerData[client][0] = 0.0;
}

void TF2_SetClientLeaveSeat(int client)
{
	if(client > 0)
	{
		int iVehicle = EntRefToEntIndex(g_iPlayerInVehicle[client][1]);
		if(iVehicle != INVALID_ENT_REFERENCE)
		{	
			int iSeatNum = g_iPlayerInVehicle[client][0];
			g_iVehicleData[iVehicle][iSeatNum] = 0;
			
			if(iSeatNum == 1)
			{
				SDKUnhook(iVehicle, SDKHook_StartTouch, Hook_StartTouch);
				SDKUnhook(iVehicle, SDKHook_EndTouch, Hook_EndTouch);
			}
		}
		else
		{
			g_iVehicleData[iVehicle][0] = 0;
		}
		
		int info = EntRefToEntIndex(g_iPlayerInVehicle[client][2]);
		if(info != INVALID_ENT_REFERENCE)
		{	
			char strClassname[32];
			GetEntityClassname(info, strClassname, sizeof(strClassname));
			
			if(StrEqual(strClassname, "info_target"))
			{
				AcceptEntityInput(client, "ClearParent");
				AcceptEntityInput(info, "ClearParent");
				AcceptEntityInput(info, "Kill");
			}
		}
		
		g_iPlayerInVehicle[client][0] = 0;
		g_iPlayerInVehicle[client][1] = 0;
		g_iPlayerInVehicle[client][2] = 0;
		
		g_fPlayerData[client][0] = 0.0;
		
		//Fix client angle
		float fAngle[3];
		GetClientAbsAngles(client, fAngle);
		fAngle[2] = 0.0;
		TeleportEntity(client, NULL_VECTOR, fAngle, NULL_VECTOR);
		
	}
}

float[] TF2_GetVehicleVelocity(float angle[3], float speed)
{
	float local_angle[3];
	local_angle[0] *= -1.0;
	local_angle[0] = DegToRad(angle[0]);
	local_angle[1] = DegToRad(angle[1]);
	
	float outVel[3];
	outVel[0] = speed * Cosine(local_angle[0]) * Cosine(local_angle[1]);
	outVel[1] = speed * Cosine(local_angle[0]) * Sine(local_angle[1]);
	outVel[2] = -40.0;  //speed*Sine(local_angle[0]);
	
	return outVel;
}

void SetDEBUGBeamPoints(float fStart[3], float fEnd[3], int red, int green, int blue)
{
	if(!iDebug)	return;
	int iColour[4];
	iColour[0] = red;
	iColour[1] = green;
	iColour[2] = blue;
	iColour[3] = 255;
	
	TE_SetupBeamPoints(fStart, fEnd, g_ModelIndex, g_HaloIndex, 0, 15, 0.1, 1.0, 1.0, 1, 0.0, iColour, 10);
	TE_SendToAll();
}

bool TF2_IsPlayerStuckInVehicle(int client)
{
	float vecMin[3], vecMax[3], vecOrigin[3];	
	GetClientMins(client, vecMin);
	GetClientMaxs(client, vecMax);
	GetClientAbsOrigin(client, vecOrigin);
	
	TR_TraceHullFilter(vecOrigin, vecOrigin, vecMin, vecMax, MASK_PLAYERSOLID, TraceRayIsNotClient, client);
	return TF2_IsEntityVehicle(TR_GetEntityIndex());
}

public bool TraceRayIsNotClient(int entity, int client)
{
	return (entity > MaxClients);
}



bool GetPointAimPosition(float cleyepos[3], float cleyeangle[3], float maxtracedistance, float resultvecpos[3], TraceEntityFilter Tfunction, int filter)
{
	float eyeanglevector[3];

	Handle traceresulthandle = INVALID_HANDLE;
	
	traceresulthandle = TR_TraceRayFilterEx(cleyepos, cleyeangle, MASK_SOLID, RayType_Infinite, Tfunction, filter);
	
	if(TR_DidHit(traceresulthandle) == true)
	{
		float endpos[3];
		TR_GetEndPosition(endpos, traceresulthandle);
		//TR_GetPlaneNormal(traceresulthandle, resultvecnormal);
		
		if((GetVectorDistance(cleyepos, endpos) <= maxtracedistance) || maxtracedistance <= 0)
		{	
			resultvecpos[0] = endpos[0];
			resultvecpos[1] = endpos[1];
			resultvecpos[2] = endpos[2];
			
			CloseHandle(traceresulthandle);
			return true;		
		}
		else
		{	
			GetAngleVectors(cleyeangle, eyeanglevector, NULL_VECTOR, NULL_VECTOR);
			NormalizeVector(eyeanglevector, eyeanglevector);
			ScaleVector(eyeanglevector, maxtracedistance);
			
			AddVectors(cleyepos, eyeanglevector, resultvecpos);
			
			CloseHandle(traceresulthandle);
			return true;
		}	
	}
	CloseHandle(traceresulthandle);
	return false;
}

public bool tracerayfilterrocket(int entity, int mask, any data)
{
	if (IsValidEntity(entity))
		return false;
	
	return true;	
}

stock int GetClientAimEntity(int client)
{
	float fOrigin[3], fAngles[3];
	GetClientEyePosition(client, fOrigin);
	GetClientEyeAngles(client, fAngles);
	
	Handle trace = TR_TraceRayFilterEx(fOrigin, fAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilter, client);

	if (TR_DidHit(trace)) 
	{	
		int iEntity = TR_GetEntityIndex(trace);
		if(iEntity > 0 && IsValidEntity(iEntity))
		{
			CloseHandle(trace);
			return iEntity;
		}
	}
	CloseHandle(trace);
	return -1;
}
public bool TraceEntityFilter(int entity, int mask, any data) 
{
	return data != entity;
}


void AnglesNormalize(float vAngles[3])
{
	while (vAngles[0] > 89.0)vAngles[0] -= 360.0;
	while (vAngles[0] < -89.0)vAngles[0] += 360.0;
	while (vAngles[1] > 180.0)vAngles[1] -= 360.0;
	while (vAngles[1] < -180.0)vAngles[1] += 360.0;
}




/**
		Pelipoika Area
*/
//https://github.com/Pelipoika/The-unfinished-and-abandoned/blob/master/triggerbot.sp
float[] VelocityExtrapolate(int entity, float pos[3])		
{
	float absVel[3];		
	GetEntPropVector(entity, Prop_Data, "m_vecVelocity", absVel);		
	
	float v[3];		
	
	v[0] = pos[0] + (absVel[0] * GetTickInterval());		
	v[1] = pos[1] + (absVel[1] * GetTickInterval());		
	v[2] = pos[2] + (absVel[2] * GetTickInterval());		
	
	return v;		
}