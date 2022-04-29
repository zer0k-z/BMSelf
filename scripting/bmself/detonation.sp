void OnPluginStart_Detonation()
{
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
	if (!gH_DHooks_ApplyAbsVelocityImpulse)
	{
		SetFailState("Failed to setup detour for CBaseEntity::ApplyAbsVelocityImpulse");
	}
	if (!DHookEnableDetour(gH_DHooks_ApplyAbsVelocityImpulse, false, Detour_ApplyAbsVelocityImpulse))
	{
		SetFailState("Failed to detour CBaseEntity::ApplyAbsVelocityImpulse.");
	}
	
	// Disable screen shaking
	HookUserMessage(GetUserMessageId("Shake"), OnShakeTransmit, true);
	// Bump mine smoke effect
	AddTempEntHook("EffectDispatch", TE_OnEffectDispatch);
}

public MRESReturn Detour_BumpMineDetonate(int bumpmine, Handle hReturn, Handle hParams)
{
	gI_CurrentBMOwner = GetEntPropEnt(bumpmine, Prop_Data, "m_hOwnerEntity");
	return MRES_Ignored;
}

// Prevent bumpmine detonation from shaking other players' screen
public Action OnShakeTransmit(UserMsg msg_id, Protobuf pb, const int[] players, int playersNum,	bool reliable, bool init) 
{
	if (gI_CurrentBMOwner != -1 && players[0] != gI_CurrentBMOwner)
	{
		gI_LastBMAffectedTime[players[0]] = GetEntData(players[0], gH_GameData.GetOffset("LastBMAffectedTime"));
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// Prevent bumpmine detonation from boosting other players
public MRESReturn Detour_ApplyAbsVelocityImpulse(int client, Handle hReturn, Handle hParams)
{
	if (gI_CurrentBMOwner != -1 && client != gI_CurrentBMOwner)
	{
		SetEntData(client, gH_GameData.GetOffset("LastBMAffectedTime"), gI_LastBMAffectedTime[client]);
		return MRES_Supercede;
	}
	return MRES_Ignored;
}

// Prevent bumpmine from applying particle effects to unaffected players
public Action TE_OnEffectDispatch(const char[] te_name, const int[] Players, int numClients, float delay)
{
	static int effectTable = INVALID_STRING_TABLE;
	if (effectTable == INVALID_STRING_TABLE) 
	{
		effectTable = FindStringTable("EffectDispatch");
	}

	static int particleEffectTable = INVALID_STRING_TABLE;
	if (particleEffectTable == INVALID_STRING_TABLE) 
	{
		particleEffectTable = FindStringTable("ParticleEffectNames");
	}

	char effectName[64];
	ReadStringTable(effectTable, TE_ReadNum("m_iEffectName"), effectName, sizeof(effectName));
	if (!StrEqual(effectName, "ParticleEffect"))
	{
		return Plugin_Continue;
	}

	char particleEffectName[64];
	ReadStringTable(particleEffectTable, TE_ReadNum("m_nHitBox"), particleEffectName, sizeof(particleEffectName));
	int entIndex = TE_ReadNum("entindex");

	if (StrEqual(particleEffectName, "bumpmine_player_trail"))
	{
		// Other players aren't affected by the bump mines so no reason to give them the smoke trail.
		if (entIndex != gI_CurrentBMOwner)
		{
			return Plugin_Stop;
		}
	}
	/* TODO: Let players hide other bump mines and hook this as well.
	else if (StrEqual(particleEffectName, "bumpmine_detonate"))
	{
		RemoveTempEntHook("EffectDispatch", TE_OnEffectDispatch);
		TEBumpMineDetonate te;
		te.Init();
		te.Send(gI_CurrentBMOwner);
		AddTempEntHook("EffectDispatch", TE_OnEffectDispatch);
		return Plugin_Stop;
	}*/
	return Plugin_Continue;
}

public MRESReturn Detour_BumpMineDetonatePost(int bumpmine, Handle hReturn, Handle hParams)
{
	gI_CurrentBMOwner = -1;
	return MRES_Ignored;
}
