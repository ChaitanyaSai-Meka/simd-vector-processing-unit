# Starting target. Use the routed 1-lane estimate (period minus setup WNS)
# to tune this value if needed, then rerun all four builds at the same period.
create_clock -name clk -period 10.000 [get_ports clk]
