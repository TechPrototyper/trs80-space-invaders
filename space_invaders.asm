; ============================================================
; Space Invaders for TRS-80 Model III
; Assemble: zmac space_invaders.asm -o space_invaders.cmd
; Run:      trs80gp -m3 space_invaders.cmd
; ============================================================

        ORG     5200H

; --- Constants ---
SCREEN          EQU     3C00H
COLS            EQU     64
KB_LEFT         EQU     3820H
KB_RIGHT        EQU     3820H
KB_SPACE        EQU     3840H
SOUND_PORT      EQU     0FFH

INV_COLS        EQU     11
INV_ROWS        EQU     5
MAX_INV         EQU     55
INV_SPACING     EQU     4
INV_START_COL   EQU     8
INV_START_ROW   EQU     2
PLAYER_ROW      EQU     14
PLAYER_COL      EQU     30
PLAYER_WIDTH    EQU     4

CHAR_BLANK      EQU     128

INV_DEAD        EQU     0
INV_ALIVE       EQU     1

PK_DIR          EQU     128
PK_STATE        EQU     64
PK_YPOS         EQU     48
PK_TYPE         EQU     15

INV_ENTRY       EQU     4

; --- Entry Point ---
START:
        DI
        LD      SP, 7FFFH

        CALL    CLS
        CALL    InitInvaders
        CALL    InitPlayer

        XOR     A
        LD      (BULLET_ACTIVE), A
        LD      (BULLET_STATE), A
        LD      (BULLET_X), A
        LD      (BULLET_Y), A

        LD      A, 16
        LD      (MOVE_CNT), A
        LD      A, 0
        LD      (FORM_STATE), A
        LD      (FORM_DIR), A
        LD      (TURN_FLAG), A
        LD      (TORP_ACTIVE), A
        LD      (TORP_CNT), A
        LD      A, 3
        LD      (LIVES), A
        CALL    DrawScore
        CALL    DrawLives

MainLoop:
        CALL    EraseAllInvaders
        CALL    RenderAllInvaders
        CALL    RenderBullet
        CALL    RenderTorpedo
        CALL    ReadKeyboard
        CALL    UpdateBullet
        CALL    UpdateInvaders
        CALL    UpdateTorpedo
        CALL    MaybeFireTorpedo
        CALL    FrameDelay
        JP      MainLoop

; ============================================================
; CLS
; ============================================================
CLS:
        LD      HL, SCREEN
        LD      (HL), CHAR_BLANK
        LD      DE, SCREEN + 1
        LD      BC, 1023
        LDIR
        RET

; ============================================================
; InitInvaders
; ============================================================
InitInvaders:
        LD      HL, INV_MATRIX
        LD      C, INV_ROWS

_init_row:
        LD      A, C
        SUB     INV_ROWS
        NEG
        LD      B, A

        ; Type: row 0->0, rows 1-2->1, rows 3-4->2
        LD      A, B
        CP      0
        LD      A, 0
        JR      Z, _init_set_type
        LD      A, B
        CP      3
        JR      C, _init_set_type_1
        LD      A, 2
        JR      _init_set_type
_init_set_type_1:
        LD      A, 1
_init_set_type:
        LD      (INV_TYPE_TMP), A

        ; Screen addr: row_index * 2 + INV_START_ROW
        ; Reference formation uses 2 character rows between invader rows.
        LD      A, B
        ADD     A, B
        ADD     A, INV_START_ROW
        CALL    _row_to_addr

        LD      B, INV_COLS

_init_col:
        LD      (HL), INV_ALIVE
        INC     HL
        LD      A, (INV_TYPE_TMP)
        AND     PK_TYPE
        LD      (HL), A
        INC     HL
        LD      (HL), E
        INC     HL
        LD      (HL), D
        INC     HL

        LD      A, E
        ADD     A, INV_SPACING
        LD      E, A
        JR      NC, _init_de_nc
        INC     D
_init_de_nc:
        DJNZ    _init_col

        DEC     C
        JR      NZ, _init_row
        RET

_row_to_addr:
        LD      E, A
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
        LD      A, E
        ADD     A, LOW(SCREEN + INV_START_COL)
        LD      E, A
        LD      D, HIGH(SCREEN + INV_START_COL)
        RET     NC
        INC     D
        RET

; ============================================================
; InitPlayer
; ============================================================
InitPlayer:
        LD      A, PLAYER_COL
        LD      (PLAYER_X), A
        ; Draw 4 static player ships
        LD      A, 16
        LD      (PLAYER_X), A
        CALL    DrawPlayer
        LD      A, 32
        LD      (PLAYER_X), A
        CALL    DrawPlayer
        LD      A, 48
        LD      (PLAYER_X), A
        CALL    DrawPlayer
        LD      A, 60
        LD      (PLAYER_X), A
        CALL    DrawPlayer
        RET

; ============================================================
; RenderAllInvaders
; ============================================================
RenderAllInvaders:
        LD      IX, INV_MATRIX
        LD      B, MAX_INV

_render_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _render_skip

        PUSH    BC

        ; Get sprite pointer via subroutine
        LD      A, (IX+1)
        CALL    GetSpritePtr
        ; HL = sprite data pointer

        ; Get screen addr
        LD      E, (IX+2)
        LD      D, (IX+3)

        ; Copy the 4-character screen footprint from the 5-byte template row.
        ; Byte 0 is the leading blank column, bytes 1-3 hold the 3 visible chars.
        LD      BC, 4
        LDIR

        ; Draw lower row (+64 down), skipping the trailing blank from the top row.
        INC     HL
        LD      A, E
        ADD     A, 64
        LD      E, A
        JR      NC, _rm_nc
        INC     D
_rm_nc:
        LD      BC, 4
        LDIR



        POP     BC
        JR      _render_advance

_render_skip:
_render_advance:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _render_loop
        RET

; ============================================================
; EraseAllInvaders
; Clears every stored invader footprint before redrawing.
; ============================================================
EraseAllInvaders:
        LD      IX, INV_MATRIX
        LD      B, MAX_INV

_erase_loop:
        LD      E, (IX+2)
        LD      D, (IX+3)
        PUSH    DE
        POP     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK

        LD      A, L
        ADD     A, 61
        LD      L, A
        JR      NC, _erase_row2
        INC     H
_erase_row2:
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK

        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _erase_loop
        RET

; ============================================================
; GetSpritePtr: A = packed byte -> HL = sprite data pointer
; ============================================================
GetSpritePtr:
        LD      C, A
        LD      HL, SPRITE_BASE

        ; Layout: type*60 + state*30 + yPos*10
        LD      A, C
        AND     PK_TYPE
        CP      1
        JR      Z, _sp_add_type1
        CP      2
        JR      Z, _sp_add_type2
        JR      _sp_state
_sp_add_type1:
        LD      DE, 60
        ADD     HL, DE
        JR      _sp_state
_sp_add_type2:
        LD      DE, 120
        ADD     HL, DE

_sp_state:
        LD      A, C
        AND     PK_STATE
        JR      Z, _sp_ypos
        LD      DE, 30
        ADD     HL, DE

_sp_ypos:
        LD      A, C
        AND     PK_YPOS
        JR      Z, _sp_done
        CP      16
        JR      Z, _sp_add_y1
        LD      DE, 20
        ADD     HL, DE
        JR      _sp_done
_sp_add_y1:
        LD      DE, 10
        ADD     HL, DE
_sp_done:
        RET

; ============================================================
; DrawPlayer / ErasePlayer
; ============================================================
DrawPlayer:
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        CALL    ScreenAddr
        LD      (HL), 128
        INC     HL
        LD      (HL), 182
        INC     HL
        LD      (HL), 182
        INC     HL
        LD      (HL), 128
        LD      A, L
        SUB     64
        LD      L, A
        JR      NC, _dp_nc
        DEC     H
_dp_nc:
        LD      (HL), 128
        INC     HL
        LD      (HL), 129
        INC     HL
        LD      (HL), 129
        INC     HL
        LD      (HL), 128
        RET

ErasePlayer:
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        CALL    ScreenAddr
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        LD      A, L
        SUB     64
        LD      L, A
        JR      NC, _ep_nc
        DEC     H
_ep_nc:
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        INC     HL
        LD      (HL), CHAR_BLANK
        RET

; ============================================================
; ReadKeyboard
; ============================================================
ReadKeyboard:
        LD      A, (KB_LEFT)
        BIT     5, A
        JR      NZ, _kb_right
        LD      A, (PLAYER_X)
        OR      A
        JR      Z, _kb_right
        CALL    ErasePlayer
        DEC     A
        LD      (PLAYER_X), A
        CALL    DrawPlayer
_kb_right:
        LD      A, (KB_RIGHT)
        BIT     6, A
        JR      NZ, _kb_fire
        LD      A, (PLAYER_X)
        CP      COLS - PLAYER_WIDTH
        JR      Z, _kb_fire
        CALL    ErasePlayer
        INC     A
        LD      (PLAYER_X), A
        CALL    DrawPlayer
_kb_fire:
        LD      A, (KB_SPACE)
        BIT     7, A
        JR      NZ, _kb_done
        LD      A, (BULLET_ACTIVE)
        OR      A
        RET     NZ
        LD      A, 1
        LD      (BULLET_ACTIVE), A
        LD      A, (PLAYER_X)
        INC     A
        LD      (BULLET_X), A
        LD      A, PLAYER_ROW - 1
        LD      (BULLET_Y), A
        LD      A, 0
        LD      (BULLET_STATE), A
        CALL    PewSound
_kb_done:
        RET

; ============================================================
; Bullet
; ============================================================
RenderBullet:
        LD      A, (BULLET_ACTIVE)
        OR      A
        RET     Z
        LD      A, (BULLET_X)
        LD      C, A
        LD      A, (BULLET_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      A, (BULLET_STATE)
        AND     1
        JR      Z, _bc186
        LD      A, 170
        JR      _bd
_bc186:
        LD      A, 186
_bd:
        LD      (HL), A
        RET

EraseBullet:
        LD      A, (BULLET_X)
        LD      C, A
        LD      A, (BULLET_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      (HL), CHAR_BLANK
        RET

UpdateBullet:
        LD      A, (BULLET_ACTIVE)
        OR      A
        RET     Z
        CALL    EraseBullet
        LD      HL, BULLET_STATE
        LD      A, (HL)
        INC     A
        AND     7
        LD      (HL), A
        LD      A, (HL)
        OR      A
        JR      NZ, _bncm
        LD      HL, BULLET_Y
        DEC     (HL)
        LD      A, (HL)
        CP      INV_START_ROW - 1
        JR      C, _bkill
_bncm:
        CALL    CheckBulletHit
        CALL    RenderBullet
        RET
_bkill:
        XOR     A
        LD      (BULLET_ACTIVE), A
        RET

CheckBulletHit:
        LD      A, (BULLET_X)
        LD      C, A
        LD      A, (BULLET_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      D, H
        LD      E, L
        LD      IX, INV_MATRIX
        LD      B, MAX_INV
_cl_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _cl_next
        LD      A, (IX+2)
        LD      H, A
        LD      A, (IX+3)
        LD      L, A
        LD      A, D
        CP      H
        JR      NZ, _cl_bot
        LD      A, E
        CP      L
        JR      Z, _bhit
        INC     L
        CP      L
        JR      Z, _bhit
        INC     L
        CP      L
        JR      Z, _bhit
        JR      _cl_nh
_cl_bot:
        LD      A, E
        ADD     A, 64
        LD      E, A
        LD      A, (IX+2)
        ADD     A, 64
        LD      C, A
        LD      A, (IX+3)
        LD      B, A
        LD      A, D
        CP      B
        JR      NZ, _cl_nh
        LD      A, E
        CP      C
        JR      Z, _bhit
        INC     C
        CP      C
        JR      Z, _bhit
        INC     C
        CP      C
        JR      Z, _bhit
_cl_nh:
_cl_next:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _cl_loop
        RET
_bhit:
        LD      (IX+0), INV_DEAD
        CALL    ExplosionSound
        CALL    AddScore
        XOR     A
        LD      (BULLET_ACTIVE), A
        RET

; ============================================================
; UpdateInvaders
; ============================================================
UpdateInvaders:
        LD      HL, MOVE_CNT
        DEC     (HL)
        RET     NZ
        LD      A, 16
        LD      (MOVE_CNT), A
        CALL    CheckBoundary
        LD      A, (TURN_FLAG)
        OR      A
        JR      Z, _ju
        CALL    FormationTurn
        JR      _ud
_ju:
        CALL    MoveFormation
_ud:
        RET

CheckBoundary:
        XOR     A
        LD      (TURN_FLAG), A
        LD      IX, INV_MATRIX
        LD      B, MAX_INV
_bnd_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _bnd_next
        LD      A, (IX+2)
        AND     63
        LD      A, (FORM_DIR)
        OR      A
        JR      NZ, _chk_l
        LD      A, (IX+2)
        AND     63
        CP      60
        JR      C, _bnd_next
        LD      A, 1
        LD      (TURN_FLAG), A
        JR      _bnd_next
_chk_l:
        LD      A, (IX+2)
        AND     63
        CP      2
        JR      NC, _bnd_next
        LD      A, 1
        LD      (TURN_FLAG), A
_bnd_next:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _bnd_loop
        RET

FormationTurn:
        LD      HL, FORM_DIR
        LD      A, (HL)
        XOR     1
        LD      (HL), A
        LD      IX, INV_MATRIX
        LD      B, MAX_INV
_tr_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _tr_next
        LD      A, (IX+1)
        XOR     PK_DIR
        ADD     A, 16
        AND     207
        LD      (IX+1), A
        LD      A, (IX+2)
        ADD     A, 64
        LD      (IX+2), A
_tr_next:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _tr_loop
        RET

MoveFormation:
        LD      A, (FORM_DIR)
        OR      A
        JR      NZ, _ml
        LD      IX, INV_MATRIX
        LD      B, MAX_INV
_mr_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _mr_next
        LD      A, (IX+1)
        XOR     PK_STATE
        LD      (IX+1), A
        LD      A, (IX+2)
        INC     A
        LD      (IX+2), A
_mr_next:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _mr_loop
        RET
_ml:
        LD      IX, INV_MATRIX
        LD      B, MAX_INV
_ml_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _ml_next
        LD      A, (IX+1)
        XOR     PK_STATE
        LD      (IX+1), A
        LD      A, (IX+2)
        DEC     A
        LD      (IX+2), A
_ml_next:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DJNZ    _ml_loop
        RET

; ============================================================
; ScreenAddr: B=Y, C=X -> HL=SCREEN+Y*64+X
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
        ADD     HL, DE
        POP     DE
        POP     AF
        RET

; ============================================================
; Sound
; ============================================================
PewSound:
        LD      B, 8
_pw_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        CALL    ShortDelay
        XOR     A
        OUT     (SOUND_PORT), A
        CALL    ShortDelay
        DJNZ    _pw_loop
        RET

ExplosionSound:
        LD      B, 20
_ex_loop:
        LD      A, 1
        OUT     (SOUND_PORT), A
        CALL    ShortDelay
        XOR     A
        OUT     (SOUND_PORT), A
        CALL    ShortDelay
        DJNZ    _ex_loop
        RET

ShortDelay:
        PUSH    HL
        LD      HL, 20
_sd_loop:
        DEC     HL
        LD      A, H
        OR      L
        JR      NZ, _sd_loop
        POP     HL
        RET


; ============================================================
; Torpedo (Invader shoots down)
; ============================================================
RenderTorpedo:
        LD      A, (TORP_ACTIVE)
        OR      A
        RET     Z
        LD      A, (TORP_X)
        LD      C, A
        LD      A, (TORP_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      A, (TORP_STATE)
        AND     1
        JR      Z, _trp186
        LD      A, 170
        JR      _trp_d
_trp186:
        LD      A, 186
_trp_d:
        LD      (HL), A
        RET

EraseTorpedo:
        LD      A, (TORP_X)
        LD      C, A
        LD      A, (TORP_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      (HL), CHAR_BLANK
        RET

UpdateTorpedo:
        LD      A, (TORP_ACTIVE)
        OR      A
        RET     Z
        CALL    EraseTorpedo
        LD      HL, TORP_STATE
        LD      A, (HL)
        INC     A
        AND     7
        LD      (HL), A
        LD      A, (HL)
        OR      A
        JR      NZ, _ut_check
        LD      HL, TORP_Y
        INC     (HL)
        LD      A, (HL)
        CP      PLAYER_ROW
        JR      C, _ut_check
        XOR     A
        LD      (TORP_ACTIVE), A
        RET
_ut_check:
        ; Check if torpedo hits player
        LD      A, (TORP_X)
        LD      C, A
        LD      A, (TORP_Y)
        LD      B, A
        CALL    ScreenAddr
        LD      D, H
        LD      E, L
        LD      A, (PLAYER_X)
        LD      C, A
        LD      B, PLAYER_ROW
        CALL    ScreenAddr
        ; Check if torpedo pos overlaps player (4 chars wide)
        LD      A, D
        CP      H
        JR      NZ, _ut_miss
        LD      A, E
        CP      L
        JR      Z, _ut_hit
        INC     L
        CP      L
        JR      Z, _ut_hit
        INC     L
        CP      L
        JR      Z, _ut_hit
        INC     L
        CP      L
        JR      Z, _ut_hit
_ut_miss:
        CALL    RenderTorpedo
        RET
_ut_hit:
        CALL    ExplosionSound
        XOR     A
        LD      (TORP_ACTIVE), A
        ; Player hit - for now just reset position
        LD      A, PLAYER_COL
        LD      (PLAYER_X), A
        CALL    ErasePlayer
        CALL    DrawPlayer
        RET

MaybeFireTorpedo:
        ; Only fire if no torpedo active
        LD      A, (TORP_ACTIVE)
        OR      A
        RET     NZ
        ; Decrement counter
        LD      HL, TORP_CNT
        LD      A, (HL)
        DEC     A
        JR      Z, _mf_fire
        LD      (HL), A
        RET
_mf_fire:
        ; Reset counter to random-ish value (10-30)
        LD      A, 20
        LD      (HL), A
        ; Pick a random alive invader (use R register as pseudo-random)
        LD      A, R
        AND     3Fh
        LD      C, A
        LD      B, 0
        ; Find C-th alive invader
        LD      IX, INV_MATRIX
        LD      D, MAX_INV
_mf_loop:
        LD      A, (IX+0)
        CP      INV_ALIVE
        JR      NZ, _mf_next
        LD      A, B
        CP      C
        JR      Z, _mf_found
        INC     B
_mf_next:
        PUSH    IX
        POP     HL
        LD      DE, 4
        ADD     HL, DE
        PUSH    HL
        POP     IX
        DEC     D
        JR      NZ, _mf_loop
        RET
_mf_found:
        ; Fire from this invader
        LD      A, (IX+2)
        ADD     A, 1
        LD      (TORP_X), A
        LD      A, (IX+3)
        LD      H, A
        LD      A, (IX+2)
        LD      L, A
        ; Get row of this invader to find Y
        LD      A, (IX+2)
        LD      E, A
        LD      A, (IX+3)
        LD      D, A
        ; Y = row of invader + 2 (below invader)
        ; We need to find the screen row
        LD      A, E
        SUB     LOW(SCREEN + INV_START_COL)
        JR      C, _mf_no_borrow
        DEC     D
_mf_no_borrow:
        ; Divide by 64 to get row
        LD      L, A
        LD      H, D
        LD      DE, 64
        ; Simple division: HL / 64
        LD      A, H
        LD      B, A
        LD      A, L
        ; Row is roughly H (since L < 64 usually)
        LD      A, B
        ADD     A, 2
        LD      (TORP_Y), A
        LD      A, 1
        LD      (TORP_ACTIVE), A
        LD      A, 0
        LD      (TORP_STATE), A
        CALL    RenderTorpedo
        RET


; ============================================================
; Score / Lives Display
; ============================================================
; Draw score at top-right: row 0, col 56-63
; Draw lives at top-left: row 0, col 0-2
DrawScore:
        ; Draw score digits at row 0, col 58-59
        LD      A, 58
        LD      C, A
        LD      B, 0
        CALL    ScreenAddr
        ; Save addr
        LD      D, H
        LD      E, L
        ; First digit
        LD      A, (SCORE)
        CALL    _draw_digit_to_char
        LD      (DE), A
        ; Second digit
        INC     E
        LD      A, (SCORE+1)
        CALL    _draw_digit_to_char
        LD      (DE), A
        RET

_draw_digit_to_char:
        ; A = 0-9 -> A = block graphics char
        PUSH    BC
        PUSH    DE
        LD      B, A
        LD      HL, _digit_table
        LD      E, B
        LD      D, 0
        ADD     HL, DE
        LD      A, (HL)
        POP     DE
        POP     BC
        RET

_digit_table:
        DB      128+1+2+4+8+16+32  ; 0
        DB      128+0+0+0+0+16+32  ; 1
        DB      128+1+2+4+8+0+0    ; 2
        DB      128+1+2+4+8+16+32  ; 3
        DB      128+0+0+4+8+16+32  ; 4
        DB      128+1+0+4+8+16+32  ; 5
        DB      128+1+2+4+8+16+32  ; 6
        DB      128+1+2+0+0+0+32   ; 7
        DB      128+1+2+4+8+16+32  ; 8
        DB      128+1+2+4+8+16+32  ; 9

DrawLives:
        ; Draw lives at row 0, col 0-2
        LD      A, 0
        LD      C, A
        LD      B, 0
        CALL    ScreenAddr
        LD      A, (LIVES)
        LD      B, A
        XOR     A
        LD      (HL), A
        INC     HL
        LD      (HL), A
        INC     HL
        LD      (HL), A
        RET

AddScore:
        LD      HL, SCORE
        INC     (HL)
        LD      A, (HL)
        CP      10
        JR      C, _as_done
        XOR     A
        LD      (HL), A
        INC     HL
        INC     (HL)
_as_done:
        CALL    DrawScore
        RET

FrameDelay:
        PUSH    BC
        LD      BC, 3000H
_fd_loop:
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, _fd_loop
        POP     BC
        RET

; ============================================================
; Variables
; ============================================================
        ORG     8000H

PLAYER_X:         DB      0
BULLET_ACTIVE:    DB      0
BULLET_X:         DB      0
BULLET_Y:         DB      0
BULLET_STATE:     DB      0
MOVE_CNT:         DB      0
FORM_STATE:       DB      0
FORM_DIR:         DB      0
TURN_FLAG:        DB      0
F_REG:            DB      0
INV_TYPE_TMP:     DB      0
TORP_ACTIVE:      DB      0
TORP_X:             DB      0
TORP_Y:             DB      0
TORP_STATE:         DB      0
TORP_CNT:           DB      0
SCORE:            DB      0, 0
LIVES:            DB      3

INV_MATRIX:       DS      MAX_INV * INV_ENTRY

; ============================================================
; Sprite Data - 3 types, 2 states, 3 yPos variants
; Each variant stores 5 bytes for the upper row and 5 bytes for the lower row.
; The renderer copies 4 bytes from each row: leading blank + 3 visible chars.
; Layout per type (60 bytes):
;   S0_Y0: top5 + bot5
;   S0_Y1: top5 + bot5
;   S0_Y2: top5 + bot5
;   S1_Y0: top5 + bot5
;   S1_Y1: top5 + bot5
;   S1_Y2: top5 + bot5
; ============================================================
        ORG     9000H
SPRITE_BASE:
; Sprite Data - 3 types, 2 states, 3 yPos, 5 bytes per row
; Layout: type*60 + state*30 + yPos*10

; Type 0 - Squid
        DB      128,174,159,133,128
        DB      128,129,128,130,128

        DB      128,140,191,139,128
        DB      128,130,128,130,128

        DB      128,144,176,144,128
        DB      128,175,143,135,128

        DB      128,160,158,164,128
        DB      128,128,129,129,128

        DB      128,128,188,172,128
        DB      128,129,128,130,128

        DB      128,128,144,128,128
        DB      128,176,175,139,128

; Type 1 - Crab
        DB      128,138,191,171,128
        DB      128,131,128,131,128

        DB      128,128,174,164,128
        DB      128,143,159,143,128

        DB      128,128,138,136,128
        DB      128,175,191,175,128

        DB      128,130,191,186,128
        DB      128,128,129,128,128

        DB      128,128,175,170,128
        DB      128,130,128,130,128

        DB      128,128,130,130,128
        DB      128,159,191,159,128

; Type 2 - Octopus
        DB      128,140,191,140,128
        DB      128,129,128,130,128

        DB      128,128,172,168,128
        DB      128,143,143,139,128

        DB      128,128,136,128,128
        DB      128,175,191,175,128

        DB      128,128,188,168,128
        DB      128,129,128,130,128

        DB      128,128,168,176,128
        DB      128,130,159,138,128

        DB      128,128,128,144,128
        DB      128,168,191,175,128

        END     START
