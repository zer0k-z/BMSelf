#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <dhooks>
#pragma newdecls required
#pragma semicolon 1

Address gA_BumpMineTraceRayAddress;
int gI_TraceRayPatchRestore;
GameData gH_GameData;
Handle gH_StoreToAddressFast;

#define ASM_PATCH_LEN 24
#include "glib/memutils"

public void OnPluginStart()
{
	gH_GameData = LoadGameConfigFile("BMSelf.games");
	if (!gH_GameData)
	{
		SetFailState("Failed to load BMSelf gamedata.");
		return;
	}

	Address DuckStart;
	DuckStart = gH_GameData.GetAddress("CGameMovement::Duck_Start");
	if (!DuckStart)
	{
		SetFailState("Can't find start of the CGameMovement::Duck function.");
	}
	
	PatchHandler ASMPatch = PatchHandler(DuckStart);
	ASMPatch.Save(ASM_PATCH_LEN);
	
	Address start = ASMPatch.Address;
	char buffer[128];
	for (int i = 0; i < ASM_PATCH_LEN; i++)
	{
		Format(buffer, sizeof(buffer), "%s %x", buffer, LoadFromAddress(start+i, NumberType_Int8));
	}
	PrintToServer(buffer);
	StoreToAddress(start, 0x8B_EC_8B_55, NumberType_Int32);
	StoreToAddress(start + 4, 0x4D_8B_0C_45, NumberType_Int32);
	StoreToAddress(start + 8, 0x8B_01_89_08, NumberType_Int32);
	StoreToAddress(start + 12, 0x08_C2_5D_E5, NumberType_Int32);
	StoreToAddress(start + 16, 0x00, NumberType_Int8);

	StartPrepSDKCall(SDKCall_Static);
	
	PrepSDKCall_SetAddress(start);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	gH_StoreToAddressFast = EndPrepSDKCall();

	gA_BumpMineTraceRayAddress = gH_GameData.GetAddress("BumpMineThink") + view_as<Address>(gH_GameData.GetOffset("BumpMineTraceRayOffset"));
	PrintToServer("0x%x, %i, gA_BumpMineTraceRayAddress = 0x%x", gH_GameData.GetAddress("BumpMineThink"), gH_GameData.GetOffset("BumpMineTraceRayOffset"), gA_BumpMineTraceRayAddress);
	
	RegServerCmd("sm_rip", CommandNuke, "Apparently crashes the server");
}

public Action CommandNuke(int args)
{
	DisableBumpMineTraceRay();
	return Plugin_Handled;
}

public void OnPluginEnd()
{
}

void DisableBumpMineTraceRay()
{
	gI_TraceRayPatchRestore = LoadFromAddress(gA_BumpMineTraceRayAddress, NumberType_Int32);
	PrintToServer("Old: 0x%x at 0x%x", gI_TraceRayPatchRestore, gA_BumpMineTraceRayAddress);
	PrintToServer("Patching bytes: 0x%x", 0xE990 + (gI_TraceRayPatchRestore >>> 16 << 16));
	StoreToAddressCustom(gA_BumpMineTraceRayAddress, 0xE990 + (gI_TraceRayPatchRestore >>> 16 << 16), NumberType_Int32);
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
	PrintToServer("StoreToAddressFast addr = 0x%x, data = 0x%x", addr, data);
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