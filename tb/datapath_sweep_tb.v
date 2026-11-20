// Exercise the vector datapath at one LANES setting using the B3 golden fixtures.
`timescale 1ns/1ps

module datapath_sweep_tb;
    parameter LANES = 4;
    localparam DW = 32;
    localparam WIDTH = LANES * DW;
    localparam GROUPS = 64 / LANES;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg vector_we = 1'b0;
    reg [2:0] vd_addr, vs1_addr, vs2_addr;
    wire [WIDTH-1:0] vs1_data, vs2_data, wb_data;
    reg scalar_we = 1'b0;
    reg [2:0] rd_addr, rs2_addr;
    reg [DW-1:0] scalar_wdata;
    wire [DW-1:0] scalar_data;
    reg [3:0] alu_op;
    reg opb_sel, res_sel;
    wire [WIDTH-1:0] alu_result, mem_rdata;
    reg mem_we = 1'b0;
    reg [31:0] mem_addr;

    vreg_file #(.LANES(LANES), .DW(DW)) vector_regs (
        .clk(clk), .we(vector_we), .waddr(vd_addr), .wdata(wb_data),
        .raddr1(vs1_addr), .rdata1(vs1_data), .raddr2(vs2_addr), .rdata2(vs2_data)
    );

    sreg_file #(.DW(DW)) scalar_regs (
        .clk(clk), .we(scalar_we), .waddr(rd_addr), .wdata(scalar_wdata),
        .raddr1(3'd0), .rdata1(), .raddr2(rs2_addr), .rdata2(scalar_data)
    );

    lane_array #(.LANES(LANES), .DW(DW)) lanes (
        .vs1(vs1_data), .vs2(vs2_data), .scalar(scalar_data),
        .alu_op(alu_op), .opb_sel(opb_sel), .result(alu_result)
    );

    dmem #(.LANES(LANES), .DW(DW)) data_mem (
        .clk(clk), .we(mem_we), .addr(mem_addr), .wdata(vs1_data), .rdata(mem_rdata)
    );

    result_combiner #(.LANES(LANES), .DW(DW)) combiner (
        .alu_result(alu_result), .mem_rdata(mem_rdata), .res_sel(res_sel), .wb_data(wb_data)
    );

    task write_scalar;
        input [2:0] dest;
        input [DW-1:0] value;
        begin
            @(negedge clk);
            rd_addr = dest;
            scalar_wdata = value;
            scalar_we = 1'b1;
            @(posedge clk);
            #1 scalar_we = 1'b0;
        end
    endtask

    // Call after setting up the source on the falling edge.
    task write_vector;
        input [2:0] dest;
        input from_memory;
        begin
            vd_addr = dest;
            res_sel = from_memory;
            vector_we = 1'b1;
            @(posedge clk);
            #1 vector_we = 1'b0;
        end
    endtask

    task load_vector;
        input [2:0] dest;
        input [31:0] address;
        begin
            @(negedge clk);
            mem_addr = address;
            write_vector(dest, 1'b1);
        end
    endtask

    task run_alu;
        input [3:0] operation;
        input [2:0] dest;
        input [2:0] src1;
        input [2:0] src2;
        input broadcast;
        begin
            @(negedge clk);
            vs1_addr = src1;
            vs2_addr = src2;
            rs2_addr = src2;
            alu_op = operation;
            opb_sel = broadcast;
            write_vector(dest, 1'b0);
        end
    endtask

    reg [WIDTH-1:0] expected [0:GROUPS-1];
    reg [8*64-1:0] input_hex;
    reg [8*64-1:0] expected_hex;
    integer group;

    task check_group;
        input [8*24-1:0] source_name;
        input [WIDTH-1:0] actual;
        begin
            if (((^expected[group]) === 1'bx) || (actual !== expected[group])) begin
                $display("FAIL datapath_sweep_tb LANES=%0d group=%0d %0s: expected %h, got %h",
                         LANES, group, source_name, expected[group], actual);
                $finish_and_return(1);
            end
        end
    endtask

    initial begin
        $sformat(input_hex, "verif/data/b3_dmem_L%0d.hex", LANES);
        $sformat(expected_hex, "verif/data/b3_C_expected_L%0d.hex", LANES);
        $readmemh(input_hex, data_mem.mem, 0, 3*GROUPS - 1);
        $readmemh(expected_hex, expected, 0, GROUPS - 1);

        // The .S instructions also point at initialized vector registers v1 and v2.
        write_scalar(3'd1, 32'hffff0000);
        write_scalar(3'd2, 32'd2);

        for (group = 0; group < GROUPS; group = group + 1) begin
            load_vector(3'd0, group);
            load_vector(3'd1, GROUPS + group);
            run_alu(4'h2, 3'd2, 3'd0, 3'd1, 1'b1);  // VAND.S v2, v0, r1
            run_alu(4'h7, 3'd3, 3'd1, 3'd2, 1'b1);  // VSLL.S v3, v1, r2
            run_alu(4'h4, 3'd4, 3'd2, 3'd3, 1'b0);  // VXOR v4, v2, v3

            @(negedge clk);
            vs1_addr = 3'd4;
            mem_addr = 2*GROUPS + group;
            #1;
            check_group("vector write-back", vs1_data);
            mem_we = 1'b1;
            @(posedge clk);
            #1 mem_we = 1'b0;
        end

        // Read back after all stores so writes to aliased addresses cannot pass.
        for (group = 0; group < GROUPS; group = group + 1) begin
            @(negedge clk);
            mem_addr = 2*GROUPS + group;
            #1;
            check_group("data memory", mem_rdata);
        end

        $display("PASS datapath_sweep_tb LANES=%0d: %0d groups matched in vector registers and memory",
                 LANES, GROUPS);
        $finish;
    end
endmodule
