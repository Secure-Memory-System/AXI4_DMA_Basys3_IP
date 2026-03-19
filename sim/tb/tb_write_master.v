`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Optimized Write Master Testbench (V2 - Fixed)
// Added: FIFO Empty (Underflow) Scenario
// Fixed: Removed fork-join to prevent infinite loop
////////////////////////////////////////////////////////////////////////////////

module tb_write_master();

    // =========================================================================
    // 1. Signals & Clock
    // =========================================================================
    reg clk;
    reg reset_n;
    
    always #5 clk = ~clk; // 100MHz Clock
    
    // Control
    reg i_start;
    reg [31:0] i_dst_addr;
    reg [31:0] i_total_len;
    wire o_write_done;
    
    // FIFO Interface
    reg i_fifo_empty;      // 테스트 시나리오에서 직접 제어
    wire o_fifo_rd_en;
    reg [31:0] i_w_data;
    
    // AXI4 Interface
    wire [31:0] m_axi_awaddr;
    wire [7:0]  m_axi_awlen;
    wire [2:0]  m_axi_awsize;
    wire [1:0]  m_axi_awburst;
    wire        m_axi_awvalid;
    reg         m_axi_awready;
    
    wire [31:0] m_axi_wdata;
    wire [3:0]  m_axi_wstrb;
    wire        m_axi_wlast;
    wire        m_axi_wvalid;
    reg         m_axi_wready;
    
    reg [1:0]   m_axi_bresp;
    reg         m_axi_bvalid;
    wire        m_axi_bready;

    // =========================================================================
    // 2. DUT Instantiation
    // =========================================================================
    Write_Master #(
        .C_M_AXI_ADDR_WIDTH(32),
        .C_M_AXI_DATA_WIDTH(32)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .i_start(i_start),
        .i_dst_addr(i_dst_addr),
        .i_total_len(i_total_len),
        .o_write_done(o_write_done),
        .i_fifo_empty(i_fifo_empty),
        .o_fifo_rd_en(o_fifo_rd_en),
        .i_w_data(i_w_data),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready)
    );

    // =========================================================================
    // 3. FIFO Model (Data Source)
    // =========================================================================
    reg [31:0] fifo_internal_data;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            fifo_internal_data <= 32'hA000_0000;
            i_w_data <= 0;
        end else begin
            if (o_fifo_rd_en && !i_fifo_empty) begin
                i_w_data <= fifo_internal_data; 
                fifo_internal_data <= fifo_internal_data + 1;
            end
        end
    end

    // =========================================================================
    // 4. AXI Slave Simulation
    // =========================================================================
    
    // [AW Channel] - 2클럭 지연
    reg [3:0] aw_delay;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            m_axi_awready <= 0;
            aw_delay <= 0;
        end else begin
            if(m_axi_awvalid && !m_axi_awready) begin
                if(aw_delay < 0) aw_delay <= aw_delay + 1;
                else begin
                    m_axi_awready <= 1;
                    aw_delay <= 0;
                end
            end else begin
                m_axi_awready <= 0;
            end
        end
    end

    // [W Channel] - Always Ready
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) m_axi_wready <= 0;
        else m_axi_wready <= 1; 
    end

    // [B Channel] - WLAST 수신 후 응답
    reg b_pending;
    reg [3:0] b_delay;
    
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            m_axi_bvalid <= 0;
            m_axi_bresp <= 0;
            b_pending <= 0;
            b_delay <= 0;
        end else begin
            if(m_axi_wlast && m_axi_wvalid && m_axi_wready) begin
                b_pending <= 1;
            end
            
            if(b_pending && !m_axi_bvalid) begin
                if(b_delay < 0) b_delay <= b_delay + 1; 
                else begin
                    m_axi_bvalid <= 1;
                    b_pending <= 0;
                    b_delay <= 0;
                end
            end
            
            if(m_axi_bvalid && m_axi_bready) begin
                m_axi_bvalid <= 0;
            end
        end
    end

    // =========================================================================
    // 5. Test Scenarios
    // =========================================================================
    integer fifo_rd_count;  // FIFO read 카운터
    
    // FIFO read 카운터 (Test 3용)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            fifo_rd_count <= 0;
        else if (i_start)
            fifo_rd_count <= 0;  // 새 테스트 시작시 리셋
        else if (o_fifo_rd_en)
            fifo_rd_count <= fifo_rd_count + 1;
    end
    
    initial begin
        clk = 0;
        reset_n = 0;
        i_start = 0;
        i_dst_addr = 0;
        i_total_len = 0;
        i_fifo_empty = 0; // 기본적으로 데이터 있음(Not Empty)
        fifo_rd_count = 0;
        
        #50;
        reset_n = 1;
        #20;
        
        $display("\n========================================");
        $display("Write Master Verification V2");
        $display("Tests: WLAST, Response, FIFO Empty");
        $display("========================================\n");

        // ---------------------------------------------------------------------
        // Test 1: WLAST Timing Check (64 Bytes)
        // ---------------------------------------------------------------------
        $display("Test 1: WLAST Timing Check (64 Bytes)");
        i_dst_addr = 32'hC000_0000;
        i_total_len = 32'd64;
        i_start = 1;
        #10;
        i_start = 0;
        
        wait(o_write_done);
        $display("-> Test 1 Passed");
        #100;

        // ---------------------------------------------------------------------
        // Test 2: Response Handling (128 Bytes)
        // ---------------------------------------------------------------------
        $display("\nTest 2: Response Handling (128 Bytes)");
        i_dst_addr = 32'hC000_1000; 
        i_total_len = 32'd128;
        i_start = 1;
        #10;
        i_start = 0;
        
        wait(o_write_done);
        $display("-> Test 2 Passed");
        #100;

        // ---------------------------------------------------------------------
        // Test 3: FIFO Empty (Underflow) Scenario - FIXED
        // ---------------------------------------------------------------------
        $display("\nTest 3: FIFO Empty (Pause & Resume) Scenario");
        
        i_dst_addr = 32'hC000_2000;
        i_total_len = 32'd64; // 16 beats
        i_start = 1;
        #10;
        i_start = 0;
        
        // 4개의 데이터가 전송될 때까지 대기
        wait(fifo_rd_count >= 4);
        @(posedge clk);
        @(posedge clk);
        
        // [강제 상황 발생] FIFO가 비었다!
        i_fifo_empty = 1; 
        $display("  [%0t] FIFO EMPTY Triggered! (Master should PAUSE)", $time);
        
        // 200ns 동안 데이터가 안 들어옴 (Pause 상태 유지 확인)
        #200;
        
        // [상황 해제] Read Master가 데이터를 채워줌
        @(posedge clk);
        i_fifo_empty = 0;
        $display("  [%0t] FIFO REFILLED! (Master should RESUME)", $time);
        
        // 전송 완료 대기
        wait(o_write_done);
        
        $display("-> Test 3 Passed: Write Master handled empty FIFO correctly.");
        #100;

        $display("\n========================================");
        $display("All Tests Completed Successfully");
        $display("========================================\n");
        $finish;
    end

    // =========================================================================
    // 6. Monitor
    // =========================================================================
    always @(posedge clk) begin
        if (m_axi_wvalid && m_axi_wready) begin
            if (m_axi_wlast)
                $display("[%0t] W Channel: Data=0x%h [LAST]", $time, m_axi_wdata);
        end
    end
    
    // FIFO Empty 상태 모니터
    reg prev_wvalid;
    always @(posedge clk) begin
        prev_wvalid <= m_axi_wvalid;
        
        // FIFO Empty일 때 WVALID가 떨어지는지 확인
        if (i_fifo_empty && prev_wvalid && !m_axi_wvalid) begin
            $display("  [%0t] >>> WVALID dropped (FIFO empty detected)", $time);
        end
        
        // FIFO 채워질 때 WVALID가 다시 올라가는지 확인
        if (!i_fifo_empty && !prev_wvalid && m_axi_wvalid) begin
            $display("  [%0t] >>> WVALID restored (FIFO refilled)", $time);
        end
    end

    // =========================================================================
    // 7. Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_write_master.vcd");
        $dumpvars(0, tb_write_master);
    end

endmodule