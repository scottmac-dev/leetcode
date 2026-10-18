; USAGE: nasm -f elf64 hello.asm -o hello.o && ld hello.o -o hello
; EXPECTED: msg prints to stdout, echo $? = 0

; hello.asm - hello world in assemble
; .data  section = static initialised data programs read and write 
section .data
    msg db "Hello world from asm", 10 ; msg = label name, db = define bytes, string + 10 = ascii string plus newline (10)
    len equ $ - msg   ; equ = defines assembly time const, named number like #define or comptime, $ = current addr, - msg gets msg length

; other common sections not shown 
; .bss = holds zero initilized space, eg buf resb 64 = eserve 64 bytes 
; .rodata = read only constants

; .text holds code, read and execute but not writable, exe != write, write != exe
section .text
    global _start ; global exports symbols to the linker, _start = program entry point

; x_86 syscall contract 
; rax = syscall number 
; rdi = arg 1
; rsi = arg 2
; rdx = arg 3
; r10 = arg 4
; r8 = arg 5
; r9 = arg 6
; rax = return value
_start:
    mov rax, 1    ; syscall 1 = sys_write, write(int fd, const void *buf, size_t count)
    mov rdi, 1    ; fd 1 = stdout, arg 1 
    mov rsi, msg  ; load msg into rsi, arg 2
    mov rdx, len  ; load len into rdx, arg 3
    syscall       ; write 

    mov rax, 60   ; sys_exit
    xor rdi, rdi  ; XOR self = 0, more efficient (2 bytes) equivalent of mov rdi, 0 (7 bytes)
    syscall       ; exit(0)
