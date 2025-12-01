import numpy as np

def solve_wiener(input_file, desired_file):
    # 1. Read files
    with open(input_file, 'r') as f:
        x = np.array([float(num) for num in f.read().split()])
    with open(desired_file, 'r') as f:
        d = np.array([float(num) for num in f.read().split()])

    N = len(x)
    M = 2  # Filter length (matches your MIPS code)

    # 2. Calculate Correlations (Bias estimator 1/N like in your MIPS code)
    # Rxx
    Rxx = np.zeros(M)
    for k in range(M):
        sum_val = 0
        for n in range(k, N):
            sum_val += x[n] * x[n-k]
        Rxx[k] = sum_val / (N - k) # Note: Your MIPS uses (N-k) as divisor

    # Rdx
    Rdx = np.zeros(M)
    for k in range(M):
        sum_val = 0
        for n in range(k, N):
            sum_val += d[n] * x[n-k]
        Rdx[k] = sum_val / (N - k)

    # 3. Build Toeplitz Matrix R
    R_mat = np.zeros((M, M))
    for i in range(M):
        for j in range(M):
            R_mat[i, j] = Rxx[abs(i-j)]

    # 4. Solve R * w = Rdx
    w = np.linalg.solve(R_mat, Rdx)
    print(f"Filter Coefficients (w): {w}")

    # 5. Convolution (Filter)
    y = np.zeros(N)
    for n in range(N):
        val = 0
        for k in range(M):
            if n - k >= 0:
                val += w[k] * x[n-k]
        y[n] = val

    # 6. Calculate MMSE
    error = d - y
    mmse = np.mean(error**2)

    # 7. Print Result (Rounded to 1 decimal)
    y_rounded = [round(val, 1) for val in y]
    mmse_rounded = round(mmse, 1)

    print("-" * 30)
    print("VERIFICATION RESULT:")
    print("Filtered output:", " ".join(map(str, y_rounded)))
    print("MMSE:", mmse_rounded)
    print("-" * 30)

# Thay đường dẫn file của bạn vào đây
# solve_wiener("input/tc_1_input_1.txt", "desired/tc_0_desired.txt")