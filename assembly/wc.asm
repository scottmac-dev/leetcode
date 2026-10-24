; wc unix utility in assembly
; nasm -felf64 wc.asm && ld wc.o -o wc
; ./wc wc.asm
; echo hi | ./wc
; ./wc nope; echo $?     # should print 1

SYS_read equ 0    ; read syscall num
SYS_write equ 1   ; write syscall num
SYS_open equ 2    ; open syscall num 
SYS_close equ 3   ; close syscall num 
SYS_exit equ 60   ; exit syscall num 
BUF_SIZE equ 4096 ; 4KiB buf alias

section .bss
  buf resb BUF_SIZE ; reserve 4 KiB buffer
  outbuf resb 4352  ; output line: filename + 3 numbers + spaces
  lines resq 1      ; line count, resq 1 = reserve 8 bytes or 1 qword
  words resq 1      ; word count 
  bytes resq 1      ; byte count


section .text
    global _start

; wc_fd(edi = fd) -> eax = 0 on success, 1 on read error
; Results stored in [lines], [words], [bytes] on success.
; Clobbers: rax, rcx, rdx, rsi, rdi, r11 (all caller-saved)
wc_fd:
  ; save callee saved registers
  push rbx
  push r12
  push r13
  push r14
  push r15

  mov ebx, edi    ; rbx = fd, copy first arg into ebx, callee saved, survives syscall

  ; init counters, xor self = 0, using xxxd to onlu utilize 32-bits not whole 64 bit register
  xor r12d, r12d  ; r12 = lines 
  xor r13d, r13d  ; r13 = words 
  xor r14d, r14d  ; r14 = bytes 
  xor r15d, r15d  ; r15 = in_word state, 0 = out, 1 = 1, persits across reads 

; read syscall  
; ssize_t read(int fd, void *buf, size_t count);
.read:
  mov eax, SYS_read   ; read syscall num 0
  mov edi, ebx        ; load fd from ebx into edi
  lea rsi, [rel buf]  ; load dest buffer into rsi, lea = load effective address
  mov edx, BUF_SIZE   ; max buf size 
  syscall             ; execute
  
  ; 3 cases:
  ;   rax = 0 = EOF
  ;   rax < 0 = error 
  ;   rax > 0 = bytes read
  test rax, rax
  jz .done      ; 0 = EOF
  js .error     ; negative = errno

  add r14, rax          ; bytes += n

  ; define mem range containing read data
  lea rsi, [rel buf]    ; rsi = current byte pointer, reset to start
  lea rcx, [rsi + rax]  ; rcx = end ptr (buf + n), calculate end pos from start

; scan over read bytes
.scan:
  movzx eax, byte [rsi] ; c = *p, get byte 
  inc rsi               ; p++

  cmp al, 10        ; check for newline '\n'
  jne .check_space  ; not newline, jump
  inc r12           ; lines++

; handle word read 
.check_space:
  cmp al, ' '
  je .white_space   ; handle white_space
  sub al, 9         ; map '\t'..'\r' 9..13 -> 0..4 to handle as whitespace
  cmp al, 4
  jbe .white_space  ; unsigned 0..4 = white_space, anything else is not

  test r15d, r15d   ; not whitespace, check if in word 
  jnz .next         ; inword, continue

  inc r13           ; new word start, word++
  mov r15d, 1       ; set in word flag
  jmp .next

; handle white space 
.white_space:
  xor r15d, r15d    ; set in word flag = 0

; logic for scan continuation
.next:
  cmp rsi, rcx      ; check end of read buffer, curr = end
  jb .scan          ; more bytes, continue 
  jmp .read         ; chunk done, read next 

; finish main wc logic
.done:
  ; load globals into registers 
  mov [rel lines], r12 
  mov [rel words], r13 
  mov [rel bytes], r14 
  xor eax, eax  ; set ret value 0 (success)
  jmp .out

.error:
  mov eax, 1    ; set ret value 1 (err)

.out:
  ; restore registers in reverse order 
  pop r15 
  pop r14 
  pop r13 
  pop r12 
  pop rbx 
  ret

; utoa = unsigned int to decimal formatted value
; utoa(rax = value, rdi = dest) -> rdi = one past the last digit written
; Clobbers: rax, rcx, rdx, rsi, r8
utoa:
  mov r8, rsp   ; r8 = end of scratch area below rsp 
  mov rsi, r8   ; rsi = write cursor moving downwards 
  mov ecx, 10
.digit:
  xor edx, edx  ; div divides rdx:rax, clear high half 
  div rcx       ; rax = value / 10, rdx = value % 10 
  add dl, '0'   ; remainder as ASCII digit 
  dec rsi
  mov [rsi], dl ; store digits right to left 
  test rax, rax
  jnz .digit    ; do while: 0 emits '0'

  mov rcx, r8   ; 
  sub rcx, rsi  ; rcx = digit amount 
  rep movsb     ; copy rcx bytes from [rsi] to [rdi] and advance both
  ret

; append_str = copy null terminated string
; append_str(rsi = C string, rdi = dest) -> rdi = one past the last byte written
; Clobbers: rax, rsi
append_str:
.loop:
    mov  al, [rsi]
    test al, al
    jz   .done                 ; stop at the NUL terminator (not copied)
    mov  [rdi], al
    inc  rsi
    inc  rdi
    jmp  .loop
.done:
    ret

; format and write one line
; print_counts(rsi = filename, or 0 for none)
; Writes "lines words bytes [filename]\n" to stdout.
; Clobbers: rax, rcx, rdx, rsi, rdi, r8, r11
print_counts:
    push rbx
    mov  rbx, rsi              ; keep filename safe; utoa clobbers rsi

    lea  rdi, [rel outbuf]
    mov  rax, [rel lines]
    call utoa
    mov  byte [rdi], ' '
    inc  rdi
    mov  rax, [rel words]
    call utoa
    mov  byte [rdi], ' '
    inc  rdi
    mov  rax, [rel bytes]
    call utoa

    test rbx, rbx              ; filename given?
    jz   .newline
    mov  byte [rdi], ' '
    inc  rdi
    mov  rsi, rbx
    call append_str

.newline:
    mov  byte [rdi], 10
    inc  rdi

    lea  rsi, [rel outbuf]        ; write(1, out, rdi - out)
    mov  rdx, rdi
    sub  rdx, rsi
    mov  eax, SYS_write
    mov  edi, 1
    syscall

    pop  rbx
    ret

; entrypoint
_start:
    mov  r12, [rsp]            ; r12 = argc
    lea  r13, [rsp+8]          ; r13 = argv
    xor  r14d, r14d            ; r14 = exit status

    cmp  r12, 1
    jg   .files

    xor  edi, edi              ; no args: count stdin
    call wc_fd
    mov  r14d, eax
    test eax, eax
    jnz  .exit
    xor  esi, esi              ; no filename to print
    call print_counts
    jmp  .exit

.files:
    mov  r15d, 1               ; r15 = i
.next_file:
    mov  rdi, [r13 + r15*8]    ; argv[i], in one addressing mode
    mov  eax, SYS_open
    xor  esi, esi              ; O_RDONLY
    xor  edx, edx
    syscall
    test rax, rax
    js   .open_failed
    mov  rbx, rax              ; rbx = fd

    mov  edi, eax
    call wc_fd
    or   r14d, eax             ; status |= result
    test eax, eax
    jnz  .close                ; read error: skip printing
    mov  rsi, [r13 + r15*8]
    call print_counts

.close:
    mov  eax, SYS_close
    mov  rdi, rbx
    syscall
    jmp  .advance

.open_failed:
    mov  r14d, 1
.advance:
    inc  r15
    cmp  r15, r12
    jl   .next_file

.exit:
    mov  edi, r14d
    mov  eax, SYS_exit
    syscall
