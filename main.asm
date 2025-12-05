# Wiener filter - MARS compatible
#
# Assembler: MARS / SPIM

        .data
# =========================================================================
# DATA SECTION: File names and buffers
# =========================================================================
filename_input:   .asciiz "input.txt"
filename_desired: .asciiz "desired.txt"
filename_output:  .asciiz "output.txt"
.align 2
buffer:     .space 4000     # Buffer to hold text read from files

# =========================================================================
# SIGNAL ARRAYS
# =========================================================================
# array_x: Input signal x(n) (Noisy signal)
# array_d: Desired signal d(n) (Reference signal)
# array_y: Filtered output y(n)
# =========================================================================
array_x:    .space 2000     # Max 500 floats
array_d:    .space 2000
array_y:    .space 2000
array_y_str: .space 2000

# =========================================================================
# ALGORITHM PARAMETERS
# =========================================================================
maxSamples: .word 500
M_const:    .word 10        # Filter Length (Order). CRITICAL: Must match signal complexity.

# =========================================================================
# MATRICES AND VECTORS FOR WIENER-HOPF
# =========================================================================
# Rxx:  Auto-correlation vector of input x
# Rdx:  Cross-correlation vector between d and x
# w:    The optimal filter weights (what we are solving for)
# Rmat: The Toeplitz Matrix (System Matrix)
# Raug: Augmented Matrix [Rmat | Rdx] for Gaussian Elimination
# =========================================================================
Rxx:        .space 64
Rdx:        .space 64
w:          .space 64
Rmat:       .space 1024
Raug:       .space 2048

# Strings for printing
print_output: .asciiz "Filtered output: "
print_mmse:   .asciiz "MMSE: "
newline:      .asciiz "\n"
space:        .asciiz " "
error_msg:    .asciiz "Error: size not match\n"

# Floating point constants
const_zero: .float 0.0
const_one:  .float 1.0
const_ten:  .float 10.0

# Data for output string conversion
string_buffer:   .space 64
str_minus:       .asciiz "-"
str_dot:         .asciiz "."
str_zero:        .asciiz "0"


        .text
        .globl main
# =========================================================================
# MAIN ROUTINE
# 1. Reads input.txt -> array_x
# 2. Reads desired.txt -> array_d
# 3. Checks if sizes match.
# 4. Jumps to the processing logic.
# =========================================================================
main:
    # --- Step 1: Read Input Signal ---
    jal read_input_file
    move $s5, $v0           # $s5 stores N (number of samples in x)
    
    # --- Step 2: Read Desired Signal ---
    jal read_desired_file
    move $s7, $v0           # $s7 stores N (number of samples in d)

    # --- Step 3: Validate Sizes ---
    bne $s5, $s7, print_size_error # If N_x != N_d, error
    beqz $s5, exit_prog     # If N=0, exit

    # --- Step 4: Begin Wiener Filter Calculation ---
    j parse_done

# =========================================================================
# FILE READING HELPERS
# These functions open a file, read the text content into a buffer,
# and then parse that text into floating point numbers.
# =========================================================================

# Reads "input.txt" and parses floats into array_x
read_input_file:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    # Open File
    li $v0, 13
    la $a0, filename_input
    li $a1, 0
    syscall
    move $s0, $v0

    # Read Content
    li $v0, 14
    move $a0, $s0
    la $a1, buffer
    li $a2, 4000
    syscall

    # Close File
    li $v0, 16
    move $a0, $s0
    syscall

    # Parse Content
    la $s1, buffer
    la $s2, array_x
    li $t1, 0
    
    move $a0, $s1
    move $a1, $s2
    jal parse_loop_new
    move $v0, $t1       # Return count of numbers read

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# Reads "desired.txt" and parses floats into array_d
read_desired_file:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    li $v0, 13
    la $a0, filename_desired
    li $a1, 0
    syscall
    move $s0, $v0

    li $v0, 14
    move $a0, $s0
    la $a1, buffer
    li $a2, 4000
    syscall

    li $v0, 16
    move $a0, $s0
    syscall

    la $s1, buffer
    la $s3, array_d
    li $t1, 0

    move $a0, $s1
    move $a1, $s3
    jal parse_loop_new
    move $v0, $t1       # Return count of numbers read

    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# Generic loop that iterates through the text buffer, finds numbers, 
# calls the parser, and stores them in the destination array.
parse_loop_new:
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    
    move $s1, $a0       # Buffer pointer
    move $s2, $a1       # Destination array pointer
    li $t1, 0           # Counter
    
parse_loop_new_start:
    lb $t3, 0($s1)
    beqz $t3, parse_loop_new_done # End of string?
    
    # Skip whitespace (Space, Tab, Newline, CR)
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
    
    # Found a non-whitespace character -> Parse Number
    j call_parse_number
adv_char_new:
    addi $s1, $s1, 1
    j parse_loop_new_start

call_parse_number:
    jal parse_number_func # Returns float in $f0
    
    # Store $f0 in array[i]
    sll $t4, $t1, 2
    add $t5, $s2, $t4
    swc1 $f0, 0($t5)
    
    addi $t1, $t1, 1      # Increment count
    j parse_loop_new_start

parse_loop_new_done:
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    jr $ra

# Core parsing logic: Converts string (e.g., "-12.5") to float ($f0)
parse_number_func:
parse_number:
    # Check sign
    li $t5, 1
    lb $t3, 0($s1)
    li $t4, 45          # '-'
    beq $t3, $t4, sign_minus
    li $t4, 43          # '+'
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
    # Parse integer part
    li $t6, 0
    lb $t3, 0($s1)
int_loop:
    li $t4, 48
    li $t7, 57
    blt $t3, $t4, int_done
    bgt $t3, $t7, int_done
    sub $t8, $t3, $t4
    li $t9, 10
    mul $t6, $t6, $t9
    add $t6, $t6, $t8
    addi $s1, $s1, 1
    lb $t3, 0($s1)
    j int_loop
int_done:
    # Check for decimal point
    li $t4, 46
    beq $t3, $t4, parse_frac
    
    # No decimal point
    move $t7, $t6
    mtc1 $t7, $f2
    cvt.s.w $f2, $f2
    l.s $f4, const_zero
    li $t8, 1
    j assemble_signed

parse_frac:
    # Parse fractional part
    addi $s1, $s1, 1
    li $t7, 0
    li $t8, 1
frac_parse2:
    lb $t3, 0($s1)
    li $t4, 48
    li $t9, 57
    blt $t3, $t4, frac_parse2_done
    bgt $t3, $t9, frac_parse2_done
    sub $t4, $t3, $t4
    mul $t7, $t7, 10
    add $t7, $t7, $t4
    mul $t8, $t8, 10
    addi $s1, $s1, 1
    j frac_parse2
frac_parse2_done:
    # Combine Integer and Fractional parts
    move $t9, $t6
    mtc1 $t9, $f2
    cvt.s.w $f2, $f2        # Int part as float
    move $t9, $t7
    mtc1 $t9, $f4
    cvt.s.w $f4, $f4        # Frac part as float
    move $t9, $t8
    mtc1 $t9, $f6
    cvt.s.w $f6, $f6        # Divisor (10, 100, etc.)
    beq $t8, $zero, frac_no_div
    div.s $f8, $f4, $f6     # Frac / Divisor
    add.s $f10, $f2, $f8    # Total = Int + Frac
    j frac_done2
frac_no_div:
    mov.s $f10, $f2
frac_done2:
    j assemble_signed

assemble_signed:
    # Apply sign
    li $t9, 1
    bgt $t8, $t9, use_f10
    mov.s $f10, $f2
use_f10:
    move $t9, $t5
    mtc1 $t9, $f12
    cvt.s.w $f12, $f12
    mul.s $f0, $f10, $f12   # Final float result in $f0
    jr $ra

# =========================================================================
# WIENER FILTER ALGORITHM START
# =========================================================================
parse_done:
    la $t0, M_const
    lw $s6, 0($t0)      # Load Filter Length M (10)
    
    la $s2, array_x
    la $s3, array_d
    la $s4, array_y

    # ---------------------------------------------------------------------
    # SECTION 1: COMPUTE CORRELATION VECTORS
    # Calculate Auto-correlation (Rxx) and Cross-correlation (Rdx)
    # Rxx[k] = (1/N) * sum(x[n] * x[n-k])
    # Rdx[k] = (1/N) * sum(d[n] * x[n-k])
    # ---------------------------------------------------------------------
    li $t7, 0           # k = 0

k_loop:
    bge $t7, $s6, k_done
    l.s $f20, const_zero
    l.s $f22, const_zero

    move $t8, $t7       # n starts at k (to handle lag)
n_loop2:
    bge $t8, $s5, n_done2

    # Load x[n]
    sll $t9, $t8, 2
    add $t6, $s2, $t9
    lwc1 $f4, 0($t6)

    # Load x[n-k] (Lagged input)
    sub $t4, $t8, $t7
    sll $t5, $t4, 2
    add $t6, $s2, $t5
    lwc1 $f6, 0($t6)

    # Rxx Accumulation
    mul.s $f8, $f4, $f6
    add.s $f20, $f20, $f8

    # Load d[n]
    sll $t4, $t8, 2
    add $t5, $s3, $t4
    lwc1 $f10, 0($t5)
    
    # Rdx Accumulation
    mul.s $f12, $f10, $f6
    add.s $f22, $f22, $f12

    addi $t8, $t8, 1
    j n_loop2
n_done2:
    # Normalization: Divide by N (Biased Estimator)
    mtc1 $s5, $f14
    cvt.s.w $f14, $f14
    
    div.s $f24, $f20, $f14  # Final Rxx[k]
    div.s $f26, $f22, $f14  # Final Rdx[k]

    # Store results
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

    # ---------------------------------------------------------------------
    # SECTION 2: CONSTRUCT TOEPLITZ & AUGMENTED MATRIX
    # The Wiener-Hopf equation is Rxx * w = Rdx.
    # We build the Toeplitz matrix Rmat where Rmat[i,j] = Rxx[|i-j|].
    # We then create Raug = [Rmat | Rdx] to solve using Gaussian Elimination.
    # ---------------------------------------------------------------------
    li $t8, 0           # i (row)
i_build:
    bge $t8, $s6, build_done
    li $t9, 0           # j (col)
j_build:
    bge $t9, $s6, store_aug
    
    # Calculate Toeplitz index: |i - j|
    sub $t0, $t8, $t9
    bltz $t0, make_pos_abs
    j abs_done
make_pos_abs:
    sub $t0, $zero, $t0
abs_done:
    # Fetch Rxx[|i-j|]
    sll $t1, $t0, 2
    la $t2, Rxx
    add $t3, $t2, $t1
    lwc1 $f30, 0($t3)

    # Store in Rmat[i][j]
    mul $t4, $t8, $s6
    add $t4, $t4, $t9
    sll $t5, $t4, 2
    la $t6, Rmat
    add $t7, $t6, $t5
    swc1 $f30, 0($t7)

    addi $t9, $t9, 1
    j j_build
store_aug:
    # Append Rdx[i] as the last column of Raug
    sll $t1, $t8, 2
    la $t2, Rdx
    add $t3, $t2, $t1
    lwc1 $f31, 0($t3)
    
    # Raug index: i*(M+1) + M
    addi $t0, $s6, 1
    mul $t4, $t8, $t0
    add $t4, $t4, $s6
    sll $t5, $t4, 2
    la $t6, Raug
    add $t7, $t6, $t5
    swc1 $f31, 0($t7)

    addi $t8, $t8, 1
    j i_build
build_done:
    # Copy Rmat into the left part of Raug
    li $t9, 0           # i
copy_rows:
    bge $t9, $s6, copy_done
    li $t0, 0           # j
copy_cols:
    bge $t0, $s6, next_row_copy
    
    # Read Rmat
    mul $t1, $t9, $s6
    add $t1, $t1, $t0
    sll $t2, $t1, 2
    la $t3, Rmat
    add $t4, $t3, $t2
    lwc1 $f1, 0($t4)

    # Write Raug
    addi $t5, $s6, 1
    mul $t5, $t9, $t5
    add $t5, $t5, $t0
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

    # ---------------------------------------------------------------------
    # SECTION 3: GAUSSIAN ELIMINATION (FORWARD ELIMINATION)
    # Transform Raug into Row Echelon Form to prepare for solving w.
    # ---------------------------------------------------------------------
    addi $t8, $s6, 1      # Width of Raug (M+1)
    li $t0, 0           # Pivot row i
elim_outer:
    bge $t0, $s6, elim_done
    
    # Get Pivot element [i][i]
    mul $t1, $t0, $t8
    add $t1, $t1, $t0
    sll $t2, $t1, 2
    la $t3, Raug
    add $t4, $t3, $t2
    lwc1 $f16, 0($t4)

    # Normalize the Pivot Row (Divide row by pivot)
    move $t5, $t0
norm_cols:
    bge $t5, $t8, norm_done
    mul $t6, $t0, $t8
    add $t6, $t6, $t5
    sll $t7, $t6, 2
    la $t9, Raug
    add $t9, $t9, $t7
    lwc1 $f17, 0($t9)
    div.s $f17, $f17, $f16
    swc1 $f17, 0($t9)
    addi $t5, $t5, 1
    j norm_cols
norm_done:
    
    # Eliminate rows below the pivot
    addi $t5, $t0, 1      # Next row
elim_rows2:
    bge $t5, $s6, next_pivot
    
    # Factor to eliminate = Raug[next_row][pivot_col]
    mul $t1, $t5, $t8
    add $t1, $t1, $t0
    sll $t2, $t1, 2
    la $t3, Raug
    add $t4, $t3, $t2
    lwc1 $f19, 0($t4)

    # Subtract scaled pivot row from current row
    move $t1, $t0
elim_cols2:
    bge $t1, $t8, after_elim_cols2
    mul $t2, $t5, $t8
    add $t2, $t2, $t1
    sll $t3, $t2, 2
    la $t4, Raug
    add $t9, $t4, $t3
    lwc1 $f20, 0($t9)     # Current element

    mul $t2, $t0, $t8
    add $t2, $t2, $t1
    sll $t3, $t2, 2
    la $t4, Raug
    add $t6, $t4, $t3
    lwc1 $f21, 0($t6)     # Pivot row element

    mul.s $f22, $f19, $f21
    sub.s $f20, $f20, $f22 # New = Current - Factor*Pivot
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

    # ---------------------------------------------------------------------
    # SECTION 4: BACK SUBSTITUTION
    # Solve for weights 'w' starting from the bottom row up.
    # ---------------------------------------------------------------------
    add $t0, $s6, $zero
    addi $t0, $t0, -1     # Start at last row (M-1)
backsub_outer:
    bltz $t0, backsub_done
    l.s $f16, const_zero
    addi $t1, $t0, 1      # Column j = i+1
    
    # Sum known values (w[j] * coeff)
backsub_inner:
    bge $t1, $s6, compute_rhs2
    mul $t2, $t0, $t8
    add $t2, $t2, $t1
    sll $t3, $t2, 2
    la $t4, Raug
    add $t5, $t4, $t3
    lwc1 $f17, 0($t5)

    sll $t6, $t1, 2
    la $t7, w
    add $t9, $t7, $t6
    lwc1 $f18, 0($t9)

    mul.s $f19, $f17, $f18
    add.s $f16, $f16, $f19

    addi $t1, $t1, 1
    j backsub_inner
compute_rhs2:
    # w[i] = RHS - Sum
    mul $t2, $t0, $t8
    add $t2, $t2, $s6
    sll $t3, $t2, 2
    la $t4, Raug
    add $t5, $t4, $t3
    lwc1 $f20, 0($t5)

    sub.s $f21, $f20, $f16
    sll $t6, $t0, 2
    la $t7, w
    add $t9, $t7, $t6
    swc1 $f21, 0($t9)     # Store optimal weight w[i]

    addi $t0, $t0, -1
    j backsub_outer
backsub_done:

    # ---------------------------------------------------------------------
    # SECTION 5: APPLY FILTER (COMPUTE Y)
    # y[n] = sum(w[k] * x[n-k]) for k=0 to M-1
    # ---------------------------------------------------------------------
    li $t0, 0           # n = 0
y_compute:
    bge $t0, $s5, after_y_compute
    l.s $f16, const_zero
    li $t1, 0           # k = 0
k_for_y:
    bge $t1, $s6, after_k_for_y
    sub $t2, $t0, $t1     # Index: n - k
    bltz $t2, skip_k_y    # Skip if index < 0 (assumes x[<0] = 0)
    
    # Load w[k]
    sll $t3, $t1, 2
    la $t4, w
    add $t5, $t4, $t3
    lwc1 $f17, 0($t5)

    # Load x[n-k]
    sll $t6, $t2, 2
    la $t7, array_x
    add $t8, $t7, $t6
    lwc1 $f18, 0($t8)

    # Accumulate Convolution
    mul.s $f19, $f17, $f18
    add.s $f16, $f16, $f19
skip_k_y:
    addi $t1, $t1, 1
    j k_for_y
after_k_for_y:
    # Store result y[n]
    sll $t9, $t0, 2
    la $t3, array_y
    add $t4, $t3, $t9
    swc1 $f16, 0($t4)

    addi $t0, $t0, 1
    j y_compute
    
after_y_compute:
    # ---------------------------------------------------------------------
    # SECTION 6: CALCULATE MMSE (EMPIRICAL METHOD)
    # Formula: MMSE = (1/N) * Sum( (d[n] - y[n])^2 )
    # This matches the Python verification script logic.
    # ---------------------------------------------------------------------
    
    l.s $f16, const_zero    # $f16 will hold the Sum of Squared Errors
    li $t0, 0               # n = 0

calc_mmse_empirical:
    bge $t0, $s5, finish_mmse_empirical # Loop until N ($s5)

    # 1. Load Desired d[n]
    sll $t1, $t0, 2
    la $t2, array_d
    add $t3, $t2, $t1
    lwc1 $f4, 0($t3)

    # 2. Load Output y[n]
    la $t2, array_y         # y is already calculated in Section 5
    add $t3, $t2, $t1
    lwc1 $f6, 0($t3)

    # 3. Calculate Squared Error: (d - y)^2
    sub.s $f8, $f4, $f6     # error = d[n] - y[n]
    mul.s $f8, $f8, $f8     # square = error * error

    # 4. Accumulate
    add.s $f16, $f16, $f8

    addi $t0, $t0, 1
    j calc_mmse_empirical

finish_mmse_empirical:
    # 5. Divide by N to get Mean
    mtc1 $s5, $f20          # Move N to float register
    cvt.s.w $f20, $f20      # Convert N to float
    div.s $f16, $f16, $f20  # MMSE = Sum / N
    
# ---------------------------------------------------------------------
    # SECTION 7: PRINT RESULTS (CONSOLE)
    # FIXED: Changed loop counter from $t0 to $s1.
    # $t0 was getting overwritten by float_to_string, causing the infinite loop.
    # ---------------------------------------------------------------------
    la $a0, print_output
    li $v0, 4
    syscall

    li $s1, 0               # CHANGE: Use $s1 as loop counter (n) instead of $t0
print_yloop:
    bge $s1, $s5, print_done
    
    sll $t1, $s1, 2
    la $t2, array_y
    add $t3, $t2, $t1
    lwc1 $f12, 0($t3)
    
    # 1. Round
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    # 2. Convert to String
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal float_to_string
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    # 3. Print String
    la $a0, string_buffer
    li $v0, 4
    syscall
    
    # Print Space
    la $a0, space
    li $v0, 4
    syscall
    
    addi $s1, $s1, 1        # CHANGE: Increment $s1
    j print_yloop

print_done:
    la $a0, newline
    li $v0, 4
    syscall

    la $a0, print_mmse
    li $v0, 4
    syscall

    mov.s $f12, $f16      # Move MMSE to print register
    
    # 1. Round MMSE
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    # 2. Convert MMSE to String
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal float_to_string
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    # 3. Print MMSE String
    la $a0, string_buffer
    li $v0, 4
    syscall

    la $a0, newline
    li $v0, 4
    syscall

    # ---------------------------------------------------------------------
    # SECTION 8: WRITE TO FILE (output.txt)
    # ---------------------------------------------------------------------
    #jal print_to_file

exit_prog:
    li $v0, 10
    syscall
    
print_size_error:
    li $v0, 4
    la $a0, error_msg
    syscall
    j exit_prog 

# =========================================================================
# UTILITY FUNCTIONS
# =========================================================================

# Rounds value in $f12 to 1 decimal place (e.g., 5.67 -> 5.7)
round_to_one_decimal:
    addi $sp, $sp, -12
    sw $ra, 0($sp)
    s.s $f1, 4($sp)
    s.s $f2, 8($sp)
    l.s $f1, const_ten
    
    mul.s $f2, $f12, $f1
    round.w.s $f2, $f2
    cvt.s.w $f2, $f2
    div.s $f12, $f2, $f1
    
    lw $ra, 0($sp)
    l.s $f1, 4($sp)
    l.s $f2, 8($sp)
    addi $sp, $sp, 12
    jr $ra

# Writes result to output.txt using String Conversion
print_to_file:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s7, 0($sp)

    li $v0, 13
    la $a0, filename_output
    li $a1, 1
    syscall
    move $s0, $v0

    li $v0, 15
    move $a0, $s0
    la $a1, print_output
    li $a2, 17
    syscall

    li $s7, 0
file_yloop:
    bge $s7, $s5, file_print_done
    
    sll $t1, $s7, 2
    la $t2, array_y
    add $t3, $t2, $t1
    lwc1 $f12, 0($t3)
    
    # Round
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    jal round_to_one_decimal
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    # Convert to String
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal float_to_string
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    # Get Length
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, string_buffer
    jal get_string_length
    move $t1, $v0
    lw $ra, 0($sp)
    addi $sp, $sp, 4

    # Write String
    li $v0, 15
    move $a0, $s0
    la $a1, string_buffer
    move $a2, $t1
    syscall

    # Write Space
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
    
    # Write MMSE
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

# Converts Float ($f12) to ASCII string at ($a0)
# Converts Float ($f12) to ASCII string at ($a0)
# MODIFIED: Rounds to 1 decimal place logic (via loop=1) 
# and explicitly pads "000" at the end.
float_to_string:
    addi $sp, $sp, -8
    sw $ra, 4($sp)
    sw $s7, 0($sp)
    
    move $s7, $a0
    l.s $f0, const_zero
    
    # Handle negative
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
    # Handle integer part
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
    # Add Decimal Point
    addi $sp, $sp, -4
    sw $ra, 0($sp)
    la $a0, str_dot
    li $a1, 1
    move $a2, $s7
    jal append_string
    move $s7, $v0
    lw $ra, 0($sp)
    addi $sp, $sp, 4
    
    # Handle Fractional part
    cvt.s.w $f1, $f1
    sub.s $f12, $f12, $f1

    l.s $f10, const_ten
    
    # --- STEP 1: Calculate the 1st decimal digit ---
    li $t0, 1  # Run loop exactly once for the actual value

ftos_loop_frac:
    beq $t0, $zero, ftos_pad_zeros
    
    mul.s $f12, $f12, $f10
    trunc.w.s $f1, $f12
    mfc1 $t1, $f1
    
    addi $t1, $t1, 48       # Convert int to ASCII
    sb $t1, 0($s7)
    addi $s7, $s7, 1
    
    cvt.s.w $f1, $f1
    sub.s $f12, $f12, $f1
    
    addi $t0, $t0, -1
    j ftos_loop_frac

ftos_pad_zeros:
    # --- STEP 2: Manually Pad 3 Zeros ---
    li $t1, 48              # ASCII for '0'
    
    sb $t1, 0($s7)          # 1st zero
    addi $s7, $s7, 1
    
    sb $t1, 0($s7)          # 2nd zero
    addi $s7, $s7, 1
    
    sb $t1, 0($s7)          # 3rd zero
    addi $s7, $s7, 1

    # --- End String ---
    sb $zero, 0($s7)        # Null terminate
    
    lw $s7, 0($sp)
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra
    


# ftos_end_loop_frac:
#     sb $zero, 0($s7) # Null terminate
    
#     lw $s7, 0($sp)
#     lw $ra, 4($sp)
#     addi $sp, $sp, 8
#     jr $ra

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