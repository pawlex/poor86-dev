module i486_biu (
    input  logic        clk,
    input  logic        rst_n,

    // --- CPU Core Interface ---
    input  logic        core_req,       // CPU requests transaction (ADS# equivalent)
    input  logic        core_write,     // 1 = Write, 0 = Read
    input  logic        core_m_io,      // 1 = I/O space, 0 = Memory space
    input  logic [31:0] core_addr,      // CPU address bus
    input  logic [31:0] core_wdata,     // CPU write data
    input  logic [3:0]  core_be,        // Byte enables ([3:0])
    output logic [31:0] core_rdata,     // CPU read data
    output logic        core_ready,     // CPU ready / cycle complete (BRDY# equivalent)

    // --- Cache Controller Interface (For Cacheable Memory) ---
    output logic        cache_req,
    output logic        cache_write,
    output logic [31:0] cache_addr,
    output logic [31:0] cache_wdata,
    output logic [3:0]  cache_be,
    input  logic [31:0] cache_rdata,
    input  logic        cache_ready,

    // --- System Uncached / MMIO / I/O Bus Interface ---
    output logic        sys_req,
    output logic        sys_write,
    output logic        sys_m_io,       // 1 = I/O, 0 = Memory-Mapped IO
    output logic [31:0] sys_addr,
    output logic [31:0] sys_wdata,
    output logic [3:0]  sys_be,
    input  logic [31:0] sys_rdata,
    input  logic        sys_ready,

    // --- Cache Coherency / DMA Snoop Interface ---
    input  logic        snoop_req,      // External DMA write request
    input  logic [31:0] snoop_addr,     // DMA address being modified
    output logic        snoop_hit_out   // Signals cache controller to invalidate line
);

    // -------------------------------------------------------------------------
    // Address Decoding & Region Routing
    // -------------------------------------------------------------------------
    // Define memory boundaries (e.g., RAM below 16MB is cacheable, above is MMIO)
    // I/O space is completely separated by core_m_io == 1'b1
    logic is_cacheable_mem;
    
    always_comb begin
        if (core_m_io) begin
            is_cacheable_mem = 1'b0; // I/O space is never cached
        end else begin
            // Example map: Lower 16MB (0x0000_0000 to 0x00FF_FFFF) is cacheable RAM.
            // Addresses >= 0x0100_0000 are treated as Uncacheable MMIO (e.g., framebuffers, MMIO registers).
            is_cacheable_mem = (core_addr < 32'h0100_0000);
        end
    end

    // -------------------------------------------------------------------------
    // Posted Write Buffer (Decouples CPU writes from slow bus/cache latency)
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic        valid;
        logic        m_io;
        logic        cacheable;
        logic [31:0] addr;
        logic [31:0] wdata;
        logic [3:0]  be;
    } write_buf_t;

    write_buf_t write_buffer;
    logic       write_buf_full;

    assign write_buf_full = write_buffer.valid;

    // -------------------------------------------------------------------------
    // BIU Control State Machine & Arbitration
    // -------------------------------------------------------------------------
    typedef enum logic [1:0] {
        BIU_IDLE        = 2'b00,
        BIU_CACHE_WAIT  = 2'b01,
        BIU_SYS_WAIT    = 2'b10
    } biu_state_t;

    biu_state_t state;

    // Internal routing wires
    logic cache_req_int, sys_req_int;
    
    always_comb begin
        cache_req   = 1'b0;
        sys_req     = 1'b0;
        cache_write = core_write;
        sys_write   = core_write;
        cache_addr  = core_addr;
        sys_addr    = core_addr;
        cache_wdata = core_wdata;
        sys_wdata   = core_wdata;
        cache_be    = core_be;
        sys_be      = core_be;
        sys_m_io    = core_m_io;

        // Default ready handling
        core_ready  = 1'b0;
        core_rdata  = 32'h0;

        // Route based on state and current transaction type
        case (state)
            BIU_IDLE: begin
                if (core_req) begin
                    if (core_write) begin
                        // Posted Write Handling: If it's a write, we can absorb it 
                        // into the write buffer instantly for high performance.
                        // Reads are strictly non-posted and must wait.
                    end else begin
                        // Read Transaction (Non-Posted)
                        if (is_cacheable_mem) begin
                            cache_req = 1'b1;
                            core_rdata = cache_rdata;
                            core_ready = cache_ready;
                        end else begin
                            sys_req = 1'b1;
                            core_rdata = sys_rdata;
                            core_ready = sys_ready;
                        end
                    end
                end else if (write_buffer.valid) begin
                    // Drain posted write buffer when bus is free
                    if (write_buffer.cacheable) begin
                        cache_req   = 1'b1;
                        cache_write = 1'b1;
                        cache_addr  = write_buffer.addr;
                        cache_wdata = write_buffer.wdata;
                        cache_be    = write_buffer.be;
                    end else begin
                        sys_req     = 1'b1;
                        sys_write   = 1'b1;
                        sys_m_io    = write_buffer.m_io;
                        sys_addr    = write_buffer.addr;
                        sys_wdata   = write_buffer.wdata;
                        sys_be      = write_buffer.be;
                    end
                end
            end

            BIU_CACHE_WAIT: begin
                cache_req  = 1'b1;
                core_rdata = cache_rdata;
                core_ready = cache_ready;
            end

            BIU_SYS_WAIT: begin
                sys_req    = 1'b1;
                core_rdata = sys_rdata;
                core_ready = sys_ready;
            end
        endcase
    end

    // Sequential State & Buffer Updates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= BIU_IDLE;
            write_buffer.valid <= 1'b0;
            snoop_hit_out <= 1'b0;
        end else begin
            snoop_hit_out <= snoop_req; // Forward external DMA snoop/invalidate pulses

            case (state)
                BIU_IDLE: begin
                    if (core_req) begin
                        if (core_write) begin
                            // Accept write into posted write buffer instantly
                            write_buffer.valid     <= 1'b1;
                            write_buffer.m_io      <= core_m_io;
                            write_buffer.cacheable <= is_cacheable_mem;
                            write_buffer.addr      <= core_addr;
                            write_buffer.wdata     <= core_wdata;
                            write_buffer.be        <= core_be;
                            core_ready             <= 1'b1; // Posted write completes immediately to CPU
                        end else begin
                            // Non-posted read transaction
                            if (is_cacheable_mem) begin
                                if (!cache_ready) state <= BIU_CACHE_WAIT;
                            end else begin
                                if (!sys_ready) state <= BIU_SYS_WAIT;
                            end
                        end
                    end else if (write_buffer.valid) begin
                        // Check if buffer write completed
                        if (write_buffer.cacheable && cache_ready) begin
                            write_buffer.valid <= 1'b0;
                        end else if (!write_buffer.cacheable && sys_ready) begin
                            write_buffer.valid <= 1'b0;
                        end
                    end
                end

                BIU_CACHE_WAIT: begin
                    if (cache_ready) state <= BIU_IDLE;
                end

                BIU_SYS_WAIT: begin
                    if (sys_ready) state <= BIU_IDLE;
                end
            endcase
        end
    end

endmodule