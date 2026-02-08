#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_DESCRIPTION "Regex triggers for names, chat, and commands."
#define PLUGIN_VERSION "2.5.12"
#define MAX_EXPRESSION_LENGTH 512
#define MATCH_SIZE 64

// Define created to use settings specifically for my own servers.
// allows easier release of this plugin.
// #define CUSTOM
// #define DEBUG

#include <sourcemod>
#include <sdktools>
#include <regex>
#include <multicolors>

#undef REQUIRE_EXTENSIONS
#include <tf2>
#include <discord>
#define REQUIRE_EXTENSIONS

enum {
	NAME = 0,
	CHAT,
	COMMAND,
	TRIGGER_COUNT
}

ArrayList g_aSections[TRIGGER_COUNT];
ConVar g_cvarStatus,
	   g_cvarConfigPath,
	   g_cvarCheckChat,
	   g_cvarCheckCommands,
	   g_cvarCheckNames,
	   g_cvarUnnamedPrefix,
	   g_cvarDiscordWebhook,
	   g_cvarServerName;
Regex g_rRegexCaptures;
StringMap g_smClientLimits[TRIGGER_COUNT][MAXPLAYERS+1];
bool g_bLate,
	 g_bChanged[MAXPLAYERS+1],
	 g_bDiscord;
char g_sConfigPath[PLATFORM_MAX_PATH],
	 g_sDiscordWebhook[256],
	 g_sOldName[MAXPLAYERS+1][MAX_NAME_LENGTH],
	 g_sUnfilteredName[MAXPLAYERS+1][MAX_NAME_LENGTH],
	 g_sPrefix[MAX_NAME_LENGTH],
	 g_sServerName[32];
EngineVersion g_EngineVersion;

// https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/tf/bot/tf_bot.cpp#L143
char g_sRandomNames[][] = {
	"Chucklenuts",
	"CryBaby",
	"WITCH",
	"ThatGuy",
	"Still Alive",
	"Hat-Wearing MAN",
	"Me",
	"Numnutz",
	"H@XX0RZ",
	"The G-Man",
	"Chell",
	"The Combine",
	"Totally Not A Bot",
	"Pow!",
	"Zepheniah Mann",
	"THEM",
	"LOS LOS LOS",
	"10001011101",
	"DeadHead",
	"ZAWMBEEZ",
	"MindlessElectrons",
	"TAAAAANK!",
	"The Freeman",
	"Black Mesa",
	"Soulless",
	"CEDA",
	"BeepBeepBoop",
	"NotMe",
	"CreditToTeam",
	"BoomerBile",
	"Someone Else",
	"Mann Co.",
	"Dog",
	"Kaboom!",
	"AmNot",
	"0xDEADBEEF",
	"HI THERE",
	"SomeDude",
	"GLaDOS",
	"Hostage",
	"Headful of Eyeballs",
	"CrySomeMore",
	"Aperture Science Prototype XR7",
	"Humans Are Weak",
	"AimBot",
	"C++",
	"GutsAndGlory!",
	"Nobody",
	"Saxton Hale",
	"RageQuit",
	"Screamin' Eagles",
	"Ze Ubermensch",
	"Maggot",
	"CRITRAWKETS",
	"Herr Doktor",
	"Gentlemanne of Leisure",
	"Companion Cube",
	"Target Practice",
	"One-Man Cheeseburger Apocalypse",
	"Crowbar",
	"Delicious Cake",
	"IvanTheSpaceBiker",
	"I LIVE!",
	"Cannon Fodder",
	"trigger_hurt",
	"Nom Nom Nom",
	"Divide by Zero",
	"GENTLE MANNE of LEISURE",
	"MoreGun",
	"Tiny Baby Man",
	"Big Mean Muther Hubbard",
	"Force of Nature",
	"Crazed Gunman",
	"Grim Bloody Fable",
	"Poopy Joe",
	"A Professional With Standards",
	"Freakin' Unbelievable",
	"SMELLY UNFORTUNATE",
	"The Administrator",
	"Mentlegen",
	"Archimedes!",
	"Ribs Grow Back",
	"It's Filthy in There!",
	"Mega Baboon",
	"Kill Me",
	"Glorified Toaster with Legs"
};

enum struct Section {
	char Name[128];
	ArrayList Regexes;
	StringMap Rules;

	void Initialize(const char[] name)
	{
		strcopy(this.Name, sizeof(Section::Name), name);
		this.Regexes = new ArrayList();
		this.Rules = new StringMap();
	}
	void Destroy()
	{
		delete this.Regexes;
		delete this.Rules;
	}
}

public Plugin myinfo = {
	name = "RegexTrigger",
	author = "JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("sm_regextriggers_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY).SetString(PLUGIN_VERSION);
	g_cvarStatus = CreateConVar("sm_regex_allow", "1", "Status of the plugin.\n(1 = on, 0 = off)", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarConfigPath = CreateConVar("sm_regex_config_path", "configs/regextriggers/", "Location to store the regex filters at.", FCVAR_NONE);
	g_cvarCheckChat = CreateConVar("sm_regex_check_chat", "1", "Filter out and check chat messages.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarCheckCommands = CreateConVar("sm_regex_check_commands", "1", "Filter out and check commands.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarCheckNames = CreateConVar("sm_regex_check_names", "1", "Filter out and check names.", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarUnnamedPrefix = CreateConVar("sm_regex_prefix", "", "Prefix for random name when player has become unnamed", FCVAR_NONE);
	g_cvarServerName = CreateConVar("sm_regex_server_name", "No name set!", "Name to display in discord when relaying", FCVAR_NONE);

	// Discord
	g_cvarDiscordWebhook = CreateConVar("sm_regex_discord_webhook", "", "Discord webhook URL for flagged words relay", FCVAR_NONE);

	g_cvarUnnamedPrefix.AddChangeHook(cvarChanged_Prefix);
	g_cvarDiscordWebhook.AddChangeHook(cvarChanged_DiscordWebhook);
	g_cvarServerName.AddChangeHook(cvarChanged_ServerName);

	AutoExecConfig();

	g_cvarUnnamedPrefix.GetString(g_sPrefix, sizeof(g_sPrefix));
	g_cvarDiscordWebhook.GetString(g_sDiscordWebhook, sizeof(g_sDiscordWebhook));
	g_cvarConfigPath.GetString(g_sConfigPath, sizeof(g_sConfigPath));
	g_cvarServerName.GetString(g_sServerName, sizeof g_sServerName);

	BuildPath(Path_SM, g_sConfigPath, sizeof(g_sConfigPath), g_sConfigPath);
	Format(g_sConfigPath, sizeof(g_sConfigPath), "%sregextriggers.cfg", g_sConfigPath);

	if (!FileExists(g_sConfigPath))
	{
		SetFailState("Error finding file: %s", g_sConfigPath);
	}

#if defined DEBUG
	RegAdminCmd("sm_testname", cmdTestName, ADMFLAG_ROOT);
#endif

	HookUserMessage(GetUserMessageId("SayText2"), hookUserMessage, true);
	HookEvent("player_connect_client", eventPlayerConnect, EventHookMode_Pre);
	HookEvent("player_connect", eventPlayerConnect, EventHookMode_Pre);
	HookEvent("player_changename", eventOnChangeName, EventHookMode_Pre);

	LoadTranslations("common.phrases");

	for (int i = 0; i < TRIGGER_COUNT; ++i)
	{
		g_aSections[i] = new ArrayList(sizeof(Section));

		for (int j = 1; j <= MaxClients; ++j)
		{
			g_smClientLimits[i][j] = new StringMap();
		}
	}

	g_rRegexCaptures = new Regex("\\\\\\d+");

    KeyValues kv = new KeyValues("GameInfo");
	kv.ImportFromFile("gameinfo.txt");

	char gameDir[128];
	GetGameFolderName(gameDir, sizeof(gameDir));

    g_EngineVersion = GetEngineVersion();
	if (!StrEqual(gameDir, "tf") &&
		(kv.GetNum("DependsOnAppID") == 440 ||
		(g_EngineVersion == Engine_SDK2013 && FileExists("resource/tf.ttf"))))
	{
		g_EngineVersion = Engine_TF2;
	}
    delete kv;

	if (g_bLate)
	{
		for (int i = 1; i <= MaxClients; ++i)
		{
			if (IsClientConnected(i) && !IsFakeClient(i))
			{
				FormatEx(g_sOldName[i], sizeof(g_sOldName[]), "%N", i);
				FormatEx(g_sUnfilteredName[i], sizeof(g_sUnfilteredName[]), "%N", i);
			}
		}

		timerLoadExpressions(null);
	}
	else
	{
		// 5 second delay to ease OnPluginStart workload
		CreateTimer(5.0, timerLoadExpressions);
	}
}

public void OnAllPluginsLoaded()
{
	g_bDiscord = GetExtensionFileStatus("discord.ext") > 0;
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "discord"))
	{
		g_bDiscord = false;
	}
}

public void OnClientPostAdminCheck(int client)
{
	if (!g_cvarStatus.BoolValue)
	{
		return;
	}

	ClearData(client);
	ConnectNameCheck(client);
}

public void OnClientDisconnect(int client)
{
	ClearData(client);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] args)
{
	if (!g_cvarStatus.BoolValue || !g_cvarCheckChat.BoolValue || IsChatTrigger())
	{
		return Plugin_Continue;
	}

	// I use a plugin on my own servers that forces say_team to say
#if defined CUSTOM
	if (StrEqual(command, "say_team"))
	{
		return Plugin_Handled;
	}
#endif

	if (!args[0] || !client)
	{
		return Plugin_Continue;
	}

	return CheckClientMessage(client, command, args);
}

public Action OnClientCommand(int client, int argc) {
	if (!g_cvarStatus.BoolValue || !g_cvarCheckCommands.BoolValue || client == 0) {
		return Plugin_Continue;
	}

	char command[256];
	GetCmdArgString(command, sizeof(command));

	if (!command[0] || StrContains(command, "say") == 0) {
		return Plugin_Continue;
	}

	char args[256];
	GetCmdArgString(args, sizeof(args));

	return CheckClientCommand(client, command);
}

// =================== ConVar Hook

void cvarChanged_Prefix(ConVar convar, const char[] oldValue, const char[] newValue)
{
	strcopy(g_sPrefix, sizeof(g_sPrefix), newValue);
}

void cvarChanged_DiscordWebhook(ConVar convar, const char[] oldValue, const char[] newValue)
{
	strcopy(g_sDiscordWebhook, sizeof(g_sDiscordWebhook), newValue);
}

void cvarChanged_ServerName(ConVar convar, const char[] oldValue, const char[] newValue)
{
	strcopy(g_sServerName, sizeof(g_sServerName), newValue);
}

// =================== Hooks

public Action eventPlayerConnect(Event event, const char[] name, bool dontBroadcast)
{
	event.BroadcastDisabled = true;
	return Plugin_Continue;
}

public Action hookUserMessage(UserMsg msg_hd, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	char sMessage[96];
	bf.ReadString(sMessage, sizeof(sMessage));
	bf.ReadString(sMessage, sizeof(sMessage));

	return (StrContains(sMessage, "Name_Change") != -1) ? Plugin_Handled : Plugin_Continue;
}

public Action eventOnChangeName(Event event, const char[] name, bool dontBroadcast)
{
	/* This event hook is a bit hacky because it's called each time the name is changed,
	 * including the name changes triggered by the plugin. Because of this, it can cause
	 * loops to occur. Some of the checks that occur here are to prevent that from happening.
	 * If the player name matches a filter, g_bChanged will be true and CheckClientName will
	 * set the players name, retriggering this hook. CheckClientName will be called again,
	 * however, the second time, it will only announce the name change to the server. */

	if (!g_cvarStatus.BoolValue || !g_cvarCheckNames.BoolValue)
	{
		return Plugin_Continue;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	char currentName[MAX_NAME_LENGTH];
	event.GetString("oldname", currentName, sizeof(currentName));

	char newName[MAX_NAME_LENGTH];
	event.GetString("newname", newName, sizeof(newName));

	// If old name is empty (initial connect), stored old name, or current name equal to new name, don't do anything.
	if (!g_sOldName[client][0] || StrEqual(g_sOldName[client], newName) || StrEqual(currentName, newName))
	{
		g_bChanged[client] = false;
		return Plugin_Continue;
	}

	// If name is unchanged, store it so we can use it for discord relay.
	if (!g_bChanged[client])
	{
		strcopy(g_sUnfilteredName[client], sizeof(g_sUnfilteredName[]), newName);
	}

	return CheckClientName(client, newName, sizeof(newName));
}

// =================== Commands
#if defined DEBUG
public Action cmdTestName(int client, int args)
{
	char arg[128];
	GetCmdArg(1, arg, sizeof(arg));

	SetClientName(client, arg);
	return Plugin_Handled;
}
#endif
// =================== Timers

Action timerLoadExpressions(Handle timer)
{
	LoadRegexConfig(g_sConfigPath);

	PrintToChatAll("Regex config loaded.");

	return Plugin_Continue;
}

void timerForgive(Handle timer, DataPack dp)
{
	dp.Reset();
	int client = GetClientOfUserId(dp.ReadCell());

	if (!client)
	{
		delete dp;
		return;
	}

	int index = dp.ReadCell();

	char sectionName[128];
	dp.ReadString(sectionName, sizeof(sectionName));

	delete dp;

	int count;
	if (g_smClientLimits[index][client].GetValue(sectionName, count) && count > 0)
	{
		g_smClientLimits[index][client].SetValue(sectionName, --count);
	}
}

// =================== Config Loading

void LoadRegexConfig(const char[] config)
{
	if (!FileExists(config))
	{
		ThrowError("Error finding file: %s", config);
	}

	KeyValues kv = new KeyValues("RegexFilters");
	kv.ImportFromFile(config);

	if (!kv.GotoFirstSubKey())
	{
		ThrowError("Error reading config at %s. No first sub key.", config);
	}

	do {
		char sectionName[128];
		kv.GetSectionName(sectionName, sizeof(sectionName));

		Section section[TRIGGER_COUNT];
		section[NAME].Initialize(sectionName);
		section[CHAT].Initialize(sectionName);
		section[COMMAND].Initialize(sectionName);

		if (!kv.GotoFirstSubKey(false))
		{
			LogError("Config section %s has no keys", sectionName);
			continue;
		}

		char key[128];
		char buffer[MAX_EXPRESSION_LENGTH];
		do {
			kv.GetSectionName(key, sizeof(key));

			if (StrEqual(key, "namepattern"))
			{
				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				RegisterExpression(buffer, section[NAME]);
			}
			else if (StrEqual(key, "chatpattern"))
			{
				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				RegisterExpression(buffer, section[CHAT]);
			}
			else if (StrEqual(key, "cmdpattern"))
			{
				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				RegisterExpression(buffer, section[COMMAND]);
			}
			else if (StrEqual(key, "replace"))
			{
				ArrayList replacements;

				for (int i = 0; i < TRIGGER_COUNT; ++i)
				{
					if (!section[i].Rules.GetValue("replace", replacements))
					{
						replacements = new ArrayList(ByteCountToCells(sizeof(buffer)));
						section[i].Rules.SetValue("replace", replacements);
					}

					kv.GetString(NULL_STRING, buffer, sizeof(buffer));
					replacements.PushString(buffer);
				}
			}
			else if (StrEqual(key, "block") || StrEqual(key, "limit") || StrEqual(key, "relay"))
			{
				UpdateRuleValue(section, key, kv.GetNum(NULL_STRING));
			}
			else if (StrEqual(key, "forgive"))
			{
				UpdateRuleValue(section, key, kv.GetFloat(NULL_STRING));
			}
			else if (StrEqual(key, "action") || StrEqual(key, "warn") || StrEqual(key, "punish"))
			{
				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				UpdateRuleString(section, key, buffer);
			}
			else if (StrEqual(key, "immunity"))
			{
				kv.GetString(NULL_STRING, buffer, sizeof(buffer));
				UpdateRuleValue(section, key, ReadFlagString(buffer));
			}
			else {
				LogError("Invalid key while parsing config. Section: %s Key: %s", sectionName, key);
			}

		} while (kv.GotoNextKey(false));

		// for each section type ...
		for (int i = 0; i < TRIGGER_COUNT; ++i)
		{
			// if section has at least one regex and rule ...
			if (section[i].Regexes.Length && section[i].Rules.Size)
			{
				// push it to its respective arraylist ...
				g_aSections[i].PushArray(section[i], sizeof(section[]));
			}
			// otherwise ...
			else {
				// destroy the section Handles.
				section[i].Destroy();
			}
		}

		kv.GoBack();
	} while (kv.GotoNextKey());

	delete kv;
}

void UpdateRuleValue(Section section[TRIGGER_COUNT], const char[] key, any value)
{
	for (int i = 0; i < TRIGGER_COUNT; ++i)
	{
		section[i].Rules.SetValue(key, value);
	}
}

void UpdateRuleString(Section section[TRIGGER_COUNT], const char[] key, const char[] value)
{
	for (int i = 0; i < TRIGGER_COUNT; ++i)
	{
		section[i].Rules.SetString(key, value);
	}
}

void RegisterExpression(const char[] key, Section section)
{
	char expression[MAX_EXPRESSION_LENGTH];
	int flags = ParseExpression(key, expression, sizeof(expression));

	if (flags == -1)
	{
		return;
	}

	char error[128];
	RegexError errorcode;
	Regex regex = new Regex(expression, flags, error, sizeof(error), errorcode);

	if (regex == null)
	{
		LogError("Error compiling expression '%s' with flags '%i': [%i] %s", expression, flags, errorcode, error);
		return;
	}

	section.Regexes.Push(regex);
}

int ParseExpression(const char[] key, char[] expression, int size)
{
	strcopy(expression, size, key);
	TrimString(expression);

	int flags;
	int a;
	int b;
	int c;

	if (expression[strlen(expression) - 1] == '\'')
	{
		for (; expression[flags] != '\0'; flags++)
		{
			if (expression[flags] == '\'')
			{
				a++;
				b = c;
				c = flags;
			}
		}

		if (a < 2)
		{
			LogError("Regex Filter line malformed: %s", key);
			return -1;
		}

		expression[b] = '\0';
		expression[c] = '\0';
		flags = FindRegexFlags(expression[b + 1]);

		TrimString(expression);

		if (a > 2 && expression[0] == '\'')
		{
			strcopy(expression, strlen(expression) - 1, expression[1]);
		}
	}

	return flags;
}

int FindRegexFlags(const char[] flags)
{
	char sBuffer[7][16];
	ExplodeString(flags, "|", sBuffer, 7, 16);

	int new_flags;
	for (int i = 0; i < 7; ++i)
	{
		if (sBuffer[i][0] == '\0')
		{
			continue;
		}
		if (StrEqual(sBuffer[i], "CASELESS"))
		{
			new_flags |= PCRE_CASELESS;
		}
		else if (StrEqual(sBuffer[i], "MULTILINE"))
		{
			new_flags |= PCRE_MULTILINE;
		}
		else if (StrEqual(sBuffer[i], "DOTALL"))
		{
			new_flags |= PCRE_DOTALL;
		}
		else if (StrEqual(sBuffer[i], "EXTENDED"))
		{
			new_flags |= PCRE_EXTENDED;
		}
		else if (StrEqual(sBuffer[i], "UNGREEDY"))
		{
			new_flags |= PCRE_UNGREEDY;
		}
		else if (StrEqual(sBuffer[i], "UTF8"))
		{
			new_flags |= PCRE_UTF8;
		}
		else if (StrEqual(sBuffer[i], "NO_UTF8_CHECK"))
		{
			new_flags |= PCRE_NO_UTF8_CHECK;
		}
		else if (StrEqual(sBuffer[i], "UCP"))
		{
			new_flags |= PCRE_UCP;
		}
	}

	return new_flags;
}

// =================== Internal Functions

void ClearData(int client)
{
	g_bChanged[client] = false;
	g_sOldName[client][0] = '\0';
	g_sUnfilteredName[client][0] = '\0';

	for (int i = 0; i < TRIGGER_COUNT; ++i)
	{
		g_smClientLimits[i][client].Clear();
	}
}

void ParseAndExecute(int client, char[] command, int size)
{
	char buffer[32];
	IntToString(GetClientUserId(client), buffer, sizeof buffer);
	ReplaceString(command, size, "%u", buffer);

	IntToString(client, buffer, sizeof buffer);
	ReplaceString(command, size, "%i", buffer);

	FormatEx(buffer, sizeof(buffer), "%N", client);
	ReplaceString(command, size, "%n", buffer);

	ServerCommand(command);
}

bool LimitClient(int client, int type, const char[] sectionName, int limit, StringMap rules)
{
	if (type >= TRIGGER_COUNT)
	{
		LogError("Invalid type %i. Expected in range of (0, %i)", type, TRIGGER_COUNT-1);
		return false;
	}

	char buffer[128];
	int clientLimitCount;
	g_smClientLimits[type][client].GetValue(sectionName, clientLimitCount);
	g_smClientLimits[type][client].SetValue(sectionName, ++clientLimitCount);

	CPrintToChat(
		  client
		, "\x01[{red}Filter\x01] Max limit for this trigger is set to {lime}%i\x01. Current: {lime}%i."
		, limit
		, clientLimitCount
	);

	float forgive;
	if (rules.GetValue("forgive", forgive))
	{
		DataPack dp = new DataPack();
		dp.WriteCell(GetClientUserId(client));
		dp.WriteCell(type);
		dp.WriteString(sectionName);
		CreateTimer(forgive, timerForgive, dp);

		CPrintToChat(client, "\x01[{red}Filter\x01] Forgiven in {lime}%0.1f\x01 seconds", forgive);
	}

	if (clientLimitCount >= limit && rules.GetString("punish", buffer, sizeof(buffer)))
	{
		CPrintToChat(client, "\x01[{red}Filter\x01] You have hit the limit of {lime}%i", limit);

		ParseAndExecute(client, buffer, sizeof(buffer));

		if (!IsClientConnected(client))
		{
			return false;
		}
	}

	return true;
}

void ReplaceText(Regex regex, int matchCount, ArrayList replaceList, char[] text, int size)
{
	int captureCount = regex.CaptureCount();
	char[][][] matches = new char[matchCount][captureCount][MATCH_SIZE];

	char buffer[MATCH_SIZE];
	char buffer2[8];
	// for each match
	for (int j = 0; j < matchCount; j++)
	{
		// Get random replacement text
		char replacement[128];
		replaceList.GetString(GetRandomInt(0, replaceList.Length-1), replacement, sizeof(replacement));

		for (int k = 0; k < captureCount; ++k)
		{
			// Store all captures in dynamic char array, where 0 is the entire match
			regex.GetSubString(k, matches[j][k], MATCH_SIZE, j);
		}

		// check if there are capture group characters in replacement text (eg:\0, \1, \2)
		int charcount = g_rRegexCaptures.MatchAll(replacement);
		// if there are ...
		if (charcount > 0)
		{
			// make a loop for each character
			for (int k = 0; k < charcount; ++k)
			{
				// extract it from substring and store in buffer
				g_rRegexCaptures.GetSubString(0, buffer, sizeof(buffer), k);

				// copy buffer integer to buffer2
				strcopy(buffer2, sizeof(buffer2), buffer[1]);

				// convert to index
				int index = StringToInt(buffer2);

				if (index >= captureCount || index < 1)
				{
					continue;
				}

				ReplaceString(replacement, sizeof(replacement), buffer, matches[j][index]);
			}
		}

		ReplaceString(text, size, matches[j][0], replacement);
	}
}

void AnnounceNameChange(int client, char[] newName, bool connecting = false)
{
	if (connecting) {
		CPrintToChatAll("%s connected", newName);
	} else if (!StrEqual(g_sOldName[client], newName)) {
		CPrintToChatAllEx(client, "\x01* {teamcolor}%s\x01 changed name to {teamcolor}%s", g_sOldName[client], newName);
	}

	g_bChanged[client] = false;
	strcopy(g_sOldName[client], MAX_NAME_LENGTH, newName);
}

void ConnectNameCheck(int client)
{
	if (IsFakeClient(client) || !g_cvarCheckNames.BoolValue)
	{
		return;
	}

	char clientName[MAX_NAME_LENGTH];
	FormatEx(clientName, sizeof(clientName), "%N", client);
	FormatEx(g_sUnfilteredName[client], sizeof(g_sUnfilteredName[]), "%N", client);

	CheckClientName(client, clientName, sizeof(clientName), true);
}

Action CheckClientName(int client, char[] newName, int size, bool connecting = false)
{
	if (client < 1 || client > MaxClients || IsFakeClient(client))
	{
		return Plugin_Continue;
	}

	// If name has already been checked, try to announce
	if (g_bChanged[client])
	{
		AnnounceNameChange(client, newName, connecting);
		return Plugin_Continue;
	}

	ArrayList nameSections = g_aSections[NAME];

	int begin;
	int end = nameSections.Length;

	Section nameSection;

	char sectionName[128];
	ArrayList regexList;
	StringMap rules;

	Regex regex;
	RegexError errorcode;

	int matchCount;
	int immunityFlag;
	char buffer[256];
	int limit;
	bool relay;
	ArrayList replaceList;
	bool replaced;

	while (begin != end)
	{
		nameSections.GetArray(begin, nameSection, sizeof(Section));

		rules = nameSection.Rules;

		if (rules.GetValue("immunity", immunityFlag) && CheckCommandAccess(client, "", immunityFlag, true))
		{
			begin++;
			continue;
		}

		strcopy(sectionName, sizeof(sectionName), nameSection.Name);

		regexList = nameSection.Regexes;
		int len = regexList.Length;
		for (int i = 0; i < len; i++)
		{
			regex = regexList.Get(i);

			matchCount = regex.MatchAll(newName, errorcode);
			if (matchCount < 1 || errorcode != REGEX_ERROR_NONE)
			{
				continue;
			}

			if (rules.GetString("warn", buffer, sizeof(buffer)))
			{
				CPrintToChat(client, "\x01[{red}Filter\x01] {lime}%s", buffer);
			}

			if (rules.GetString("action", buffer, sizeof(buffer)))
			{
				ParseAndExecute(client, buffer, sizeof(buffer));
			}

			if (rules.GetValue("limit", limit))
			{
				bool result = LimitClient(client, NAME, sectionName, limit, rules);

				if (!result) // false if not connected
				{
					return Plugin_Continue;
				}
			}

			rules.GetValue("relay", relay);

			if (rules.GetValue("replace", replaceList))
			{
				g_bChanged[client] = true;
				replaced = true;

				ReplaceText(regex, matchCount, replaceList, newName, size);
			}

			if (newName[0] == '\0')
			{
				break;
			}

			if (replaced)
			{
				begin = -1;
				replaced = false;
				break;
			}
		}

		if (newName[0] == '\0')
		{
			break;
		}

		begin++;
	}

	Action ret = Plugin_Continue;

	if (g_bChanged[client])
	{
		TrimString(newName);

		if (StrEqual(g_sOldName[client], newName))
		{
			g_bChanged[client] = false;
		}

		if (newName[0] == '\0')
		{
			int randomnum = GetRandomInt(0, sizeof(g_sRandomNames)-1);
			FormatEx(newName, MAX_NAME_LENGTH, "%s%s", g_sPrefix, g_sRandomNames[randomnum]);
		}

		SetClientName(client, newName);

		ret = Plugin_Stop;
	}

	if (relay && g_bDiscord && g_sDiscordWebhook[0])
	{
		char output[192];
		FormatEx(output, sizeof(output), "**%s** `%s`  -->  `%s`", g_sServerName, g_sUnfilteredName[client], newName);

		DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
		webhook.Execute(output);
	}

	AnnounceNameChange(client, newName, connecting);

	return ret;
}

Action CheckClientMessage(int client, const char[] command, const char[] text)
{
	char message[128];
	strcopy(message, sizeof(message), text);

	ArrayList chatSections = g_aSections[CHAT];

	int begin;
	int end = chatSections.Length;

	Section chatSection;

	StringMap rules;
	int immunityFlag;

	char sectionName[128];
	ArrayList regexList;

	int matchCount;

	Regex regex;
	RegexError errorcode;

	char buffer[256];
	int limit;
	int relay;
	bool block;
	ArrayList replaceList;
	bool replaced;
	bool changed;

	while (begin != end)
	{
		chatSections.GetArray(begin, chatSection, sizeof(chatSection));

		rules = chatSection.Rules;

		if (rules.GetValue("immunity", immunityFlag) && CheckCommandAccess(client, "", immunityFlag, true))
		{
			begin++;
			continue;
		}

		strcopy(sectionName, sizeof(sectionName), chatSection.Name);

		regexList = chatSection.Regexes;

		for (int i = 0; i < regexList.Length; i++)
		{
			regex = regexList.Get(i);

			matchCount = regex.MatchAll(message, errorcode);
			if (matchCount < 1 || errorcode != REGEX_ERROR_NONE)
			{
				continue;
			}

			if (rules.GetString("warn", buffer, sizeof(buffer)))
			{
				CPrintToChat(client, "\x01[{red}Filter\x01] {lime}%s", buffer);
			}

			if (rules.GetString("action", buffer, sizeof(buffer)))
			{
				ParseAndExecute(client, buffer, sizeof(buffer));
			}

			if (rules.GetValue("limit", limit))
			{
				bool result = LimitClient(client, CHAT, sectionName, limit, rules);

				if (!result)
				{
					return Plugin_Handled;
				}
			}

			rules.GetValue("relay", relay);

			if (rules.GetValue("block", block) && block)
			{
				if (relay && g_bDiscord && g_sDiscordWebhook[0])
				{
					char clientName[MAX_NAME_LENGTH];
					GetClientName(client, clientName, sizeof(clientName));

					char output[256];
					if (changed)
					{
						Format(output, sizeof(output), "**%s** %s: `%s` --> `%s` **Blocked**", g_sServerName, clientName, text, message);
					}
					else
					{
						Format(output, sizeof(output), "**%s** %s: `%s`", g_sServerName, clientName, message);
					}

					DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
					webhook.Execute(output);
				}

				return Plugin_Handled;
			}

			if (rules.GetValue("replace", replaceList))
			{
				replaced = true;
				changed = true;

				ReplaceText(regex, matchCount, replaceList, message, sizeof(message));
			}

			if (message[0] == '\0')
			{
				return Plugin_Handled;
			}

			if (replaced)
			{
				begin = -1;
				replaced = false;
				break;
			}
		}

		++begin;
	}

	if (changed)
	{
		if (relay && g_bDiscord && g_sDiscordWebhook[0])
		{
			char clientName[MAX_NAME_LENGTH];
			Format(clientName, sizeof(clientName), "%N", client);

			char output[256];
			Format(output, sizeof(output), "**%s** %s: `%s`  -->  `%s`", g_sServerName, clientName, text, message);

			DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
			webhook.Execute(output);
		}

		FakeClientCommand(client, "%s %s", command, message);
		return Plugin_Handled;
	}

	if (relay && g_bDiscord && g_sDiscordWebhook[0])
	{
		char clientName[MAX_NAME_LENGTH];
		Format(clientName, sizeof(clientName), "%N", client);

		char output[256];
		Format(output, sizeof(output), "**%s** %s: `%s`", g_sServerName, clientName, message);

		DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
		webhook.Execute(output);
	}

	return Plugin_Continue;
}

Action CheckClientCommand(int client, char[] cmd)
{
	char command[128];
	strcopy(command, sizeof(command), cmd);

	ArrayList commandSections = g_aSections[COMMAND];

	int begin;
	int end = commandSections.Length;

	Section commandSection;

	StringMap rules;
	int immunityFlag;

	char sectionName[128];
	ArrayList regexList;

	Regex regex;
	RegexError errorcode;

	int matchCount;
	char buffer[128];
	int limit;
	bool relay;
	bool block;
	ArrayList replaceList;
	bool replaced;
	bool changed;

	while (begin != end)
	{
		commandSections.GetArray(begin, commandSection, sizeof(commandSection));

		rules = commandSection.Rules;

		if (rules.GetValue("immunity", immunityFlag) && CheckCommandAccess(client, "", immunityFlag, true))
		{
			begin++;
			continue;
		}

		strcopy(sectionName, sizeof(sectionName), commandSection.Name);

		regexList = commandSection.Regexes;

		for (int i = 0; i < regexList.Length; i++)
		{
			regex = regexList.Get(i);

			matchCount = regex.MatchAll(command, errorcode);
			if (matchCount <= 0 || errorcode != REGEX_ERROR_NONE)
			{
				begin++;
				continue;
			}

			if (rules.GetString("warn", buffer, sizeof(buffer)))
			{
				CPrintToChat(client, "\x01[{red}Filter\x01] {lime}%s", buffer);
			}

			if (rules.GetString("action", buffer, sizeof(buffer)))
			{
				ParseAndExecute(client, buffer, sizeof(buffer));
			}

			if (rules.GetValue("limit", limit))
			{
				bool result = LimitClient(client, COMMAND, sectionName, limit, rules);

				if (!result)
				{
					return Plugin_Handled;
				}
			}

			rules.GetValue("relay", relay);

			if (rules.GetValue("block", block) && block)
			{
				if (relay && g_bDiscord && g_sDiscordWebhook[0])
				{
					char clientName[MAX_NAME_LENGTH];
					GetClientName(client, clientName, sizeof(clientName));

					char output[256];
					if (changed)
					{
						Format(output, sizeof(output), "**%s** Command| %s: `%s` --> `%s` **Blocked**", g_sServerName, clientName, cmd, command);
					}
					else
					{
						Format(output, sizeof(output), "**%s** Command| %s: `%s`", g_sServerName, clientName, command);
					}

					DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
					webhook.Execute(output);
				}

				return Plugin_Handled;
			}

			if (rules.GetValue("replace", replaceList))
			{
				i = -1;
				replaced = true;
				changed = true;

				ReplaceText(regex, matchCount, replaceList, command, sizeof(command));
			}

			if (command[0] == '\0')
			{
				return Plugin_Handled;
			}

			if (replaced)
			{
				begin = -1;
				replaced = false;
				break;
			}
		}

		begin++;
	}

	if (changed)
	{
		if (relay && g_bDiscord && g_sDiscordWebhook[0])
		{
			char clientName[MAX_NAME_LENGTH];
			Format(clientName, sizeof(clientName), "%N", client);

			char output[256];
			Format(output, sizeof(output), "**%s** Command| %s: `%s`  -->  `%s`", g_sServerName, clientName, cmd, command);

			DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
			webhook.Execute(output);
		}

		FakeClientCommand(client, "%s", command);
		return Plugin_Handled;
	}

	if (relay && g_bDiscord && g_sDiscordWebhook[0])
	{
		char clientName[MAX_NAME_LENGTH];
		Format(clientName, sizeof(clientName), "%N", client);

		char output[256];
		Format(output, sizeof(output), "**%s** Command| %s: `%s`", g_sServerName, clientName, command);

		DiscordWebhook webhook = new DiscordWebhook(null, g_sDiscordWebhook);
		webhook.Execute(output);
	}

	return Plugin_Continue;
}
