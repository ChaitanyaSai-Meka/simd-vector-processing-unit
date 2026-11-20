// Phase II instruction decoder and three-state controller.
`timescale 1ns/1ps

module control_unit (
    input              clk,
    input              rst,
    input      [31:0]  instr,
    input      [31:0]  pc,
    input      [31:0]  rs1_data,
    input      [31:0]  rs2_data,

    output     [2:0]   vs1_addr,
    output     [2:0]   vs2_addr,
    output     [2:0]   vd_addr,
    output     [2:0]   rs1_addr,
    output     [2:0]   rs2_addr,
    output     [2:0]   rd_addr,
    output reg [3:0]   alu_op,
    output reg         opb_sel,
    output reg         res_sel,
    output reg         vreg_we,
    output reg         sreg_we,
    output reg [31:0]  sreg_wdata,
    output reg         dmem_we,
    output     [31:0]  dmem_addr,
    output reg         pc_en,
    output reg         branch_en,
    output     [31:0]  branch_target,

    output reg         halted,
    output reg [31:0]  cycle_count,
    output reg [31:0]  instr_count
);
    localparam [1:0] FETCH     = 2'b00;
    localparam [1:0] DECODE_EX = 2'b01;
    localparam [1:0] WRITEBACK = 2'b10;

    localparam [5:0] OP_VSRL  = 6'h08;
    localparam [5:0] OP_VLD   = 6'h10;
    localparam [5:0] OP_VST   = 6'h11;
    localparam [5:0] OP_SADDI = 6'h20;
    localparam [5:0] OP_SLI   = 6'h21;
    localparam [5:0] OP_BNE   = 6'h22;
    localparam [5:0] OP_HALT  = 6'h3f;

    reg [1:0] state;
    reg [31:0] saved_instr;

    wire [5:0] opcode = saved_instr[31:26];
    wire is_vector_alu = (opcode <= OP_VSRL);
    wire is_scalar_alu = (opcode == OP_SADDI) || (opcode == OP_SLI);
    wire writes_vector = is_vector_alu || (opcode == OP_VLD);
    wire [31:0] immediate = {{16{saved_instr[15]}}, saved_instr[15:0]};

    // Store data uses the destination field; the base register still uses rs1.
    assign vs1_addr = (opcode == OP_VST) ? saved_instr[25:23] : saved_instr[22:20];
    assign vs2_addr = saved_instr[19:17];
    assign vd_addr = saved_instr[25:23];
    assign rs1_addr = saved_instr[22:20];
    assign rs2_addr = saved_instr[19:17];
    assign rd_addr = saved_instr[25:23];
    assign dmem_addr = rs1_data + immediate;
    assign branch_target = pc + immediate;

    always @* begin
        alu_op = 4'b0;
        opb_sel = 1'b0;
        res_sel = 1'b0;
        vreg_we = 1'b0;
        sreg_we = 1'b0;
        dmem_we = 1'b0;
        pc_en = 1'b0;
        branch_en = 1'b0;

        // These outputs also feed modules with no reset input.
        if (!rst && !halted) begin
            if ((state == DECODE_EX) || (state == WRITEBACK)) begin
                if (is_vector_alu) begin
                    alu_op = opcode[3:0];
                    opb_sel = saved_instr[16];
                end
                res_sel = (opcode == OP_VLD);
            end

            case (state)
                DECODE_EX: begin
                    pc_en = (opcode != OP_HALT);
                    dmem_we = (opcode == OP_VST);
                    branch_en = (opcode == OP_BNE) && (rs1_data != rs2_data);
                end
                WRITEBACK: begin
                    vreg_we = writes_vector;
                    sreg_we = is_scalar_alu;
                end
                default: begin end
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= FETCH;
            saved_instr <= 32'b0;
            sreg_wdata <= 32'b0;
            halted <= 1'b0;
            cycle_count <= 32'b0;
            instr_count <= 32'b0;
        end else if (!halted) begin
            cycle_count <= cycle_count + 32'd1;
            case (state)
                FETCH: begin
                    saved_instr <= instr;
                    state <= DECODE_EX;
                end
                DECODE_EX: begin
                    if (writes_vector || is_scalar_alu) begin
                        if (is_scalar_alu)
                            sreg_wdata <= (opcode == OP_SLI) ? immediate : dmem_addr;
                        state <= WRITEBACK;
                    end else begin
                        // Stores, branches, reserved opcodes and HALT finish here.
                        instr_count <= instr_count + 32'd1;
                        if (opcode == OP_HALT)
                            halted <= 1'b1;
                        else
                            state <= FETCH;
                    end
                end
                WRITEBACK: begin
                    instr_count <= instr_count + 32'd1;
                    state <= FETCH;
                end
                default: state <= FETCH;
            endcase
        end
    end
endmodule
