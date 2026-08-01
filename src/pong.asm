INCLUDE "lib/hardware.inc"
INCLUDE "lib/objects.asm"

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                        P O N G  V A R I A T I O N S                        ;;
;;————————————————————————————————————————————————————————————————————————————;;
;;                           Sebastián Romero Cruz                            ;;
;;                               Aestās MMXXVI                                ;;
;;————————————————————————————————————————————————————————————————————————————;;
;;                                                                            ;;
;;                             E8 AB B8 E8 A1 8C                              ;;
;;                             E7 84 A1 E5 B8 B8                              ;;
;;                                                                            ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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
	ld [wYComputer], a ; store initial y-coord of paddle

	; initial x,y-coord of ball
	ld [wYBall], a   ; store initial y-coord of ball
	ld a, BALL_X_ST  ; initial x-coord of ball
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
 	ld hl, OAM_START ; start of OAM
	ld a, [wYPlayer]
	ld d, PAD_X_CRD
	call RenderPaddle

	ld hl, COM_OAM
	ld a, [wYComputer]
	ld d, COM_X_CRD
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
	ld [wCooldownTimer], a

	; Enable vblank interrupt
	ld a, IE_VBLANK
	ld [rIE], a
	ei ; enable interrupts

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Main Game Loop
;; - Waits for vblank interrupt to set wVBlankFlag
;; - Reads ctrl pad and updates the player paddle's position
;; - Updates the computer paddle's position (AI)
;; - Throttles and updates the ball's position once the cooldown timer set by
;;   ResetX expires
;; - Renders both paddles and the ball
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
	cp UPPER_BND
	jr z, .update

	inc a
	ld [wYPlayer], a

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; Check for up button press
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.up
	ld a, d
	and a, JOYP_UP ; check if up was pressed
	jr nz, .update ; if not, no button was pressed (for now)

	ld a, [wYPlayer]

	; clamp top
	cp LOWER_BND
	jr z, .update

	dec a
	ld [wYPlayer], a

	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
	;; Update, render, loop
	;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.update
	; The computer paddle tracks the ball every frame, independent of the
	; ball's own movement cooldown below, so it doesn't visibly stutter.
	call UpdateComputer

	ld a, [wCooldownTimer]
	cp COOLDOWN
	jr z, .ballMoves

	inc a
	ld [wCooldownTimer], a
	jr .render

.ballMoves
    call UpdateBall
.render
	ld hl, OAM_START ; start of OAM; player
	ld a, [wYPlayer]
	ld d, PAD_X_CRD
	call RenderPaddle

	ld hl, COM_OAM ; start of OAM; player
	ld a, [wYComputer]
	ld d, COM_X_CRD
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Update Computer
;; - Moves the computer paddle (AI) one pixel per frame toward the ball
;; - Compares the paddle's vertical midpoint (wYComputer + PAD_HEIGHT / 2,
;;   a compile-time constant folded in by RGBDS) against the ball's raw
;;   y-coord, since the paddle should center on the ball, not merely touch it
;;   with its top edge
;; - Moves down (increments y) if the paddle's midpoint is above the ball
;;   (smaller y, since y grows downward), up (decrements y) otherwise
;; - Clamps against the same UPPER_BND/LOWER_BND the player paddle uses
;; - Saves/restores af so it's safe to call unconditionally from GameLoop
;;   without disturbing the caller's a-register or flags
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
UpdateComputer:
	push af
	ld a, [wYComputer]
	add a, PAD_HEIGHT / 2 ; evaluated at assemble time
	ld b, a

	ld a, [wYBall]

	cp a, b
	jr nc, .moveDown
.moveUp ; ball higher
	ld a, [wYComputer]
	cp a, LOWER_BND
	jr z, .end

	dec a
	ld [wYComputer], a

	jr .end

.moveDown ; ball lower
	ld a, [wYComputer]
	cp a, UPPER_BND
	jr z, .end

	inc a
	ld [wYComputer], a

.end
	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Update Ball
;; - Bounces the ball off the top/bottom walls (UPPER_BND_BALL/LOWER_BND) by
;;   flipping wYBallDir, then advances the ball's y-coord by wYBallDir
;; - Checks the ball against both paddles' bounding boxes and flips
;;   wXBallDir on a hit (see CheckPaddleCollision)
;; - Resets the ball to the center once it crosses either side wall
;;   (LEFT_BOUND/RGHT_BOUND), then advances the ball's x-coord by wXBallDir
;; - Writes the resulting y/x-coords into BALL_OAM via hl
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
UpdateBall:
	; top and bottom walls
    ld hl, BALL_OAM

    ld a, [wYBall]
    cp a, UPPER_BND_BALL

    call nc, FlipY
    jr nc, .yCoord

    cp a, LOWER_BND
    call c, FlipY

.yCoord:
    ld a, [wYBallDir]
    ld b, a
	ld a, [wYBall]
	add a, b
	ld [wYBall], a
	ld [hli], a

	push hl

	; Paddle AABB collission check
	ld hl, wYPlayer
	ld d, PAD_X_COL
	call CheckPaddleCollision

	; Computer AABB collission check
	ld hl, wYComputer
	ld d, COM_X_COL
	call CheckPaddleCollision

	pop hl

.xCoord
	ld a, [wXBall]
	cp LEFT_BOUND
	call c, ResetX

	ld a, [wXBall]
	cp RGHT_BOUND
	call nc, ResetX

.setX
	ld a, [wXBallDir]
	ld b, a
	ld a, [wXBall]
	add a, b
	ld [wXBall], a
	ld [hli], a

	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Check Paddle Collision
;; - Performs an AABB (axis-aligned bounding box) check between the ball and
;;   a paddle: hl points at the paddle's y-coord variable (wYPlayer or
;;   wYComputer), d holds the paddle's collision x-coord (PAD_X_COL or
;;   COM_X_COL)
;; 1. Bails if the ball's x-coord doesn't match the paddle's collision plane
;; 2. Bails if the ball's y-coord is above the paddle's top edge
;; 3. Bails if the ball's y-coord is below the paddle's bottom edge
;;    (top + PAD_HEIGHT)
;; 4. Otherwise the ball is within the paddle's span, so flip wXBallDir
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
CheckPaddleCollision:
	; 1. if the ball's x-coord matches the paddle's right x-coord...
	ld a, [wXBall]
	cp a, d
	jr nz, .endCheck

	; 2. if the ball's y-coord is under the paddle's top y-coord...
	ld a, [hl]
	ld b, a
	ld a, [wYBall]
	cp a, b
	jr c, .endCheck

	; 3. if the ball's y-coord is over the paddle's bottom y-coord
	ld a, [hl]
	add a, PAD_HEIGHT
	ld b, a
	ld a, [wYBall]
	cp a, b
	jr nc, .endCheck

	; 4. then flip the x-direction
	call FlipX

.endCheck
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Flip Y
;; - Negates wYBallDir (two's complement: complement the bits, then +1),
;;   reversing the ball's vertical direction on a top/bottom wall bounce.
;; - Saves/restores af so it's safe to call conditionally (call nc/c, FlipY)
;;   from UpdateBall without disturbing the caller's a-register or flags -
;;   callers rely on a still holding [wYBall] and the flags from the
;;   preceding cp after this returns.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
FlipY:
	push af
	ld a, [wYBallDir]
	cpl
	inc a
	ld [wYBallDir], a
	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Flip X
;; - Negates wXBallDir (two's complement), reversing the ball's horizontal
;;   direction on a paddle bounce.
;; - Saves/restores af for the same reason as FlipY: callers invoke it
;;   conditionally (call, FlipX from CheckPaddleCollision; call c/nc, ResetX
;;   from UpdateBall) and rely on the flags/a-register surviving the call.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
FlipX:
	push af
	ld a, [wXBallDir]
	cpl
	inc a
	ld [wXBallDir], a
	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reset X
;; - Called from UpdateBall when the ball crosses either side wall, i.e. a
;;   "score"
;; - Recenters the ball at BALL_X_ST and flips wXBallDir so it launches back
;;   toward the paddle that just conceded
;; - Resets wCooldownTimer to 0, which briefly pauses UpdateBall (see
;;   GameLoop's .update) before the ball starts moving again
;; - Saves/restores af so it's safe to call conditionally (call c/nc, ResetX)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
ResetX:
	; actual reset
	push af
	ld a, BALL_X_ST
	ld [wXBall], a
	call FlipX

	ld a, 0
	ld [wCooldownTimer], a

	pop af
	ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Render Paddle
;; - Draws a paddle on the field as three stacked 8x8 tiles
;; - a holds the paddle's top y-coord, d holds its x-coord, hl points at the
;;   first of its 4 OAM entries (OAM_START for the player, COM_OAM for the
;;   computer)
;; - Loops 3 times, writing y, x, tile index 0, and no-flip/palette-0 attrs
;;   for each tile, advancing y by 8 each iteration to stack them vertically
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RenderPaddle:
	; Draw paddle on field
	ld c, a
	ld b, 3
.paddleLoop
	ld a, c

	ld [hli], a ; write y-coord and increment pointer

	ld a, d ; x = d + 8 offset
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Render Ball
;; - Writes the ball's single OAM entry (BALL_OAM) from wYBall/wXBall, using
;;   tile index 1 and no-flip/palette-0 attrs
;; - Preserves hl across the call (push/pop) since callers (UpdateBall via
;;   GameLoop, Initialise) rely on hl for their own OAM bookkeeping
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
RenderBall:
	push hl
    ld hl, BALL_OAM
	ld a, [wYBall]
	ld [hli], a

	ld a, [wXBall]
	ld [hli], a

	ld a, 1
	ld [hli], a

	ld a, %00000000
	ld [hli], a
	pop hl
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

SECTION "Input Variables", WRAM0

; general
wVBlankFlag:    db
wCooldownTimer: db

; paddles
wYPlayer: 	    db
wYComputer:		db

; ball
wYBall: 	    db
wXBall: 	    db
wXBallDir:      db
wYBallDir:      db

; OAM related
DEF OAM_START      EQU $FE00
DEF BALL_OAM       EQU $FE0C
DEF COM_OAM		   EQU $FE10

; y-axis
DEF UPPER_BND      EQU 136
DEF UPPER_BND_BALL EQU 152
DEF LOWER_BND      EQU 16

; x-axis
DEF PAD_X_COL  	   EQU 28
DEF PAD_X_CRD	   EQU 20
DEF COM_X_COL	   EQU 138
DEF COM_X_CRD	   EQU 146

DEF PAD_HEIGHT 	   EQU 24
DEF LEFT_BOUND	   EQU 8
DEF RGHT_BOUND	   EQU 160

DEF BALL_X_ST	   EQU 88

; general
DEF COLL_TOLER     EQU 5
DEF COOLDOWN	   EQU 30

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
