# v_anims database: the curated list below -> ../shared/database.lua
# Run: python tools/build_database.py [GTA anim dir]   (default C:/Games/GTA San Andreas/anim/)
# Every name is checked against the GTA IFP files; a non-dive animation whose root bone travels more
# than MAX_TRAVEL metres is refused (walks, runs, jumps). Labels: v_locals v_anims.group.<cmd>.
# entry: "BLOCK:Name[:flags][<INTROBLOCK:Intro][>OUTROBLOCK:Outro]"
# flags: l = loop (default), o = once, h = hold last frame, m = moves the player (dives only)
import json, os, sys
import ifp

CATS = ["sit", "lie", "stand", "social", "gesture", "react", "dance", "food", "act", "work", "sport", "gang", "dive"]

G = [
 # ---------------------------------------------------------------- sitting
 ("sit", "sit", [
   "BEACH:ParkSit_M_loop<SUNBATHE:ParkSit_M_in>SUNBATHE:ParkSit_M_out",
   "BEACH:ParkSit_W_loop<SUNBATHE:ParkSit_W_in>SUNBATHE:ParkSit_W_out",
   "BEACH:SitnWait_loop_W<SUNBATHE:SitnWait_in_W>SUNBATHE:SitnWait_out_W",
   "Attractors:Stepsit_loop<Attractors:Stepsit_in>Attractors:Stepsit_out",
   "SUNBATHE:ParkSit_M_IdleA", "SUNBATHE:ParkSit_M_IdleB", "SUNBATHE:ParkSit_M_IdleC",
   "SUNBATHE:ParkSit_W_idleA", "SUNBATHE:ParkSit_W_idleB", "SUNBATHE:ParkSit_W_idleC",
   "TATTOOS:TAT_Back_Sit_Loop_P",
 ]),
 ("chair", "sit", [
   "ped:SEAT_idle", "INT_OFFICE:OFF_Sit_Idle_Loop", "INT_OFFICE:OFF_Sit_Bored_Loop", "INT_OFFICE:OFF_Sit_Read",
   "INT_OFFICE:OFF_Sit_Watch", "INT_OFFICE:OFF_Sit_Type_Loop", "INT_OFFICE:OFF_Sit_Crash", "FOOD:FF_Sit_Loop",
   "FOOD:FF_Sit_Look", "MISC:SEAT_LR", "MISC:Seat_talk_01", "MISC:Seat_talk_02", "MISC:SEAT_watch",
   "HAIRCUTS:BRB_Sit_Loop", "TATTOOS:TAT_Sit_Loop_P", "INT_HOUSE:LOU_Loop",
 ]),
 ("console", "sit", ["CRIB:PED_Console_Loop", "CRIB:PED_Console_Win:o", "CRIB:PED_Console_Loose:o"]),
 ("casino", "sit", [
   "CASINO:cards_loop", "CASINO:cards_pick_01:o", "CASINO:cards_pick_02:o", "CASINO:cards_raise:o",
   "CASINO:cards_win:o", "CASINO:cards_lose:o", "CASINO:Slot_wait", "CASINO:Slot_Plyr", "CASINO:Slot_bet_01:o",
   "CASINO:Slot_bet_02:o", "CASINO:Roulette_loop", "CASINO:Roulette_bet:o", "CASINO:dealone:o",
 ]),
 # ---------------------------------------------------------------- lying
 ("lay", "lie", [
   "BEACH:Lay_Bac_Loop<SUNBATHE:Lay_Bac_in>SUNBATHE:Lay_Bac_out", "BEACH:bather", "INT_HOUSE:BED_Loop_L",
   "INT_HOUSE:BED_Loop_R", "SUNBATHE:Lay_Bac_in:h", "ped:FLOOR_hit:h", "ped:FLOOR_hit_f:h",
 ]),
 ("crack", "lie", [
   "CRACK:crckidle1", "CRACK:crckidle2", "CRACK:crckidle3", "CRACK:crckidle4",
   "CRACK:crckdeth1:h", "CRACK:crckdeth2:h", "CRACK:crckdeth3:h", "CRACK:crckdeth4:h",
 ]),
 ("dead", "lie", [
   "ped:KO_skid_back:h", "ped:KO_skid_front:h", "ped:KO_spin_L:h", "ped:KO_spin_R:h",
   "FOOD:FF_Die_Bkw:h", "FOOD:FF_Die_Fwd:h", "FOOD:FF_Die_Left:h", "FOOD:FF_Die_Right:h", "WUZI:CS_Dead_Guy:h",
 ]),
 ("injured", "lie", ["SWEET:Sweet_injuredloop", "SWAT:gnstwall_injurd"]),
 # ---------------------------------------------------------------- standing
 ("idle", "stand", [
   "PLAYIDLES:shift:o", "PLAYIDLES:shldr:o", "PLAYIDLES:time:o", "ped:IDLE_HBHB", "ped:idlestance_old",
   "ped:woman_idlestance", "ped:Idlestance_fat", "ped:roadcross", "ped:roadcross_female", "ped:roadcross_gang",
   "ped:roadcross_old", "WUZI:Wuzi_stand_loop", "ped:Idle_Gang1", "MUSCULAR:MuscleIdle", "FAT:FatIdle",
 ]),
 ("lean", "stand", ["GANGS:leanIDLE", "MISC:Plyrlean_loop", "SMOKING:F_smklean_loop", "SMOKING:M_smklean_loop"]),
 ("crossarms", "stand", [
   "COP_AMBIENT:Coplook_loop<COP_AMBIENT:Coplook_in>COP_AMBIENT:Coplook_out", "COP_AMBIENT:Coplook_watch",
   "COP_AMBIENT:Coplook_think", "COP_AMBIENT:Copbrowse_loop<COP_AMBIENT:Copbrowse_in>COP_AMBIENT:Copbrowse_out",
 ]),
 ("lookaround", "stand", [
   "ON_LOOKERS:lkaround_loop", "ON_LOOKERS:lkup_loop", "ped:flee_lkaround_01:o", "CAMERA:camstnd_lkabt:o",
   "OTB:betslp_lkabt",
 ]),
 ("stretch", "stand", ["PLAYIDLES:stretch:o", "PLAYIDLES:strleg:o"]),
 ("tired", "stand", ["ped:IDLE_tired", "FAT:IDLE_tired"]),
 ("scratch", "stand", ["ped:XPRESSscratch:o", "MISC:Scratchballs_01:o"]),
 ("hike", "stand", ["MISC:Hiker_Pose:h", "MISC:Hiker_Pose_L:h", "ped:IDLE_taxi:o"]),
 ("pose", "stand", [
   "CLOTHES:CLO_Pose_Loop", "CLOTHES:CLO_Pose_Hat:o", "CLOTHES:CLO_Pose_Legs:o", "CLOTHES:CLO_Pose_Shoes:o",
   "CLOTHES:CLO_Pose_Torso:o", "CLOTHES:CLO_Pose_Watch:o", "TATTOOS:TAT_Idle_Loop_T",
 ]),
 # ---------------------------------------------------------------- talking / social
 ("talk", "social", [
   "GANGS:prtial_gngtlkA", "GANGS:prtial_gngtlkB", "GANGS:prtial_gngtlkC", "GANGS:prtial_gngtlkD",
   "GANGS:prtial_gngtlkE", "GANGS:prtial_gngtlkF", "GANGS:prtial_gngtlkG", "GANGS:prtial_gngtlkH",
   "ped:IDLE_chat", "MISC:Idle_Chat_02", "ped:endchat_01:o", "ped:endchat_02:o", "ped:endchat_03:o",
 ]),
 ("phone", "social", ["ped:phone_talk<ped:phone_in>ped:phone_out"]),
 ("handshake", "social", [
   "GANGS:hndshkaa:o", "GANGS:hndshkba:o", "GANGS:hndshkca:o", "GANGS:hndshkcb:o", "GANGS:hndshkda:o",
   "GANGS:hndshkea:o", "GANGS:hndshkfa:o", "GANGS:prtial_hndshk_01:o", "GANGS:prtial_hndshk_biz_01:o",
 ]),
 ("kiss", "social", [
   "KISSING:Grlfrd_Kiss_01:o", "KISSING:Grlfrd_Kiss_02:o", "KISSING:Grlfrd_Kiss_03:o",
   "KISSING:Playa_Kiss_01:o", "KISSING:Playa_Kiss_02:o", "KISSING:Playa_Kiss_03:o",
 ]),
 ("argue", "social", [
   "KISSING:GF_StreetArgue_01:o", "KISSING:GF_StreetArgue_02:o", "PAULNMAC:PnM_Argue1_A:o",
   "PAULNMAC:PnM_Argue1_B:o", "PAULNMAC:PnM_Argue2_B:o", "PAULNMAC:PnM_Loop_A", "PAULNMAC:PnM_Loop_B",
 ]),
 ("give", "social", ["KISSING:gift_give:o", "KISSING:gift_get:o", "DEALER:DEALER_DEAL:o", "DEALER:DRUGS_BUY:o", "DEALER:shop_pay:o"]),
 ("slap", "social", ["MISC:bitchslap:o", "SWEET:sweet_ass_slap:o", "SWEET:plyr_hndshldr_01:o"]),
 # ---------------------------------------------------------------- gestures
 ("wave", "gesture", ["ON_LOOKERS:wave_loop<ON_LOOKERS:wave_in>ON_LOOKERS:wave_out", "KISSING:gfwave2:o", "BD_FIRE:BD_GF_Wave:o"]),
 ("point", "gesture", [
   "ON_LOOKERS:point_loop<ON_LOOKERS:point_in>ON_LOOKERS:point_out",
   "ON_LOOKERS:Pointup_loop<ON_LOOKERS:Pointup_in>ON_LOOKERS:Pointup_out", "ON_LOOKERS:lkup_point:o",
   "ON_LOOKERS:panic_point:o",
 ]),
 ("shout", "gesture", [
   "ON_LOOKERS:shout_loop<ON_LOOKERS:shout_in>ON_LOOKERS:shout_out", "ON_LOOKERS:shout_01:o",
   "ON_LOOKERS:shout_02:o", "ON_LOOKERS:Pointup_shout:o", "ON_LOOKERS:panic_shout:o", "RIOT:RIOT_shout:o",
 ]),
 ("comehere", "gesture", [
   "RYDER:RYD_Beckon_01:o", "RYDER:RYD_Beckon_02:o", "RYDER:RYD_Beckon_03:o", "CAMERA:camstnd_cmon:o",
   "MISC:BMX_comeon:o", "OTB:wtchrace_cmon:o",
 ]),
 ("yes", "gesture", ["GANGS:Invite_Yes:o", "COP_AMBIENT:Coplook_nod:o", "COP_AMBIENT:Copbrowse_nod:o"]),
 ("no", "gesture", ["GANGS:Invite_No:o", "MISC:plyr_shkhead:o", "COP_AMBIENT:Coplook_shake:o", "COP_AMBIENT:Copbrowse_shake:o"]),
 ("fucku", "gesture", ["ped:fucku:o", "RIOT:RIOT_FUKU:o"]),
 ("clap", "gesture", ["DANCING:bd_clap", "DANCING:bd_clap1"]),
 ("signal", "gesture", ["SWAT:swt_go:o", "SWAT:swt_sty:o", "SWAT:swt_lkt:o"]),
 # ---------------------------------------------------------------- reactions
 ("handsup", "react", ["SHOP:SHP_Rob_HandsUp", "ROB_BANK:SHP_HandsUp_Scr:h", "ped:handsup:h"]),
 ("cower", "react", [
   "ped:cower", "ped:DUCK_cower", "ped:handscower:h", "ON_LOOKERS:panic_cower", "ON_LOOKERS:panic_hide",
   "SHOP:SHP_Duck:h",
 ]),
 ("panic", "react", [
   "ON_LOOKERS:panic_loop<ON_LOOKERS:panic_in>ON_LOOKERS:panic_out", "BD_FIRE:BD_Panic_Loop",
   "BD_FIRE:BD_Panic_01:o", "BD_FIRE:BD_Panic_02:o", "BD_FIRE:BD_Panic_03:o", "BD_FIRE:BD_Panic_04:o",
 ]),
 ("laugh", "react", ["RAPPING:Laugh_01:o"]),
 ("cheer", "react", [
   "STRIP:PUN_HOLLER", "STRIP:PUN_LOOP", "OTB:wtchrace_win:o", "CASINO:manwinb:o", "CASINO:manwind:o",
   "BSKTBALL:BBALL_react_score:o", "RIOT:RIOT_CHANT",
 ]),
 ("lose", "react", ["OTB:wtchrace_lose:o", "CASINO:Roulette_lose:o", "BSKTBALL:BBALL_react_miss:o"]),
 ("angry", "react", ["RIOT:RIOT_ANGRY", "RIOT:RIOT_ANGRY_B", "RIOT:RIOT_challenge", "RIOT:RIOT_PUNCHES"]),
 ("mourn", "react", ["GRAVEYARD:mrnF_loop", "GRAVEYARD:mrnM_loop", "GRAVEYARD:prst_loopa"]),
 ("vomit", "react", ["FOOD:EAT_Vomit_P:o", "FOOD:EAT_Vomit_SK:o"]),
 ("cough", "react", ["ped:gas_cwr", "HEIST9:CAS_G2_GasKO:h"]),
 # ---------------------------------------------------------------- dance
 ("dance", "dance", [
   "DANCING:dance_loop", "DANCING:DAN_Loop_A", "DANCING:DAN_Down_A", "DANCING:DAN_Left_A", "DANCING:DAN_Right_A",
   "DANCING:DAN_Up_A", "DANCING:dnce_M_a", "DANCING:dnce_M_b", "DANCING:dnce_M_c", "DANCING:dnce_M_d",
   "DANCING:dnce_M_e",
 ]),
 ("gfunk", "dance", ["GFUNK:Dance_B%d" % i for i in range(1, 17)] + ["GFUNK:Dance_G%d" % i for i in range(1, 17)]),
 ("runman", "dance", ["RUNNINGMAN:Dance_B%d" % i for i in range(1, 17)] + ["RUNNINGMAN:Dance_G%d" % i for i in range(1, 17)]),
 ("wop", "dance", ["WOP:Dance_B%d" % i for i in range(1, 17)] + ["WOP:Dance_G%d" % i for i in range(1, 17)]),
 ("strip", "dance", [
   "STRIP:strip_A", "STRIP:strip_B", "STRIP:strip_C", "STRIP:strip_D", "STRIP:strip_E", "STRIP:strip_F",
   "STRIP:strip_G", "STRIP:STR_Loop_A", "STRIP:STR_Loop_B", "STRIP:STR_Loop_C",
 ]),
 ("rap", "dance", ["RAPPING:RAP_A_Loop", "RAPPING:RAP_B_Loop", "RAPPING:RAP_C_Loop"]),
 # ---------------------------------------------------------------- food, drink, smoke
 ("smoke", "food", [
   "SMOKING:M_smk_loop<SMOKING:M_smk_in>SMOKING:M_smk_out", "SMOKING:M_smkstnd_loop", "SMOKING:M_smk_drag:o",
   "SMOKING:M_smk_tap:o", "GANGS:smkcig_prtl", "GANGS:smkcig_prtl_F", "SHOP:Smoke_RYD",
 ]),
 ("drink", "food", [
   "BAR:dnk_stndM_loop", "BAR:dnk_stndF_loop", "GANGS:drnkbr_prtl", "GANGS:drnkbr_prtl_F", "VENDING:VEND_Drink_P:o",
   "VENDING:VEND_Drink2_P:o", "INT_OFFICE:OFF_Sit_Drink",
 ]),
 ("eat", "food", [
   "FOOD:EAT_Burger:o", "FOOD:EAT_Chicken:o", "FOOD:EAT_Pizza:o", "VENDING:VEND_Eat_P:o", "VENDING:vend_eat1_P:o",
   "ped:gum_eat:o", "FOOD:FF_Sit_Eat1", "FOOD:FF_Sit_Eat2", "FOOD:FF_Sit_Eat3",
 ]),
 # ---------------------------------------------------------------- actions
 ("crouch", "act", [
   "BOMBER:BOM_Plant_Loop<BOMBER:BOM_Plant_In>BOMBER:BOM_Plant_2Idle", "CAMERA:camcrch_idleloop",
   "BOMBER:BOM_Plant_Crouch_In:h", "ped:WEAPON_crouch:h", "WUZI:Wuzi_grnd_chk:o",
 ]),
 ("bomb", "act", ["BOMBER:BOM_Plant:o", "MISC:Plunger_01:o"]),
 ("photo", "act", [
   "CAMERA:picstnd_take:o", "CAMERA:piccrch_take:o", "CAMERA:camstnd_idleloop", "CAMERA:camcrch_stay",
 ]),
 ("use", "act", [
   "ped:ATM:o", "VENDING:VEND_Use:o", "HEIST9:Use_SwipeCard:o", "CRIB:CRIB_Use_Switch:o", "MISC:door_jet:o",
   "INT_SHOP:shop_shelf:o",
 ]),
 ("knock", "act", ["MISC:bng_wndw:o", "MISC:bng_wndw_02:o", "POLICE:Door_Kick:o"]),
 ("spray", "act", ["GRAFFITI:spraycan_fire", "SPRAYCAN:spraycan_full:o", "GRAFFITI:graffiti_Chkout:o"]),
 ("wash", "act", ["BD_FIRE:wash_up:o"]),
 ("piss", "act", ["PAULNMAC:Piss_loop<PAULNMAC:Piss_in>PAULNMAC:Piss_out"]),
 ("bet", "act", ["OTB:betslp_loop<OTB:betslp_in>OTB:betslp_out", "OTB:betslp_tnk:o", "OTB:wtchrace_loop"]),
 ("peek", "act", ["SWAT:swt_wllpk_L:o", "SWAT:swt_wllpk_R:o"]),
 ("threat", "act", ["SHOP:ROB_Loop_Threat", "SHOP:ROB_Shifty:o", "SHOP:SHP_Gun_Threat:o", "ped:ARRESTgun:h"]),
 # ---------------------------------------------------------------- work
 ("fix", "work", ["CAR:Fixn_Car_Loop", "CAR:flag_drop:o"]),
 ("cpr", "work", ["MEDIC:CPR"]),
 ("copsign", "work", ["POLICE:CopTraf_Stop", "POLICE:CopTraf_Come", "POLICE:CopTraf_Away", "POLICE:CopTraf_Left"]),
 ("shop", "work", [
   "INT_SHOP:shop_loop", "INT_SHOP:shop_cashier:o", "INT_SHOP:shop_lookA:o", "INT_SHOP:shop_lookB:o",
   "SHOP:SHP_Serve_Idle", "SHOP:SHP_Serve_Loop",
 ]),
 ("bar", "work", [
   "BAR:BARman_idle", "BAR:Barserve_loop", "BAR:Barserve_glass:o", "BAR:Barserve_bottle:o", "BAR:Barserve_give:o",
   "BAR:Barcustom_loop", "BAR:Barcustom_order:o",
 ]),
 ("dealer", "work", ["DEALER:DEALER_IDLE", "DEALER:DEALER_IDLE_01", "DEALER:DEALER_IDLE_02", "DEALER:DEALER_IDLE_03", "GANGS:DEALER_IDLE"]),
 # ---------------------------------------------------------------- sport, fighting
 ("fight", "sport", [
   "ped:FIGHTIDLE", "FIGHT_B:FightB_IDLE", "FIGHT_C:FightC_IDLE", "FIGHT_D:FightD_IDLE", "FIGHT_C:FightC_Spar",
   "FIGHT_C:FightC_blocking", "CRACK:Bbalbat_Idle_01", "CRACK:Bbalbat_Idle_02",
 ]),
 ("punch", "sport", ["ped:FightA_1:o", "FIGHT_B:FightB_1:o", "FIGHT_C:HitC_1:o", "RIOT:RIOT_PUNCHES:o"]),
 ("box", "sport", ["GYMNASIUM:GYMshadowbox"]),
 ("taichi", "sport", ["PARK:Tai_Chi_Loop<PARK:Tai_Chi_in>PARK:Tai_Chi_Out"]),
 ("bball", "sport", [
   "BSKTBALL:BBALL_idleloop", "BSKTBALL:BBALL_def_loop", "BSKTBALL:BBALL_Jump_Shot:o", "BSKTBALL:BBALL_pickup:o",
 ]),
 ("pool", "sport", ["POOL:POOL_Idle_Stance", "POOL:POOL_ChalkCue:o"]),
 # ---------------------------------------------------------------- gang
 ("gsign", "gang", [
   "GHANDS:gsign1", "GHANDS:gsign2", "GHANDS:gsign3", "GHANDS:gsign4", "GHANDS:gsign5",
   "GHANDS:gsign1LH", "GHANDS:gsign2LH", "GHANDS:gsign3LH", "GHANDS:gsign4LH", "GHANDS:gsign5LH",
   "GHANDS:LHGsign1:o", "GHANDS:LHGsign2:o", "GHANDS:LHGsign3:o", "GHANDS:LHGsign4:o", "GHANDS:LHGsign5:o",
   "GHANDS:RHGsign1:o", "GHANDS:RHGsign2:o", "GHANDS:RHGsign3:o", "GHANDS:RHGsign4:o", "GHANDS:RHGsign5:o",
 ]),
 # ---------------------------------------------------------------- dives (the only animations that move the player)
 ("dive", "dive", ["ped:EV_dive:m", "DODGE:Cover_Dive_01:m", "DODGE:Cover_Dive_02:m", "MISC:Run_Dive:m", "DODGE:Crush_Jump:m"]),
 ("roll", "dive", ["ped:Crouch_Roll_L:m", "ped:Crouch_Roll_R:m", "ped:EV_step:m"]),
]

# Non-dive entries must stay in place (metres of root bone travel, horizontal)
MAX_TRAVEL = 0.8
MAX_INTRO = 0.5

def main(gta_dir, out_lua):
    d = ifp.dump(gta_dir)
    lower = {b.lower(): (b, {n.lower(): n for n in v}) for b, v in d.items()}

    def find(spec):
        blk, name = spec.split(":")[:2]
        if blk.lower() not in lower or name.lower() not in lower[blk.lower()][1]:
            raise SystemExit("missing anim " + spec)
        rb, names = lower[blk.lower()]
        rn = names[name.lower()]
        return rb, rn, d[rb][rn]

    def mtaBlock(b):
        return "ped" if b == "ped" else b

    errors, out, seen_cmd, total = [], [], set(), 0
    out.append("-- GENERATED by tools/build_database.py from tools/spec.py and the GTA SA IFP files. Do not edit by hand.")
    out.append("-- Entry: { block, anim, flags, intro, outro, ms } flags: l loop, o once, h hold last frame, m moves the player")
    out.append("-- ms = length of the main animation (once / hold / move), intro / outro = { block, anim, ms }")
    out.append("ANIM_CATEGORIES = { " + ", ".join('"%s"' % c for c in CATS) + " }")
    out.append("ANIM_GROUPS = {")
    for cmd, cat, entries in G:
        assert cat in CATS, cat
        assert cmd not in seen_cmd, cmd
        seen_cmd.add(cmd)
        out.append('    { cmd = "%s", cat = "%s", anims = {' % (cmd, cat))
        seen = set()
        for e in entries:
            outro = intro = None
            if ">" in e: e, outro = e.split(">")
            if "<" in e: e, intro = e.split("<")
            parts = e.split(":")
            flags = parts[2] if len(parts) > 2 else "l"
            b, n, info = find(e)
            key = (b.lower(), n.lower())
            if key in seen: errors.append("dup %s %s" % (cmd, e))
            seen.add(key)
            if "m" not in flags and info["maxd"] > MAX_TRAVEL:
                errors.append("moves %.2f m: %s/%s" % (info["maxd"], cmd, e))
            fields = ['"%s"' % mtaBlock(b), '"%s"' % n, '"%s"' % flags]
            for extra in (intro, outro):
                if extra:
                    xb, xn, xi = find(extra)
                    if xi["maxd"] > MAX_INTRO: errors.append("intro/outro moves %.2f: %s" % (xi["maxd"], extra))
                    fields.append('{ "%s", "%s", %d }' % (mtaBlock(xb), xn, round(xi["dur"] * 1000)))
                else:
                    fields.append("false")
            fields.append(str(round(info["dur"] * 1000)))
            out.append("        { " + ", ".join(fields) + " },")
            total += 1
        out.append("    } },")
    out.append("}")
    if errors:
        print("\n".join(errors))
        raise SystemExit(1)
    open(out_lua, "w", newline="\n").write("\n".join(out) + "\n")
    print("groups", len(G), "anims", total)

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1] if len(sys.argv) > 1 else ifp.GTA, os.path.join(here, "..", "shared", "database.lua"))
