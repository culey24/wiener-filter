# Wiener filter - MARS compatible
# Assembler: MARS / SPIM

.data
filename_input:   .asciiz "input/tc_0_input_1.txt"   
filename_desired: .asciiz "desired/tc_0_desired.txt"  
filename_output:  .asciiz "output.txt"    
.align 2
buffer:     .space 4000

# storage for up to 500 samples
input_signal:    .space 2000     # 500 * 4
desired_signal:    .space 2000
output_signal:    .space 2000
output_signal_str: .space 2000

# parameters
maxSamples: .word 500
M_const:    .word 3      

# working/algorithm arrays 
Rxx:        .space 64
Rdx:        .space 64
optimize_coefficient:          .space 64
Rmat:       .space 1024
Raug:       .space 2048

print_output: .asciiz "Filtered output: " 
print_mmse:   .asciiz "MMSE: "
newline:      .asciiz "\n"
space:        .asciiz " "                 
error_msg:  .asciiz "Error: size not match\n"

const_zero: .float 0.0
const_one:  .float 1.0
const_ten:  .float 10.0    

string_buffer:   .space 64     
str_minus:       .asciiz "-"
str_dot:         .asciiz "."
str_zero:        .asciiz "0"

# MMSE variable save
mmse: .float 0.0

.text
.globl main
main:
    jal read_input_file
    move $s5, $v0           # $s5 = N_x 
    
    jal read_desired_file
    move $s7, $v0           # $s7 = N_d 

    #size check 
    bne $s5, $s7, print_size_error # if (N_x != N_d)
    
    # s5 = N
    beqz $s5, exit_prog     # if (N == 0), 

    j parse_done      

read_input_file:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # file open
    li $v0, 13
    la $a0, filename_input
    li $a1, 0
    syscall
    move $s0, $v0      

    # read to buffer
    li $v0, 14
    move $a0, $s0
    la $a1, buffer
    li $a2, 4000
    syscall

    # file close
    li $v0, 16
    move $a0, $s0
    syscall

    la $s1, buffer      
    la $s2, input_signal    
    li $t1, 0          
    
    # parse_loop_new call
    move $a0, $s1     
    move $a1, $s2       
    jal parse_loop_new
    move $v0, $t1      

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

read_desired_file:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # file open
    li $v0, 13
    la $a0, filename_desired
    li $a1, 0
    syscall
    move $s0, $v0       # file descriptor in s0

    # read to buffet
    li $v0, 14
    move $a0, $s0
    la $a1, buffer
    li $a2, 4000
    syscall

    # file closee
    li $v0, 16
    move $a0, $s0
    syscall

    la $s1, buffer     
    la $s3, desired_signal    
    li $t1, 0          

    # parse_loop_new call
    move $a0, $s1      
    move $a1, $s3       
    jal parse_loop_new
    move $v0, $t1       

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

parse_loop_new:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    move $s1, $a0       
    move $s2, $a1       
    li $t1, 0           
    
parse_loop_new_start:
    lb $t3, 0($s1)      # t3 = *s1
    beqz $t3, parse_loop_new_done  # end of buffer
    
    # skip whitespaces
    li $t4, 32
    beq $t3, $t4, adv_char_new
    li $t4, 9
    beq $t3, $t4, adv_char_new
    li $t4, 10
    beq $t3, $t4, adv_char_new
    li $t4, 13
    beq $t3, $t4, adv_char_new
    li $t4, 11
    beq $t3, $t4, adv_char_new
    # non-space -> parse number
    j call_parse_number
adv_char_new:
    addi $s1, $s1, 1
    j parse_loop_new_start

call_parse_number:
    jal parse_number_func

    sll $t4, $t1, 2     # t4 = i * 4
    add $t5, $s2, $t4   # t5 = &array[i]
    swc1 $f0, 0($t5)    # array[i] = $f0
    
    addi $t1, $t1, 1    # i++
    j parse_loop_new_start

parse_loop_new_done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

parse_number_func:
    # deleted*
    
# parse_number: parse one decimal number with optional sign and fractional part
# result in $f0. Advances pointer $s1 to first byte after token.
parse_number:
    # default sign = +1 in t5
    li $t5, 1
    lb $t3, 0($s1)
    li $t4, 45          # -
    beq $t3, $t4, sign_minus
    li $t4, 43          # +
    beq $t3, $t4, sign_plus
    j parse_int
sign_minus:
    li $t5, -1
    addi $s1, $s1, 1
    j parse_int
sign_plus:
    li $t5, 1
    addi $s1, $s1, 1

parse_int:
    li $t6, 0          
    lb $t3, 0($s1)
int_loop:
    li $t4, 48
    li $t7, 57
    blt $t3, $t4, int_done
    bgt $t3, $t7, int_done
    sub $t8, $t3, $t4     # digit value
    li $t9, 10
    mul $t6, $t6, $t9
    add $t6, $t6, $t8
    addi $s1, $s1, 1
    lb $t3, 0($s1)
    j int_loop
int_done:
    # check for decimal point
    li $t4, 46          # '.'
    beq $t3, $t4, parse_frac
    # assemble float (no fraction)
    # convert integer -> float in f2
    move $t7, $t6
    mtc1 $t7, $f2
    cvt.s.w $f2, $f2
    # frac part zero
    l.s $f4, const_zero
    # Set t8 (fracDiv) to 1 to signal no fraction
    li $t8, 1
    j assemble_signed

parse_frac:
    # skip '.'
    addi $s1, $s1, 1

    # parse fraction properly:
    li $t7, 0           # frac accumulator
    li $t8, 1           # frac_div (power of 10)
frac_parse2:
    lb $t3, 0($s1)
    li $t4, 48
    li $t9, 57
    blt $t3, $t4, frac_parse2_done
    bgt $t3, $t9, frac_parse2_done
    sub $t4, $t3, $t4     # digit
    mul $t7, $t7, 10
    add $t7, $t7, $t4
    mul $t8, $t8, 10
    addi $s1, $s1, 1
    j frac_parse2
frac_parse2_done:
    # integerPart in t6, frac in t7, fracDiv in t8
    move $t9, $t6
    mtc1 $t9, $f2
    cvt.s.w $f2, $f2
    move $t9, $t7
    mtc1 $t9, $f4
    cvt.s.w $f4, $f4
    move $t9, $t8
    mtc1 $t9, $f6
    cvt.s.w $f6, $f6
    # f10 = f2 + f4/f6
    beq $t8, $zero, frac_no_div
    div.s $f8, $f4, $f6
    add.s $f10, $f2, $f8
    j frac_done2
frac_no_div:
    mov.s $f10, $f2
frac_done2:
    # f10 holds the result
    j assemble_signed

assemble_signed:
    # if we came from int-only, f2 has integer part and t8=1
    # if we came from frac, f10 has the full value
    
    # Check if we need to use f10 or f2
    li $t9, 1
    bgt $t8, $t9, use_f10  # if t8 > 1, fraction was parsed, f10 is correct
    mov.s $f10, $f2          # else, no fraction, just use int part from f2
use_f10:

    # apply sign (t5 contains 1 or -1)
    # move sign to float
    move $t9, $t5
    mtc1 $t9, $f12
    cvt.s.w $f12, $f12
    mul.s $f0, $f10, $f12     # parsed float now in $f0
    
    jr $ra

parse_number_return:
    jr $ra

parse_done:
    # (s5 = N)
    
    # load M
    la $t0, M_const
    lw $s6, 0($t0)      # s6 = M
    
    la $s2, input_signal
    la $s3, desired_signal
    la $s4, output_signal

    li $t7, 0           # k = 0

k_loop:
    bge $t7, $s6, k_done
    # sum_xx, sum_dx = 0.0
    l.s $f20, const_zero
    l.s $f22, const_zero

    # n = k .. N-1
    move $t8, $t7       # n = k
n_loop2:
    bge $t8, $s5, n_done2

    # load x[n]
    sll $t9, $t8, 2
    add $t6, $s2, $t9     # t6 = addr of x[n]
    lwc1 $f4, 0($t6)

    # load x[n-k]
    sub $t4, $t8, $t7
    sll $t5, $t4, 2
    add $t6, $s2, $t5
    lwc1 $f6, 0($t6)

    mul.s $f8, $f4, $f6
    add.s $f20, $f20, $f8

    # load d[n]
    sll $t4, $t8, 2
    add $t5, $s3, $t4
    lwc1 $f10, 0($t5)
    mul.s $f12, $f10, $f6
    add.s $f22, $f22, $f12

    addi $t8, $t8, 1
    j n_loop2
n_done2:
    # denom = N - k
    mtc1 $s5, $f14          
    cvt.s.w $f14, $f14

    div.s $f24, $f20, $f14  # Rxx[k]
    div.s $f26, $f22, $f14  # Rdx[k]

    # store Rxx[k], Rdx[k]
    sll $t4, $t7, 2
    la $t5, Rxx
    add $t6, $t5, $t4
    swc1 $f24, 0($t6)

    la $t5, Rdx
    add $t6, $t5, $t4
    swc1 $f26, 0($t6)

    addi $t7, $t7, 1
    j k_loop
k_done:
    li $t8, 0           # i = 0 (using t8 for t28)
i_build:
    bge $t8, $s6, build_done
    li $t9, 0           # j = 0 (using t9 for t29)
j_build:
    bge $t9, $s6, store_aug
    # index = abs(i - j)
    sub $t0, $t8, $t9
    bltz $t0, make_pos_abs
    j abs_done
make_pos_abs:
    sub $t0, $zero, $t0
abs_done:
    sll $t1, $t0, 2
    la $t2, Rxx
    add $t3, $t2, $t1
    lwc1 $f30, 0($t3)

    # store into Rmat[ i*M + j ]
    mul $t4, $t8, $s6
    add $t4, $t4, $t9
    sll $t5, $t4, 2
    la $t6, Rmat
    add $t7, $t6, $t5
    swc1 $f30, 0($t7)

    addi $t9, $t9, 1
    j j_build
store_aug:
    # store Rdx[i] into augmented last column (col M)
    sll $t1, $t8, 2
    la $t2, Rdx
    add $t3, $t2, $t1
    lwc1 $f31, 0($t3)

    addi $t0, $s6, 1      # t0 = M+1
    mul $t4, $t8, $t0     # i * (M+1)
    add $t4, $t4, $s6     # i*(M+1) + M
    sll $t5, $t4, 2
    la $t6, Raug
    add $t7, $t6, $t5
    swc1 $f31, 0($t7)

    addi $t8, $t8, 1
    j i_build
build_done:
    # copy rmat into augmented left M columns
    li $t9, 0           # i = 0 (using t9 for t15)
copy_rows:
    bge $t9, $s6, copy_done
    li $t0, 0           # j = 0
copy_cols:
    bge $t0, $s6, next_row_copy
    # Rmat[i*M + j]
    mul $t1, $t9, $s6
    add $t1, $t1, $t0
    sll $t2, $t1, 2
    la $t3, Rmat
    add $t4, $t3, $t2
    lwc1 $f1, 0($t4)

    # Raug[i*(M+1) + j]
    addi $t5, $s6, 1    # t5 = M+1
    mul $t5, $t9, $t5   # i * (M+1)
    add $t5, $t5, $t0   # i*(M+1) + j
    sll $t6, $t5, 2
    la $t7, Raug
    add $t8, $t7, $t6
    swc1 $f1, 0($t8)

    addi $t0, $t0, 1
    j copy_cols
next_row_copy:
    addi $t9, $t9, 1
    j copy_rows
copy_done:
    # Gaussian elimination (no pivoting) on Raug (M x (M+1))
    # s6 = M
    addi $t8, $s6, 1      # t8 = M+1 (width of Raug)
    li $t0, 0           # pivot row i
elim_outer:
    bge $t0, $s6, elim_done
    # pivot element at [i*width + i]
    mul $t1, $t0, $t8
    add $t1, $t1, $t0
    sll $t2, $t1, 2
    la $t3, Raug
    add $t4, $t3, $t2
    lwc1 $f16, 0($t4)     # f16 = $f_pivot

    # normalize pivot row (columns j = i .. M)
    move $t5, $t0         # j = i
norm_cols:
    bge $t5, $t8, norm_done # j goes up to M (which is < M+1)
    mul $t6, $t0, $t8
    add $t6, $t6, $t5
    sll $t7, $t6, 2
    la $t9, Raug
    add $t9, $t9, $t7
    lwc1 $f17, 0($t9)     # f17 = $f_elem
    div.s $f17, $f17, $f16  # f17 = $f_newel
    swc1 $f17, 0($t9)
    addi $t5, $t5, 1
    j norm_cols
norm_done:
    # eliminate rows below: r = i+1..M-1
    addi $t5, $t0, 1      # r = i+1 (using t5 for t10)
elim_rows2:
    bge $t5, $s6, next_pivot
    # fac = Raug[r*width + i]
    mul $t1, $t5, $t8
    add $t1, $t1, $t0
    sll $t2, $t1, 2
    la $t3, Raug
    add $t4, $t3, $t2
    lwc1 $f19, 0($t4)     # f19 = $f_fac

    move $t1, $t0         # j = i (using t1 for t15)
elim_cols2:
    bge $t1, $t8, after_elim_cols2 # j goes up to M
    # Raug[r*width + j]
    mul $t2, $t5, $t8
    add $t2, $t2, $t1
    sll $t3, $t2, 2
    la $t4, Raug
    add $t9, $t4, $t3
    lwc1 $f20, 0($t9)     # f20 = $f_rval

    # Raug[i*width + j]
    mul $t2, $t0, $t8
    add $t2, $t2, $t1
    sll $t3, $t2, 2
    la $t4, Raug
    add $t6, $t4, $t3
    lwc1 $f21, 0($t6)     # f21 = $f_pivotval

    mul.s $f22, $f19, $f21  # f22 = $f_temp
    sub.s $f20, $f20, $f22  # f20 = $f_newr
    swc1 $f20, 0($t9)

    addi $t1, $t1, 1
    j elim_cols2
after_elim_cols2:
    addi $t5, $t5, 1
    j elim_rows2
next_pivot:
    addi $t0, $t0, 1
    j elim_outer
elim_done:
    # back substitution
    # s6 = M, t8 = M+1
    add $t0, $s6, $zero
    addi $t0, $t0, -1     # i = M-1
backsub_outer:
    bltz $t0, backsub_done
    l.s $f16, const_zero  # f16 = $f_sum
    addi $t1, $t0, 1      # j = i+1
backsub_inner:
    bge $t1, $s6, compute_rhs2 # j goes up to M-1
    # Raug[i*width + j]
    mul $t2, $t0, $t8
    add $t2, $t2, $t1
    sll $t3, $t2, 2
    la $t4, Raug
    add $t5, $t4, $t3
    lwc1 $f17, 0($t5)     # f17 = $f_rij

    # optimize_coefficient[j]
    sll $t6, $t1, 2
    la $t7, optimize_coefficient
    add $t9, $t7, $t6
    lwc1 $f18, 0($t9)     # f18 = $f_wj

    mul.s $f19, $f17, $f18  # f19 = $f_tmp
    add.s $f16, $f16, $f19  # f_sum += f_tmp

    addi $t1, $t1, 1
    j backsub_inner
compute_rhs2:
    # Raug[i*width + M] (rhs)
    mul $t2, $t0, $t8
    add $t2, $t2, $s6       # col M
    sll $t3, $t2, 2
    la $t4, Raug
    add $t5, $t4, $t3
    lwc1 $f20, 0($t5)     # f20 = $f_rhs

    sub.s $f21, $f20, $f16  # f21 = $f_wi
    sll $t6, $t0, 2
    la $t7, optimize_coefficient
    add $t9, $t7, $t6
    swc1 $f21, 0($t9)

    addi $t0, $t0, -1
    j backsub_outer
backsub_done:
    # compute y[n]
    li $t0, 0           # n = 0
y_compute:
    bge $t0, $s5, after_y_compute
    l.s $f16, const_zero  # f16 = $f_yacc
    li $t1, 0           # k = 0
k_for_y:
    bge $t1, $s6, after_k_for_y
    sub $t2, $t0, $t1     # n-k
    bltz $t2, skip_k_y
    # optimize_coefficient[k]
    sll $t3, $t1, 2
    la $t4, optimize_coefficient
    add $t5, $t4, $t3
    lwc1 $f17, 0($t5)     # f17 = $f_wk

    # x[n-k]
    sll $t6, $t2, 2
    la $t7, input_signal
    add $t8, $t7, $t6
    lwc1 $f18, 0($t8)     # f18 = $f_x

    mul.s $f19, $f17, $f18  # f19 = $f_p
    add.s $f16, $f16, $f19
skip_k_y:
    addi $t1, $t1, 1
    j k_for_y
after_k_for_y:
    sll $t9, $t0, 2
    la $t3, output_signal
    add $t4, $t3, $t9
    swc1 $f16, 0($t4)

    addi $t0, $t0, 1
    j y_compute
after_y_compute:
    # compute MMSE 
    l.s $f16, const_zero  # f16 = $f_mmse_sum
    li $t0, 0           # n = 0
mmse_loop2:
    bge $t0, $s5, mmse_done2
    sll $t1, $t0, 2
    # d[n]
    la $t2, desired_signal
    add $t3, $t2, $t1
    lwc1 $f17, 0($t3)     # f17 = $f_dn

    # y[n]
    la $t4, output_signal
    add $t5, $t4, $t1
    lwc1 $f18, 0($t5)     # f18 = $f_yn

    sub.s $f19, $f17, $f18  # f19 = $f_err
    mul.s $f19, $f19, $f19  # f19 = $f_sq
    add.s $f16, $f16, $f19

    addi $t0, $t0, 1
    j mmse_loop2
mmse_done2:
    mtc1 $s5, $f20      # f20 = $f_n
    cvt.s.w $f20, $f20
    div.s $f16, $f16, $f20  # f16 = $f_mmse

    # save mmse
    la $t0, mmse
    swc1 $f16, 0($t0)

    # print y[]
    la $a0, print_output
    li $v0, 4
    syscall

    li $t0, 0
print_yloop:
    bge $t0, $s5, print_done
    sll $t1, $t0, 2
    la $t2, output_signal
    add $t3, $t2, $t1
    lwc1 $f12, 0($t3)
    
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    li $v0, 2
    syscall
    la $a0, space
    li $v0, 4
    syscall
    addi $t0, $t0, 1
    j print_yloop
print_done:
    # la $a0, newline
    # li $v0, 4
    # syscall

    la $a0, newline
    li $v0, 4
    syscall

    la $a0, print_mmse
    li $v0, 4
    syscall

    mov.s $f12, $f16      # move $f_mmse to $f12
    
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    li $v0, 2
    syscall
    la $a0, newline
    li $v0, 4
    syscall

    jal print_to_file

exit_prog:
    li $v0, 10
    syscall
    
print_size_error:
    li $v0, 4
    la $a0, error_msg
    syscall
    j exit_prog 

round_to_one_decimal:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    s.s $f1, 4($sp)
    s.s $f2, 8($sp)
    l.s $f1, const_ten      # f1 = 10.0
    
    # f2 = (f12 * 10.0)
    mul.s $f2, $f12, $f1
    
    # f2 = round_to_int(f2)
    round.w.s $f2, $f2     
    
    # f2 = (float)f2
    cvt.s.w $f2, $f2     
    
    # f12 = f2 / 10.0
    div.s $f12, $f2, $f1
    
    lw $ra, 0($sp)
    l.s $f1, 4($sp)         
    l.s $f2, 8($sp)         
    addi $sp, $sp, 12
    jr $ra

print_to_file:
    addi $sp, $sp, -8
    sw $ra, 4($sp)        
    sw $s7, 0($sp)   

    li $v0, 13              # syscall 13: open file
    la $a0, filename_output 
    li $a1, 1             
    syscall
    move $s0, $v0           # $s0 = file descriptor 

    li $v0, 15              # syscall 15: write to file
    move $a0, $s0
    la $a1, print_output
    li $a2, 17              #  "Filtered output: " lenght
    syscall

    li $s7, 0            
file_yloop:
    bge $s7, $s5, file_print_done # i >= N (s5=N)

    sll $t1, $s7, 2       
    la $t2, output_signal
    add $t3, $t2, $t1
    lwc1 $f12, 0($t3)    
    
    # 1. LÀM TRÒN
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer     

    jal float_to_string       
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal get_string_length     
    move $t1, $v0             
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    li $v0, 15
    move $a0, $s0
    la $a1, string_buffer
    move $a2, $t1            
    syscall

    li $v0, 15
    move $a0, $s0
    la $a1, space
    li $a2, 1
    syscall
    
    addi $s7, $s7, 1      
    j file_yloop
file_print_done:

    li $v0, 15
    move $a0, $s0
    la $a1, newline
    li $a2, 1
    syscall

    li $v0, 15
    move $a0, $s0
    la $a1, print_mmse
    li $a2, 6
    syscall

    mov.s $f12, $f16
    
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal float_to_string
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal get_string_length
    move $t1, $v0
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    li $v0, 15
    move $a0, $s0
    la $a1, string_buffer
    move $a2, $t1
    syscall

    li $v0, 15
    move $a0, $s0
    la $a1, newline
    li $a2, 1
    syscall

    li $v0, 16
    move $a0, $s0
    syscall

    lw $s7, 0($sp)         
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra

float_to_string:
    addi $sp, $sp, -8      
    sw $ra, 4($sp)          
    sw $s7, 0($sp)          
    
    move $s7, $a0          
    l.s $f0, const_zero     
    
    c.lt.s $f12, $f0       
    bc1f ftos_check_integer_part

    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, str_minus
    li $a1, 1
    move $a2, $s7         
    jal append_string
    move $s7, $v0           
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    abs.s $f12, $f12        
    
ftos_check_integer_part:
    trunc.w.s $f1, $f12    
    
    mfc1 $a0, $f1           
    move $a1, $s7           
    
    bnez $a0, ftos_int_is_not_zero 
    
    la $t0, str_zero
    lb $t1, 0($t0)
    sb $t1, 0($s7)
    addi $s7, $s7, 1
    j ftos_write_decimal_point    
    
ftos_int_is_not_zero:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal int_to_string_recursive 
    move $s7, $v0          
    lw $ra, 0($sp)
    addi $sp, $sp, 4

ftos_write_decimal_point:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, str_dot
    li $a1, 1
    move $a2, $s7
    jal append_string
    move $s7, $v0
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    cvt.s.w $f1, $f1       
    sub.s $f12, $f12, $f1  

    l.s $f10, const_ten     
    li $t0, 1              

ftos_loop_frac:
    beq $t0, $zero, ftos_end_loop_frac
    
    mul.s $f12, $f12, $f10  # f12 *= 10.0
    trunc.w.s $f1, $f12
    mfc1 $t1, $f1

    addi $t1, $t1, 48
    sb $t1, 0($s7)
    addi $s7, $s7, 1

    cvt.s.w $f1, $f1
    sub.s $f12, $f12, $f1
    
    addi $t0, $t0, -1
    j ftos_loop_frac

ftos_end_loop_frac:

    sb $zero, 0($s7)
    
    lw $s7, 0($sp)          
    lw $ra, 4($sp)
    addi $sp, $sp, 8        
    jr $ra

int_to_string_recursive:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $a0, 0($sp)          
    
    li $t0, 10
    div $a0, $t0            
    mflo $a0                
    
    bnez $a0, itos_recursive_call    
    
    
    lw $a0, 0($sp)          
    j itos_process_remainder     
    
itos_recursive_call:  
    jal int_to_string_recursive
    move $a1, $v0           
    lw $a0, 0($sp)          
    
itos_process_remainder:
    li $t0, 10
    div $a0, $t0
    mfhi $t1                
    
    addi $t1, $t1, 48       
    sb $t1, 0($a1)          
    addi $v0, $a1, 1        
    
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra

append_string:
    move $t0, $zero

loop_append:
    beq $t0, $a1, end_append 
    lbu $t1, 0($a0)
    sb $t1, 0($a2)
    addi $a0, $a0, 1
    addi $a2, $a2, 1
    addi $t0, $t0, 1
    j loop_append

end_append:
    move $v0, $a2           
    jr $ra

get_string_length:
    li $v0, 0              
    
strlen_loop:
    lb $t0, 0($a0)
    beqz $t0, strlen_done
    addi $a0, $a0, 1
    addi $v0, $v0, 1
    j strlen_loop

strlen_done:
    jr $ra