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
SCORE_X     equ WIDTH - 8 - (3 * 16)
SCORE_OFFSET equ (SCORE_X / 8) * 4

; Eén slangsegment is 2x1 schermpixels: horizontaal verdubbeld, maar één
; scanline hoog zoals het oorspronkelijke spel.
SNAKE_CELLS       equ 128
SNAKE_MAX_LEN     equ SNAKE_CELLS - 1
SNAKE_INITIAL_LEN equ 14
SNAKE_START       equ ((100 / 4) * ROW_BYTES + (200 / 8) * 4) << 2
FOOD_INITIAL      equ (100 / 4) * ROW_BYTES + (304 / 8) * 4
GROWTH_PER_FOOD   equ 20
MOVE_DELAY        equ 4000
BOOST_EXTRA_STEPS equ 3
FOOD_SOUND_TONE equ 03eh
FOOD_SOUND_DURATION equ 10
CRASH_TONE_START equ 60h
CRASH_TONE_STEP  equ 07h
CRASH_TONE_STEPS equ 40
CRASH_TONE_DURATION equ 15

DIR_RIGHT equ 0
DIR_LEFT  equ 1
DIR_UP    equ 2
DIR_DOWN  equ 3

; De MBC-555 heeft een seriële toetsenbord-UART op deze fysieke I/O-poorten.
KBD_DATA    equ 38h
KBD_CONTROL equ 3ah
KBD_RX_READY equ 02h
KEY_LEFT    equ 1ch
KEY_RIGHT   equ 1dh
KEY_UP      equ 1eh
KEY_DOWN    equ 1fh

setup:
  push cs
  pop ds
  call init_menu_keyboard
  jmp menu_screen

menu_screen:
  call init_menu_keyboard
  call show_menu
menu_loop:
  call check_keys
  jz menu_loop
  cmp al,' '
  je start_game
  and al,5fh
  cmp al,'P'
  jne menu_loop
start_game:
  call init_game_keyboard
  call reset_game

game_loop:
  call read_keyboard
  call move_snake
  jc .crashed
 .boost:
  cmp byte [boost_moves],0
  je .keep_playing
  dec byte [boost_moves]
  call move_snake
  jnc .boost
.crashed:
  call play_crash_sound
  jmp menu_screen
.keep_playing:
  mov cx,MOVE_DELAY
.delay:
  loop .delay
  jmp game_loop

; De menu-UART levert ASCII voor P en spatie.
init_menu_keyboard:
  mov al,40h
  out KBD_CONTROL,al
  mov al,0bfh                ; 8 bit, even parity, 2 stopbits, klok /64
  out KBD_CONTROL,al
  mov al,14h                 ; receive enable + error reset
  out KBD_CONTROL,al
  ret

; De spel-UART-configuratie levert de fysieke Sanyo-cursortoetsen als
; ASCII-controlcodes 1Ch..1Fh.
init_game_keyboard:
  xor al,al
  out KBD_CONTROL,al
  out KBD_CONTROL,al
  mov al,0ffh
  out KBD_CONTROL,al
  out KBD_CONTROL,al
  mov al,37h
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
  call check_keys
  jz .done
  cmp al,KEY_UP
  je .up
  cmp al,KEY_DOWN
  je .down
  cmp al,KEY_LEFT
  je .left
  cmp al,KEY_RIGHT
  je .right
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
  cmp byte [snake_direction],DIR_RIGHT
  je .boost
  mov byte [snake_direction],DIR_RIGHT
  ret
.left:
  cmp byte [snake_direction],DIR_RIGHT
  je .done
  cmp byte [snake_direction],DIR_LEFT
  je .boost
  mov byte [snake_direction],DIR_LEFT
  ret
.up:
  cmp byte [snake_direction],DIR_DOWN
  je .done
  cmp byte [snake_direction],DIR_UP
  je .boost
  mov byte [snake_direction],DIR_UP
  ret
.down:
  cmp byte [snake_direction],DIR_UP
  je .done
  cmp byte [snake_direction],DIR_DOWN
  je .boost
  mov byte [snake_direction],DIR_DOWN
.boost:
  mov byte [boost_moves],BOOST_EXTRA_STEPS
.done:
  ret

; Retourneert Z=0 wanneer AL een nieuwe toetscode bevat.
check_keys:
  in al,KBD_CONTROL
  mov ah,al
  and al,00001000b
  mov [cs:key.ctrl],al
  test ah,KBD_RX_READY
  jz .return
  in al,KBD_DATA
  mov [cs:key.code],al
  mov al,37h
  out KBD_CONTROL,al
  or al,1
  mov ax,[cs:key]
.return:
  ret

reset_game:
  call clear_screen
  call clear_top_margin
  call draw_playfield
  mov word [snake_head_index],0
  mov word [snake_length],SNAKE_INITIAL_LEN
  mov word [growth_remaining],0
  mov word [score],0
  mov byte [snake_direction],DIR_RIGHT
  mov byte [boost_moves],0
  call draw_score

  mov di,snake_positions
  mov ax,SNAKE_START
  mov cx,SNAKE_INITIAL_LEN
.initial_cell:
  mov [di],ax
  push ax
  call draw_white_dot
  pop ax
  call step_left
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
  call step_right
  jmp short .new_head
.not_right:
  cmp byte [snake_direction],DIR_LEFT
  jne .not_left
  call step_left
  jmp short .new_head
.not_left:
  cmp byte [snake_direction],DIR_UP
  jne .down
  call step_up
  jmp short .new_head
.down:
  call step_down
.new_head:
  call is_outside_playfield
  jc .crashed
  mov byte [ate_food],0
  call is_food_at_position
  jc .eat_food

  ; De rode plane is alleen nul op de blauwe achtergrond. Kader en lichaam
  ; zijn er beide wit en veroorzaken dus een botsing.
  push ax
  call packed_to_vram
  mov bx,RED
  mov es,bx
  test byte [es:di],al
  pop ax
  jne .crashed
  jmp short .insert_head
.eat_food:
  call clear_food
  call play_food_sound
  inc word [score]
  cmp word [score],1000
  jb .score_in_range
  mov word [score],0
.score_in_range:
  call draw_score
  add word [growth_remaining],GROWTH_PER_FOOD
  mov byte [ate_food],1
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
  cmp word [snake_length],SNAKE_MAX_LEN
  jae .growth_limit
  dec word [growth_remaining]
  inc word [snake_length]
  jmp short .after_tail

.growth_limit:
  ; Houd één vrije positie in de ringbuffer. Bij de limiet beweegt de
  ; staart door en stapelt resterende groei niet verder op.
  mov word [growth_remaining],0

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
.after_tail:
  cmp byte [ate_food],0
  je .ok
  call place_food
.ok:
  clc
  ret
.crashed:
  stc
  ret

; Kies een lege byte-uitgelijnde 8x4-positie binnen het kader met een LFSR.
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
  shl ax,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
  shl bx,1
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

; Maak de bovenste acht scanlines zwart; deze horen niet bij het speelveld.
clear_top_margin:
  mov ax,RED
  mov es,ax
  call clear_top_margin_plane
  mov ax,GREEN
  mov es,ax
  call clear_top_margin_plane
  mov ax,BLUE
  mov es,ax
  call clear_top_margin_plane
  ret

clear_top_margin_plane:
  xor ax,ax
  xor di,di
  mov cx,ROW_BYTES
  rep stosw
  ret

; Teken een blauw-cyaan schaakpatroon. De blauwe pixels zijn de bestaande
; achtergrond; alleen de groene plane hoeft voor de cyaan pixels gezet te zijn.
draw_playfield:
  mov al,FIELD_TOP
  call draw_dotted_hline
  mov al,FIELD_BOTTOM
  call draw_dotted_hline
  mov ax,GREEN
  mov es,ax
  call draw_dotted_vlines
  ret

; AL is een y-coordinaat. Blauw, cyaan, blauw, cyaan over een hele scanline.
draw_dotted_hline:
  push ax
  push bx
  push cx
  push di
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
  shl ax,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  shl di,1
  add di,ax
  add di,bx
  mov ax,GREEN
  mov es,ax
  mov cx,COLS
  mov al,55h                 ; x=0 blauw, x=1 cyaan
.next_byte:
  mov es:[di],al
  add di,4
  loop .next_byte
  pop es
  pop di
  pop cx
  pop bx
  pop ax
  ret

; Verticale rand: twee pixels. Per scanline wisselt blauw/cyaan om.
draw_dotted_vlines:
  mov di,(10 / 4) * ROW_BYTES + (FIELD_LEFT / 8) * 4 + (10 & 3)
  mov al,40h                 ; links: blauw, cyaan
  mov ah,80h                 ; daaronder: cyaan, blauw
  call draw_dotted_vline
  mov di,(10 / 4) * ROW_BYTES + (638 / 8) * 4 + (10 & 3)
  mov al,01h                 ; rechts: blauw, cyaan
  mov ah,02h                 ; daaronder: cyaan, blauw
  call draw_dotted_vline
  ret

; ES is de groene plane, DI de eerste scanline, AL/AH de alternerende maskers.
draw_dotted_vline:
  push bx
  push cx
  mov bl,10 & 3
  mov cx,FIELD_BOTTOM - FIELD_TOP - 1
.next_pixel:
  or es:[di],al
  xchg al,ah
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

; Posities bevatten de Sanyo-VRAM-offset in bits 2..15 en de 2-pixel-maskindex
; in bits 0..1. Dit ondersteunt verticale beweging per enkele scanline.
packed_to_vram:
  mov dx,ax
  mov bx,dx
  and bx,3
  shr dx,1
  shr dx,1
  mov di,dx
  mov al,[cs:dot_masks + bx]
  ret

; CF=1 als de 2x1-kop een van de vier spelveldranden zou raken. Deze
; controle is los van de zichtbare blauw-cyaan rand, waarin blauwe pixels
; dezelfde kleur hebben als de achtergrond.
is_outside_playfield:
  push ax
  push bx
  push cx
  push dx
  push si
  mov cx,ax
  and cx,3                    ; horizontale 2-pixelmaskindex
  call packed_to_vram
  mov ax,di
  xor dx,dx
  mov bx,ROW_BYTES
  div bx                       ; AX=vier-scanlineblok, DX=blokrest
  mov si,dx
  and si,3                     ; alleen scanline 0..3, niet de x-positie

  cmp ax,2                    ; y=0..7 is de zwarte bovenmarge
  jb .outside
  cmp ax,49
  ja .outside
  cmp ax,2
  jne .not_top_block
  cmp si,2                    ; y=8/9 valt op of boven de bovenrand
  jb .outside
.not_top_block:
  cmp ax,49
  jne .check_x
  cmp si,3                    ; y=199 is de onderrand
  jae .outside
.check_x:
  shr dx,1
  shr dx,1                    ; bytekolom 0..79
  or dx,dx
  jnz .not_left
  or cx,cx                    ; x=0/1 is de linker rand
  jz .outside
.not_left:
  cmp dx,COLS - 1
  jne .inside
  cmp cx,3                    ; x=638/639 is de rechter rand
  je .outside
.inside:
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  clc
  ret
.outside:
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  stc
  ret

step_right:
  mov bx,ax
  and bx,3
  cmp bx,3
  jne .same_byte
  and ax,0fffch
  add ax,16                    ; volgende videobytekolom
  ret
.same_byte:
  inc ax
  ret

step_left:
  mov bx,ax
  and bx,3
  or bx,bx
  jnz .same_byte
  and ax,0fffch
  sub ax,16                    ; vorige videobytekolom
  add ax,3
  ret
.same_byte:
  dec ax
  ret

step_up:
  mov bx,ax
  shr bx,1
  shr bx,1
  and bx,3
  or bx,bx
  jnz .same_block
  sub ax,1268                  ; offset -317 over de blokgrens
  ret
.same_block:
  sub ax,4                     ; offset -1
  ret

step_down:
  mov bx,ax
  shr bx,1
  shr bx,1
  and bx,3
  cmp bx,3
  jne .same_block
  add ax,1268                  ; offset +317 over de blokgrens
  ret
.same_block:
  add ax,4                     ; offset +1
  ret

; CF=1 als de 2x1-kop een gele pixel van het 8x4-balletje raakt.
is_food_at_position:
  push ax
  call packed_to_vram
  mov bx,di
  sub bx,[food_offset]
  jb .not_food
  cmp bx,3
  ja .not_food
  mov ah,[food_masks + bx]
  test al,ah
  jz .not_food
  pop ax
  stc
  ret
.not_food:
  pop ax
  clc
  ret

; AX is een slangpositie. De witte 2x1-pixelstip overschrijft alleen haar bits.
draw_white_dot:
  push ax
  push bx
  push cx
  push dx
  push si
  push di
  push es
  call packed_to_vram
  mov bx,RED
  mov es,bx
  or es:[di],al
  mov bx,GREEN
  mov es,bx
  or es:[di],al
  mov bx,BLUE
  mov es,bx
  or es:[di],al
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
  call packed_to_vram
  mov ah,al
  not ah
  mov bx,RED
  mov es,bx
  and es:[di],ah
  mov bx,GREEN
  mov es,bx
  and es:[di],ah
  mov bx,BLUE
  mov es,bx
  or es:[di],al
  pop es
  pop di
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Geel = rood + groen zonder blauw. Alleen de gele bits worden aangeraakt,
; zodat de vier hoekpixels van het 8x4-balletje blauw blijven.
draw_food:
  mov di,[food_offset]
  mov bx,RED
  mov es,bx
  call draw_food_in_red_or_green
  mov bx,GREEN
  mov es,bx
  call draw_food_in_red_or_green
  mov bx,BLUE
  mov es,bx
  and byte es:[di],0c3h
  and byte es:[di + 1],00h
  and byte es:[di + 2],00h
  and byte es:[di + 3],0c3h
  ret

draw_food_in_red_or_green:
  or byte es:[di],3ch
  or byte es:[di + 1],0ffh
  or byte es:[di + 2],0ffh
  or byte es:[di + 3],3ch
  ret

; Wis uitsluitend de gele pixels van het vorige balletje en herstel blauw.
clear_food:
  mov di,[food_offset]
  mov bx,RED
  mov es,bx
  and byte es:[di],0c3h
  and byte es:[di + 1],00h
  and byte es:[di + 2],00h
  and byte es:[di + 3],0c3h
  mov bx,GREEN
  mov es,bx
  and byte es:[di],0c3h
  and byte es:[di + 1],00h
  and byte es:[di + 2],00h
  and byte es:[di + 3],0c3h
  mov bx,BLUE
  mov es,bx
  or byte es:[di],3ch
  or byte es:[di + 1],0ffh
  or byte es:[di + 2],0ffh
  or byte es:[di + 3],3ch
  ret

; De MBC-55x leidt de USART-break-bit naar de speaker. Behoud alle
; spelregisters, want deze routine draait precies tussen kopberekening en
; het invoegen van de nieuwe kop in de slang.
play_food_sound:
  push ax
  push bx
  push cx
  push dx
  mov bx,FOOD_SOUND_TONE
  mov dx,FOOD_SOUND_DURATION
  call play
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; Een oplopende periode betekent een dalende toon: hoog naar laag.
play_crash_sound:
  push ax
  push bx
  push cx
  push dx
  push si
  mov bx,CRASH_TONE_START
  mov si,CRASH_TONE_STEPS
.next_note:
  mov dx,CRASH_TONE_DURATION
  call play
  add bx,CRASH_TONE_STEP
  dec si
  jnz .next_note
  pop si
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; BX=toonfrequentie, DX=duur.
play:
  mov cx,bx
  mov ax,35h
.toggle_break:
  xor al,8
  out KBD_CONTROL,al
.delay:
  dec ah
  jnz .continue
  dec dx
  jz .done
.continue:
  loop .delay
  mov cx,bx
  jmp .toggle_break
.done:
  ret

; Teken de score als drie witte ROM-glyphs in de zwarte bovenmarge. Elke
; bronpixel wordt met stretch_bits horizontaal verdubbeld, dus 8x8 wordt 16x8.
draw_score:
  push ax
  push bx
  push dx
  push di
  call clear_top_margin
  mov ax,[score]
  xor dx,dx
  mov bx,100
  div bx
  push dx
  add al,'0'
  mov di,SCORE_OFFSET          ; rechts uitgelijnd, met 8 pixels marge
  call draw_double_char
  pop ax
  xor dx,dx
  mov bx,10
  div bx
  push dx
  add al,'0'
  add di,8                    ; volgend dubbelbreed teken
  call draw_double_char
  pop dx
  add dl,'0'
  mov al,dl
  add di,8                    ; volgend dubbelbreed teken
  call draw_double_char
  pop di
  pop dx
  pop bx
  pop ax
  ret

; AL=ASCII-teken, DI=Sanyo-VRAM-offset van de eerste glyph-byte op y=0.
draw_double_char:
  push ax
  push bx
  push cx
  push dx
  push di
  push si
  push bp
  push es
  push ds
  xor ah,ah
  mov si,ax
  shl si,1
  shl si,1
  shl si,1                    ; acht bytes per 8x8-glyph
  add si,1000h                ; font op FE00:1000
  mov ax,ROM_SEG
  mov ds,ax
  mov bp,8
  xor dh,dh
.scanline:
  mov al,[si]
  call stretch_bits
  mov bx,RED
  mov es,bx
  mov es:[di],ah
  mov es:[di + 4],al
  mov bx,GREEN
  mov es,bx
  mov es:[di],ah
  mov es:[di + 4],al
  mov bx,BLUE
  mov es,bx
  mov es:[di],ah
  mov es:[di + 4],al
  inc si
  inc di
  inc dh
  cmp dh,4
  jb .next_scanline
  xor dh,dh
  add di,ROW_BYTES - 4
.next_scanline:
  dec bp
  jnz .scanline
  pop ds
  pop es
  pop bp
  pop si
  pop di
  pop dx
  pop cx
  pop bx
  pop ax
  ret

; AL=abcdefgh wordt AX=aabbccddeeffgghh.
stretch_bits:
  push cx
  push bx
  mov bl,al
  xor ax,ax
  mov cx,8
.bit:
  shl ax,1
  shl ax,1
  shl bl,1
  jnc .zero
  or ax,3
.zero:
  loop .bit
  pop bx
  pop cx
  ret

clear_plane:
  xor ax,ax
  xor di,di
  mov cx,PLANE_BYTES/2
  rep stosw
  ret

snake_direction:  db DIR_RIGHT
boost_moves:      db 0
ate_food:         db 0
snake_head_index: dw 0
snake_length:     dw SNAKE_INITIAL_LEN
growth_remaining: dw 0
score:            dw 0
food_offset:      dw FOOD_INITIAL
random_seed:      dw 0ace1h
snake_positions:  times SNAKE_CELLS dw 0
dot_masks:        db 0c0h,30h,0ch,03h
food_masks:       db 3ch,0ffh,0ffh,3ch
key:
  .code db 0
  .ctrl db 0

; Drie conventionele scanline-planes in B, G, R-volgorde.
menu_pic:
  incbin "assets/sanyo/menu-ok-336x116.pic"

%include "footer.asm"
