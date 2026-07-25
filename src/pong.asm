INCLUDE "hardware.inc"
INCLUDE "lib/objects.asm"

SECTION "Header", ROM0[$100]

	jp Initialise

	ds $150 - @, 0 ; Make room for the header

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

	ld a, 80
	ld [wYPaddle], a

	ld d, 0
	ld hl, $FE00 ; start of OAM
	ld bc, OAM_SIZE
	call SetOAM

	; Draw paddle on field
	call RenderPaddle

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
	ei

GameLoop:
.localVBlank:
	halt 
	ld a, [wVBlankFlag]
	cp 0
	jr z, .localVBlank

	ld a, 0
	ld [wVBlankFlag], a

	ld a, JOYP_GET_CTRL_PAD
	call .nibbleise
	ld d, a		  ; store button states

	and a, JOYP_DOWN ; check if down was pressed
	jr nz, .up ; if not, hop to up instructions

	ld a, [wYPaddle]
	inc a
	ld [wYPaddle], a

.up
	ld a, d
	and a, JOYP_UP ; check if up was pressed
	jr nz, .end ; if not, no button was pressed (for now)

	ld a, [wYPaddle]
	dec a
	ld [wYPaddle], a

.end
	call RenderPaddle
	jr GameLoop

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

; Copies bc bytes from [de] to [hl], one byte at a time.
Memcpy:
	ld a, [de]
	ld [hli], a
	inc de
	dec bc
	ld a, b
	or a, c
	jr nz, Memcpy
	ret

SetOAM:
	ld a, d
	ld [hli], a
	dec bc
	ld a, b
	or a, c
	jr nz, SetOAM
	ret

RenderPaddle:
	; Draw paddle on field
	ld hl, $FE00 ; start of OAM
	ld a, [wYPaddle]
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
wYPaddle: db

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
