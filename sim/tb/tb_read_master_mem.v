`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Vivado-compatible AXI4 Read Master Testbench (Full Dump Version)
// Goal: Read 64KB from "input_mem.mem" and save to "output_full_dump.txt"
////////////////////////////////////////////////////////////////////////////////

module tb_read_master_mem();

    // =========================================================================
    // 1. Signals & Variables
    // =========================================================================
    reg clk;
    reg reset_n;
    integer file_handle; // 결과 파일
    
    always #5 clk = ~clk; // 100MHz Clock
    
    // DUT Control Signals
    reg i_start;
    reg [31:0] i_src_addr;
    reg [31:0] i_total_len;
    wire o_read_done;
    
    // FIFO Interface (항상 받을 준비가 되어 있다고 가정)
    reg i_fifo_full;
    wire o_fifo_push;
    wire [31:0] o_r_data;
    
    // AXI Interface
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
    // 2. DUT Instantiation
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
        .i_fifo_full(i_fifo_full), // Backpressure 없이 0으로 고정 예정
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
    // 3. Memory Model (64KB) & Initialization
    // =========================================================================
    reg [31:0] bram0 [0:16383]; // 64KB (16384 words)
    parameter BRAM0_BASE = 32'hC000_0000;
    
    initial begin
        for (integer i = 0; i < 16384; i = i + 1) begin
            bram0[i] = 32'hC000_0000;
        end

        // 2. input_mem.mem 파일 로드
        // 파일이 시뮬레이션 디렉토리에 있어야 합니다.
        $readmemh("input_mem.mem", bram0);
        
        #10;
        $display("[INFO] Memory Loaded. Ready to dump.");
    end
    
    // =========================================================================
    // 4. AXI Slave Simulation Logic (Simple & Fast)
    // =========================================================================
    // AR Channel
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) m_axi_arready <= 0;
        else begin
            // 요청이 오면 1클럭 뒤에 바로 Ready (빠른 전송)
            if (m_axi_arvalid && !m_axi_arready) m_axi_arready <= 1;
            else m_axi_arready <= 0;
        end
    end
    
    // R Channel (AR 정보를 기반으로 데이터 전송)
    reg [31:0] r_addr_latch;
    reg [7:0]  r_len_latch;
    reg        r_active;
    reg [7:0]  r_cnt;
    
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_rvalid <= 0;
            m_axi_rlast <= 0;
            m_axi_rdata <= 0;
            r_active <= 0;
            r_cnt <= 0;
        end else begin
            // 1. 주소 래치 (AR Handshake)
            if (m_axi_arvalid && m_axi_arready) begin
                r_addr_latch <= m_axi_araddr;
                r_len_latch <= m_axi_arlen;
                r_active <= 1;
                r_cnt <= 0;
            end
            
            // 2. 데이터 전송 (Data Phase)
            if (r_active) begin
                if (!m_axi_rvalid || (m_axi_rvalid && m_axi_rready)) begin
                    m_axi_rvalid <= 1;
                    
                    // 메모리 읽기 (주소 계산)
                    m_axi_rdata <= bram0[(r_addr_latch - BRAM0_BASE)/4 + r_cnt];
                    
                    // Last 신호 처리
                    if (r_cnt == r_len_latch) begin
                        m_axi_rlast <= 1;
                        r_active <= 0; // 전송 끝
                    end else begin
                        m_axi_rlast <= 0;
                        r_cnt <= r_cnt + 1;
                    end
                end
            end else if (m_axi_rvalid && m_axi_rready) begin
                // 전송이 끝난 후 Valid 내림
                m_axi_rvalid <= 0;
                m_axi_rlast <= 0;
            end
        end
    end

    // =========================================================================
    // 5. Main Execution Block (Whole Read)
    // =========================================================================
    initial begin
        // 파일 열기
        file_handle = $fopen("output_full_dump.txt", "w");
        if (file_handle == 0) begin
            $display("Error: Failed to open output_full_dump.txt");
            $finish;
        end
        
        $display("==================================================");
        $display(" Start Full Memory Dump (64KB)");
        $display("==================================================");

        // 초기화
        clk = 0;
        reset_n = 0;
        i_start = 0;
        i_src_addr = 0;
        i_total_len = 0;
        i_fifo_full = 0; // FIFO는 항상 비어있다고 가정 (무한 흡입)
        
        #50;
        reset_n = 1;
        #20;
        
        // -------------------------------------------------------------
        // [명령] 64KB 전체 읽기
        // -------------------------------------------------------------
        i_src_addr = BRAM0_BASE;    // 0x00004000
        i_total_len = 32'd65536;    // 64KB (전체 용량)
        i_start = 1;
        #10;
        i_start = 0;
        
        // -------------------------------------------------------------
        // [대기] 다 읽을 때까지 기다림 (약 1ms 시뮬레이션 시간 소요 예상)
        // -------------------------------------------------------------
        wait(o_read_done);
        
        #100;
        $display("==================================================");
        $display(" Dump Completed. Closing File.");
        $display("==================================================");
        
        $fclose(file_handle);
        $finish;
    end
    
    // =========================================================================
    // 6. Data Logger (파일 저장)
    // =========================================================================
    always @(posedge clk) begin
        // 유효한 데이터가 나갈 때마다 파일에 기록
        if (m_axi_rvalid && m_axi_rready) begin
            // 텍스트 파일에 16진수 데이터만 깔끔하게 저장 (Data Only)
            // 예: AABBCCDD
            $fdisplay(file_handle, "%h", m_axi_rdata);
            
            // 만약 주소도 같이 보고 싶다면 아래 주석을 해제하고 위를 주석 처리하세요.
            // $fdisplay(file_handle, "Data: %h (Last: %b)", m_axi_rdata, m_axi_rlast);
        end
    end

endmodule