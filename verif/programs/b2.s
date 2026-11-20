# B2: C[i] = min_signed(A[i], 4096).
    SLI    r1, 0
    SLI    r2, GROUPS
    SLI    r3, 4096             # T
    SLI    r4, -1               # All ones for mask inversion
loop:
    VLD    v0, 0(r1)
    VSLT.S v1, v0, r3           # cmp = (A < T)
    VSUB   v2, v1, v1           # zero from the initialized compare result
    VSUB   v1, v2, v1           # mask = 0 - cmp
    VAND   v3, v0, v1           # Keep A where mask is all ones
    VXOR.S v4, v1, r4           # Invert the mask
    VAND.S v4, v4, r3           # Keep T where the inverted mask is all ones
    VOR    v5, v3, v4
    VST    v5, C_BASE(r1)
    SADDI  r1, r1, 1
    BNE    r1, r2, loop
    HALT
