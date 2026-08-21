%define SIZE_640x200

%include "header.asm"

FIELD_TOP    equ 9
FIELD_BOTTOM equ 199
FIELD_LEFT   equ 0
FIELD_RIGHT  equ 639

MENU_BYTES  equ 336 / 8
MENU_ROWS   equ 116 / 4
MENU_PLANE  equ MENU_BYTES * 116
MENU_OFFSET equ (40 / 4) * ROW_BYTES + ((640 - 336) / 16) * 4

; Eén slangsegment is 2x2 schermpixels: één oorspronkelijke pixel met de
; verticale verdubbeling die bij de 1:2-pixelverhouding past.
SNAKE_CELLS       equ 128
SNAKE_INITIAL_LEN equ 8
SNAKE_START       equ (50 << 9) + 100 ; y/2=50, x/2=100
FOOD_INITIAL      equ (50 << 9) + 120 ; y/2=50, x/2=120
GROWTH_PER_FOOD   equ 4
MOVE_DELAY        equ 22000

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
  jmp menu_screen

menu_screen:
  call show_menu
menu_loop:
  in al,KBD_CONTROL
  test al,KBD_RX_READY
  jz menu_loop
  in al,KBD_DATA
  cmp al,' '
  je start_game
  and al,5fh
  cmp al,'P'
  jne menu_loop
start_game:
  call reset_game

game_loop:
  call read_keyboard
  call move_snake
  jnc .keep_playing
  jmp menu_screen
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

; Teken het bestaande Sanyo-menu opnieuw als start- en game-overscherm.
show_menu:
  call clear_screen
  mov si,menu_pic
  mov ax,BLUE
  mov es,ax
  call copy_menu_plane
  mov ax,GREEN
  mov es,ax
  call copy_menu_plane
  mov ax,RED
  mov es,ax
  call copy_menu_plane
  ret

; Zet een lineaire 336x116-plane om naar Sanyo's vier-scanline-indeling.
copy_menu_plane:
  mov di,MENU_OFFSET
  mov bp,MENU_ROWS
.row:
  mov bx,si
  mov cx,MENU_BYTES
.column:
  mov al,[bx]
  mov es:[di],al
  mov al,[bx + MENU_BYTES]
  mov es:[di + 1],al
  mov al,[bx + MENU_BYTES * 2]
  mov es:[di + 2],al
  mov al,[bx + MENU_BYTES * 3]
  mov es:[di + 3],al
  inc bx
  add di,4
  loop .column
  add di,ROW_BYTES - MENU_BYTES * 4
  add si,MENU_BYTES * 4
  dec bp
  jnz .row
  ret

; Lees hoogstens één getypte toets. Naast WASD werken de vier fysieke
; cursorpijlen op het Sanyo-cijferblok: 8 omhoog, 4 links, 5 omlaag, 6 rechts.
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
  call draw_white_dot
  pop ax
  dec ax
  add di,2
  loop .initial_cell
  mov word [food_position],FOOD_INITIAL
  call draw_food
  ret

; CF=1 wanneer de slang de rand of haar lichaam raakt.
move_snake:
  mov bx,[snake_head_index]
  shl bx,1
  mov ax,[snake_positions + bx]
  cmp byte [snake_direction],DIR_RIGHT
  jne .not_right
  inc ax
  jmp short .new_head
.not_right:
  cmp byte [snake_direction],DIR_LEFT
  jne .not_left
  dec ax
  jmp short .new_head
.not_left:
  cmp byte [snake_direction],DIR_UP
  jne .down
  sub ax,512
  jmp short .new_head
.down:
  add ax,512
.new_head:
  cmp ax,[food_position]
  je .eat_food

  ; De rode plane is alleen nul op de blauwe achtergrond. Kader en lichaam
  ; zijn er beide wit en veroorzaken dus een botsing.
  push ax
  call position_to_vram
  mov bx,RED
  mov es,bx
  test byte [es:di],al
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
  call draw_white_dot

  cmp word [growth_remaining],0
  je .erase_tail
  dec word [growth_remaining]
  inc word [snake_length]
  cmp ax,[food_position]
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
  call clear_dot
.ok:
  clc
  ret
.crashed:
  stc
  ret

; Kies een lege 2x2-pixelpositie binnen het kader met een kleine 16-bits LFSR.
place_food:
.try_again:
  mov ax,[random_seed]
  shl ax,1
  jnc .no_tap
  xor ax,0b400h
.no_tap:
  mov [random_seed],ax

  ; x/2 = 1..318, uit de lage negen bits.
  mov bx,ax
  and bx,01ffh
  cmp bx,318
  jb .column_ok
  sub bx,318
.column_ok:
  inc bx

  ; y/2 = 5..98, uit de hoge zeven bits.
  mov cl,8
  shr ax,cl
  and ax,007fh
  cmp ax,94
  jb .row_ok
  sub ax,94
.row_ok:
  add ax,5
  mov cl,9
  shl ax,cl
  add ax,bx

  push ax
  call position_to_vram
  mov bx,RED
  mov es,bx
  test byte [es:di],al
  pop ax
  jne .try_again
  mov [food_position],ax
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

; AX is een gepakte positie: x/2 in bits 0..8, y/2 in bits 9..15.
; Retourneert DI als VRAM-offset en AL als mask voor twee horizontale pixels.
position_to_vram:
  mov dx,ax
  mov bp,dx
  and bp,3
  mov bx,dx
  and bx,01ffh
  shr bx,1
  shr bx,1
  shl bx,1
  shl bx,1                    ; (x/2)/4 * 4
  mov di,bx
  mov dx,ax
  mov cl,9
  shr dx,cl                    ; y/2
  mov cx,dx
  and dx,1
  shl dx,1                     ; scanline 0 of 2 binnen het blok
  shr cx,1                     ; vier-scanlineblok
  mov si,cx
  shl cx,1
  shl cx,1
  shl cx,1
  shl cx,1
  shl cx,1
  shl cx,1
  shl cx,1
  shl cx,1                     ; blok * 256
  shl si,1
  shl si,1
  shl si,1
  shl si,1
  shl si,1
  shl si,1                     ; blok * 64
  add di,cx
  add di,si
  add di,dx
  mov al,[cs:dot_masks + bp]
  ret

; AX is een slangpositie. De witte 2x2-pixelstip overschrijft alleen haar bits.
draw_white_dot:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push es
  call position_to_vram
  mov ah,al
  mov bx,RED
  mov es,bx
  or es:[di],al
  or es:[di + 1],al
  mov bx,GREEN
  mov es,bx
  or es:[di],al
  or es:[di + 1],al
  mov bx,BLUE
  mov es,bx
  or es:[di],al
  or es:[di + 1],al
  pop es
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; AX is een slangpositie; herstel uitsluitend de blauwe achtergrond eronder.
clear_dot:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push es
  call position_to_vram
  mov ah,al
  not ah
  mov bx,RED
  mov es,bx
  and es:[di],ah
  and es:[di + 1],ah
  mov bx,GREEN
  mov es,bx
  and es:[di],ah
  and es:[di + 1],ah
  mov bx,BLUE
  mov es,bx
  or es:[di],al
  or es:[di + 1],al
  pop es
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Geel = rood + groen zonder blauw, maar alleen binnen het stipmasker.
; Daardoor blijft de blauwe achtergrond rondom de stip transparant zichtbaar.
draw_food:
  mov ax,[food_position]
  call position_to_vram
  mov ah,al
  mov bx,RED
  mov es,bx
  or es:[di],al
  or es:[di + 1],al
  mov bx,GREEN
  mov es,bx
  or es:[di],al
  or es:[di + 1],al
  not ah
  mov bx,BLUE
  mov es,bx
  and es:[di],ah
  and es:[di + 1],ah
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
food_position:    dw FOOD_INITIAL
random_seed:      dw 0ace1h
snake_positions:  times SNAKE_CELLS dw 0
dot_masks:        db 0c0h,30h,0ch,03h

; Drie conventionele scanline-planes in B, G, R-volgorde.
menu_pic:
  incbin "assets/sanyo/menu-ok-336x116.pic"

%include "footer.asm"
