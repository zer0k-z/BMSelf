void OnPluginStart_Detection()
{
	// Bump mine's sphere query and trace setup.
	gA_BumpMineSphereAddress = gH_GameData.GetAddress("BumpMineThink") + view_as<Address>(gH_GameData.GetOffset("BumpMineSphereQueryOffset"));
	gA_BumpMineTraceRayAddress = gH_GameData.GetAddress("BumpMineThink") + view_as<Address>(gH_GameData.GetOffset("BumpMineTraceRayOffset"));
	gA_BumpMineThinkAddress = gH_GameData.GetAddress("BumpMineThink") + view_as<Address>(gH_GameData.GetOffset("ThinkTimer"));
	gI_BumpMineThinkFastAddress = LoadFromAddress(gH_GameData.GetAddress("ThinkFast") + view_as<Address>(gH_GameData.GetOffset("ThinkFastOffset")),NumberType_Int32);
	gI_BumpMineThinkSlowAddress = LoadFromAddress(gA_BumpMineThinkAddress, NumberType_Int32);
	// Bump mines' trace ray never hits the owner, so there is no reason to toggle this on and off constantly.
	DisableBumpMineTraceRay();
}

void OnPluginEnd_Detection()
{
	// StoreToAddressFast does not work here.
	RestoreBumpMineSphereQuery(true);
	RestoreBumpMineTraceRay(true);
}

void OnEntityCreated_Detection(int entity, const char[] classname)
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
	// TODO: Make this toggleable on a player by player basis.
	ReduceBumpMineThinkTime();
}

public void OnBumpMineThinkPost(int bumpmine)
{
	RestoreBumpMineSphereQuery();
	RestoreBumpMineThinkTime();
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

void ReduceBumpMineThinkTime()
{
	static bool firstRun = true;
	if (firstRun)
	{
		StoreToAddress(gA_BumpMineThinkAddress, gI_BumpMineThinkFastAddress, NumberType_Int32);
	}
	else
	{
		StoreToAddressCustom(gA_BumpMineThinkAddress, gI_BumpMineThinkFastAddress, NumberType_Int32);
		firstRun = false;
	}
}

void RestoreBumpMineThinkTime(bool slow = false)
{
	if (slow)
	{
		StoreToAddress(gA_BumpMineThinkAddress, gI_BumpMineThinkSlowAddress, NumberType_Int32);
	}
	else
	{
		StoreToAddressCustom(gA_BumpMineThinkAddress, gI_BumpMineThinkSlowAddress, NumberType_Int32);
	}
}