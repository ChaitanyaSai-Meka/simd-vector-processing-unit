`timescale 1ns/1ps

module result_combiner_tb;
    localparam LANES = 4;
    localparam DW = 32;
    localparam WIDTH = LANES * DW;

    reg [WIDTH-1:0] alu_result, mem_rdata;
    reg res_sel;
    wire [WIDTH-1:0] wb_data;
    integer fail_count = 0;

    result_combiner #(.LANES(LANES), .DW(DW)) dut (
        .alu_result(alu_result),
        .mem_rdata(mem_rdata),
        .res_sel(res_sel),
        .wb_data(wb_data)
    );

    task check;
        input [WIDTH-1:0] expected;
        begin
            if (wb_data !== expected) begin
                $display("FAIL  result_combiner_tb: res_sel=%b expected=%h actual=%h",
                         res_sel, expected, wb_data);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        alu_result = 128'h00000011_00000022_00000033_00000044;
        mem_rdata  = 128'hAAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD;

        res_sel = 0;
        #1;
        check(alu_result);

        res_sel = 1;
        #1;
        check(mem_rdata);

        if (fail_count != 0)
            $finish_and_return(1);

        $display("PASS  result_combiner_tb: all 2 checks passed");
        $finish;
    end
endmodule
