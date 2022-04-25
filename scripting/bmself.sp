#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#include <bmself>
#pragma newdecls required
#pragma semicolon 1


public Plugin myinfo =
{
	name = "BMSelf",
	author = "zer0.k",
	description = "Prevent bump mine from affecting non owners",
	version = "1.2.0",
	url = "https://github.com/zer0k-z/BMSelf"
};


// Credits to backwards for the original plugin, GAMMACASE for StoreToAddressFast, lacyyy for bump mine logic.
GameData gH_GameData;

// Misc
Handle gH_StoreToAddressFast;
Handle gH_WorldSpaceCenter_SDKCall;

// Detection
bool gB_BumpMineSphereQueryDisabled;
Address gA_BumpMineSphereAddress;
int gI_SpherePatchRestore;

Address gA_BumpMineTraceRayAddress;
int gI_TraceRayPatchRestore;

Address gA_BumpMineThinkAddress;
int gI_BumpMineThinkSlowAddress;
int gI_BumpMineThinkFastAddress;

// Detonation
int gI_CurrentBMOwner = -1;
Handle gH_DHooks_BumpMineDetonate, gH_DHooks_ApplyAbsVelocityImpulse;

#define BM_BBOX_CHECK_DIST 81.0
#define ASM_PATCH_LEN 17
#include "glib/memutils"

#include "bmself/misc.sp"
#include "bmself/detection.sp"
#include "bmself/detonation.sp"

public void OnPluginStart()
{
	gH_GameData = LoadGameConfigFile("bmself.games");
	if (!gH_GameData)
	{
		SetFailState("Failed to load BMSelf gamedata.");
		return;
	}
	OnPluginStart_Misc();
	OnPluginStart_Detonation();
	OnPluginStart_Detection();
}

public void OnPluginEnd()
{
	OnPluginEnd_Detection();
}

public void OnEntityCreated(int entity, const char[] classname)
{
	OnEntityCreated_Detection(entity, classname);
}