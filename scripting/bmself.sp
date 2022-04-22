#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#pragma newdecls required
#pragma semicolon 1


public Plugin myinfo =
{
	name = "BMSelf",
	author = "zer0.k",
	description = "Prevent bump mine from affecting non owners",
	version = "1.1.0",
	url = "https://github.com/zer0k-z/BMSelf"
};


// Credits to backwards for the original plugin, GAMMACASE for StoreToAddressFast, lacyyy for bump mine logic.

GameData gH_GameData;
Handle gH_StoreToAddressFast;
Handle gH_WorldSpaceCenter_SDKCall;
Handle gH_DHooks_BumpMineDetonate, gH_DHooks_ApplyAbsVelocityImpulse;

int gI_CurrentBMOwner;

bool gB_BumpMineSphereQueryDisabled;
Address gA_BumpMineSphereAddress;
int gI_SpherePatchRestore;

Address gA_BumpMineTraceRayAddress;
int gI_TraceRayPatchRestore;

#define BM_BBOX_CHECK_DIST 81.0
#define ASM_PATCH_LEN 17
#include "glib/memutils"

public void OnPluginStart()
{
	gH_GameData = LoadGameConfigFile("bmself.games");
	if (!gH_GameData)
	{
		SetFailState("Failed to load BMSelf gamedata.");
		return;
	}

	// CBaseEntity::WorldSpaceCenter SDKCall setup
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetVirtual(gH_GameData.GetOffset("CBaseEntity::WorldSpaceCenter"));
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	gH_WorldSpaceCenter_SDKCall = EndPrepSDKCall();

	// CBumpMineProjectile::Detonate detour
	gH_DHooks_BumpMineDetonate = DHookCreateFromConf(gH_GameData, "CBumpMineProjectile::Detonate");
	if (!gH_DHooks_BumpMineDetonate)
	{
		SetFailState("Failed to setup detour for CBumpMineProjectile::Detonate");
	}

	if (!DHookEnableDetour(gH_DHooks_BumpMineDetonate, false, Detour_BumpMineDetonate))
	{
		SetFailState("Failed to detour BumpMineDetonate.");
	}

	if (!DHookEnableDetour(gH_DHooks_BumpMineDetonate, true, Detour_BumpMineDetonatePost))
	{ 
		SetFailState("Failed to detour BumpMineDetonatePost.");
	}

	// CBaseEntity::ApplyAbsVelocityImpulse detour
	gH_DHooks_ApplyAbsVelocityImpulse = DHookCreateFromConf(gH_GameData, "CBaseEntity::ApplyAbsVelocityImpulse");
	if (!DHookEnableDetour(gH_DHooks_ApplyAbsVelocityImpulse, false, Detour_ApplyAbsVelocityImpulse))
	{
		SetFailState("Failed to detour ApplyAbsVelocityImpulse.");
	}

	// StoreToAddressFast setup, credit to GAMMACASE
	// Takes over CGameMovement::Duck because CCSGameMovement::Duck does not use this.
	// NOTE: 1.11 should get rid of this workaround!
	Address duckStart;
	duckStart = gH_GameData.GetAddress("CGameMovement::Duck_Start");
	if (!duckStart)
	{
		SetFailState("Can't find start of the CGameMovement::Duck function.");
	}
	
	PatchHandler ASMPatch = PatchHandler(duckStart);
	ASMPatch.Save(ASM_PATCH_LEN);
	
	StoreToAddress(duckStart, 0x8B_EC_8B_55, NumberType_Int32);
	StoreToAddress(duckStart + 4, 0x4D_8B_0C_45, NumberType_Int32);
	StoreToAddress(duckStart + 8, 0x8B_01_89_08, NumberType_Int32);
	StoreToAddress(duckStart + 12, 0x08_C2_5D_E5, NumberType_Int32);
	StoreToAddress(duckStart + 16, 0x00, NumberType_Int8);
	
	StartPrepSDKCall(SDKCall_Static);
	
	PrepSDKCall_SetAddress(duckStart);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	gH_StoreToAddressFast = EndPrepSDKCall();

	// Bump mine's sphere query and trace setup.
	gA_BumpMineSphereAddress = gH_GameData.GetAddress("BumpMineThink") + view_as<Address>(gH_GameData.GetOffset("BumpMineSphereQueryOffset"));
	gA_BumpMineTraceRayAddress = gH_GameData.GetAddress("BumpMineThink") + view_as<Address>(gH_GameData.GetOffset("BumpMineTraceRayOffset"));

	// Bump mines' trace ray never hits the owner, so there is no reason to toggle this on and off constantly.
	DisableBumpMineTraceRay();
}

public void OnPluginEnd()
{
	// StoreToAddressFast does not work here.
	RestoreBumpMineSphereQuery(true);
	RestoreBumpMineTraceRay(true);
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (StrEqual(classname, "bumpmine_projectile"))
	{
		SDKHook(entity, SDKHook_Think, OnBumpMineThink);
		SDKHook(entity, SDKHook_ThinkPost, OnBumpMineThinkPost);
	}
}

// Bumpmine think
public void OnBumpMineThink(int bumpmine)
{
	// If the thrower is not nearby, disable its sphere query
	// ...unless it's still activating or it's already detonating.
	if (!IsBumpMineActivated(bumpmine) || IsBumpMineDetonating(bumpmine))
	{
		return;
	}
	int owner = GetEntPropEnt(bumpmine, Prop_Data, "m_hOwnerEntity");
	if (!IsPlayerInRange(owner, bumpmine))
	{
		DisableBumpMineSphereQuery();
	}
}

public void OnBumpMineThinkPost(int bumpmine)
{
	RestoreBumpMineSphereQuery();
}

// Prevent bumpmine detonation from boosting other players
public MRESReturn Detour_BumpMineDetonate(int bumpmine, Handle hReturn, Handle hParams)
{
	gI_CurrentBMOwner = GetEntPropEnt(bumpmine, Prop_Data, "m_hOwnerEntity");
	return MRES_Ignored;
}

public MRESReturn Detour_ApplyAbsVelocityImpulse(int client, Handle hReturn, Handle hParams)
{
	if (gI_CurrentBMOwner != -1 && client != gI_CurrentBMOwner)
	{
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

public MRESReturn Detour_BumpMineDetonatePost(int bumpmine, Handle hReturn, Handle hParams)
{
	gI_CurrentBMOwner = -1;
	return MRES_Ignored;
}

// =====[ HELPERS ]=====
bool IsBumpMineActivated(int bumpmine)
{
	Address addr = GetEntityAddress(bumpmine);
	int offset = gH_GameData.GetOffset("BumpMineActivated");
	return view_as<bool>(LoadFromAddress(addr+view_as<Address>(offset), NumberType_Int8));
}

bool IsBumpMineDetonating(int bumpmine)
{
	Address addr = GetEntityAddress(bumpmine);
	int offset = gH_GameData.GetOffset("BumpMineDetonating");
	return view_as<bool>(LoadFromAddress(addr+view_as<Address>(offset), NumberType_Int8));
}

bool IsPlayerInRange(int client, int bumpmine)
{
	if(!IsValidClient(client) || !IsPlayerAlive(client))
	{
		return false;
	}
	// Credit to lacyyy for the detection logic.
	float minePos[3], distVec[3];
	SDKCall(gH_WorldSpaceCenter_SDKCall, bumpmine, minePos);
	CalcNearestPoint(client, minePos, distVec);

	// First check
	// The player bbox must be within a 162x162x162 cube inside the bump mine's bbox.
	for (int i = 0; i < 3; i++)
	{
		if (FloatAbs(distVec[i] - minePos[i]) > BM_BBOX_CHECK_DIST)
		{
			PrintToServer("%f - %f = %f", distVec[i], minePos[i], FloatAbs(distVec[i] - minePos[i]));
			return false;
		}
	}

	// Second check
	// This is apparently some sort of ellipsoid that depends on the player's and bump mine's bbox center.
	float ang[3], up[3];
	GetEntPropVector(bumpmine, Prop_Send, "m_angRotation", ang);
	GetAngleVectors(ang, NULL_VECTOR, NULL_VECTOR, up);

	float playerPos[3], dist, x, final;
	SDKCall(gH_WorldSpaceCenter_SDKCall, client, playerPos);
	SubtractVectors(playerPos, minePos, distVec);
	dist = GetVectorDistance(playerPos, minePos);
	x = FloatClamp(FloatAbs(GetVectorDotProduct(distVec, up) / (dist + 0.00000011920929)) - 0.02, 0.0, 1.0);
	final = ((x * -1.5) + 2.0) * dist;

	return final <= 64.0;
}

void DisableBumpMineSphereQuery()
{
	// Save the current instructions, so we can restore them later.
	// 0xE990 = NOP + JMP
	static bool firstRun = true;

	if (!gB_BumpMineSphereQueryDisabled)
	{
		gB_BumpMineSphereQueryDisabled = true;
		gI_SpherePatchRestore = LoadFromAddress(gA_BumpMineSphereAddress, NumberType_Int32);
		if (firstRun)
		{
			StoreToAddress(gA_BumpMineTraceRayAddress, 0xE990 + (gI_TraceRayPatchRestore >>> 16 << 16), NumberType_Int32);
		}
		else
		{
			StoreToAddressCustom(gA_BumpMineTraceRayAddress, 0xE990 + (gI_TraceRayPatchRestore >>> 16 << 16), NumberType_Int32);
			firstRun = false;
		}
		StoreToAddressCustom(gA_BumpMineSphereAddress, 0xE990 + (gI_SpherePatchRestore >>> 16 << 16), NumberType_Int32);
	}
}

void RestoreBumpMineSphereQuery(bool slow = false)
{
	if (gB_BumpMineSphereQueryDisabled)
	{
		if (slow)
		{
			StoreToAddress(gA_BumpMineSphereAddress, gI_SpherePatchRestore, NumberType_Int32);
		}
		else
		{
			StoreToAddressCustom(gA_BumpMineSphereAddress, gI_SpherePatchRestore, NumberType_Int32);
		}
		
		gB_BumpMineSphereQueryDisabled = false;
	}
}

void DisableBumpMineTraceRay()
{
	static bool firstRun = true;
	
	gI_TraceRayPatchRestore = LoadFromAddress(gA_BumpMineTraceRayAddress, NumberType_Int32);
	if (firstRun)
	{
		StoreToAddress(gA_BumpMineTraceRayAddress, 0xE990 + (gI_TraceRayPatchRestore >>> 16 << 16), NumberType_Int32);
	}
	else
	{
		StoreToAddressCustom(gA_BumpMineTraceRayAddress, 0xE990 + (gI_TraceRayPatchRestore >>> 16 << 16), NumberType_Int32);
		firstRun = false;
	}
}

void RestoreBumpMineTraceRay(bool slow = false)
{
	if (slow)
	{
		StoreToAddress(gA_BumpMineTraceRayAddress, gI_TraceRayPatchRestore, NumberType_Int32);
	}
	else
	{
		StoreToAddressCustom(gA_BumpMineTraceRayAddress, gI_TraceRayPatchRestore, NumberType_Int32);
	}
}


// =====[ STOCKS ]=====

//Faster than native StoreToAddress by ~45 times.
stock void StoreToAddressFast(Address addr, any data)
{
	ASSERT(gH_StoreToAddressFast);
	
	int ret = SDKCall(gH_StoreToAddressFast, addr, data);
	ASSERT(ret == data);
}

stock void StoreToAddressCustom(Address addr, any data, NumberType type)
{
	if (gH_StoreToAddressFast && type == NumberType_Int32)
	{
		StoreToAddressFast(addr, data);
	}
	else
	{
		StoreToAddress(addr, view_as<int>(data), type);
	}
}

/**
 * Checks if the value is a valid client entity index, if they are in-game and not GOTV.
 *
 * @param client		Client index.
 * @return				Whether client is valid.
 */
stock bool IsValidClient(int client)
{
	return client >= 1 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client);
}

/**
 * Gets the nearest point in the oriented bounding box of an entity to a point.
 *
 * @param entity			Entity index.
 * @param origin			Point's origin.
 * @param result			Result point.
 */
stock void CalcNearestPoint(int entity, float origin[3], float result[3])
{
	float entOrigin[3], entMins[3], entMaxs[3], trueMins[3], trueMaxs[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entOrigin);
	GetEntPropVector(entity, Prop_Send, "m_vecMaxs", entMaxs);
	GetEntPropVector(entity, Prop_Send, "m_vecMins", entMins);

	AddVectors(entOrigin, entMins, trueMins);
	AddVectors(entOrigin, entMaxs, trueMaxs);

	for (int i = 0; i < 3; i++)
	{
		result[i] = FloatClamp(origin[i], trueMins[i], trueMaxs[i]);
	}
}

/**
 * Clamp a float value between an upper and lower bound.
 *
 * @param value			Preferred value.
 * @param min			Minimum value.
 * @param max			Maximum value.
 * @return				The closest value to the preferred value.
 */
stock float FloatClamp(float value, float min, float max)
{
	if (value >= max)
	{
		return max;
	}
	if (value <= min)
	{
		return min;
	}
	return value;
}
