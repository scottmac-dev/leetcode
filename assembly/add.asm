; USAGE
; nasm -f elf64 add.asm -o add.o && ld add.o -o add
; ./add; echo $?     # prints 13

; add.asm
section .text 
  global _start  ; start is entrypoint to program

; int add_ints(int a, int b)
add_ints:
    ; push mains stack base pointer, raising stack pointer
    push rbp
    ; create its own stack base for the add function 
    mov rbp, rsp
    ; make room for the two 32 bit integers allocating 4 bytes on stack
    mov dword [rbp-4], edi ; a
    mov dword [rbp-8], esi ; b
    ; load variables into space made on stack 
    mov edx, dword [rbp-4]  ; load a into edx
    mov eax, dword [rbp-8]  ; load b into eax
    ; add arithmetic, eax = a + b, eax is common return value 
    add eax, edx
    ; pop base pointer clearing stack to enter back into main 
    pop rbp 
    ; return from fn 
    ret

; program start
_start:
    mov edi, 5    ; arg 1: a = 5
    mov esi, 8    ; arg 2: b = 8
    call add_ints ; fn call, return to eax
    mov edi, eax  ; use result (eax) as exit code (edi)
    mov eax, 60   ; loads sys_exit syscall into eax 
    syscall       ; executes exit with edi exit value 
