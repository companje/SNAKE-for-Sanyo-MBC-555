%define SIZE_640x200

%include "header.asm"

; Het speelveld volgt de geometrie van de oorspronkelijke 320x200-versie,
; met een horizontale verdubbeling voor de 640 pixels brede Sanyo-modus.
FIELD_TOP    equ 9
FIELD_BOTTOM equ 199
FIELD_LEFT   equ 0
FIELD_RIGHT  equ 639

FOOD_X       equ 304             ; byte-uitgelijnd: acht schermpixels breed
FOOD_Y       equ 80              ; vier-scanline-uitgelijnd
FOOD_OFFSET  equ (FOOD_Y / 4) * ROW_BYTES + (FOOD_X / 8) * 4

setup:
  push cs
  pop ds

  ; Blauw is de speelveldachtergrond; rood en groen beginnen op nul.
  mov ax,RED
  mov es,ax
  call clear_plane
  mov ax,GREEN
  mov es,ax
  call clear_plane
  mov ax,BLUE
  mov es,ax
  mov cx,PLANE_BYTES/2
  mov ax,-1
  xor di,di
  rep stosw

  call draw_playfield
  call draw_food

draw:
  jmp draw

; Teken het witte kader. Horizontale lijnen worden per videobyte getekend;
; de twee verticale lijnen volgen de vier-scanline-indeling van de VRAM.
draw_playfield:
  mov al,FIELD_TOP
  call draw_white_hline
  mov al,FIELD_BOTTOM
  call draw_white_hline

  mov ax,RED
  mov es,ax
  call draw_white_vlines
  mov ax,GREEN
  mov es,ax
  call draw_white_vlines
  ret

; AL is een y-coordinaat. Schrijf een volledige 640-pixel witte lijn.
draw_white_hline:
  push ax
  push bx
  push cx
  push di
  push bp
  push es

  xor ah,ah
  mov bx,ax
  and bx,3
  shr ax,1
  shr ax,1
  mov di,ax
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1                    ; blok * 256
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1                    ; blok * 64
  add di,ax
  add di,bx
  mov bp,di

  mov ax,RED
  mov es,ax
  call draw_hline_in_plane
  mov ax,GREEN
  mov es,ax
  call draw_hline_in_plane
  mov ax,BLUE
  mov es,ax
  call draw_hline_in_plane

  pop es
  pop bp
  pop di
  pop cx
  pop bx
  pop ax
  ret

; ES is één kleurplane, BP is de Sanyo-offset van de eerste byte.
draw_hline_in_plane:
  mov di,bp
  mov cx,COLS
  mov al,0ffh
.next_byte:
  mov es:[di],al
  add di,4
  loop .next_byte
  ret

; ES is rood of groen. Teken de linker en rechter witte rand van y=10 t/m 198.
draw_white_vlines:
  mov di,(10 / 4) * ROW_BYTES + (FIELD_LEFT / 8) * 4 + (10 & 3)
  mov al,80h
  call draw_vline_in_plane
  mov di,(10 / 4) * ROW_BYTES + (FIELD_RIGHT / 8) * 4 + (10 & 3)
  mov al,01h
  call draw_vline_in_plane
  ret

; ES is één kleurplane, DI de eerste pixel en AL het bitmasker.
draw_vline_in_plane:
  push bx
  push cx
  mov bl,10 & 3
  mov cx,FIELD_BOTTOM - FIELD_TOP - 1
.next_pixel:
  or es:[di],al
  inc bl
  cmp bl,4
  jb .same_block
  xor bl,bl
  add di,ROW_BYTES - 3
  loop .next_pixel
  jmp short .done
.same_block:
  inc di
  loop .next_pixel
.done:
  pop cx
  pop bx
  ret

; Een eenvoudig 8x4 geel balletje. Geel = rood + groen, zonder blauw.
draw_food:
  mov ax,RED
  mov es,ax
  call draw_food_in_red_or_green
  mov ax,GREEN
  mov es,ax
  call draw_food_in_red_or_green
  mov ax,BLUE
  mov es,ax
  mov di,FOOD_OFFSET
  xor ax,ax
  mov es:[di],al
  mov es:[di + 1],al
  mov es:[di + 2],al
  mov es:[di + 3],al
  ret

draw_food_in_red_or_green:
  mov di,FOOD_OFFSET
  mov al,3ch
  mov es:[di],al
  mov al,0ffh
  mov es:[di + 1],al
  mov es:[di + 2],al
  mov al,3ch
  mov es:[di + 3],al
  ret

clear_plane:
  xor ax,ax
  xor di,di
  mov cx,PLANE_BYTES/2
  rep stosw
  ret

%include "footer.asm"
