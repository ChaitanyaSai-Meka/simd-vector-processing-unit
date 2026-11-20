# B3: C[i] = (A[i] & 0xffff0000) ^ (B[i] << 2).
    SLI    r1, 0
    SLI    r2, GROUPS
    SLI    r3, 2                # Shift used in the loop
    SLI    r4, -1
    SLI    r5, 16
    VLD    v2, 0(r0)            # Initialize v2 before using it to make a zero
    VSUB   v2, v2, v2
    VOR.S  v2, v2, r4
    VSLL.S v2, v2, r5           # Build the mask once from 16-bit immediates
loop:
    VLD    v0, 0(r1)
    VLD    v1, B_BASE(r1)
    VAND   v3, v0, v2
    VSLL.S v4, v1, r3
    VXOR   v5, v3, v4
    VST    v5, C_BASE(r1)
    SADDI  r1, r1, 1
    BNE    r1, r2, loop
    HALT
