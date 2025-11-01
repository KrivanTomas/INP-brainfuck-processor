-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2025 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Tomáš Křivan <xkrivat00 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is
    -- finite state machine
    type fsm_state is (
        RST, INIT, INIT_FIX, FETCH1, FETCH2, HALT, NOP, RIGHT, LEFT, ADD1, ADD2, SUB1, SUB2,
        WRITE1, WRITE2, WRITE_BUSY, READ, READ_END, IMM, ZERO,
        START_WHILE, END_WHILE, W_CHK, EW_CHK, W_IN, 
        W_SKIP, WS_INC, WS_DEC, WS_CHK, WS_END,
        W_BACK, WB_INC, WB_DEC, WB_CHK, WB_CONTINUE1, WB_CONTINUE2, W_OUT1, W_OUT2,
        START_DO_WHILE, END_DO_WHILE, EDW_CHK,
        DW_BACK, DWB_INC, DWB_DEC, DWB_CHK, DWB_CONTINUE1, DWB_CONTINUE2, DW_OUT1, DW_OUT2
    );
    signal state : fsm_state := RST;
    signal next_state : fsm_state := RST;
    signal instr : fsm_state := NOP;

    -- program counter
    signal pc_reg : std_logic_vector(12 downto 0);
    signal pc_inc : std_logic;
    signal pc_dec : std_logic;

    -- pointer counter
    signal ptr_reg : std_logic_vector(12 downto 0);
    signal ptr_inc : std_logic;
    signal ptr_dec : std_logic;
    signal ptr_rst : std_logic;

    -- loop counter
    signal loop_reg : std_logic_vector(12 downto 0);
    signal loop_inc : std_logic;
    signal loop_dec : std_logic;

    -- loop comparator
    signal loop_cmp : std_logic;

    -- address multiplexor (mx1)
    signal addr_sel : std_logic;

    -- data multiplexor (mx2)
    signal data_sel : std_logic_vector(1 downto 0);

    -- ALU? parts
    signal read_imm : std_logic_vector(7 downto 0);
    signal read_dec : std_logic_vector(7 downto 0);
    signal read_inc : std_logic_vector(7 downto 0);
begin


 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze 
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a 
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly. 
    
    fsm_output : process(state)
    begin
        READY <= '1'; -- casteji true
        DONE <= '0';
        DATA_EN <= '0';
        DATA_RDWR <= '0';
        IN_REQ <= '0';
        OUT_WE <= '0';
        OUT_INV <= '0';
        pc_inc <= '0';
        pc_dec <= '0';
        ptr_inc <= '0';
        ptr_dec <= '0';
        ptr_rst <= '0';
        loop_inc <= '0';
        loop_dec <= '0';
        addr_sel <= '0';
        data_sel <= "00";

        case state is
            when RST =>
                ptr_rst <= '1';
                READY <= '0';
            when INIT =>
                ptr_inc <= '1';
                READY <= '0';
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when INIT_FIX =>
                ptr_dec <= '1';
            when FETCH1 =>
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when FETCH2 =>
                pc_inc <= '0';
            when HALT =>
                DONE <= '1';
            when RIGHT =>
                pc_inc <= '1';
                ptr_inc <= '1';
            when LEFT =>
                pc_inc <= '1';
                ptr_dec <= '1';
            when ADD1 =>
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when ADD2 =>
                pc_inc <= '1';
                DATA_RDWR <= '0';
                addr_sel <= '0';
                data_sel <= "11";
                DATA_EN <= '1';
            when SUB1 =>
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when SUB2 =>
                pc_inc <= '1';
                DATA_RDWR <= '0';
                addr_sel <= '0';
                data_sel <= "10";
                DATA_EN <= '1';
            when READ =>
                IN_REQ <= '1';
            when READ_END =>
                IN_REQ <= '1';
                DATA_RDWR <= '0';
                addr_sel <= '0';
                data_sel <= "00";
                DATA_EN <= '1';
                pc_inc <= '1';
            when WRITE1 =>
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when WRITE_BUSY =>
                OUT_INV <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when WRITE2 =>
                pc_inc <= '1';
                OUT_WE <= '1';
            when IMM =>
                pc_inc <= '1';
                DATA_RDWR <= '0';
                addr_sel <= '0';
                data_sel <= "01";
                DATA_EN <= '1';
            when START_WHILE =>
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when W_CHK =>
                pc_inc <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when W_SKIP =>
                pc_inc <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when WS_INC =>
                loop_inc <= '1';
            when WS_DEC =>
                loop_dec <= '1';
            when WS_CHK =>
                pc_inc <= '0';
            when WS_END =>
                pc_dec <= '1';
            when END_WHILE =>
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when EW_CHK => 
                pc_dec <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when W_BACK =>
                pc_dec <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when WB_INC =>
                loop_inc <= '1';
            when WB_DEC =>
                loop_dec <= '1';
            when WB_CHK =>
                pc_inc <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';



            when END_DO_WHILE =>
                DATA_RDWR <= '1';
                addr_sel <= '0';
                DATA_EN <= '1';
            when EDW_CHK => 
                pc_dec <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when DW_BACK =>
                pc_dec <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
            when DWB_INC =>
                loop_inc <= '1';
            when DWB_DEC =>
                loop_dec <= '1';
            when DWB_CHK =>
                pc_inc <= '1';
                DATA_RDWR <= '1';
                addr_sel <= '1';
                DATA_EN <= '1';
        
                

            when others =>
                READY <= '1';
                pc_inc <= '1';
        end case;
        
    end process;

    fsm_register : process(CLK, RESET)
    begin
        if(RESET='1') then
            state <= RST;
        elsif rising_edge(CLK) then
            if(EN='1') then
                state <= next_state;
            end if;
        end if;
    end process;

    fsm_next_state_logic : process(state, instr, IN_VLD, OUT_BUSY, loop_cmp)
    begin
        case state is
            when RST =>
                next_state <= INIT;
            when INIT =>
                next_state <= INIT;
                if(instr=HALT) then
                    next_state <= INIT_FIX;    
                end if;
            when INIT_FIX =>
                next_state <= FETCH1;
            when HALT =>
                next_state <= HALT;
            when FETCH1 => 
                next_state <= FETCH2;
            when FETCH2 => 
                next_state <= instr;
            when ADD1 =>
                next_state <= ADD2;
            when SUB1 =>
                next_state <= SUB2;
            when READ =>
                next_state <= READ;
                if(IN_VLD='1') then
                    next_state <= READ_END;
                end if;
            when WRITE1 =>
                next_state <= WRITE1;
                if(OUT_BUSY='0') then
                    next_state <= WRITE2;
                else 
                    next_state <= WRITE_BUSY;
                end if;
            when WRITE_BUSY =>
                next_state <= WRITE_BUSY;
                if(OUT_BUSY='0') then
                    next_state <= WRITE2;
                end if;     

            when START_WHILE =>
                next_state <= W_CHK;
            when W_CHK =>
                next_state <= FETCH1;
                if(instr=ZERO) then
                    next_state <= W_SKIP;
                end if;
            when W_SKIP =>
                next_state <= W_SKIP;
                if(instr=START_WHILE) then
                    next_state <= WS_INC;
                elsif(instr=END_WHILE) then
                    next_state <= WS_DEC;
                end if;
            when WS_INC =>
                next_state <= W_SKIP;
            when WS_DEC =>
                next_state <= WS_CHK;
            when WS_CHK =>
                next_state <= W_SKIP;
                if(loop_cmp='1') then
                    next_state <= WS_END;
                end if;

            when END_WHILE =>
                next_state <= EW_CHK;
            when EW_CHK =>
                next_state <= W_OUT1;
                if(instr/=ZERO) then
                    next_state <= W_BACK;
                end if;
            when W_BACK =>
                next_state <= W_BACK;
                if(instr=END_WHILE) then
                    next_state <= WB_INC;
                elsif(instr=START_WHILE) then
                    next_state <= WB_DEC;
                end if;
            when WB_INC =>
                next_state <= W_BACK;
            when WB_DEC =>
                next_state <= WB_CHK;
            when WB_CHK =>
                next_state <= W_BACK;
                if(loop_cmp='1') then
                    next_state <= WB_CONTINUE1;
                end if;
            when WB_CONTINUE1 =>
                next_state <= WB_CONTINUE2;
            when W_OUT1 =>
                next_state <= W_OUT2;

            when END_DO_WHILE =>
                next_state <= EDW_CHK;
            when EDW_CHK =>
                next_state <= DW_OUT1;
                if(instr/=ZERO) then
                    next_state <= DW_BACK;
                end if;
            when DW_BACK =>
                next_state <= DW_BACK;
                if(instr=END_DO_WHILE) then
                    next_state <= DWB_INC;
                elsif(instr=START_DO_WHILE) then
                    next_state <= DWB_DEC;
                end if;
            when DWB_INC =>
                next_state <= DW_BACK;
            when DWB_DEC =>
                next_state <= DWB_CHK;
            when DWB_CHK =>
                next_state <= DW_BACK;
                if(loop_cmp='1') then
                    next_state <= DWB_CONTINUE1;
                end if;
            when DWB_CONTINUE1 =>
                next_state <= DWB_CONTINUE2;
            when DW_OUT1 =>
                next_state <= DW_OUT2;

            when others =>
                next_state <= FETCH1;
        end case;
    end process;
        

    addr_mux : process(addr_sel, ptr_reg, pc_reg)
    begin
        case addr_sel is
            when '0' =>
                DATA_ADDR <= ptr_reg;
            when '1' =>
                DATA_ADDR <= pc_reg;
            when others =>
                DATA_ADDR <= (others=>'0');
        end case;
    end process;

    data_mux : process(data_sel, IN_DATA, read_dec, read_inc, read_imm)
    begin
        case data_sel is
            when "00" =>
                DATA_WDATA <= IN_DATA;
            when "01" =>
                DATA_WDATA <= read_imm;
            when "10" =>
                DATA_WDATA <= read_dec;
            when "11" =>
                DATA_WDATA <= read_inc;
            when others =>
                DATA_WDATA <= (others=>'0');
        end case;
    end process;

    alu_imm : process(DATA_RDATA)
    begin
        case DATA_RDATA is
            when x"30" =>
                read_imm <= x"00";
            when x"31" =>
                read_imm <= x"10";
            when x"32" =>
                read_imm <= x"20";
            when x"33" =>
                read_imm <= x"30";
            when x"34" =>
                read_imm <= x"40";
            when x"35" =>
                read_imm <= x"50";
            when x"36" =>
                read_imm <= x"60";
            when x"37" =>
                read_imm <= x"70";
            when x"38" =>
                read_imm <= x"80";
            when x"39" =>
                read_imm <= x"90";
            when x"41" =>
                read_imm <= x"A0";
            when x"42" =>
                read_imm <= x"B0";
            when x"43" =>
                read_imm <= x"C0";
            when x"44" =>
                read_imm <= x"D0";
            when x"45" =>
                read_imm <= x"E0";
            when x"46" =>
                read_imm <= x"F0";
            when others => 
                read_imm <= x"00";
        end case;
    end process;

    alu_dec : process(DATA_RDATA)
    begin
        read_dec <= DATA_RDATA - 1;
    end process;

    alu_inc : process(DATA_RDATA)
    begin
        read_inc <= DATA_RDATA + 1;
    end process;

    read_passthrough : process(DATA_RDATA)
    begin
        OUT_DATA <= DATA_RDATA;
    end process;

    instruction_decoder : process(DATA_RDATA)
    begin 
        case DATA_RDATA is
            when x"00" =>
                instr <= ZERO;
            when x"3E" =>
                instr <= RIGHT;
            when x"3C" =>
                instr <= LEFT;
            when x"2B" =>
                instr <= ADD1;
            when x"2D" =>
                instr <= SUB1;
            when x"5B" =>
                instr <= START_WHILE;
            when x"5D" =>
                instr <= END_WHILE;
            when x"28" =>
                instr <= START_DO_WHILE;
            when x"29" =>
                instr <= END_DO_WHILE;
            when x"2E" =>
                instr <= WRITE1;
            when x"2C" =>
                instr <= READ;
            when x"30" | x"31" | x"32" | x"33" | x"34" | x"35" | x"36" | x"37" | x"38" | x"39" | x"41" | x"42" | x"43" | x"44" | x"45" | x"46" =>
                instr <= IMM;
            when x"40" =>
                instr <= HALT;
            when others =>
                instr <= NOP;
        end case;
    end process;

    pc_cntr : process(CLK, RESET) 
    begin
        if(RESET='1') then
            pc_reg <= (others=>'0');
        elsif rising_edge(CLK) and EN='1' then
            if(pc_inc='1') then
                pc_reg <= pc_reg + 1;
            elsif(pc_dec='1') then
                pc_reg <= pc_reg - 1;
            end if;
        end if;
    end process;

    ptr_cntr : process(CLK, RESET, ptr_rst) 
    begin
        if(RESET='1' or ptr_rst='1') then
            ptr_reg <= (others=>'0');
        elsif rising_edge(CLK) and EN='1' then
            if(ptr_inc='1') then
                ptr_reg <= ptr_reg + 1;
            elsif(ptr_dec='1') then
                ptr_reg <= ptr_reg - 1;
            end if;
        end if;
    end process;
    
    loop_cntr : process(CLK, RESET) 
    begin
        if(RESET='1') then
            loop_reg <= (others=>'0');
        elsif rising_edge(CLK) and EN='1' then
            if(loop_inc='1') then
                loop_reg <= loop_reg + 1;
            elsif(loop_dec='1') then
                loop_reg <= loop_reg - 1;
            end if;
        end if;
    end process;

    loop_comparator : process(loop_reg)
    begin
        if(loop_reg="0000000000000") then
            loop_cmp <= '1';
        else 
            loop_cmp <= '0';
        end if;
    end process;

end behavioral;
