# B1: C[i] = A[i] + B[i] (32-bit wraparound).
    SLI   r1, 0
    SLI   r2, GROUPS
loop:
    VLD   v0, 0(r1)
    VLD   v1, B_BASE(r1)
    VADD  v2, v0, v1
    VST   v2, C_BASE(r1)
    SADDI r1, r1, 1
    BNE   r1, r2, loop
    HALT
