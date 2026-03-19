`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Vivado-compatible AXI4 Read Master Testbench (64KB BRAM0 Version)
////////////////////////////////////////////////////////////////////////////////

module tb_read_master();

    // =========================================================================
    // Signals
    // =========================================================================
    reg clk;
    reg reset_n;
    
    always #5 clk = ~clk;
    
    reg i_start;
    reg [31:0] i_src_addr;
    reg [31:0] i_total_len;
    wire o_read_done;
    
    reg i_fifo_full;
    wire o_fifo_push;
    wire [31:0] o_r_data;
    
    wire [31:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid;
    reg         m_axi_arready;
    
    reg [31:0]  m_axi_rdata;
    reg         m_axi_rlast;
    reg         m_axi_rvalid;
    wire        m_axi_rready;
    
    // =========================================================================
    // DUT
    // =========================================================================
    Read_Master #(
        .C_M_AXI_ADDR_WIDTH(32),
        .C_M_AXI_DATA_WIDTH(32)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .i_start(i_start),
        .i_src_addr(i_src_addr),
        .i_total_len(i_total_len),
        .o_read_done(o_read_done),
        .i_fifo_full(i_fifo_full),
        .o_fifo_push(o_fifo_push),
        .o_r_data(o_r_data),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );
    
    // =========================================================================
    // Memory Model - BRAM0 (Base Address: 0x00004000)
    // [수정] 크기 64KB로 확장 (16384 words x 4 bytes = 65536 bytes = 64KB)
    // =========================================================================
    reg [31:0] bram0 [0:16383]; // 0~16383 인덱스 (총 16,384개)
    
    parameter BRAM0_BASE = 32'h0000_4000;  // BRAM0 시작 주소
    
    integer i;
    initial begin
        // BRAM0 초기화: 0x00004000부터 시작하는 데이터
        // [수정] 16384번 반복하여 64KB 영역 전체 초기화
        for (i = 0; i < 16384; i = i + 1) begin
            bram0[i] = BRAM0_BASE + (i * 4); 
        end
    end
    
    // =========================================================================
    // AR Channel
    // =========================================================================
    reg [3:0] ar_delay_cnt;
    reg       ar_waiting;
    reg [31:0] stored_addr;
    reg [7:0]  stored_len;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_arready <= 1'b0;
            ar_delay_cnt <= 4'd0;
            ar_waiting <= 1'b0;
            stored_addr <= 32'd0;
            stored_len <= 8'd0;
        end else begin
            if (m_axi_arvalid && !ar_waiting && !m_axi_arready) begin
                ar_waiting <= 1'b1;
                ar_delay_cnt <= 4'd0;
            end
            
            if (ar_waiting && !m_axi_arready) begin
                if (ar_delay_cnt < 4'd2) begin
                    ar_delay_cnt <= ar_delay_cnt + 4'd1;
                end else begin
                    m_axi_arready <= 1'b1;
                    stored_addr <= m_axi_araddr;
                    stored_len <= m_axi_arlen;
                end
            end
            
            if (m_axi_arvalid && m_axi_arready) begin
                m_axi_arready <= 1'b0;
                ar_waiting <= 1'b0;
            end
        end
    end
    
    // =========================================================================
    // R Channel - BRAM0에서 데이터 읽기
    // =========================================================================
    reg [7:0] r_beat_cnt;
    reg [7:0] r_total_beats;
    reg [31:0] r_addr;
    reg       r_active;
    reg [3:0] r_delay_cnt;
    reg       r_waiting;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_rvalid <= 1'b0;
            m_axi_rlast <= 1'b0;
            m_axi_rdata <= 32'd0;
            r_beat_cnt <= 8'd0;
            r_total_beats <= 8'd0;
            r_addr <= 32'd0;
            r_active <= 1'b0;
            r_delay_cnt <= 4'd0;
            r_waiting <= 1'b0;
        end else begin
            if (m_axi_arvalid && m_axi_arready && !r_active) begin
                r_active <= 1'b1;
                r_addr <= stored_addr;
                r_total_beats <= stored_len;
                r_beat_cnt <= 8'd0;
                r_waiting <= 1'b1;
                r_delay_cnt <= 4'd0;
            end
            
            if (r_active && !m_axi_rvalid && r_waiting) begin
                if (r_delay_cnt < 4'd1) begin
                    r_delay_cnt <= r_delay_cnt + 4'd1;
                end else begin
                    m_axi_rvalid <= 1'b1;
                    
                    // BRAM0에서 데이터 읽기 (주소 변환)
                    // [수정] 64KB 범위 체크 (0x10000 = 65536 bytes)
                    if ((r_addr + (r_beat_cnt * 4)) >= BRAM0_BASE && 
                        (r_addr + (r_beat_cnt * 4)) < (BRAM0_BASE + 32'h10000)) begin
                        m_axi_rdata <= bram0[((r_addr + (r_beat_cnt * 4)) - BRAM0_BASE) >> 2];
                    end else begin
                        m_axi_rdata <= 32'hDEAD_BEEF;  // 범위 밖 에러
                    end
                    
                    m_axi_rlast <= (r_beat_cnt == r_total_beats) ? 1'b1 : 1'b0;
                    r_waiting <= 1'b0;
                end
            end
            
            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                m_axi_rlast <= 1'b0;
                
                if (r_beat_cnt < r_total_beats) begin
                    r_beat_cnt <= r_beat_cnt + 8'd1;
                    r_waiting <= 1'b1;
                    r_delay_cnt <= 4'd0;
                end else begin
                    r_active <= 1'b0;
                end
            end
        end
    end
    
    // =========================================================================
    // Test Scenario - Optimized Core Tests
    // =========================================================================
    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        i_start = 1'b0;
        i_src_addr = 32'd0;
        i_total_len = 32'd0;
        i_fifo_full = 1'b0;
        
        #50;
        reset_n = 1'b1;
        #20;
        
        $display("\n========================================");
        $display("AXI4 Read Master Core Test Suite");
        $display("Target: 64KB BRAM, 64B Max Burst, 4KB FIFO");
        $display("========================================\n");
        
        // ---------------------------------------------------------------------
        // 1. Basic & Max Burst Test
        // 목표: 최대 버스트 길이(64B)를 한 번의 트랜잭션으로 처리하는지 확인
        // ---------------------------------------------------------------------
        $display("Test 1: Single Burst (Max 64 Bytes)");
        i_src_addr = BRAM0_BASE;      // 0x00004000
        i_total_len = 32'd64;         // 64 Bytes
        i_start = 1'b1;
        #10;
        i_start = 1'b0;
        
        wait(o_read_done == 1'b1);
        $display("-> Test 1 Passed");
        #100;
        
        // ---------------------------------------------------------------------
        // 2. Multi-Burst Test (New & Critical)
        // 목표: 64B를 초과하는 데이터(256B)를 요청했을 때,
        //       Master가 알아서 64B씩 4번 나누어(Loop) 전송하는지 확인
        // ---------------------------------------------------------------------
        $display("\nTest 2: Multi-Burst Transfer (256 Bytes -> 4 Bursts)");
        i_src_addr = BRAM0_BASE + 32'h0100; // 0x00004100
        i_total_len = 32'd256;              // 256 Bytes
        i_start = 1'b1;
        #10;
        i_start = 1'b0;
        
        wait(o_read_done == 1'b1);
        $display("-> Test 2 Passed (Check Waveform: Should see 4 Address Handshakes)");
        #100;
        
        // ---------------------------------------------------------------------
        // 3. 4KB Boundary Crossing Test
        // 목표: 0x4FF0에서 64B를 요청하면 0x5000 경계를 넘게 됨.
        //       1st Burst(16B) -> 경계 도달 -> 2nd Burst(48B)로 나뉘는지 확인
        // ---------------------------------------------------------------------
        $display("\nTest 3: 4KB Boundary Crossing (0x4FF0, 64 Bytes)");
        i_src_addr = BRAM0_BASE + 32'h0FF0; // 0x00004FF0 (경계 16B 전)
        i_total_len = 32'd64;
        i_start = 1'b1;
        #10;
        i_start = 1'b0;
        
        wait(o_read_done == 1'b1);
        $display("-> Test 3 Passed (Check Waveform: ARADDR should jump to 0x5000)");
        #100;
        
        // ---------------------------------------------------------------------
        // 4. FIFO Backpressure Test
        // 목표: 데이터 전송 중 FIFO Full(1)이 되면 Master가 멈추는지(Pause) 확인
        // ---------------------------------------------------------------------
        $display("\nTest 4: FIFO Backpressure (Pause & Resume)");
        fork
            // Process A: 마스터 실행 (128 Bytes 전송)
            begin
                i_src_addr = BRAM0_BASE + 32'h2000; // 0x00006000
                i_total_len = 32'd128;              // 2번의 버스트 필요
                i_start = 1'b1;
                #10;
                i_start = 1'b0;
                wait(o_read_done == 1'b1);
            end
            
            // Process B: 중간에 FIFO Full 걸기
            begin
                // 첫 번째 버스트(64B) 중 10번째 데이터 쯤에서 멈춤
                repeat(10) @(posedge o_fifo_push);
                @(posedge clk);
                i_fifo_full = 1'b1;
                $display("  [%0t] FIFO FULL Triggered!", $time);
                
                #200; // 200ns 동안 멈춤 (Master가 대기해야 함)
                
                @(posedge clk);
                i_fifo_full = 1'b0;
                $display("  [%0t] FIFO Available (Resume)", $time);
            end
        join
        $display("-> Test 4 Passed");
        #100;

        $display("\n========================================");
        $display("All Core Tests Completed Successfully");
        $display("========================================\n");
        $finish;
    end
    
    // =========================================================================
    // Monitor
    // =========================================================================
    always @(posedge clk) begin
        if (m_axi_arvalid && m_axi_arready) begin
            $display("[%0t] AR: addr=0x%h, len=%0d", $time, m_axi_araddr, m_axi_arlen+1);
        end
        
        if (m_axi_rvalid && m_axi_rready) begin
            $display("[%0t] R: data=0x%h, last=%0b", $time, m_axi_rdata, m_axi_rlast);
        end
        
        if (o_read_done) begin
            $display("[%0t] READ DONE", $time);
        end
    end

endmodule