void OnPluginStart_Misc()
{
	// CBaseEntity::WorldSpaceCenter SDKCall setup
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetVirtual(gH_GameData.GetOffset("CBaseEntity::WorldSpaceCenter"));
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	gH_WorldSpaceCenter_SDKCall = EndPrepSDKCall();

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