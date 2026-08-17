// ============================================================================
// NOTE — this sketch predates the memory architecture now decided.
// See docs/PLAN_OF_RECORD.md. Two things changed underneath it:
//
//   * MAIN MEMORY IS SDRAM, not serial PSRAM. 16-bit at CPUCLK x2
//     (66.67 MHz), CL2, two ranks via CS#[1:0]. The downstream port below
//     still models a PSRAM line-streaming interface.
//   * QSPI PSRAM IS VIDEO-ONLY now, on its own buses, and never carries
//     CPU traffic. The two masters were separated precisely so this
//     controller could stay single-master.
//
// The cache structure above the memory port is unaffected by either.
// ============================================================================
module ecp5_cache_subsystem (
    input  logic        clk,
    input  logic        rst_n,

    // Upstream 486 CPU Interface
    input  logic        cpu_req,
    input  logic        cpu_write,
    input  logic [31:0] cpu_addr,
    input  logic [31:0] cpu_wdata,
    // OPEN: no byte-enable input exists here, so this interface cannot
    // express a partial write at all -- the question below is currently
    // answered by omission. A 486 drives BE0-3 and writes 1, 2, 3 or 4
    // bytes; something must carry that. Add `input logic [3:0] cpu_be`.
    output logic [31:0] cpu_rdata,
    output logic        cpu_done,

    // ------------------------------------------------------------------
    // OPEN -- MASKED WRITES, OR FULL-LINE WRITES WITH READ-FILL?
    //
    // Does this controller honour byte enables on the way out, or does it
    // only ever write whole lines -- making every partial write a
    // READ-MODIFY-WRITE?
    //
    //   cost of RMW : a full read before the write, tRCD + CL ~= 60 ns at
    //                 66 MHz, against a 30 ns CPU cycle. Two CPU cycles
    //                 spent on a byte write, on the latency-critical path.
    //   cost of DQM : nothing. The two pins are already budgeted and
    //                 SDRAM masks natively.
    //
    // 32->16 MAPPING IS CLEAN: a 32-bit CPU write is two 16-bit SDRAM
    // cycles, so BE0/BE1 become the first cycle's DQM[1:0] and BE2/BE3 the
    // second. No encoding problem.
    //
    // COUPLED TO CACHE POLICY, AND POSSIBLY MOOT: with write-back plus
    // write-allocate, partial writes land in the cache and lines are
    // written back whole, so DQM is barely exercised. With write-through,
    // no-allocate, or any uncached region, partial writes reach memory
    // directly and masking is essential. DECIDE THE CACHE POLICY FIRST --
    // this follows from it, not the other way round.
    //
    // NOT A QUESTION FOR THE VIDEO PATH: QSPI PSRAM is byte-addressable,
    // so the write-combining buffer flushes only its dirty bytes with
    // neither masking nor RMW. Do not generalise the answer here onto it.
    // ------------------------------------------------------------------

    // Downstream Serial PSRAM Streaming Interface
    output logic        psram_req,
    output logic [31:0] psram_addr,
    input  logic        psram_ack,
    input  logic [127:0] psram_rdata_line,
    input  logic        psram_data_valid
);

    // -------------------------------------------------------------------------
    // Parameters & Address Parsing
    // -------------------------------------------------------------------------
    localparam int SETS      = 256;
    localparam int WAYS      = 4;
    localparam int LINE_B    = 16;  // 16-byte lines
    localparam int INDEX_W   = 8;   // $clog2(256)
    localparam int TAG_W     = 32 - INDEX_W - 4; // 20 bits

    wire [3:0]            offset = cpu_addr[3:0];
    wire [INDEX_W-1:0]    index  = cpu_addr[INDEX_W+3 : 4];
    wire [TAG_W-1:0]      tag    = cpu_addr[31 : INDEX_W+4];

    // -------------------------------------------------------------------------
    // Tier 1: 4-Way Set-Associative L2 Cache Arrays (Inferred ECP5 BRAMs)
    // -------------------------------------------------------------------------
    // Yosys automatically infers DP16KD EBR blocks for these 2D arrays
    logic [127:0] l2_data_mem [0:WAYS-1][0:SETS-1];
    logic [TAG_W-1:0] l2_tag_mem  [0:WAYS-1][0:SETS-1];
    logic             l2_valid    [0:WAYS-1][0:SETS-1];
    logic             l2_dirty    [0:WAYS-1][0:SETS-1];
    logic [1:0]       l2_plru     [0:SETS-1]; // Binary tree / pseudo-LRU bits for 4 ways

    // Parallel Tag and Hit Evaluation
    logic [WAYS-1:0] hit_vec;
    logic            cache_hit;
    logic [1:0]      hit_way;
    logic [127:0]    hit_data;

    always_comb begin
        hit_vec   = '0;
        cache_hit = 1'b0;
        hit_way   = 2'd0;
        hit_data  = '0;

        for (int w = 0; w < WAYS; w++) begin
            if (l2_valid[w][index] && (l2_tag_mem[w][index] == tag)) begin
                hit_vec[w] = 1'b1;
                cache_hit  = 1'b1;
                hit_way    = w[1:0];
                hit_data   = l2_data_mem[w][index];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Tier 2: 3-Stream Prefetch Buffer (Packed into 1 ECP5 EBR Block)
    // -------------------------------------------------------------------------
    // 3 streams, each holding 16 lines of 16 bytes = 256 bytes per stream (total 768 bytes)
    logic [127:0] stream_mem [0:2][0:15]; 
    logic [25:0]  stream_tag [0:2];       // Tracks upper address bits [31:6]
    logic [3:0]   stream_head[0:2];       // Head pointer for circular buffer
    logic         stream_active[0:2];
    logic [1:0]   stream_lro;             // Least Recently Oldest replacement tracker

    // Check if CPU request hits any of the 3 active prefetch streams
    logic         stream_hit;
    logic [1:0]   stream_hit_id;
    logic [127:0] stream_hit_data;

    always_comb begin
        stream_hit      = 1'b0;
        stream_hit_id   = 2'd0;
        stream_hit_data = '0;

        for (int s = 0; s < 3; s++) begin
            if (stream_active[s] && (stream_tag[s] == cpu_addr[31:6])) begin
                stream_hit    = 1'b1;
                stream_hit_id = s[1:0];
                // Read corresponding line from circular buffer using lower address bits [5:4]
                stream_hit_data = stream_mem[s][cpu_addr[5:4] + stream_head[s]];
            end
        end
    end

    // -------------------------------------------------------------------------
    // FSM Control State Machine & Pipeline
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE        = 3'b000,
        ALLOCATE    = 3'b001, // Pumping stream data into L2 cache
        PSRAM_WAIT  = 3'b010, // Waiting for serial PSRAM burst response
        EVICT       = 3'b011  // Flushing dirty L2 line
    } state_t;

    state_t state, next_state;
    logic [1:0] victim_way;

    // Select victim way using PLRU bits on a miss
    always_comb begin
        // Simple PLRU extraction for 4 ways
        case (l2_plru[index])
            2'b00:   victim_way = 2'd0;
            2'b01:   victim_way = 2'd1;
            2'b10:   victim_way = 2'd2;
            default: victim_way = 2'd3;
        endcase
    end

    // Sequential Logic & RAM Updates
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            cpu_done <= 1'b0;
            cpu_rdata <= '0;
            psram_req <= 1'b0;
            psram_addr <= '0;
            for(int s=0; s<3; s++) begin
                stream_active[s] <= 1'b0;
                stream_tag[s] <= '0;
                stream_head[s] <= '0;
            end
            for(int s=0; s<SETS; s++) l2_plru[s] <= '0;
            for(int w=0; w<WAYS; w++) begin
                for(int s=0; s<SETS; s++) begin
                    l2_valid[w][s] <= 1'b0;
                    l2_dirty[w][s] <= 1'b0;
                end
            end
        end else begin
            // Default completion pulse drop
            cpu_done <= 1'b0;
            psram_req <= 1'b0;

            case (state)
                IDLE: begin
                    if (cpu_req) begin
                        if (cache_hit) begin
                            // L2 Hit: Serve CPU instantly (0 wait states)
                            cpu_done <= 1'b1;
                            case (cpu_addr[3:2])
                                2'b00: cpu_rdata <= hit_data[31:0];
                                2'b01: cpu_rdata <= hit_data[63:32];
                                2'b10: cpu_rdata <= hit_data[95:64];
                                2'b11: cpu_rdata <= hit_data[127:96];
                            endcase

                            if (cpu_write) begin
                                l2_dirty[hit_way][index] <= 1'b1;
                                case (cpu_addr[3:2])
                                    2'b00: l2_data_mem[hit_way][index][31:0]   <= cpu_wdata;
                                    2'b01: l2_data_mem[hit_way][index][63:32]  <= cpu_wdata;
                                    2'b10: l2_data_mem[hit_way][index][95:64]  <= cpu_wdata;
                                    2'b11: l2_data_mem[hit_way][index][127:96] <= cpu_wdata;
                                endcase
                            end
                            // Update PLRU bits
                            l2_plru[index] <= hit_way;

                        end else if (stream_hit) begin
                            // Stream Hit: Rescue data from the internal prefetch buffer, allocate into L2
                            cpu_done <= 1'b1;
                            case (cpu_addr[3:2])
                                2'b00: cpu_rdata <= stream_hit_data[31:0];
                                2'b01: cpu_rdata <= stream_hit_data[63:32];
                                2'b10: cpu_rdata <= stream_hit_data[95:64];
                                2'b11: cpu_rdata <= stream_hit_data[127:96];
                            endcase

                            // Allocate into L2 Victim Way
                            l2_valid[victim_way][index] <= 1'b1;
                            l2_tag_mem[victim_way][index] <= tag;
                            l2_dirty[victim_way][index] <= cpu_write;
                            l2_data_mem[victim_way][index] <= stream_hit_data;

                        end else begin
                            // Stream & L2 Miss: Must request burst from serial PSRAM
                            psram_req <= 1'b1;
                            psram_addr <= {cpu_addr[31:6], 6'h0}; // Align to 64-byte block
                            state <= PSRAM_WAIT;
                        end
                    end
                end

                PSRAM_WAIT: begin
                    // Wait for serial PSRAM controller to fetch the block
                    psram_req <= 1'b1;
                    if (psram_ack && psram_data_valid) begin
                        // Load data into the LRO stream buffer and forward to L2
                        // (Stream ID chosen via stream_lro pointer)
                        stream_active[stream_lro] <= 1'b1;
                        stream_tag[stream_lro]    <= cpu_addr[31:6];
                        stream_head[stream_lro]   <= '0;
                        stream_mem[stream_lro][0] <= psram_rdata_line; // Load line into stream

                        // Fulfill CPU request immediately
                        cpu_done <= 1'b1;
                        case (cpu_addr[3:2])
                            2'b00: cpu_rdata <= psram_rdata_line[31:0];
                            2'b01: cpu_rdata <= psram_rdata_line[63:32];
                            2'b10: cpu_rdata <= psram_rdata_line[95:64];
                            2'b11: cpu_rdata <= psram_rdata_line[127:96];
                        endcase

                        // Allocate into L2
                        l2_valid[victim_way][index]   <= 1'b1;
                        l2_tag_mem[victim_way][index] <= tag;
                        l2_dirty[victim_way][index]   <= cpu_write;
                        l2_data_mem[victim_way][index]<= psram_rdata_line;

                        // Rotate LRO stream pointer
                        stream_lro <= stream_lro + 2'd1;
                        state      <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule