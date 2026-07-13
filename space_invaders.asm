; ============================================================
; SPACE INVADERS - TRS-80 Model I/III (64x16, block graphics)
;
; Formation-based model: one origin (FORM_COL/FORM_ROW/FORM_SUB)
; positions all 55 invaders. FORM_SUB is both the 1-pixel
; horizontal shift and the animation state (matches the two
; target screenshots StartGame / StartGameOneMoveRight).
;
; Sprite templates are 5 bytes per char row (blank margins left
; and right) so horizontal movement self-cleans - no flicker.
;
; Assemble: zmac space_invaders.asm   -> zout/space_invaders.cmd
; Run:      trs80gp -m3 zout/space_invaders.cmd
; Keys:     Left/Right arrows move, SPACE fires
; ============================================================

        ORG     5200H

; --- Hardware ---
SCREEN          EQU     3C00H
KBD_CTL         EQU     3840H   ; bit5=LEFT bit6=RIGHT bit7=SPACE (1=pressed)
SOUND_PORT      EQU     0FFH
BLANK           EQU     128

; --- Layout (from target screenshots) ---
FORM_COL0       EQU     13      ; leftmost invader char column at start
FORM_ROW0       EQU     1       ; top invader char row at start
; March limits are computed from the outermost ALIVE column, so the
; formation keeps marching until the surviving edge invader touches
; the screen border. FORM_COL is treated as SIGNED (can go negative
; when left formation columns are dead).
INV_COLS        EQU     11
INV_ROWS        EQU     5
SHIELD_ROW      EQU     13
PLAYER_ROW      EQU     15
PLAYER_X0       EQU     24
PLAYER_XMAX     EQU     61

BULLET_CH       EQU     149     ; left pixel column lit
TORP_CH         EQU     170     ; right pixel column lit

SIDEBAR_W       EQU     5       ; columns 0..4 are the status sidebar
UFO_XMIN        EQU     5       ; row 0 right of the sidebar is all UFO
UFO_XMAX        EQU     61      ; sprite is 3 wide -> spans up to col 63

; ============================================================
; Entry
; ============================================================
START:
        DI
        LD      SP, 7FFFH

; ============================================================
; Splash - title + high score, wait for a SPACE tap.
; Waits press AND release so the game doesn't start firing.
; ============================================================
Splash:
        CALL    Cls
        LD      HL, TXT_TITLE
        LD      DE, SCREEN + 1 * 64 + 25
        LD      BC, 14
        LDIR
        LD      HL, TXT_MISSION
        LD      DE, SCREEN + 3 * 64 + 16
        LD      BC, 32
        LDIR
        LD      HL, TXT_HISC
        LD      DE, SCREEN + 5 * 64 + 24
        LD      BC, 11
        LDIR
        LD      HL, HISCORE_D
        LD      DE, SCREEN + 5 * 64 + 35
        LD      B, 4
_sp_hs:
        LD      A, (HL)
        ADD     A, '0'
        LD      (DE), A
        INC     HL
        INC     DE
        DJNZ    _sp_hs
        ; score advance table: saucer + the three invader types
        LD      B, 7
        LD      C, 25
        CALL    ScreenAddr
        LD      (HL), 174
        INC     HL
        LD      (HL), 143
        INC     HL
        LD      (HL), 157
        LD      HL, TXT_MYST
        LD      DE, SCREEN + 7 * 64 + 31
        LD      BC, 11
        LDIR
        LD      B, 9
        LD      C, 24
        LD      E, 0                    ; squid
        CALL    DrawTableSprite
        LD      HL, TXT_P30
        LD      DE, SCREEN + 9 * 64 + 31
        LD      BC, 11
        LDIR
        LD      B, 11
        LD      C, 24
        LD      E, 1                    ; crab
        CALL    DrawTableSprite
        LD      HL, TXT_P20
        LD      DE, SCREEN + 11 * 64 + 31
        LD      BC, 11
        LDIR
        LD      B, 13
        LD      C, 24
        LD      E, 2                    ; octopus
        CALL    DrawTableSprite
        LD      HL, TXT_P10
        LD      DE, SCREEN + 13 * 64 + 31
        LD      BC, 11
        LDIR
        LD      HL, TXT_START
        LD      DE, SCREEN + 15 * 64 + 22
        LD      BC, 20
        LDIR
_sp_rel:
        LD      A, (KBD_CTL)
        BIT     7, A
        JR      NZ, _sp_rel
_sp_prs:
        LD      A, (KBD_CTL)
        BIT     7, A
        JR      Z, _sp_prs
_sp_rel2:
        LD      A, (KBD_CTL)
        BIT     7, A
        JR      NZ, _sp_rel2

RESTART:
        CALL    Cls
        XOR     A
        LD      (SCORE_D), A
        LD      (SCORE_D+1), A
        LD      (SCORE_D+2), A
        LD      (SCORE_D+3), A
        LD      (GAME_OVER), A
        LD      (WAVE_NUM), A           ; InitWave bumps it to 1
        LD      A, 3
        LD      (LIVES), A
        CALL    DrawHUD
        CALL    InitWave

MainLoop:
        CALL    ReadKeys
        CALL    UpdateBullet
        CALL    UpdateFormation
        CALL    UpdateTorpedo
        CALL    MaybeFireTorpedo
        CALL    UpdateUFO
        CALL    UpdateExplosions
        ; wave ends only once the mystery ship is gone too
        LD      A, (WAVE_DONE)
        OR      A
        JR      Z, _ml_nowave
        LD      A, (UFO_ACT)
        OR      A
        CALL    Z, InitWave
_ml_nowave:
        LD      A, (GAME_OVER)
        OR      A
        JP      NZ, GameOver
        CALL    FrameDelay
        JP      MainLoop

; ============================================================
; Cls - clear whole screen
; ============================================================
Cls:
        LD      HL, SCREEN
        LD      (HL), BLANK
        LD      DE, SCREEN + 1
        LD      BC, 1023
        LDIR
        RET

; ============================================================
; InitWave - fresh formation, shields, player, projectiles
; ============================================================
InitWave:
        LD      A, (UFO_ACT)
        OR      A
        CALL    NZ, EraseUFO            ; row 0 is not part of the area clear
        XOR     A
        LD      (UFO_ACT), A
        LD      (UFO_PH), A
        CALL    UFOReload
        ; snuff any running explosions (row-0 ones survive the area clear)
        LD      IX, EXPL_TBL
        LD      B, NEXPL
_iw_expl:
        LD      A, (IX+0)
        OR      A
        JR      Z, _iw_exnext
        PUSH    BC
        LD      B, (IX+2)
        LD      C, (IX+3)
        LD      E, (IX+4)
        CALL    ExplErase
        POP     BC
        LD      (IX+0), 0
_iw_exnext:
        LD      DE, 5
        ADD     IX, DE
        DJNZ    _iw_expl
        XOR     A
        LD      (WAVE_DONE), A
        LD      (BUL_ACT), A
        LD      (TORP_ACT), A
        LD      (TORP_PH), A
        LD      (FORM_SUB), A
        LD      (FORM_YSUB), A
        LD      (FORM_DIR), A           ; 0 = moving right
        LD      A, 50
        LD      (TORP_CNT), A
        LD      A, FORM_COL0
        LD      (FORM_COL), A
        LD      A, 14
        LD      (FORM_CNT), A           ; grace; accu needs 16 more frames,
                                        ; so step 1 lands on frame 30 as before
        LD      HL, 0
        LD      (FORM_ACC), HL
        LD      HL, WAVE_NUM
        INC     (HL)
        ; per-wave start depth: later waves begin lower (pixel-wise),
        ; capped at wave 5 = one YSUB step above the last playable row
        LD      A, (HL)
        DEC     A                       ; 0-based wave index
        CP      NWAVE_START
        JR      C, _iw_dcap
        LD      A, NWAVE_START - 1
_iw_dcap:
        ADD     A, A                    ; 2 bytes per entry
        LD      E, A
        LD      D, 0
        LD      HL, WAVE_START_TBL
        ADD     HL, DE
        LD      A, (HL)
        LD      (FORM_ROW), A
        INC     HL
        LD      A, (HL)
        LD      (FORM_YSUB), A
        LD      A, INV_COLS * INV_ROWS
        LD      (ALIVE_CNT), A
        LD      A, PLAYER_X0
        LD      (PLAYER_X), A

        ; all invaders alive
        LD      HL, ALIVE_ARR
        LD      B, INV_COLS * INV_ROWS
_iw_fill:
        LD      (HL), 1
        INC     HL
        DJNZ    _iw_fill

        ; clear play area rows 1..15
        LD      HL, SCREEN + 64
        LD      (HL), BLANK
        LD      DE, SCREEN + 65
        LD      BC, 15 * 64 - 1
        LDIR

        CALL    DrawShields
        CALL    DrawPlayer
        CALL    DrawFormation
        CALL    DrawHUD                 ; area clear wiped the sidebar rows
        RET

; ============================================================
; DrawHUD - status sidebar in columns 0..4: SCORE + digits,
; player tag, reserve ships bottom-left. Row 0 right of the
; sidebar stays free for the mystery ship.
; ============================================================
DrawHUD:
        LD      HL, TXT_SCORE
        LD      DE, SCREEN
        LD      BC, 5
        LDIR
        LD      HL, TXT_P1
        LD      DE, SCREEN + 3 * 64
        LD      BC, 2
        LDIR
        CALL    DrawScore
        CALL    DrawLives
        RET

TXT_SCORE:
        DB      'SCORE'
TXT_P1:
        DB      'P1'
TXT_OVER:
        DB      'GAME OVER'
TXT_AGAIN:
        DB      'PRESS SPACE'
TXT_TITLE:
        DB      'SPACE INVADERS'
TXT_HISC:
        DB      'HIGH SCORE '
TXT_START:
        DB      'PRESS SPACE TO START'
TXT_MISSION:
        DB      'DEFEND EARTH - STOP THE INVASION'
TXT_MYST:
        DB      '= ? MYSTERY'
TXT_P30:
        DB      '= 30 POINTS'
TXT_P20:
        DB      '= 20 POINTS'
TXT_P10:
        DB      '= 10 POINTS'

; DrawTableSprite - splash helper: blit invader type E (0..2),
; state 0 / ysub 0, at B=row (2 rows), C=col (5 chars)
DrawTableSprite:
        LD      D, 0
        LD      HL, TYPE_OFF
        ADD     HL, DE
        LD      A, (HL)                 ; type*60
        CALL    ScreenAddr              ; HL = target (preserves A, DE)
        EX      DE, HL
        LD      L, A
        LD      H, 0
        LD      BC, SPRITES
        ADD     HL, BC
        LD      BC, 5
        LDIR
        LD      A, E
        ADD     A, 59
        LD      E, A
        JR      NC, _dts_nc
        INC     D
_dts_nc:
        LD      BC, 5
        LDIR
        RET

DrawScore:
        LD      HL, SCORE_D
        LD      DE, SCREEN + 64         ; sidebar row 1
        LD      B, 4
_dsc_loop:
        LD      A, (HL)
        ADD     A, '0'
        LD      (DE), A
        INC     HL
        INC     DE
        DJNZ    _dsc_loop
        RET

; DrawLives - reserve ships (LIVES-1, max 3) parked bottom-left
DrawLives:
        LD      HL, SCREEN + 13 * 64
        CALL    _dl_blank3
        LD      HL, SCREEN + 14 * 64
        CALL    _dl_blank3
        LD      HL, SCREEN + 15 * 64
        CALL    _dl_blank3
        LD      A, (LIVES)
        OR      A
        RET     Z
        DEC     A
        RET     Z
        CP      3
        JR      C, _dl_n
        LD      A, 3
_dl_n:
        LD      B, A
        LD      HL, SCREEN + 15 * 64
_dl_draw:
        LD      (HL), 160               ; the player ship glyph
        INC     HL
        LD      (HL), 184
        INC     HL
        LD      (HL), 176
        LD      DE, -66                 ; one row up, back to col 0
        ADD     HL, DE
        DJNZ    _dl_draw
        RET
_dl_blank3:
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        RET

; AddScoreTens: A = tens to add (1..3), updates display
AddScoreTens:
        LD      HL, SCORE_D + 2         ; tens digit
        ADD     A, (HL)
        CP      10
        JR      C, _ast_store
        SUB     10
        LD      (HL), A
        DEC     HL                      ; hundreds
        INC     (HL)
        LD      A, (HL)
        CP      10
        JR      C, _ast_done
        LD      (HL), 0
        DEC     HL                      ; thousands
        INC     (HL)
        LD      A, (HL)
        CP      10
        JR      C, _ast_done
        LD      (HL), 0
        JR      _ast_done
_ast_store:
        LD      (HL), A
_ast_done:
        CALL    DrawScore
        RET

; ============================================================
; DrawShields - exact char codes from target screenshots
; ============================================================
DrawShields:
        LD      HL, SHIELD_A
        LD      DE, SCREEN + SHIELD_ROW * 64 + 14
        CALL    DrawShield1
        LD      HL, SHIELD_B
        LD      DE, SCREEN + SHIELD_ROW * 64 + 26
        CALL    DrawShield1
        LD      HL, SHIELD_A
        LD      DE, SCREEN + SHIELD_ROW * 64 + 39
        CALL    DrawShield1
        LD      HL, SHIELD_B
        LD      DE, SCREEN + SHIELD_ROW * 64 + 51
        ; fall through
DrawShield1:
        LD      BC, 6
        LDIR
        ; next char row: advance DE by 64-6
        LD      A, E
        ADD     A, 58
        LD      E, A
        JR      NC, _dsh_nc
        INC     D
_dsh_nc:
        LD      BC, 6
        LDIR
        RET

SHIELD_A:
        DB      128,176,176,176,144,128
        DB      191,191,143,175,191,149
SHIELD_B:
        DB      128,160,176,176,176,128
        DB      170,191,159,143,191,191

; ============================================================
; Player
; ============================================================
DrawPlayer:
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        CALL    ScreenAddr
        LD      (HL), 160
        INC     HL
        LD      (HL), 184
        INC     HL
        LD      (HL), 176
        RET

ErasePlayer:
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        CALL    ScreenAddr
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        RET

; ============================================================
; ReadKeys - TRS-80 keyboard matrix, active high
; ============================================================
ReadKeys:
        LD      A, (KBD_CTL)
        LD      B, A
        BIT     5, B                    ; LEFT
        JR      Z, _rk_right
        LD      A, (PLAYER_X)
        CP      SIDEBAR_W + 1
        JR      C, _rk_right            ; stay right of the sidebar
        CALL    ErasePlayer
        LD      HL, PLAYER_X
        DEC     (HL)
        CALL    DrawPlayer
_rk_right:
        BIT     6, B                    ; RIGHT
        JR      Z, _rk_fire
        LD      A, (PLAYER_X)
        CP      PLAYER_XMAX
        JR      NC, _rk_fire
        CALL    ErasePlayer
        LD      HL, PLAYER_X
        INC     (HL)
        CALL    DrawPlayer
_rk_fire:
        BIT     7, B                    ; SPACE
        RET     Z
        LD      A, (BUL_ACT)
        OR      A
        RET     NZ
        ; spawn at PLAYER_X+1, one row above player
        LD      A, (PLAYER_X)
        INC     A
        LD      (BUL_X), A
        LD      C, A
        LD      A, PLAYER_ROW - 1
        LD      (BUL_Y), A
        LD      B, A
        CALL    ScreenAddr
        LD      A, (HL)
        CP      BLANK
        JR      Z, _rk_fire_ok
        ; shot straight into own shield: erode it, no bullet
        CALL    ErodeShieldUp
        JP      PewSound
_rk_fire_ok:
        LD      (HL), BULLET_CH
        LD      A, 1
        LD      (BUL_ACT), A
        JP      PewSound

; ============================================================
; UpdateBullet - 1 row per frame, peek-before-draw collision
; ============================================================
UpdateBullet:
        LD      A, (BUL_ACT)
        OR      A
        RET     Z
        ; erase current position
        LD      A, (BUL_X)
        LD      C, A
        LD      A, (BUL_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      (HL), BLANK
        ; move up
        LD      A, (BUL_Y)
        DEC     A
        LD      (BUL_Y), A
        CP      1
        JR      C, _ub_die              ; reached HUD row
        ; peek new cell
        LD      B, A
        LD      A, (BUL_X)
        LD      C, A
        CALL    ScreenAddr
        LD      A, (HL)
        CP      BLANK
        JR      NZ, _ub_hit
        LD      (HL), BULLET_CH
        RET
_ub_die:
        XOR     A
        LD      (BUL_ACT), A
        ; bullet crossed into row 0 - did it hit the UFO?
        LD      A, (UFO_ACT)
        OR      A
        RET     Z
        LD      A, (UFO_X)
        LD      C, A
        LD      A, (BUL_X)
        SUB     C
        CP      3
        RET     NC
        JP      KillUFO
_ub_hit:
        XOR     A
        LD      (BUL_ACT), A
        CALL    ResolveInvaderHit       ; Z set on success
        RET     Z
        ; not an invader: erode shields, otherwise vanish
        LD      A, (BUL_Y)
        CP      SHIELD_ROW
        RET     C
        LD      A, (BUL_X)
        LD      C, A
        LD      A, (BUL_Y)
        LD      B, A
        CALL    ScreenAddr
        JP      ErodeShieldUp

; ============================================================
; ResolveInvaderHit - map (BUL_X,BUL_Y) to formation slot.
; Returns Z on kill, NZ on miss.
; ============================================================
ResolveInvaderHit:
        LD      A, (FORM_ROW)
        LD      C, A
        LD      A, (BUL_Y)
        SUB     C
        JR      C, _ri_fail
        CP      10
        JR      NC, _ri_fail
        SRL     A                       ; formation row 0..4
        LD      (HIT_ROW), A
        LD      A, (FORM_COL)
        LD      C, A
        LD      A, (BUL_X)
        SUB     C                       ; signed offset, FORM_COL may be < 0
        CP      4 * INV_COLS            ; negative wraps high -> also fails
        JR      NC, _ri_fail
        LD      B, A
        AND     3
        CP      3
        JR      Z, _ri_fail             ; gap column between invaders
        LD      A, B
        SRL     A
        SRL     A                       ; formation col 0..10
        CP      INV_COLS
        JR      NC, _ri_fail
        LD      (HIT_COL), A
        ; idx = row*11 + col
        LD      A, (HIT_ROW)
        LD      B, A
        ADD     A, A
        LD      C, A
        ADD     A, A
        ADD     A, A
        ADD     A, C
        ADD     A, B                    ; *11
        LD      C, A
        LD      A, (HIT_COL)
        ADD     A, C
        LD      E, A
        LD      D, 0
        LD      HL, ALIVE_ARR
        ADD     HL, DE
        LD      A, (HL)
        OR      A
        JR      Z, _ri_fail
        ; kill it
        LD      (HL), 0
        CALL    EraseHitInvader
        ; score by type
        LD      A, (HIT_ROW)
        LD      E, A
        LD      D, 0
        LD      HL, ROW_TYPE
        ADD     HL, DE
        LD      E, (HL)
        LD      HL, TYPE_PTS
        ADD     HL, DE
        LD      A, (HL)
        CALL    AddScoreTens
        CALL    BoomSound
        LD      HL, ALIVE_CNT
        DEC     (HL)
        JR      NZ, _ri_ok
        LD      A, 1
        LD      (WAVE_DONE), A
_ri_ok:
        XOR     A                       ; Z = success
        RET
_ri_fail:
        OR      1                       ; NZ = miss
        RET

; EraseHitInvader - explosion animation over slot (HIT_ROW, HIT_COL);
; the explosion self-erases the 5x2 area when it burns out
EraseHitInvader:
        LD      A, (HIT_ROW)
        ADD     A, A
        LD      C, A
        LD      A, (FORM_ROW)
        ADD     A, C
        LD      B, A                    ; char row
        LD      A, (HIT_COL)
        ADD     A, A
        ADD     A, A
        LD      C, A
        LD      A, (FORM_COL)
        DEC     A
        ADD     A, C
        LD      C, A                    ; char col (blit origin)
        LD      E, 0
        JP      SpawnExplosion

ROW_TYPE:
        DB      0, 1, 1, 2, 2           ; squid, crab, crab, octopus, octopus
TYPE_PTS:
        DB      3, 2, 1                 ; tens: 30 / 20 / 10 points

; Torpedo reload scale per wave (1..12+), 32 = 1.0, /1.2 each wave
TORP_SCL:
        DB      32, 27, 22, 18, 15, 13, 11, 9, 8, 7, 6, 5

; Formation start position per wave: FORM_ROW, FORM_YSUB pairs.
; Wave 1 must stay (FORM_ROW0, 0) - the target images depend on it.
WAVE_START_TBL:
        DB      FORM_ROW0, 0            ; wave 1
        DB      FORM_ROW0, 2            ; wave 2
        DB      FORM_ROW0 + 1, 0        ; wave 3
        DB      FORM_ROW0 + 1, 1        ; wave 4
        DB      FORM_ROW0 + 1, 2        ; wave 5+
NWAVE_START     EQU     5

; March speed by ALIVE_CNT (index 1..55), 8.8 fixed-point px/frame.
; Generated curve: per-kill delta grows from ~1.6 to ~6 units, i.e.
; gentle early, brutal with the last few invaders.
; 55 alive = 1 step/15 frames, 1 alive = 1 step/1.1 frames.
FORM_SPD_TBL:
        DB      0, 230, 224, 217, 211, 205, 199, 194
        DB      188, 182, 176, 171, 166, 160, 155, 150
        DB      145, 140, 135, 130, 125, 121, 116, 112
        DB      107, 103, 99, 95, 91, 87, 83, 80
        DB      76, 72, 69, 66, 62, 59, 56, 53
        DB      50, 47, 45, 42, 39, 37, 34, 32
        DB      30, 28, 26, 24, 22, 20, 19, 17

; ============================================================
; UpdateFormation - one pixel step every FORM_CNT frames
; ============================================================
UpdateFormation:
        LD      A, (ALIVE_CNT)
        OR      A
        RET     Z
        LD      HL, FORM_CNT            ; wave-start grace frames
        LD      A, (HL)
        OR      A
        JR      Z, _uf_run
        DEC     (HL)
        RET
_uf_run:
        ; speed accumulator: every kill nudges the pace up a little
        ; (8.8 fixed-point pixels/frame from FORM_SPD_TBL[ALIVE_CNT])
        LD      A, (ALIVE_CNT)
        LD      E, A
        LD      D, 0
        LD      HL, FORM_SPD_TBL
        ADD     HL, DE
        LD      E, (HL)
        LD      HL, (FORM_ACC)
        LD      D, 0
        ADD     HL, DE
        LD      A, H
        OR      A
        JR      NZ, _uf_step
        LD      (FORM_ACC), HL
        RET
_uf_step:
        LD      H, 0                    ; consume one whole step
        LD      (FORM_ACC), HL
        CALL    MarchTick
        ; step
        LD      A, (FORM_DIR)
        OR      A
        JR      NZ, _uf_left
        ; moving right
        LD      A, (FORM_SUB)
        OR      A
        JR      NZ, _uf_r_char
        LD      A, 1
        LD      (FORM_SUB), A
        JP      DrawFormation
_uf_r_char:
        CALL    FindEdges               ; E = rightmost alive column
        LD      A, E
        ADD     A, A
        ADD     A, A
        LD      C, A
        LD      A, (FORM_COL)
        ADD     A, C                    ; char col of rightmost alive invader
        CP      60                      ; its blit spans +3 -> col 63
        JR      NC, _uf_desc_l
        LD      A, (FORM_COL)
        INC     A
        LD      (FORM_COL), A
        XOR     A
        LD      (FORM_SUB), A
        JP      DrawFormation
_uf_left:
        LD      A, (FORM_SUB)
        OR      A
        JR      Z, _uf_l_char
        XOR     A
        LD      (FORM_SUB), A
        JP      DrawFormation
_uf_l_char:
        CALL    FindEdges               ; D = leftmost alive column
        LD      A, D
        ADD     A, A
        ADD     A, A
        LD      C, A
        LD      A, (FORM_COL)
        ADD     A, C                    ; char col of leftmost alive invader
        CP      SIDEBAR_W + 2           ; its blit spans -1 -> sidebar edge
        JR      C, _uf_desc_r
        LD      A, (FORM_COL)
        DEC     A
        LD      (FORM_COL), A
        LD      A, 1
        LD      (FORM_SUB), A
        JP      DrawFormation
_uf_desc_l:
        LD      A, 1
        JR      _uf_descend
_uf_desc_r:
        XOR     A
_uf_descend:
        LD      (FORM_DIR), A
        ; descend by ONE pixel: ysub 0->1->2, then char row rollover
        LD      A, (FORM_YSUB)
        CP      2
        JR      Z, _uf_rollover
        INC     A
        LD      (FORM_YSUB), A
        JP      DrawFormation
_uf_rollover:
        ; invasion check: the bottommost ALIVE invader's sprite bottom
        ; (char row FORM_ROW + 2*bottom + 1) would touch the shield row
        CALL    FindBottomRow           ; E = bottom alive formation row
        LD      A, E
        ADD     A, A
        LD      C, A
        LD      A, SHIELD_ROW - 1
        SUB     C                       ; threshold for FORM_ROW+1
        LD      C, A
        LD      A, (FORM_ROW)
        INC     A
        CP      C
        JR      C, _uf_desc_ok
        LD      A, 1
        LD      (GAME_OVER), A
        RET
_uf_desc_ok:
        CALL    EraseTopStripes
        LD      A, (FORM_ROW)
        INC     A
        LD      (FORM_ROW), A
        XOR     A
        LD      (FORM_YSUB), A
        JP      DrawFormation

; FindEdges - D = leftmost alive column, E = rightmost alive column
; (0..10). Requires at least one alive invader.
FindEdges:
        LD      D, 0FFH
        LD      E, 0
        LD      C, 0                    ; column index
_fe_col:
        LD      HL, ALIVE_ARR
        LD      A, C
        ADD     A, L
        LD      L, A
        JR      NC, _fe_nc0
        INC     H
_fe_nc0:
        LD      B, INV_ROWS
_fe_row:
        LD      A, (HL)
        OR      A
        JR      NZ, _fe_alive
        LD      A, L
        ADD     A, INV_COLS
        LD      L, A
        JR      NC, _fe_nc1
        INC     H
_fe_nc1:
        DJNZ    _fe_row
        JR      _fe_next
_fe_alive:
        LD      A, D
        CP      0FFH
        JR      NZ, _fe_r
        LD      D, C
_fe_r:
        LD      E, C
_fe_next:
        INC     C
        LD      A, C
        CP      INV_COLS
        JR      NZ, _fe_col
        RET

; FindBottomRow - E = bottommost formation row (0..4) holding a
; live invader. Requires at least one alive.
FindBottomRow:
        LD      HL, ALIVE_ARR + INV_COLS * INV_ROWS - 1
        LD      E, INV_ROWS - 1
_fbr_row:
        LD      B, INV_COLS
_fbr_col:
        LD      A, (HL)
        OR      A
        RET     NZ
        DEC     HL
        DJNZ    _fbr_col
        DEC     E
        BIT     7, E
        JR      Z, _fbr_row
        LD      E, 0                    ; unreachable while ALIVE_CNT > 0
        RET

; EraseTopStripes - on char-row rollover the top char row of every
; formation row goes stale; blank those 5 stripes over the span of
; the alive columns (only there were sprites drawn).
EraseTopStripes:
        CALL    FindEdges               ; D = left col, E = right col
        LD      A, E
        SUB     D
        ADD     A, A
        ADD     A, A
        ADD     A, 5
        LD      (ETS_W), A              ; stripe width in chars
        LD      A, D
        ADD     A, A
        ADD     A, A
        LD      C, A
        LD      A, (FORM_COL)
        ADD     A, C
        DEC     A
        LD      (ETS_X), A              ; blit start col (>= 0 by march limits)
        LD      A, (FORM_ROW)
        LD      B, A                    ; stripe row
        LD      D, 5                    ; 5 formation rows
_ets_loop:
        PUSH    DE
        PUSH    BC
        LD      A, (ETS_X)
        LD      C, A
        CALL    ScreenAddr
        LD      A, (ETS_W)
        LD      B, A
_ets_fill:
        LD      (HL), BLANK
        INC     HL
        DJNZ    _ets_fill
        POP     BC
        POP     DE
        INC     B
        INC     B                       ; next formation row (+2 chars)
        DEC     D
        JR      NZ, _ets_loop
        RET

; ============================================================
; DrawFormation - blit all alive invaders (5x2 chars each)
; ============================================================
DrawFormation:
        XOR     A
        LD      (K_VAR), A
        LD      HL, ALIVE_ARR
        LD      (ALIVE_PTR), HL
_df_row:
        ; template = SPRITES + type*60 + state*30 + ysub*10
        LD      A, (K_VAR)
        LD      E, A
        LD      D, 0
        LD      HL, ROW_TYPE
        ADD     HL, DE
        LD      E, (HL)                 ; type 0..2
        LD      HL, TYPE_OFF
        ADD     HL, DE
        LD      C, (HL)                 ; type*60
        LD      A, (FORM_SUB)
        OR      A
        JR      Z, _df_state0
        LD      A, 30
_df_state0:
        ADD     A, C                    ; + state*30
        LD      C, A
        LD      A, (FORM_YSUB)
        LD      E, A
        LD      HL, YSUB_OFF
        ADD     HL, DE
        LD      A, (HL)                 ; ysub*10
        ADD     A, C
        LD      E, A
        LD      D, 0
        LD      HL, SPRITES
        ADD     HL, DE
        LD      (CUR_TMPL), HL
        ; base screen address: row FORM_ROW+2k, col FORM_COL-1
        LD      A, (K_VAR)
        ADD     A, A
        LD      C, A
        LD      A, (FORM_ROW)
        ADD     A, C
        LD      B, A
        LD      A, (FORM_COL)
        DEC     A
        LD      C, A
        CALL    ScreenAddr
        LD      (CUR_ADDR), HL
        LD      A, INV_COLS
        LD      (F_VAR), A
_df_col:
        LD      HL, (ALIVE_PTR)
        LD      A, (HL)
        INC     HL
        LD      (ALIVE_PTR), HL
        OR      A
        JR      Z, _df_next
        ; blit 5 top + 5 bottom
        LD      HL, (CUR_TMPL)
        LD      DE, (CUR_ADDR)
        LD      BC, 5
        LDIR
        LD      A, E
        ADD     A, 59
        LD      E, A
        JR      NC, _df_nc
        INC     D
_df_nc:
        LD      BC, 5
        LDIR
_df_next:
        LD      HL, (CUR_ADDR)
        LD      BC, 4
        ADD     HL, BC
        LD      (CUR_ADDR), HL
        LD      HL, F_VAR
        DEC     (HL)
        JR      NZ, _df_col
        LD      A, (K_VAR)
        INC     A
        LD      (K_VAR), A
        CP      INV_ROWS
        JP      NZ, _df_row
        RET

; ============================================================
; Torpedo - invader shot, 1 row per 2 frames
; ============================================================
MaybeFireTorpedo:
        LD      A, (TORP_ACT)
        OR      A
        RET     NZ
        LD      HL, TORP_CNT
        DEC     (HL)
        RET     NZ
        ; reload pause 25..56 frames, scaled by wave: rate +20% per
        ; wave => reload * (32 / 1.2^(wave-1)) / 32, table-capped
        LD      A, R
        AND     31
        ADD     A, 25
        LD      E, A
        LD      D, 0
        PUSH    HL
        LD      A, (WAVE_NUM)
        CP      13
        JR      C, _mft_wcap
        LD      A, 12
_mft_wcap:
        LD      C, A
        LD      B, 0
        LD      HL, TORP_SCL - 1
        ADD     HL, BC
        LD      A, (HL)                 ; scale factor, /32
        LD      HL, 0
        LD      B, 8
_mft_mul:
        ADD     HL, HL
        RLCA
        JR      NC, _mft_mnc
        ADD     HL, DE
_mft_mnc:
        DJNZ    _mft_mul                ; HL = base * scale
        LD      A, L
        SRL     H
        RRA
        SRL     H
        RRA
        SRL     H
        RRA
        SRL     H
        RRA
        SRL     H
        RRA                             ; A = HL >> 5
        OR      A
        JR      NZ, _mft_rok
        LD      A, 1
_mft_rok:
        POP     HL
        LD      (HL), A
        ; pick a column 0..10
        LD      A, R
        AND     15
        CP      INV_COLS
        JR      C, _mft_col
        SUB     6
_mft_col:
        LD      (HIT_COL), A            ; reuse as temp
        ; find lowest alive invader in that column
        LD      E, A
        LD      D, 0
        LD      HL, ALIVE_ARR + 44      ; bottom row
        ADD     HL, DE
        LD      B, 5
_mft_scan:
        LD      A, (HL)
        OR      A
        JR      NZ, _mft_found
        LD      DE, -11
        ADD     HL, DE
        DJNZ    _mft_scan
        RET                             ; column empty
_mft_found:
        ; formation row = B-1; spawn row = FORM_ROW + 2*(B-1) + 2 = FORM_ROW + 2*B
        LD      A, B
        ADD     A, A
        LD      C, A
        LD      A, (FORM_ROW)
        ADD     A, C
        CP      PLAYER_ROW + 1
        RET     NC
        LD      (TORP_Y), A
        LD      B, A
        ; x = FORM_COL + 4*col + 1 (sprite middle)
        LD      A, (HIT_COL)
        ADD     A, A
        ADD     A, A
        INC     A
        LD      C, A
        LD      A, (FORM_COL)
        ADD     A, C
        LD      (TORP_X), A
        LD      C, A
        CALL    ScreenAddr
        LD      A, (HL)
        CP      BLANK
        RET     NZ                      ; spawn cell occupied: skip
        LD      (HL), TORP_CH
        LD      A, 1
        LD      (TORP_ACT), A
        RET

UpdateTorpedo:
        LD      A, (TORP_ACT)
        OR      A
        RET     Z
        LD      HL, TORP_PH
        LD      A, (HL)
        XOR     1
        LD      (HL), A
        RET     NZ                      ; move every 2nd frame
        ; erase
        LD      A, (TORP_X)
        LD      C, A
        LD      A, (TORP_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      (HL), BLANK
        ; move down
        LD      A, (TORP_Y)
        INC     A
        LD      (TORP_Y), A
        CP      16
        JR      NC, _ut_die
        ; peek new cell
        LD      B, A
        LD      A, (TORP_X)
        LD      C, A
        CALL    ScreenAddr
        LD      A, (HL)
        CP      BLANK
        JR      NZ, _ut_hit
        LD      (HL), TORP_CH
        RET
_ut_die:
        XOR     A
        LD      (TORP_ACT), A
        RET
_ut_hit:
        XOR     A
        LD      (TORP_ACT), A
        LD      A, (TORP_Y)
        CP      PLAYER_ROW
        JR      Z, _ut_player
        CP      SHIELD_ROW
        RET     C                       ; hit bullet/invader region: vanish
        ; erode shield from above
        JP      ErodeShieldDown
_ut_player:
        ; hit something on player row - the player?
        LD      A, (PLAYER_X)
        LD      C, A
        LD      A, (TORP_X)
        SUB     C
        RET     C                       ; left of player
        CP      3
        RET     NC                      ; right of player
        ; player hit! synchronous explosion over the ship
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        LD      E, 1
        LD      D, 0
        CALL    ExplDrawStage
        CALL    DeathSound              ; doubles as the stage-0 hold
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        LD      E, 1
        LD      D, 1
        CALL    ExplDrawStage
        LD      B, 5
_utp1:
        CALL    FrameDelay
        DJNZ    _utp1
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        LD      E, 1
        LD      D, 2
        CALL    ExplDrawStage
        LD      B, 5
_utp2:
        CALL    FrameDelay
        DJNZ    _utp2
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        LD      E, 1
        CALL    ExplErase
        LD      HL, LIVES
        DEC     (HL)
        CALL    DrawLives
        LD      A, (LIVES)
        OR      A
        JR      NZ, _ut_respawn
        LD      A, 1
        LD      (GAME_OVER), A
        RET
_ut_respawn:
        CALL    DrawPlayer              ; redraw (torpedo never overwrote it)
        LD      B, 4                    ; short breather before play resumes
_ut_pause:
        CALL    FrameDelay
        DJNZ    _ut_pause
        RET

; ============================================================
; Explosions - up to NEXPL concurrent, three diffusion stages
; (dense core -> spread -> sparse dots), each confined to the
; sprite's own blit area, then self-erasing.
; Slot: timer, stage, row, col, kind (0 = 5x2 invader, 1 = 3x1 strip)
; ============================================================
NEXPL           EQU     4
EXPL_STAGE_LEN  EQU     3               ; game frames per stage

; SpawnExplosion: B=row, C=col (blit origin), E=kind.
; No free slot -> just blank the area (sprite must not linger).
SpawnExplosion:
        LD      HL, EXPL_TBL
        LD      D, NEXPL
_se_find:
        LD      A, (HL)
        OR      A
        JR      Z, _se_take
        LD      A, L
        ADD     A, 5
        LD      L, A
        JR      NC, _se_nc
        INC     H
_se_nc:
        DEC     D
        JR      NZ, _se_find
        JP      ExplErase
_se_take:
        LD      (HL), EXPL_STAGE_LEN
        INC     HL
        LD      (HL), 0                 ; stage
        INC     HL
        LD      (HL), B
        INC     HL
        LD      (HL), C
        INC     HL
        LD      (HL), E
        LD      D, 0
        JP      ExplDrawStage

; UpdateExplosions - tick timers, advance stages, erase at the end
UpdateExplosions:
        LD      IX, EXPL_TBL
        LD      B, NEXPL
_ue_loop:
        LD      A, (IX+0)
        OR      A
        JR      Z, _ue_next
        DEC     A
        LD      (IX+0), A
        JR      NZ, _ue_next
        LD      A, (IX+1)
        INC     A
        CP      3
        JR      NC, _ue_erase
        LD      (IX+1), A
        LD      (IX+0), EXPL_STAGE_LEN
        PUSH    BC
        LD      D, A
        LD      B, (IX+2)
        LD      C, (IX+3)
        LD      E, (IX+4)
        CALL    ExplDrawStage
        POP     BC
        JR      _ue_next
_ue_erase:
        PUSH    BC
        LD      B, (IX+2)
        LD      C, (IX+3)
        LD      E, (IX+4)
        CALL    ExplErase
        POP     BC                      ; timer stayed 0 -> slot free
_ue_next:
        LD      DE, 5
        ADD     IX, DE
        DJNZ    _ue_loop
        RET

; ExplDrawStage: B=row, C=col, D=stage 0..2, E=kind
ExplDrawStage:
        CALL    ScreenAddr              ; HL = target (preserves DE)
        LD      A, E
        OR      A
        JR      NZ, _eds_strip
        LD      A, D                    ; kind 0: src = EXPL_INV + stage*10
        ADD     A, A
        ADD     A, A
        ADD     A, A
        ADD     A, D
        ADD     A, D
        EX      DE, HL
        LD      L, A
        LD      H, 0
        LD      BC, EXPL_INV
        ADD     HL, BC
        LD      BC, 5
        LDIR
        LD      A, E
        ADD     A, 59
        LD      E, A
        JR      NC, _eds_nc
        INC     D
_eds_nc:
        LD      BC, 5
        LDIR
        RET
_eds_strip:
        LD      A, D                    ; kind 1: src = EXPL_STRIP + stage*3
        ADD     A, A
        ADD     A, D
        EX      DE, HL
        LD      L, A
        LD      H, 0
        LD      BC, EXPL_STRIP
        ADD     HL, BC
        LD      BC, 3
        LDIR
        RET

; ExplErase: B=row, C=col, E=kind
ExplErase:
        CALL    ScreenAddr
        LD      A, E
        OR      A
        JR      NZ, _ee_strip
        LD      B, 5
_ee_top:
        LD      (HL), BLANK
        INC     HL
        DJNZ    _ee_top
        LD      DE, 59
        ADD     HL, DE
        LD      B, 5
_ee_bot:
        LD      (HL), BLANK
        INC     HL
        DJNZ    _ee_bot
        RET
_ee_strip:
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        RET

EXPL_INV:                               ; 3 stages x (5 top + 5 bottom)
        DB      128, 158, 187, 173, 128 ; dense core, margins clear
        DB      128, 181, 190, 166, 128
        DB      136, 133, 146, 168, 129 ; spread into the margins
        DB      130, 152, 133, 144, 136
        DB      129, 128, 132, 128, 160 ; sparse dots at the edges
        DB      144, 132, 128, 136, 130
EXPL_STRIP:                             ; 3 stages x 3 (UFO / player)
        DB      157, 191, 174
        DB      141, 181, 166
        DB      129, 148, 160

; ============================================================
; Shield erosion - one pixel row of the block char per hit.
; Graphics char = 128 + 6 bits: 0/1 top, 2/3 middle, 4/5 bottom.
; ============================================================
ErodeShieldUp:                          ; player bullet, from below
        LD      A, (HL)
        AND     30H
        JR      Z, _esu_mid
        LD      A, (HL)
        AND     0CFH                    ; clear bottom pixel row
        LD      (HL), A
        RET
_esu_mid:
        LD      A, (HL)
        AND     0CH
        JR      Z, _esu_top
        LD      A, (HL)
        AND     0F3H                    ; clear middle pixel row
        LD      (HL), A
        RET
_esu_top:
        LD      (HL), BLANK
        RET

ErodeShieldDown:                        ; invader torpedo, from above
        LD      A, (HL)
        AND     03H
        JR      Z, _esd_mid
        LD      A, (HL)
        AND     0FCH                    ; clear top pixel row
        LD      (HL), A
        RET
_esd_mid:
        LD      A, (HL)
        AND     0CH
        JR      Z, _esd_bot
        LD      A, (HL)
        AND     0F3H                    ; clear middle pixel row
        LD      (HL), A
        RET
_esd_bot:
        LD      (HL), BLANK
        RET

; ============================================================
; UFO / mystery ship - flies along HUD row 0 in the free span
; between SCORE (cols 0..9) and LIVES (cols 54..60).
; ============================================================
UpdateUFO:
        LD      A, (UFO_ACT)
        OR      A
        JR      NZ, _uu_fly
        LD      HL, UFO_CNT
        DEC     (HL)
        RET     NZ
        ; spawn: random direction, enter at that side
        LD      A, R
        AND     1
        LD      (UFO_DIR), A            ; 0 = fly right, 1 = fly left
        OR      A
        LD      A, UFO_XMIN
        JR      Z, _uu_spawn
        LD      A, UFO_XMAX
_uu_spawn:
        LD      (UFO_X), A
        LD      A, 1
        LD      (UFO_ACT), A
        JR      _uu_draw
_uu_fly:
        LD      A, (UFO_PH)
        XOR     1
        LD      (UFO_PH), A
        RET     Z                       ; move every 2nd frame
        CALL    EraseUFO
        CALL    UFOBlip
        LD      A, (UFO_DIR)
        OR      A
        LD      A, (UFO_X)
        JR      NZ, _uu_left
        INC     A
        CP      UFO_XMAX + 1
        JR      Z, _uu_gone
        JR      _uu_store
_uu_left:
        DEC     A
        CP      UFO_XMIN - 1
        JR      Z, _uu_gone
_uu_store:
        LD      (UFO_X), A
_uu_draw:
        LD      A, (UFO_X)
        LD      C, A
        LD      B, 0
        CALL    ScreenAddr
        EX      DE, HL
        LD      A, (UFO_X)              ; feet wiggle: frame by X parity
        AND     1
        LD      HL, UFO_SPR_A
        JR      Z, _uud_blit
        LD      HL, UFO_SPR_B
_uud_blit:
        LD      BC, 3
        LDIR
        RET

UFO_SPR_A:
        DB      174, 143, 157           ; saucer: .####. / ###### / .#..#.
UFO_SPR_B:
        DB      158, 143, 173           ; feet swapped outward
_uu_gone:
        XOR     A
        LD      (UFO_ACT), A
UFOReload:
        LD      A, R                    ; next spawn in 128..255 frames
        AND     7FH
        ADD     A, 128
        LD      (UFO_CNT), A
        RET

EraseUFO:
        LD      A, (UFO_X)
        LD      C, A
        LD      B, 0
        CALL    ScreenAddr
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        INC     HL
        LD      (HL), BLANK
        RET

; KillUFO - bullet reached row 0 inside the UFO: mystery score
; 50/100/150/200 awarded in 50-point chunks (AddScoreTens caps at +10)
KillUFO:
        LD      A, (UFO_X)
        LD      C, A
        LD      B, 0
        LD      E, 1
        CALL    SpawnExplosion          ; overdraws + later erases the saucer
        XOR     A
        LD      (UFO_ACT), A
        CALL    UFOReload
        LD      A, R
        AND     3
        INC     A
        LD      B, A                    ; 1..4 chunks
_ku_score:
        PUSH    BC
        LD      A, 5                    ; 5 tens = 50 points
        CALL    AddScoreTens
        POP     BC
        DJNZ    _ku_score
        JP      BoomSound

; ============================================================
; GameOver - message, wait for SPACE, restart
; ============================================================
GameOver:
        ; new high score? (digit arrays, most significant first)
        LD      B, 4
        LD      HL, HISCORE_D
        LD      DE, SCORE_D
_go_cmp:
        LD      A, (DE)
        CP      (HL)
        JR      C, _go_msg              ; score < hiscore: keep
        JR      NZ, _go_new             ; score > hiscore: record
        INC     HL
        INC     DE
        DJNZ    _go_cmp
        JR      _go_msg                 ; equal: keep
_go_new:
        LD      HL, SCORE_D
        LD      DE, HISCORE_D
        LD      BC, 4
        LDIR
        CALL    PrintHiScore            ; persist via printer capture
_go_msg:
        ; clear a window so the text is readable over the battlefield
        LD      B, 6
_go_clr:
        PUSH    BC
        LD      C, 23
        CALL    ScreenAddr
        LD      B, 19
_go_cl2:
        LD      (HL), BLANK
        INC     HL
        DJNZ    _go_cl2
        POP     BC
        INC     B
        LD      A, B
        CP      11
        JR      C, _go_clr
        LD      HL, TXT_OVER
        LD      DE, SCREEN + 7 * 64 + 27
        LD      BC, 9
        LDIR
        LD      HL, TXT_AGAIN
        LD      DE, SCREEN + 9 * 64 + 26
        LD      BC, 11
        LDIR
        ; wait for SPACE released, then pressed
_go_rel:
        LD      A, (KBD_CTL)
        BIT     7, A
        JR      NZ, _go_rel
_go_prs:
        LD      A, (KBD_CTL)
        BIT     7, A
        JR      Z, _go_prs
        JP      Splash

; ============================================================
; PrintHiScore - write "HSnnnn\r" to the printer (37E8H, memory
; mapped on Model I and III). tools/play.py captures the printer
; into a file and feeds the score back on the next launch.
; ============================================================
PRINTER         EQU     37E8H

PrintHiScore:
        LD      A, 'H'
        CALL    PrintChar
        LD      A, 'S'
        CALL    PrintChar
        LD      HL, HISCORE_D
        LD      B, 4
_phs_loop:
        LD      A, (HL)
        ADD     A, '0'
        CALL    PrintChar
        INC     HL
        DJNZ    _phs_loop
        LD      A, 13
        ; fall through
; PrintChar - send A to the printer. Model I maps it at 37E8H,
; Model III drives port 0F8H; we poll both status views and then
; write both ways (the inactive one is harmless on either machine).
PrintChar:
        PUSH    BC
        LD      C, A
        LD      B, 0                    ; 256 tries, then send anyway
_pc_wait:
        LD      A, (PRINTER)
        AND     0F0H
        CP      30H                     ; Model I ready pattern
        JR      Z, _pc_send
        IN      A, (0F8H)
        AND     0F0H
        CP      30H                     ; Model III ready pattern
        JR      Z, _pc_send
        DJNZ    _pc_wait
_pc_send:
        LD      A, C
        LD      (PRINTER), A
        OUT     (0F8H), A
        POP     BC
        RET

; ============================================================
; ScreenAddr: B=row, C=col -> HL = SCREEN + row*64 + col
; ============================================================
ScreenAddr:
        PUSH    AF
        PUSH    DE
        LD      HL, SCREEN
        LD      E, B
        LD      D, 0
        SLA     E
        RL      D
        SLA     E
        RL      D
        SLA     E
        RL      D
        SLA     E
        RL      D
        SLA     E
        RL      D
        SLA     E
        RL      D
        ADD     HL, DE
        LD      E, C
        LD      D, 0
        BIT     7, E
        JR      Z, _sa_pos
        DEC     D                       ; sign-extend: col may be negative
_sa_pos:
        ADD     HL, DE
        POP     DE
        POP     AF
        RET

; ============================================================
; Sound - cassette port, bits 0/1 only (bit 2 is mode select!)
; ============================================================
PewSound:
        LD      B, 12
_pew_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        LD      C, 30
        CALL    SoundDelay
        XOR     A
        OUT     (SOUND_PORT), A
        LD      C, 30
        CALL    SoundDelay
        DJNZ    _pew_loop
        RET

BoomSound:
        LD      B, 35
_boom_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        LD      A, R                    ; noisy period = explosion
        AND     63
        ADD     A, 40
        LD      C, A
        CALL    SoundDelay
        XOR     A
        OUT     (SOUND_PORT), A
        LD      C, 80
        CALL    SoundDelay
        DJNZ    _boom_loop
        RET

; MarchTick - the classic four-note bass loop, one note per
; formation step (lower period value = higher pitch)
MarchTick:
        LD      A, (MARCH_IX)
        INC     A
        AND     3
        LD      (MARCH_IX), A
        LD      E, A
        LD      D, 0
        LD      HL, MARCH_TBL
        ADD     HL, DE
        LD      D, (HL)
        LD      B, 2                    ; pulses
        LD      A, (ALIVE_CNT)
        CP      5
        JR      NC, _mt_loop
        LD      B, 1                    ; endgame: steps come every frame,
                                        ; keep the tick from eating time
_mt_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        LD      C, D
        CALL    SoundDelay
        LD      C, D
        CALL    SoundDelay
        XOR     A
        OUT     (SOUND_PORT), A
        LD      C, D
        CALL    SoundDelay
        LD      C, D
        CALL    SoundDelay
        DJNZ    _mt_loop
        RET
MARCH_TBL:
        DB      180, 200, 220, 240

; UFOBlip - short high chirp on every saucer move
UFOBlip:
        LD      B, 2
_ufb_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        LD      C, 20
        CALL    SoundDelay
        XOR     A
        OUT     (SOUND_PORT), A
        LD      C, 20
        CALL    SoundDelay
        DJNZ    _ufb_loop
        RET

; DeathSound - longer, deeper rumble than BoomSound
DeathSound:
        LD      B, 60
_dth_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        LD      A, R
        AND     127
        ADD     A, 60
        LD      C, A
        CALL    SoundDelay
        XOR     A
        OUT     (SOUND_PORT), A
        LD      C, 90
        CALL    SoundDelay
        DJNZ    _dth_loop
        RET

SoundDelay:                             ; C * ~13 T-states
_sdl_loop:
        DEC     C
        JR      NZ, _sdl_loop
        RET

; ============================================================
; FrameDelay - main loop pacing (~30 fps on 2 MHz)
; ============================================================
FrameDelay:
        PUSH    BC
        LD      BC, 0A00H
_fd_loop:
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, _fd_loop
        POP     BC
        RET

; ============================================================
; Sprite templates - generated from the target screenshots
; (gen_sprites.py), blank margin left+right for self-clean.
; Layout: type*60 + state*30 + ysub*10; 5 top + 5 bottom bytes.
; ysub = vertical pixel shift 0..2 within the 2-char-row window.
; ============================================================
SPRITES:
; type 0 - squid
        DB      128,184,185,144,128,  128,130,130,128,128    ; state 0 ysub 0
        DB      128,160,164,128,128,  128,139,139,129,128    ; state 0 ysub 1
        DB      128,128,144,128,128,  128,174,174,132,128    ; state 0 ysub 2
        DB      128,128,182,148,128,  128,130,128,130,128    ; state 1 ysub 0
        DB      128,128,152,144,128,  128,136,131,137,128    ; state 1 ysub 1
        DB      128,128,160,128,128,  128,160,141,165,128    ; state 1 ysub 2
; type 1 - crab
        DB      128,182,166,148,128,  128,130,130,128,128    ; state 0 ysub 0
        DB      128,152,152,144,128,  128,139,138,129,128    ; state 0 ysub 1
        DB      128,160,160,128,128,  128,173,169,133,128    ; state 0 ysub 2
        DB      128,136,185,153,128,  128,130,128,130,128    ; state 1 ysub 0
        DB      128,160,164,164,128,  128,136,131,137,128    ; state 1 ysub 1
        DB      128,128,144,144,128,  128,162,142,166,128    ; state 1 ysub 2
; type 2 - octopus
        DB      128,182,183,148,128,  128,129,129,129,128    ; state 0 ysub 0
        DB      128,152,156,144,128,  128,135,135,133,128    ; state 0 ysub 1
        DB      128,160,176,128,128,  128,157,157,149,128    ; state 0 ysub 2
        DB      128,168,187,185,128,  128,128,129,129,128    ; state 1 ysub 0
        DB      128,160,172,164,128,  128,130,135,135,128    ; state 1 ysub 1
        DB      128,128,176,144,128,  128,138,158,158,128    ; state 1 ysub 2

TYPE_OFF:
        DB      0, 60, 120
YSUB_OFF:
        DB      0, 10, 20

; ============================================================
; Variables
; ============================================================
PLAYER_X:       DB      0
BUL_ACT:        DB      0
BUL_X:          DB      0
BUL_Y:          DB      0
TORP_ACT:       DB      0
TORP_X:         DB      0
TORP_Y:         DB      0
TORP_PH:        DB      0
TORP_CNT:       DB      0
FORM_COL:       DB      0
FORM_ROW:       DB      0
FORM_SUB:       DB      0
FORM_YSUB:      DB      0
FORM_DIR:       DB      0
FORM_CNT:       DB      0
ALIVE_CNT:      DB      0
WAVE_DONE:      DB      0
GAME_OVER:      DB      0
LIVES:          DB      0
SCORE_D:        DB      0,0,0,0
HIT_ROW:        DB      0
HIT_COL:        DB      0
K_VAR:          DB      0
F_VAR:          DB      0
ETS_X:          DB      0
ETS_W:          DB      0
UFO_ACT:        DB      0
UFO_X:          DB      0
UFO_DIR:        DB      0
UFO_PH:         DB      0
UFO_CNT:        DB      0
MARCH_IX:       DB      0
WAVE_NUM:       DB      0
FORM_ACC:       DW      0
HISCORE_D:      DB      0, 0, 0, 0
EXPL_TBL:                               ; NEXPL x (timer,stage,row,col,kind)
        DB      0, 0, 0, 0, 0
        DB      0, 0, 0, 0, 0
        DB      0, 0, 0, 0, 0
        DB      0, 0, 0, 0, 0
CUR_TMPL:       DW      0
CUR_ADDR:       DW      0
ALIVE_PTR:      DW      0
ALIVE_ARR:      DS      INV_COLS * INV_ROWS

        END     START
