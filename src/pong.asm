INCLUDE "lib/hardware.inc"
INCLUDE "lib/objects.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                   P O N G  V A R I A T I O N S                   ;;
;;——————————————————————————————————————————————————————————————————;;
;;                      Sebastián Romero Cruz                       ;;
;;                          Aestās MMXXVI                           ;;
;;——————————————————————————————————————————————————————————————————;;
;;                                                                  ;;
;;                        E8 AB B8 E8 A1 8C                         ;;
;;                        E7 84 A1 E5 B8 B8                         ;;
;;                                                                  ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Header
;; - Sets the entry point to the Initialise routine
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Header", ROM0[$100]

	jp Initialise

	ds $150 - @, 0 ; Make room for the header

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Initialise
;; - Shuts down audio circuitry
;; - Waits for VBlank to turn off LCD
;; - Loads tile data into VRAM
;; - Loads tilemap into VRAM
;; - Initializes display registers
;; - Enables vblank interrupt
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Initialise:
	; Shut down audio circuitry
	ld a, 0
	ld [rNR52], a

	; Do not turn the LCD off outside of VBlank
WaitVBlank:
	ld a, [rLY]
	cp 144
	jr c, WaitVBlank

	; Turn the LCD off
	ld a, 0
	ld [rLCDC], a

	; Load Paddle Data
	ld de, PaddleTile
	ld hl, $8000
	ld bc, PaddleTile.End - PaddleTile
	call Memcpy

	; Load Ball data
	ld de, BallTile
	ld hl, $8010
	ld bc, BallTile.End - BallTile
	call Memcpy

	; Load the tilemap
	ld de, Tilemap
	ld hl, $9800
	ld bc, Tilemap.End - Tilemap
	call Memcpy

	; Defines what tile index 0 looks like: a pattern where every pixel is
	; color 3
	ld de, PaddleTile
	ld hl, $9000
	ld bc, PaddleTile.End - PaddleTile
	call Memcpy

	ld a, 80         ; initial y-coord of paddle
	ld [wYPlayer], a ; store initial y-coord of paddle

	; initial x,y-coord of ball
	ld [wYBall], a   ; store initial y-coord of ball
	ld a, 88         ; initial x-coord of ball
	ld [wXBall], a   ; store initial x-coord of ball

	; initial x,y-directions of ball
	ld a, %11111111
	ld [wYBallDir], a
	ld [wXBallDir], a

	ld d, 0 ; initialize OAM with 0s
	ld hl, OAM_START ; start of OAM
	ld bc, OAM_SIZE
	call SetOAM

	; Draw paddle on field
	call RenderPaddle
	call RenderBall

	; Turn the LCD on
	ld a, LCDC_ON | LCDC_BG_ON | LCDC_OBJ_ON
	ld [rLCDC], a

	; During the first (blank) frame, initialize display registers
	ld a, %11100100
	ld [rBGP], a

	ld a, %00100111
	ld [rOBP0], a

	; Initialise variables
	ld a, 0
	ld [wVBlankFlag], a

	; Enable vblank interrupt
	ld a, IE_VBLANK
	ld [rIE], a
	ei ; enable interrupts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main Game Loop
;; - Waits for vblank interrupt to set wVBlankFlag
;; - Reads ctrl pad and updates paddle position
;; - Renders paddle
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
GameLoop:
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; VBLANK Wait
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.localVBlank:
	; Wait for vblank interrupt to set wVBlankFlag
	; The vblank interrupt sets wVBlankFlag to 1, which is checked here. If it
	; is 0, the program halts until the next interrupt.
	; This ensures that the game logic runs in sync with the display refresh,
	; preventing visual tearing and ensuring smooth gameplay.
	; The halt instruction puts the CPU in a low-power state until the next
	; interrupt occurs, which is efficient for battery-powered devices like
	; the Game Boy.
	; The check for wVBlankFlag being 0 ensures that the program only proceeds
	; with game logic when a vblank has occurred, maintaining proper timing
	; and synchroniSation with the display.
	halt
	ld a, [wVBlankFlag]
	cp 0
	jr z, .localVBlank

	ld a, 0
	ld [wVBlankFlag], a

	; Ctrl Pad Logic
	; - Selects ctrl pad (and burns some cycles)
	; - Reads button states, saves them in d-register
	; - Checks if down was pressed with JOYP_DOWN mask
	;		- checks for out of bounds
	; 		- dec player's y-coord if not
	;		- if not pressed, skips to up logic
	; - Checks if up was pressed with JOYP_DOWN mask and d-register (same
	;	 logic)
	; - Renders paddle
	ld a, JOYP_GET_CTRL_PAD
	call .nibbleise
	ld d, a		  ; store button states

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; Check for down button press
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	and a, JOYP_DOWN ; check if down was pressed
	jr nz, .up ; if not, hop to up instructions

	ld a, [wYPlayer]

	; clamp bottom
	cp 136
	jr z, .end

	inc a
	ld [wYPlayer], a

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; Check for up button press
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.up
	ld a, d
	and a, JOYP_UP ; check if up was pressed
	jr nz, .end ; if not, no button was pressed (for now)

	ld a, [wYPlayer]

	; clamp top
	cp 16
	jr z, .end

	dec a
	ld [wYPlayer], a

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; Render Paddle and loop
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.end
    call UpdateBall

	call RenderPaddle
	call RenderBall
	jr GameLoop

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reads the ctrl pad and returns the button states in the a-register
;; - Selects ctrl pad (and burns some cycles)
;; - Reads button states, returns them in a-register
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.nibbleise:
	; select ctrl pad
	ld a, [rJOYP]

	; burn cycles
	call .knownret
	ld [rJOYP], a
	ld [rJOYP], a

	; read button state
	ld [rJOYP], a

	; force up nibble to all 1s, preserves button presses
	or a, $F0
.knownret
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Memcpy
;; - Copies bc bytes from de-register to hl-register, one byte at a time.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
Memcpy:
	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, Memcpy
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Set OAM
;; - Copies bc bytes from d-register to [hl], one byte at a time.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SetOAM:
	ld a, d
	ld [hli], a
	dec bc
	ld a, b
	or a, c
	jr nz, SetOAM
	ret

UpdateBall:
    ld hl, BALL_OAM
    ld a, [wYBallDir]
    ld b, a
	ld a, [wYBall]
	add a, b
	ld [wYBall], a
	ld [hli], a

	ld a, [wXBallDir]
	ld b, a
	ld a, [wXBall]
	add a, b
	ld [wXBall], a
	ld [hli], a

	ret

RenderBall:
    ld hl, BALL_OAM
	ld a, [wYBall]
	ld [hli], a

	ld a, [wXBall]
	ld [hli], a

	ld a, 1
	ld [hli], a

	ld a, %00000000
	ld [hli], a
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Render Paddle
;; - Draws paddle on field
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RenderPaddle:
	; Draw paddle on field
	ld hl, OAM_START ; start of OAM
	ld a, [wYPlayer]
	ld c, a	 ; y=80
	ld b, 3
.paddleLoop
	ld a, c

	ld [hli], a ; write y-coord and increment pointer

	ld a, 20 ; x =12 + 8 offset
	ld [hli], a ; write x-coord and increment pointer

	ld a, 0 ; tile index
	ld [hli], a ; write tile index and increment pointer

	ld a, %00000000 ; attr: no flip, palette 0, no priority
	ld [hli], a ; write attr and increment ptr

	ld a, c
	add a, 8
	ld c, a

	dec b ; sets the zero flag, so no need to cp 0
	jr nz, .paddleLoop
	ret


SECTION "Input Variables", WRAM0

wVBlankFlag: db ; for vblank interrupt
wYPlayer: 	 db
wYBall: 	 db
wXBall: 	 db
wXBallDir:   db
wYBallDir:   db

DEF OAM_START EQU $FE00
DEF BALL_OAM  EQU $FE0C

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Interrupt Handler
;; - Sets wVBlankFlag to 1 when vblank interrupt occurs
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
SECTION "Interrupt Handler", ROM0[$0040]

	push af

	ld a, 1
	ld [wVBlankFlag], a

	pop af

	reti

SECTION "Tilemap", ROM0

Tilemap:
	REPT 1024
		db 0
	ENDR
.End:
