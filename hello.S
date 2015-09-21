; "Hello Boing"
; (c) 2015 Michal Siejak [www.siejak.pl]

***********************************************
** CONSTANTS
***********************************************
SCREEN_W = 256
SCREEN_H = 256
FP_BITS  = 8
FP_ONE   = $100
FP_TWO   = $200
FP_HALF  = $080
FP_INF   = $0f00

FP_EYE   = $fc00
FP_NEGEYE= $0400
FP_SQREYE= $1000
FP_SKYTHR= $ffb9
FP_PLNTHR= $0042

SCREEN_BYTES = SCREEN_W*SCREEN_H/8*5
FRAME_BYTES  = SCREEN_W*SCREEN_H*2
FRAME16_BYTES= SCREEN_W*SCREEN_H*2
COPPER_BYTES = 2048

***********************************************
** INIT
***********************************************

        SECTION init,CODE
; Initialize everything
init:
        ; Save Workbench copper ptr
        
        move.l 4.w,a6           ; Read execbase
        
        clr.l d0                ; Open graphics.library
        move.l #gfxname,a1
        jsr -408(a6)
        
        move.l d0,a1            ; Save original copper ptr
        move.l 38(a1),-(a7)

        clr.l d0                ; Close graphics.library
        jsr -414(a6)        

        ; Save hardware registers
        
        move $dff01c,-(a7)      ; Read INTENAR
        move $dff002,-(a7)      ; Read DMACONR

        ; Set relevant hardware registers
        
        move.w #$138,d0         ; Wait for vertical blank
        bsr.w waitras
        
        move #$7fff,$dff09a     ; Disable all bits in INTENA
        move #$7fff,$dff09c     ; Disable all bits in INTREQ
        move #$7fff,$dff09c     ; Disable all bits in INTREQ (for A4000)
        move #$7fff,$dff096     ; Disable all bits in DMACON

        ; Setup bitplane pointers

        lea screen,a0           ; Patch bitplane pointers
        move.l a0,d0            ; in copper header
        lea copper_bpl,a0
        moveq #0,d1
.setbplptr:
        move.w d0,6(a0,d1.w)    ; Low-word
        swap d0
        move.w d0,2(a0,d1.w)    ; High-word
        swap d0
        add.l #32,d0            ; Add stride (32bytes per scanline)
        addq #8,d1              ; Move to next bplptr position
        cmp.w #40,d1            ; We need 5 bitplanes ...
        blt .setbplptr

        ; Construct & initialize our copper list

        lea copper_hdr,a0       ; Copy copper list header
        lea copper,a1
        move.w #(copper_end-copper_hdr)/2-1,d0
.setcophdr:
        move.w (a0)+,(a1)+
        dbf d0,.setcophdr

        ; Create copper palette

        lea palette,a0          ; Precomputed palette ptr
        move.w (a0)+,d0         ; Number of palette changes
.setpal_region:
        move.w (a0)+,d1         ; Scanline
        adda #2,a0              ; Skip framebuf sentinel
        move.w (a0)+,d2         ; Number of colors
        move.w #$182,d3         ; Base register

        cmp.w #$ff,d1           ; Allow copper to continue past
        bls.b .setpal_genwait   ; line 256 on PAL screens
        move.l #$ffdffffe,(a1)+        

.setpal_genwait:
        lsl.w #8,d1             ; Generate copper WAIT instruction
        move.b #$af,d1
        move.w d1,(a1)+
        move.w #$fffe,(a1)+

.setpal_color:
        move.w d3,(a1)+         ; Store color register in copper list
        move.w (a0)+,(a1)+      ; Store color value in copper list
        addq #2,d3              ; Increment to next color register
        dbf d2,.setpal_color    ; Loop for all colors

        dbf d0,.setpal_region   ; Loop for all regions
        
        move.l #$fffffffe,(a1)+ ; Terminate copper list
        move.l #copper,$dff080  ; Initialize copper ptr register

        ; Clear the screen

        lea screen,a0           ; Screen ptr
        move.w #SCREEN_BYTES/4-1,d0 ; Loop for all #dwords in screen
.clear:
        move.l #0,(a0)+         ; Clear 4 bytes
        dbf d0,.clear

        ; Render image
        
        jsr render
        jsr dither
        jsr blit

        ; Show image on screen
        
        move.w #$138,d0         ; Wait for vertical blank        
        bsr.w waitras
        move #$8380,$dff096     ; Enable copper & bitplane DMA        

        ; Wait for LMB
        
.waitmouse
        btst #6,$bfe001         ; Is FIR0 in CIA A cleared (LMB pressed)?
        bne.b .waitmouse

        ; Exit to OS
        
        move.w (a7)+,d0         ; Restore original value of DMACON
        move.w (a7)+,d1         ; Restore original value of INTENA
        move.l (a7)+,$dff080    ; Restore original copper ptr

        move.w #$7fff,$dff096   ; Clear & enable original bits of DMACON
        or.w #$8200,d0
        move.w d0,$dff096

        or #$0c000,d1           ; Enable interrupts
        move d1,$dff09a

        clr.l d0                ; Return to OS
        rts

; Wait for raster position
waitras:
        move.l #$1ff00,d2
        lsl.l #8,d0
        and.l d2,d0
        lea $dff004,a0
.loop:        move.l (a0),d1
        and.l d2,d1
        cmp.l d1,d0
        bne.s .loop
        rts

; Library names
gfxname:
        dc.b "graphics.library",0

*************************************************
** COPPER
*************************************************

; Copper list header
        SECTION copper_hdr,DATA
        EVEN
copper_hdr:
        dc.w $1fc,$0            ; Slow fetch mode (for AGA)
        dc.w $100,$0200         ; Disable bitplanes (+colorburst)
        
        dc.w $08e,$2ca1         ; Set 256x256 centered screen
        dc.w $090,$2ca1
        dc.w $092,$48           ; Set display DMA accordingly
        dc.w $094,$c0
        dc.w $108,$80           ; Set BPL1MOD
        dc.w $10a,$80           ; Set BPL2MOD

copper_bpl:
        dc.w $e0,$0             ; Bitplane 1 pointer
        dc.w $e2,$0
        dc.w $e4,$0             ; Bitplane 2 pointer
        dc.w $e6,$0
        dc.w $e8,$0             ; Bitplane 3 pointer
        dc.w $ea,$0
        dc.w $ec,$0             ; Bitplane 4 pointer
        dc.w $ee,$0
        dc.w $f0,$0             ; Bitplane 5 pointer
        dc.w $f2,$0
        
        dc.w $100,$5200         ; Enable bitplanes
        dc.w $180,$000          ; Set black background
copper_end:

*************************************************
** BUFFERS
*************************************************

; Chip RAM buffers
        SECTION chipbuf,BSS_C
        EVEN
screen:
        ds.b SCREEN_BYTES        

        EVEN
copper:
        ds.b COPPER_BYTES

; Screen (fake)
;        SECTION fscreen,DATA_C
;        EVEN
;screen:
;        incbin "img.bpl"

; Framebuffer
        SECTION framebuf,BSS
        EVEN
framebuf:
        ds.b FRAME_BYTES

        EVEN
framebuf16:
        ds.b FRAME16_BYTES

***********************************************
** DATA
***********************************************

        SECTION data,DATA

        EVEN
lut_sqrt:
        INCBIN "sqrt.lut"

        EVEN
lut_uv:
        INCBIN "uv.lut"

        EVEN
palette:
        INCBIN "colors.pal"

*************************************************
** MATH LIBRARY
*************************************************

; Multiply signed fp numbers 
; Result: \1
fp_mul  MACRO
        muls.w \2,\1
        asr.l #FP_BITS,\1
        ENDM

; Divide signed fp numbers
; Result: \1
fp_div  MACRO
        ext.l \1
        asl.l #FP_BITS,\1
        divs.w \2,\1
        ENDM

; Absolute value of a fp number
fp_abs  MACRO
        ; TODO
        nop
        ENDM

; Square root of a fp number
; Result: \1
; Modifies: a6
fp_sqrt MACRO
        lea lut_sqrt,a6
        and.w #$FFFE,\1 
        adda.w \1,a6
        move.w (a6),\1
        ENDM

; Vector add
; Result: \1,\2,\3
v_add   MACRO
        add.w \4,\1
        add.w \5,\2
        add.w \6,\3
        ENDM

; Vector/scalar multiply
; Result: \1,\2,\3
v_mul   MACRO
        fp_mul \1,\4
        fp_mul \2,\4
        fp_mul \3,\4        
        ENDM

; Vector dot product
; Result: \1
; Modifies: \2,\3
v_dot   MACRO
        fp_mul \1,\4
        fp_mul \2,\5
        fp_mul \3,\6
        add.w \2,\1
        add.w \3,\1
        ENDM

; Vector length
; Result: \1
; Modifies: \2,\3
v_len   MACRO
        v_dot \1,\2,\3,\1,\2,\3
        fp_sqrt \1
        ENDM

; Vector normalize
; Result: \1,\2,\3
; Modifies: d7
v_norm  MACRO
        movem.l \1/\2/\3,-(a7)
        v_len \1,\2,\3
        move.w \1,d7
        movem.l (a7)+,\1/\2/\3
        fp_div \1,d7
        fp_div \2,d7
        fp_div \3,d7
        ENDM

; Vector negate
v_neg   MACRO
        neg.w \1
        neg.w \2
        neg.w \3
        ENDM

*************************************************
** RENDERING
*************************************************

        SECTION render,CODE

raycast:
        ; Generate ray

        subi.w #FP_HALF,d1      ; Calculate rayX
        subi.w #FP_HALF,d2      ; Calculate rayY
        move.w #FP_ONE,d3       ; rayZ=1

        move.w d2,d0            ; Save sky param in d0
        cmp.w #FP_SKYTHR,d2     ; Jump to sky if we're high enough
        blt.w .sky

        move.w d1,d4            ; Make a copy of the ray
        move.w d2,d5
        move.w d3,d6
        v_len d4,d5,d6          ; Get ray length
        fp_div d1,d4            ; Normalize ray
        fp_div d2,d4
        fp_div d3,d4

.sphere:
        ; Calculate sphere intersection

        cmp.w #FP_PLNTHR,d2     ; Jump to plane if we're low enough
        bgt.w .plane

        move.w #FP_NEGEYE,d4    ; -eyeZ
        fp_mul d4,d3            ; dr=ray dot eye
        move.w d4,d5
        fp_mul d5,d5            ; dr^2
        move.w #FP_SQREYE,d6    ; eyeZ^2
        sub.w d5,d6             ; dist2=eyeZ^2 - dr^2

        cmp.w #FP_ONE,d6        ; If dist2>1, no hit
        bgt .plane

        move.w #FP_ONE,d5       ; a=sqrt(1-dist2)
        sub.w d6,d5
        fp_sqrt d5

        sub.w d5,d4             ; t=dr-a

        cmp.w #FP_INF,d4        ; If t>=INFINITY, no hit
        bge .plane

.shade_sphere:
        ; Shade sphere

        v_mul d1,d2,d3, d4      ; N=ray*t
        
        move.w d1,d4            ; u=Nx+1
        add.w #FP_ONE,d4
        move.w d2,d5            ; v=Ny+1
        add.w #FP_ONE,d5
        
        add.w #FP_ONE,d2        ; Occ=(Ny+1)*0.5
        fp_mul d2,#FP_HALF

        move.w #FP_ONE,d0       ; Occ'=1-Occ
        sub.w d2,d0
        sub.b #1,d0             ; Compensate for lack of 1.0 representation

        ; Texture sphere
        
        lea lut_uv,a6           ; u' lookup
        adda.w d4,a6
        move.b (a6),d4

        lea lut_uv,a6           ; v' lookup
        adda.w d5,a6
        move.b (a6),d5

        cmp.b d4,d5
        bne.b .tint_red

.tint_white:
        move.b d0,d1
        rts        

.tint_red:
        move.b #0,d1
        rts        

.plane:
        ; Calculate plane intersection

        cmp.w #0,d2             ; If rayY<=0, no hit
        ble .sky

        move.w #FP_ONE,d4       ; t=1/rayY
        fp_div d4,d2

        cmp.w #0,d4             ; If t<=0, no hit
        ble .sky
        cmp.w #FP_INF,d4        ; If t>=INFINITY, no hit
        bge .sky

.shade_plane:
        ; Shade plane

        v_mul d1,d2,d3, d4      ; p=eye+ray*t
        add.w #FP_EYE,d3

        v_dot d1,d2,d3,d1,d2,d3 ; |p|^2 (square length p)
        move.w #FP_ONE,d2       ; Occ=1/|p|^2
        fp_div d2,d1

        move.w #FP_ONE,d0       ; Occ'=1-Occ
        sub.w d2,d0                

        cmp.w #0,d0             ; Clamp Occ (0,1) due to
        bge.b .clamped_min      ; Q8.8 overflow
        moveq #0,d0
        bra.b .clamped_max
.clamped_min:
        cmp.w #FP_ONE,d0
        ble.b .clamped_max
        move.w #FP_ONE,d0
.clamped_max:

        move.b d0,d1
        rts

.sky:
        ; Draw sky
        move.b #$ff,d1          ; G/B is always 1

        add.w #FP_HALF,d0       ; s=rayY+0.5
        fp_mul d0,#FP_TWO       ; s=2s
        cmp.w #FP_ONE,d0        ; No need to interpolate for s>=1
        bge .sky_white

        rts

.sky_white:
        move.b #$ff,d0          ; R=1
        move.b #$ff,d1          ; G=1
        rts

render:
        lea framebuf,a0         ; Framebuffer ptr
        clr.w d1                ; Reset X-pos
        clr.w d2                ; Reset Y-pos

.loopy:
.loopx:
        movem.w d1-d2,-(a7)     ; Save state
        
        bsr.w raycast           ; Raycast!
        
        move.b d0,(a0)+         ; Store R
        move.b d1,(a0)+         ; Store G

        movem.w (a7)+,d1-d2     ; Restore state
        
        add.b #1,d1             ; Increment X-pos
        bcc.b .loopx            ; Loop if wrapped
        add.b #1,d2             ; Increment Y-pos
        bcc.b .loopy            ; Loop if wrapped

        rts                     ; We're done

*************************************************
** DRAWING
*************************************************

dither_channel:

.dither_x1y:
        cmp.b #$ff,d6           ; Skip if last X pos
        beq.b .next_x1y

        moveq #0,d3             ; Clear d3 for subsequent mulu
        move.b d5,d3            ; error * (7/16)
        mulu.w #7,d3
        lsr.w #4,d3

        moveq #0,d4             ; Clear d4 for subsequent add
        move.b (a2),d4          ; Distribute error (X+1,Y)
        add.w d3,d4
        cmp.w #$ff,d4           ; Clamp value to 255
        bls.b .store_x1y
        move.b #$ff,d4
.store_x1y:
        move.b d4,(a2)+         ; Store dithered value
        bra.b .dither_x_1y1
.next_x1y:
        adda.l #1,a2        

.dither_x_1y1:
        cmp.b #$ff,d7           ; Skip if last Y pos
        beq.b .done

        moveq #0,d3             ; Clear d3 for subsequent mulu
        move.b d5,d3            ; error * (3/16)
        mulu.w #3,d3
        lsr.w #4,d3

        moveq #0,d4             ; Clear d4 for subsequent add
        move.b (a3),d4          ; Distribute error (X-1,Y+1)
        add.w d3,d4
        cmp.w #$ff,d4           ; Clamp value to 255
        bls.b .store_x_1y1
        move.b #$ff,d4
.store_x_1y1:
        move.b d4,(a3)+         ; Store dithered value

.dither_xy1:
        moveq #0,d3             ; Clear d3 for subsequent mulu
        move.b d5,d3            ; error * (5/16)
        mulu.w #5,d3
        lsr.w #4,d3

        moveq #0,d4             ; Clear d4 for subsequent add
        move.b (a4),d4          ; Distribute error (X,Y+1)
        add.w d3,d4
        cmp.w #$ff,d4           ; Clamp value to 255
        bls.b .store_xy1
        move.b #$ff,d4
.store_xy1:
        move.b d4,(a4)+         ; Store dithered value

.dither_x1y1:
        moveq #0,d3             ; Clear d3 for subsequent add
        move.b d5,d3            ; error * (1/16)
        lsr.b #4,d3

        moveq #0,d4             ; Clear d4 for subsequent add
        move.b (a5),d4          ; Distribute error (X+1,Y+1)
        add.w d3,d4        
        cmp.w #$ff,d4           ; Clamp value to 255
        bls.b .store_x1y1
        move.b #$ff,d4
.store_x1y1:
        move.b d4,(a5)+         ; Store dithered value

.done:
        rts

dither:
        lea framebuf,a0         ; Src framebuffer ptr
        lea framebuf16,a1       ; Dithered 16-bit framebuffer ptr
        
        movea.l a0,a2           ; Dst(X+1,Y) ptr
        adda.l #2,a2
        movea.l a0,a3           ; Dst(X-1,Y+1) ptr
        adda.l #(SCREEN_W-1)*2,a3
        movea.l a3,a4           ; Dst(X, Y+1) ptr
        adda.l #2,a4
        movea.l a4,a5           ; Dst(X+1,Y+1) ptr
        adda.l #2,a5

        clr.w d6                ; Reset X-pos
        clr.w d7                ; Reset Y-pos

.loopy:
.loopx:                

        moveq #0, d0

        move.b (a0)+,d0         ; Read source R component
        move.b d0,d5            ; Compute error
        and.b #$0f,d5
        bsr.w dither_channel    ; Dither R component

        lsl.w #4,d0             ; Compute new color value (from R)
        and.w #$f00,d0

        move.b (a0)+,d1         ; Read source G component
        move.b d1,d5            ; Compute error
        and.b #$0f,d5
        bsr.w dither_channel    ; Dither G component

        and.b #$f0,d1           ; Accumulate new color value (add G)
        or.w d1,d0
        lsr.b #4,d1             ; Accumulate new color value (add B)
        or.w d1,d0
        
        move.w d0,(a1)+         ; Store new color value

        add.b #1,d6             ; Increment X-pos
        bcc.b .loopx            ; Loop if wrapped
        add.b #1,d7             ; Increment Y-pos
        bcc.b .loopy            ; Loop if wrapped
                
        rts

blit:
        ; Initialize pointers

        lea palette,a0          ; Palette ptr (first entry)
        adda.l #4,a0            ; Skip header
        lea framebuf16,a1       ; 16-bit framebuf ptr
        lea screen,a2           ; Screen ptr

        clr.l d4
        move.w (a0)+,d5         ; Get first sentinel
        move.w (a0)+,d4         ; Get first color count
        
        clr.w d6                ; Reset X-pos
        clr.w d7                ; Reset Y-pos

.loopy:
        ; Find current pal segment

        cmp.w d5,d7             ; Are we past sentinel?
        bls.b .palok            ; If not, use current pal segment
        lsl.w #1,d4             ; Get previous segment size
        adda.l d4,a0            ; Skip previous segment
        adda.l #4,a0            ; Skip last entry & scanline number
        move.w (a0)+,d5         ; Update sentinel
        move.w (a0)+,d4         ; Update color count 
        
.palok:
        move.b #8,d1            ; Reset bpl counter

.loopx:
        ; Find color in current pal segment

        movea.l a0,a3           ; Save current segment ptr
        move.w d4,a4            ; Save current color count
        move.w (a1)+,d2         ; Get current fb color
        move.b #0,d0            ; Initial out color is background
.nextcol:
        add.b #1,d0             ; Increment color index
        move.w (a3)+,d3         ; Get pal color
        cmp.w d2,d3
        dbeq d4,.nextcol        ; If not equal, try again

        cmp.b #$ff,d4           ; Have we looped through whole palette?
        bne.b .putpixel         ; If no, color has been found
        move.b #0,d0            ; If yes, reset to background color

.putpixel:
        move.w a4,d4            ; Restore current color count

        sub.b #1,d1             ; Decrement bpl counter
        move.b #1,d2            ; Compute this iteration OR value
        lsl.b d1,d2             ; which is 1<<(bpl counter)

.bpl1:
        btst #0,d0
        beq.b .bpl2
        or.b d2,(a2)
.bpl2:
        btst #1,d0
        beq.b .bpl3
        or.b d2,32(a2)
.bpl3:
        btst #2,d0
        beq.b .bpl4
        or.b d2,64(a2)
.bpl4:
        btst #3,d0
        beq.b .bpl5
        or.b d2,96(a2)
.bpl5:
        btst #4,d0
        beq.b .done
        or.b d2,128(a2)
.done:

        cmp.b #0,d1             ; Reset bpl counter if 0
        bne.b .continue
        move.b #8,d1
        adda #1,a2              ; Increment screen ptr to next byte
        
.continue:
        add.b #1,d6
        bcc.b .loopx

        adda #SCREEN_W/8*4,a2   ; Skip bitplane modulo

        add.b #1,d7
        bcc.w .loopy
                        
        rts
        
