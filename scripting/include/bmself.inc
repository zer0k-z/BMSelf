#if defined _bmself_included
#endinput
#endif
#define _bmself_included

enum struct TEBumpMineDetonate
{
	int effectIndex;
	float vOrigin[3];
	float vStart[3];
	float vAngles[3];
	int hitBox;

	void Init()
	{
		this.effectIndex = TE_ReadNum("m_iEffectName");
		this.hitBox = TE_ReadNum("m_nHitBox");
		this.vOrigin[0] = TE_ReadFloat("m_vOrigin.x");
		this.vOrigin[1] = TE_ReadFloat("m_vOrigin.y");
		this.vOrigin[2] = TE_ReadFloat("m_vOrigin.z");
		this.vStart[0] = TE_ReadFloat("m_vStart.x");
		this.vStart[1] = TE_ReadFloat("m_vStart.y");
		this.vStart[2] = TE_ReadFloat("m_vStart.z");
		TE_ReadVector("m_vAngles", this.vAngles);
	}
	void Send(int client)
	{
		TE_Start("EffectDispatch");
		TE_WriteNum("m_nHitBox", this.hitBox);
		TE_WriteFloat("m_vOrigin.x", this.vOrigin[0]);
		TE_WriteFloat("m_vOrigin.y", this.vOrigin[1]);
		TE_WriteFloat("m_vOrigin.z", this.vOrigin[2]);
		TE_WriteFloat("m_vStart.x", this.vStart[0]);
		TE_WriteFloat("m_vStart.y", this.vStart[1]);
		TE_WriteFloat("m_vStart.z", this.vStart[2]);
		TE_WriteVector("m_vAngles", this.vAngles);
		TE_SendToClient(client);
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
