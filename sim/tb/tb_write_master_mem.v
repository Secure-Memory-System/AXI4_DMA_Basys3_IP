`timescale 1ns / 1ps

////////////////////////////////////////////////////////////////////////////////
// Write Master File I/O Testbench
// Flow: input_mem.mem -> FIFO Model -> Write Master -> AXI Slave -> output.txt
////////////////////////////////////////////////////////////////////////////////

module tb_write_master_mem();

    // =========================================================================
    // 1. Signals & Setup
    // =========================================================================
    reg clk;
    reg reset_n;
    integer file_handle; // 결과 저장을 위한 파일 핸들
    
    always #5 clk = ~clk; // 100MHz Clock
    
    // Control Signals
    reg i_start;
    reg [31:0] i_dst_addr;
    reg [31:0] i_total_len;
    wire o_write_done;
    
    // FIFO Interface
    wire i_fifo_empty;
    wire o_fifo_rd_en;
    wire [31:0] i_w_data;
    
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
    // 3. FIFO Model with File Loading
    // =========================================================================
    reg [31:0] fifo_mem [0:16383]; // 64KB Buffer
    integer rd_ptr;
    integer data_count; // 파일에서 읽은 데이터 총 개수 (보통 16384)
    
    initial begin
        // 메모리 초기화
        rd_ptr = 0;
        data_count = 16384; // 64KB (32bit * 16384)
        
        // [핵심] input_mem.mem 파일 로드
        $readmemh("input_mem.mem", fifo_mem);
        #10;
        $display("[INFO] FIFO Memory Loaded from input_mem.mem");
    end

    // FIFO Logic
    // 데이터는 현재 포인터가 가리키는 값을 바로 출력 (FWFT 방식 가정)
    assign i_w_data = fifo_mem[rd_ptr];
    
    // 포인터가 끝까지 가면 Empty 상태
    assign i_fifo_empty = (rd_ptr >= data_count);
    
    // DUT가 읽어가면 포인터 증가
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rd_ptr <= 0;
        end else begin
            if (o_fifo_rd_en && !i_fifo_empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

    // =========================================================================
    // 4. AXI Slave Simulation (The Sink)
    // =========================================================================
    // AW Channel: 항상 준비
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) m_axi_awready <= 0;
        else m_axi_awready <= 1; // Always Ready
    end
    
    // W Channel: 항상 준비 (여기서 파일 쓰기 수행)
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) m_axi_wready <= 0;
        else m_axi_wready <= 1; // Always Ready
    end

    // B Channel: WLAST 받으면 응답
    reg b_pend;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            m_axi_bvalid <= 0;
            m_axi_bresp <= 0;
            b_pend <= 0;
        end else begin
            if (m_axi_wlast && m_axi_wvalid && m_axi_wready) b_pend <= 1;
            
            if (b_pend) begin
                m_axi_bvalid <= 1;
                b_pend <= 0;
            end else if (m_axi_bready) begin
                m_axi_bvalid <= 0;
            end
        end
    end

    // =========================================================================
    // 5. File Output Logic (Data Logger)
    // =========================================================================
    always @(posedge clk) begin
        // W 채널에서 유효한 데이터 전송이 일어날 때마다 파일에 기록
        if (m_axi_wvalid && m_axi_wready) begin
            // Hex 포맷으로 데이터만 저장 (input_mem.mem과 비교 용이)
            $fdisplay(file_handle, "%h", m_axi_wdata);
            
            // (디버깅용 화면 출력 - 필요시 주석 해제)
            // $display("Write Data: %h", m_axi_wdata);
        end
    end

    // =========================================================================
    // 6. Test Execution
    // =========================================================================
    initial begin
        // 파일 열기
        file_handle = $fopen("output_write_dump.txt", "w");
        if (file_handle == 0) begin
            $display("Error: Failed to open output_write_dump.txt");
            $finish;
        end

        // 초기화
        clk = 0;
        reset_n = 0;
        i_start = 0;
        i_dst_addr = 0;
        i_total_len = 0;
        
        #50;
        reset_n = 1;
        #20;
        
        $display("========================================");
        $display(" Start Write Master File Dump Test");
        $display("========================================");
        
        // -----------------------------------------------------------
        // 64KB 전체 전송 시작
        // -----------------------------------------------------------
        i_dst_addr = 32'hC000_0000; // Destination Base Address
        i_total_len = 32'd65536;    // 64KB (Total Transfer Size)
        i_start = 1;
        #10;
        i_start = 0;
        
        // 완료 대기
        wait(o_write_done);
        
        #100;
        $display("========================================");
        $display(" Write Completed. Check 'output_write_dump.txt'");
        $display("========================================");
        
        $fclose(file_handle);
        $finish;
    end

endmodule