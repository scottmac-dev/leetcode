; cat unix utility in assembly
; nasm -felf64 cat.asm && ld cat.o -o cat
; ./cat cat.asm
; echo hi | ./cat
; ./cat nope; echo $?     # should print 1

section .bss
  buf resb 4096 ; reserve 4 KiB buffer

section .text
  global _start

; syscall 3 args
sys3:
  push rbp      ; save callers stack frame pointer
  mov rbp, rsp  ; set this fn stack frame to current stack top
  
  mov qword [rbp-24], rdi ; n syscall number, in rdi, want it in rax
  mov qword [rbp-32], rsi ; a arg 1
  mov qword [rbp-40], rdx ; b arg 2 
  mov qword [rbp-48], rcx ; c arg 3 
  
  mov rax, qword [rbp-24] ; load syscall n -> rax
  mov rdi, qword [rbp-32] ; load arg 1 a -> rdi
  mov rsi, qword [rbp-40] ; load arg 2 b -> rsi
  mov rdx, qword [rbp-48] ; load arg 3 c -> rdx

  syscall ; execute, result in rax

  mov qword [rbp-8], rax  ; ret (variable) = rax, pointless as was already in rax but C code stores in var first
  mov rax, qword [rbp-8]  ; return ret (variable)
  
  pop rbp ; restore caller stack frams  
  ret     ; pop return address and jump to it

; read fd entry point
cat_fd:
  push rbp 
  mov rbp, rsp 
  sub rsp, 40               ; reserve 40 bytes
  mov qword [rbp-40], rdi   ; store fd from rdi

; sys read segment
.L10:
  mov edx, buf        ; arg 3, buffer addr 
  mov rax, [rbp-40]   ; load fd 
  mov ecx, 4096       ; arg 4, count
  mov rsi, rax        ; arg 2, fd into rsi, expected by sys3 
  mov edi, 0          ; arg 1, SYS_read 0

  call sys3

  mov [rbp-16], rax       ; n = result 
  cmp qword [rbp-16], 0   ; n == 0 ? 
  jne .L4                 ; no -> handle error, jump to L4 block 
  mov eax, 0              ; yes -> return 0 
  jmp .L5                 ; jump to L5 block

; err handle segment
.L4:
  cmp qword [rbp-16], 0   
  jns .L6                 ; clear n >= 0, continue to L6
  mov eax, 1              ; n < 0 error, return value 1
  jmp .L5                 ; continue to L5

; while loop entry point
.L6:
  mov qword [rbp-8], 0    ; offset = 0
  jmp .L7                 ; jump to while loop 

; sys write loop segment
.L9:
  mov rax, qword [rbp-16] ; rax = n
  sub rax, qword [rbp-8]  ; rax = n - offset (bytes remaining)
  mov rdx, qword [rbp-8]  ; rdx = offset
  add rdx, buf            ; rdx = buf + offser (where to write from)
  mov rcx, rax            ; arg 4, count = n - offset
  mov esi, 1              ; arg 2 fd = 1 = stdout 
  mov edi, 1              ; arg 1, sys_write call #
  
  call sys3

  mov qword [rbp-24], rax ; w = result = errno or bytes written
  cmp qword [rbp-24], 0   
  jns .L8                 ; w >= 0 continue (success or EOF)
  mov eax, 1              ; w < 0, return 1 (err)
  jmp .L5

; offset += bytes segment 
.L8:
  mov rax, qword [rbp-24]
  add qword [rbp-8], rax

; while loop for sys write condition
.L7:
  mov rax, qword [rbp-8]  ; offset 
  cmp rax, qword [rbp-16] ; cmp to n bytes 
  jl .L9                  ; off < n, continue write body
  jmp .L10                ; off >= n, break to L10 read

; end cat_fd
.L5:
  leave ; tear down stack frame 
  ret   ; return to caller

; main function
; stack frame:
;     [rbp-4]	status	dword
;     [rbp-8]	i	dword
;     [rbp-16]	fd	qword
;     [rbp-20] argc dword
;     [rbp-32]	argv	qword
main:
  push rbp      ; callers bp
  mov rbp, rsp  ; new stack frame 
  sub rsp, 32   ; alloc 32 byte stack frame 
  mov dword [rbp-20], edi ; argc 
  mov qword [rbp-32], rsi ; argv pointer
  cmp dword [rbp-20], 1   ; if (argc < 2)
  jg .L12     ; argc > 1, enter for loop
  mov edi, 0  ; argc == 1, cat_fd(0) stdin
  call cat_fd
  jmp .L13    ; exit

; init status variable 
.L12:
  mov dword [rbp-4], 0  ; status = 0
  mov dword [rbp-8], 1  ; i = 1 (arg iter)
  jmp .L14    ; for loop handler (i < argc)

; main for arg loop body, sys_open and get fd
; argv is char **, array of 8-byte pointers, element i is argv + i*8, ptr arithmetic
.L17:
  mov eax, dword [rbp-8]  ; eax = i
  cdqe                    ; sign extend eax -> rax
  lea rdx, [0+rax*8]      ; rdx = i * 8
  mov rax, qword [rbp-32] ; rax = argv
  add rax, rdx            ; rax = &argv[i]
  mov rax, [rax]          ; rax = argv[i], ptr -> filename dereference
  mov ecx, 0              ; arg 4 = 0
  mov edx, 0              ; arg 3 = 0 (mode)
  mov rsi, rax            ; arg 2 = filename
  mov edi, 2              ; arg 1 = SYS_open (2)  

  call sys3

  mov qword [rbp-16], rax ; fd = resilt
  cmp qword [rbp-16], 0   ; cmp to 0
  jns .L15                ; fd >=0, cat fd block
  mov dword [rbp-4], 1    ; fd < 0, failed, status = 1
  jmp .L16                ; continue for loop

; cat_fd and close handler 
.L15:
  mov rax, qword [rbp-16] ; rax = fd
  mov rdi, rax            ; arg 1 = fd
  
  call cat_fd

  or dword [rbp-4], eax   ; status |= cat_fd(fd) 

  mov rax, qword [rbp-16] ; rax = fd
  mov ecx, 0              ; arg 4 = 0 unused
  mov edx, 0              ; arg 3 = 0 unused
  mov rsi, rax            ; arg 2 = fd
  mov edi, 3              ; arg 1 sys_close (3)
  call sys3

; i++ for loop 
.L16:
  add dword [rbp-8], 1

; for loop, call cat_fd on all args[i] 
.L14:
  mov eax, dword [rbp-8]  ; i
  cmp eax, dword [rbp-20] ; i < argc
  jl .L17 ; less than handle 
  mov eax, dword [rbp-4]  ; return status

; end main 
.L13:
  leave 
  ret

; entry point
_start:
  mov edi, [rsp]          ; argc
  lea rsi, [rsp+8]        ; argv
  call main
  mov edi, eax            ; exit status = main's return value
  mov eax, 60             ; SYS_exit
  syscall
