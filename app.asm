%define SIZE_640x200

%include "header.asm"

FIELD_TOP    equ 9
FIELD_BOTTOM equ 199
FIELD_LEFT   equ 0
FIELD_RIGHT  equ 639

; De slang en het voedsel gebruiken cellen van 8x4 schermpixels. Daardoor
; valt iedere cel precies samen met één kolom in een Sanyo-VRAM-blok.
SNAKE_CELLS       equ 128
SNAKE_INITIAL_LEN equ 8
SNAKE_START       equ (100 / 4) * ROW_BYTES + (200 / 8) * 4
FOOD_INITIAL      equ (100 / 4) * ROW_BYTES + (304 / 8) * 4
GROWTH_PER_FOOD   equ 4
MOVE_DELAY        equ 35000

DIR_RIGHT equ 0
DIR_LEFT  equ 1
DIR_UP    equ 2
DIR_DOWN  equ 3

; De MBC-555 heeft een seriële toetsenbord-UART op deze fysieke I/O-poorten.
KBD_DATA    equ 38h
KBD_CONTROL equ 3ah
KBD_RX_READY equ 02h

setup:
  push cs
  pop ds
  call init_keyboard
  call reset_game

game_loop:
  call read_keyboard
  call move_snake
  jnc .keep_playing
  call reset_game
.keep_playing:
  mov cx,MOVE_DELAY
.delay:
  loop .delay
  jmp game_loop

; Zet de 8251 in asynchrone 8N?E2 ontvangst op 1.230 baud. De Sanyo-ROM
; vertaalt deze ASCII-toetsen normaal naar XT-codes; de game leest ze direct.
init_keyboard:
  mov al,40h                 ; interne reset: volgende byte is de mode
  out KBD_CONTROL,al
  mov al,0bfh                ; 8 bit, even parity, 2 stopbits, klok /64
  out KBD_CONTROL,al
  mov al,14h                 ; receive enable + error reset
  out KBD_CONTROL,al
  ret

; Lees hoogstens één getypte toets. Zowel WASD als het cijferblok werkt.
; Een tegengestelde richting wordt genegeerd.
read_keyboard:
  in al,KBD_CONTROL
  test al,KBD_RX_READY
  jz .done
  in al,KBD_DATA
  and al,5fh                 ; ASCII naar hoofdletter
  cmp al,'W'
  je .up
  cmp al,'8'
  je .up
  cmp al,'S'
  je .down
  cmp al,'5'
  je .down
  cmp al,'A'
  je .left
  cmp al,'4'
  je .left
  cmp al,'D'
  je .right
  cmp al,'6'
  jne .done
.right:
  cmp byte [snake_direction],DIR_LEFT
  je .done
  mov byte [snake_direction],DIR_RIGHT
  ret
.left:
  cmp byte [snake_direction],DIR_RIGHT
  je .done
  mov byte [snake_direction],DIR_LEFT
  ret
.up:
  cmp byte [snake_direction],DIR_DOWN
  je .done
  mov byte [snake_direction],DIR_UP
  ret
.down:
  cmp byte [snake_direction],DIR_UP
  je .done
  mov byte [snake_direction],DIR_DOWN
.done:
  ret

reset_game:
  call clear_screen
  call draw_playfield
  mov word [snake_head_index],0
  mov word [snake_length],SNAKE_INITIAL_LEN
  mov word [growth_remaining],0
  mov byte [snake_direction],DIR_RIGHT

  mov di,snake_positions
  mov ax,SNAKE_START
  mov cx,SNAKE_INITIAL_LEN
.initial_cell:
  mov [di],ax
  push ax
  call draw_white_cell
  pop ax
  sub ax,4
  add di,2
  loop .initial_cell
  mov word [food_offset],FOOD_INITIAL
  call draw_food
  ret

; CF=1 wanneer de slang de rand of haar lichaam raakt.
move_snake:
  mov bx,[snake_head_index]
  shl bx,1
  mov ax,[snake_positions + bx]
  cmp byte [snake_direction],DIR_RIGHT
  jne .not_right
  add ax,4
  jmp short .new_head
.not_right:
  cmp byte [snake_direction],DIR_LEFT
  jne .not_left
  sub ax,4
  jmp short .new_head
.not_left:
  cmp byte [snake_direction],DIR_UP
  jne .down
  sub ax,ROW_BYTES
  jmp short .new_head
.down:
  add ax,ROW_BYTES
.new_head:
  cmp ax,[food_offset]
  je .eat_food

  ; De rode plane is alleen nul op de blauwe achtergrond. Kader en lichaam
  ; zijn er beide wit en veroorzaken dus een botsing.
  push ax
  mov di,ax
  mov bx,RED
  mov es,bx
  cmp byte [es:di],0
  pop ax
  jne .crashed
  jmp short .insert_head
.eat_food:
  add word [growth_remaining],GROWTH_PER_FOOD
.insert_head:
  mov bx,[snake_head_index]
  or bx,bx
  jnz .decrement_head
  mov bx,SNAKE_CELLS
.decrement_head:
  dec bx
  mov [snake_head_index],bx
  shl bx,1
  mov [snake_positions + bx],ax
  call draw_white_cell

  cmp word [growth_remaining],0
  je .erase_tail
  dec word [growth_remaining]
  inc word [snake_length]
  cmp ax,[food_offset]
  jne .ok
  call place_food
  jmp short .ok

.erase_tail:
  ; Na het invoegen staat de oude staart op head_index + lengte.
  mov bx,[snake_head_index]
  add bx,[snake_length]
  cmp bx,SNAKE_CELLS
  jb .tail_index_ok
  sub bx,SNAKE_CELLS
.tail_index_ok:
  shl bx,1
  mov ax,[snake_positions + bx]
  call clear_cell
.ok:
  clc
  ret
.crashed:
  stc
  ret

; Kies een lege cel binnen het kader met een kleine 16-bits LFSR.
place_food:
.try_again:
  mov ax,[random_seed]
  shl ax,1
  jnc .no_tap
  xor ax,0b400h
.no_tap:
  mov [random_seed],ax

  ; Kolom 1..78 (x=8..624), uit de lage zeven bits.
  mov bx,ax
  and bx,007fh
  cmp bx,78
  jb .column_ok
  sub bx,78
.column_ok:
  inc bx
  shl bx,1
  shl bx,1
  mov di,bx

  ; Rij 3..48 (y=12..192), uit de hoge zes bits.
  mov cl,8
  shr ax,cl
  and ax,003fh
  cmp ax,46
  jb .row_ok
  sub ax,46
.row_ok:
  add ax,3
  mov bx,ax
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1
  shl ax,1                    ; rij * 256
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1                    ; rij * 64
  add di,ax
  add di,bx

  mov bx,RED
  mov es,bx
  cmp byte [es:di],0
  jne .try_again
  mov [food_offset],di
  call draw_food
  ret

clear_screen:
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
  ret

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

draw_hline_in_plane:
  mov di,bp
  mov cx,COLS
  mov al,0ffh
.next_byte:
  mov es:[di],al
  add di,4
  loop .next_byte
  ret

draw_white_vlines:
  mov di,(10 / 4) * ROW_BYTES + (FIELD_LEFT / 8) * 4 + (10 & 3)
  mov al,80h
  call draw_vline_in_plane
  mov di,(10 / 4) * ROW_BYTES + (FIELD_RIGHT / 8) * 4 + (10 & 3)
  mov al,01h
  call draw_vline_in_plane
  ret

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

; AX is een Sanyo-VRAM-offset van een 8x4 cel.
draw_white_cell:
  push ax
  push di
  push es
  mov di,ax
  mov ax,RED
  mov es,ax
  call fill_cell_in_plane
  mov ax,GREEN
  mov es,ax
  call fill_cell_in_plane
  mov ax,BLUE
  mov es,ax
  call fill_cell_in_plane
  pop es
  pop di
  pop ax
  ret

fill_cell_in_plane:
  mov al,0ffh
  mov es:[di],al
  mov es:[di + 1],al
  mov es:[di + 2],al
  mov es:[di + 3],al
  ret

; AX is een celoffset; maak hem opnieuw blauw.
clear_cell:
  push ax
  push di
  push es
  mov di,ax
  mov ax,RED
  mov es,ax
  call clear_cell_in_plane
  mov ax,GREEN
  mov es,ax
  call clear_cell_in_plane
  mov ax,BLUE
  mov es,ax
  call fill_cell_in_plane
  pop es
  pop di
  pop ax
  ret

clear_cell_in_plane:
  xor al,al
  mov es:[di],al
  mov es:[di + 1],al
  mov es:[di + 2],al
  mov es:[di + 3],al
  ret

; Geel = rood + groen, zonder blauw. FOOD_OFFSET is 4-scanline-uitgelijnd.
draw_food:
  mov di,[food_offset]
  mov ax,RED
  mov es,ax
  call draw_food_in_red_or_green
  mov ax,GREEN
  mov es,ax
  call draw_food_in_red_or_green
  mov ax,BLUE
  mov es,ax
  xor ax,ax
  mov es:[di],al
  mov es:[di + 1],al
  mov es:[di + 2],al
  mov es:[di + 3],al
  ret

draw_food_in_red_or_green:
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

snake_direction:  db DIR_RIGHT
snake_head_index: dw 0
snake_length:     dw SNAKE_INITIAL_LEN
growth_remaining: dw 0
food_offset:      dw FOOD_INITIAL
random_seed:      dw 0ace1h
snake_positions:  times SNAKE_CELLS dw 0

%include "footer.asm"
