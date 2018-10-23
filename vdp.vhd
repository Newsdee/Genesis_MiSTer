-- Copyright (c) 2010 Gregory Estrade (greg@torlus.com)
-- Copyright (c) 2018 Sorgelig
--
-- All rights reserved
--
-- Redistribution and use in source and synthezised forms, with or without
-- modification, are permitted provided that the following conditions are met:
--
-- Redistributions of source code must retain the above copyright notice,
-- this list of conditions and the following disclaimer.
--
-- Redistributions in synthesized form must reproduce the above copyright
-- notice, this list of conditions and the following disclaimer in the
-- documentation and/or other materials provided with the distribution.
--
-- Neither the name of the author nor the names of other contributors may
-- be used to endorse or promote products derived from this software without
-- specific prior written permission.
--
-- THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
-- AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
-- THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
-- PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
-- INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
-- CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
-- ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
-- POSSIBILITY OF SUCH DAMAGE.
--
-- Please report bugs to the author, but before you do so, please
-- make sure that this is not a derivative work and that
-- you have the latest version of this file.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity vdp is
	port(
		RST_N				: in std_logic;
		CLK				: in std_logic;
		MEMCLK			: in std_logic;
		
		SEL				: in std_logic;
		A					: in std_logic_vector(4 downto 1);
		RNW				: in std_logic;
		DI					: in std_logic_vector(15 downto 0);
		DO					: out std_logic_vector(15 downto 0);
		DTACK_N			: out std_logic;

		VRAM_REQ 		: out std_logic;
		VRAM_ACK 		: in std_logic;
		VRAM_WE_U		: out std_logic;
		VRAM_WE_L		: out std_logic;
		VRAM_A 			: out std_logic_vector(14 downto 0);
		VRAM_DO 			: out std_logic_vector(15 downto 0);
		VRAM_DI 			: in std_logic_vector(15 downto 0);
		
		TG68_HINT		: out std_logic;
		TG68_VINT		: out std_logic;
		TG68_INTACK		: in std_logic;

		T80_VINT			: out std_logic;
		T80_INTACK		: in std_logic;

		VBUS_ADDR		: out std_logic_vector(23 downto 0);
		VBUS_DATA		: in std_logic_vector(15 downto 0);
		VBUS_SEL			: out std_logic;
		VBUS_DTACK_N	: in std_logic;
		VBUS_BUSY      : out std_logic;

		PAL				: in  std_logic := '0';
		FIELD      		: out std_logic;
		INTERLACE 		: out std_logic;
		R					: out std_logic_vector(3 downto 0);
		G					: out std_logic_vector(3 downto 0);
		B					: out std_logic_vector(3 downto 0);
		HS					: out std_logic;
		VS					: out std_logic;
		HBL   			: out std_logic;
		VBL   			: out std_logic;
		CE_PIX			: out std_logic
	);
end vdp;

architecture rtl of vdp is

----------------------------------------------------------------
-- Video parameters
----------------------------------------------------------------

constant VS_LINES               : integer := 4;

-- Timing values from the Exodus emulator in HV_HCNT and HV_VCNT values

constant H_DISP_START_H32       : integer := 466; -- -46
constant H_DISP_START_H40       : integer := 457; -- -55

constant HBLANK_END_H32         : integer := 9;
constant HBLANK_END_H40         : integer := 10;

constant HBLANK_START_H32       : integer := 293;
constant HBLANK_START_H40       : integer := 357;

-- HSYNC moved a bit before the active area from the reference
-- to provide enough back porch
constant HSYNC_START_H32        : integer := 288;
constant HSYNC_SZ_H32           : integer := 26;

constant HSYNC_START_H40        : integer := 358;
constant HSYNC_SZ_H40           : integer := 32;

constant H_INT_H32              : integer := 265;
constant H_INT_H40              : integer := 329;

constant H_DISP_WIDTH_H32       : integer := 256;
constant H_DISP_WIDTH_H40       : integer := 320;

constant H_TOTAL_WIDTH_H32      : integer := 342;
constant H_TOTAL_WIDTH_H40      : integer := 427;

constant V_DISP_START_PAL_V28   : integer := 458;
constant V_DISP_START_NTSC_V28  : integer := 485; -- -27;
constant V_DISP_START_V30       : integer := 466; -- -46

constant V_DISP_HEIGHT_V28      : integer := 224;
constant V_DISP_HEIGHT_V30      : integer := 240;

constant V_INT_V28              : integer := 224;
constant V_INT_V30              : integer := 240;

constant VSYNC_START_PAL_V28    : integer := 458;
constant VSYNC_START_PAL_V30    : integer := 466;
constant VSYNC_START_NTSC_V28   : integer := 485;
constant VSYNC_START_NTSC_V30   : integer := 466;

constant NTSC_LINES             : integer := 262;
constant PAL_LINES              : integer := 312;

----------------------------------------------------------------

signal vram_req_reg	: std_logic;
signal vram_we			: std_logic;
signal vram_uds_n		: std_logic;
signal vram_lds_n		: std_logic;
signal vram_r			: std_logic_vector(15 downto 0);

----------------------------------------------------------------
-- CPU INTERFACE
----------------------------------------------------------------
signal FF_DTACK_N	: std_logic;
signal FF_DO		: std_logic_vector(15 downto 0);

type reg_t is array(0 to 23) of std_logic_vector(7 downto 0);
signal REG			: reg_t;
signal PENDING		: std_logic;
signal ADDR_LATCH	: std_logic_vector(16 downto 0);
signal REG_LATCH	: std_logic_vector(15 downto 0);
signal CODE			: std_logic_vector(5 downto 0);

type fifo_addr_t is array(0 to 3) of std_logic_vector(16 downto 0);
type fifo_data_t is array(0 to 3) of std_logic_vector(15 downto 0);
type fifo_code_t is array(0 to 3) of std_logic_vector(3 downto 0);

signal FIFO_ADDR	: fifo_addr_t;
signal FIFO_DATA	: fifo_data_t;
signal FIFO_CODE	: fifo_code_t;
signal FIFO_WR_POS: std_logic_vector(1 downto 0);
signal FIFO_RD_POS: std_logic_vector(1 downto 0);
signal FIFO_EMPTY	: std_logic;
signal FIFO_FULL	: std_logic;
signal FIFO_EN		: std_logic;
signal FIFO_CNT	: std_logic_vector(5 downto 0);
signal FIFO_SKIP	: std_logic;

signal IN_DMA		: std_logic;
signal IN_HBL		: std_logic;
signal IN_VBL		: std_logic;
signal IN_VBL_D	: std_logic;

signal SOVR			: std_logic;
signal SOVR_CLR	: std_logic;

signal SCOL			: std_logic;
signal SCOL_CLR	: std_logic;

----------------------------------------------------------------
-- INTERRUPTS
----------------------------------------------------------------
signal HINT_COUNT			: std_logic_vector(7 downto 0);
signal HINT_PENDING		: std_logic;
signal TG68_VINT_PENDING: std_logic;
signal TG68_VINT_FF		: std_logic;
signal TG68_HINT_FF		: std_logic;

----------------------------------------------------------------
-- REGISTERS
----------------------------------------------------------------
signal H40			: std_logic;
signal V30			: std_logic;

signal ADDR_STEP	: std_logic_vector(7 downto 0);

signal HSCR 		: std_logic_vector(1 downto 0);
signal HSIZE		: std_logic_vector(1 downto 0);
signal VSIZE		: std_logic_vector(1 downto 0);
signal VSCR 		: std_logic;

signal WVP			: std_logic_vector(4 downto 0);
signal WDOWN		: std_logic;
signal WHP			: std_logic_vector(4 downto 0);
signal WRIGT		: std_logic;

signal BGCOL		: std_logic_vector(5 downto 0);

signal HIT			: std_logic_vector(7 downto 0);
signal IE1			: std_logic;
signal IE0			: std_logic;
signal DE			: std_logic;
signal M3			: std_logic;
signal M5			: std_logic;
signal M128			: std_logic;
signal SHI			: std_logic;

signal DMA			: std_logic;
signal LSM			: std_logic_vector(1 downto 0);

signal ODD			: std_logic;

signal HV8			: std_logic;
signal HV			: std_logic_vector(15 downto 0);
signal STATUS		: std_logic_vector(15 downto 0);

-- Base addresses
signal HSCB			: std_logic_vector(5 downto 0);
signal NTBB			: std_logic_vector(2 downto 0);
signal NTWB			: std_logic_vector(4 downto 0);
signal NTAB			: std_logic_vector(2 downto 0);
signal SATB			: std_logic_vector(7 downto 0);

----------------------------------------------------------------
-- DATA TRANSFER CONTROLLER
----------------------------------------------------------------
type dtc_t is (
	DTC_IDLE,
	DTC_FIFO_RD,
	DTC_VRAM_WR1,
	DTC_VRAM_WR2,
	DTC_CRAM_WR,
	DTC_VSRAM_WR,
	DTC_WR_END,
	DTC_VRAM_RD1,
	DTC_VRAM_RD2,
	DTC_CRAM_RD,
	DTC_CRAM_RD1,
	DTC_CRAM_RD2,
	DTC_VSRAM_RD,
	DTC_VSRAM_RD1,
	DTC_VSRAM_RD2
);
signal DTC	: dtc_t;

type dmac_t is (
	DMA_IDLE,
	DMA_FILL_INIT,
	DMA_FILL_START,
	DMA_FILL_CRAM,
	DMA_FILL_VSRAM,
	DMA_FILL_WR,
	DMA_FILL_WR2,
	DMA_FILL_LOOP,
	DMA_COPY_INIT,
	DMA_COPY_RD,
	DMA_COPY_RD2,
	DMA_COPY_WR,
	DMA_COPY_WR2,
	DMA_COPY_LOOP,
	DMA_VBUS_INIT,
	DMA_VBUS_RD,
	DMA_VBUS_RD2,
	DMA_VBUS_SEL,
	DMA_VBUS_LOOP
);
signal DMAC	: dmac_t;

signal DMA_SEL				: std_logic;
signal DMA_VRAM_ADDR		: std_logic_vector(15 downto 0);
signal DMA_VRAM_DI		: std_logic_vector(15 downto 0);
signal DMA_VRAM_DO		: std_logic_vector(15 downto 0);
signal DMA_VRAM_DO_REG	: std_logic_vector(15 downto 0);
signal DMA_VRAM_RNW		: std_logic;
signal DMA_VRAM_UDS_N	: std_logic;
signal DMA_VRAM_LDS_N	: std_logic;
signal DMA_DTACK_N		: std_logic;
signal DMA_VRAM_A			: std_logic_vector(14 downto 0);
signal DT_WR_ADDR			: std_logic_vector(16 downto 0);
signal DT_WR_DATA			: std_logic_vector(15 downto 0);

signal DT_FF_DATA			: std_logic_vector(15 downto 0);
signal DT_FF_CODE			: std_logic_vector(3 downto 0);
signal DT_FF_SEL			: std_logic;
signal DT_FF_DTACK_N		: std_logic;
signal DT_VBUS_SEL		: std_logic;

signal DT_RD_DATA			: std_logic_vector(15 downto 0);
signal DT_RD_CODE			: std_logic_vector(3 downto 0);
signal DT_RD_SEL			: std_logic;
signal DT_RD_DTACK_N		: std_logic;

signal ADDR					: std_logic_vector(16 downto 0);
signal ADDR_SET_REQ		: std_logic;
signal ADDR_SET_ACK		: std_logic;
signal REG_SET_REQ		: std_logic;
signal REG_SET_ACK		: std_logic;

signal DT_DMAF_DATA		: std_logic_vector(15 downto 0);
signal DT_DMAV_DATA		: std_logic_vector(15 downto 0);
signal DMAF_SET_REQ		: std_logic;

signal FF_VBUS_ADDR		: std_logic_vector(23 downto 0);
signal FF_VBUS_SEL		: std_logic;

signal DMA_VBUS			: std_logic;
signal DMA_FILL_PRE		: std_logic;
signal DMA_FILL			: std_logic;
signal DMA_COPY			: std_logic;

signal DMA_LENGTH			: std_logic_vector(15 downto 0);
signal DMA_SOURCE			: std_logic_vector(15 downto 0);

----------------------------------------------------------------
-- VIDEO COUNTING
----------------------------------------------------------------
signal V_ACTIVE		: std_logic;
signal PRE_V_ACTIVE	: std_logic;

-- HV COUNTERS
signal HV_PIXDIV		: std_logic_vector(3 downto 0);
signal HV_HCNT			: std_logic_vector(8 downto 0);
signal HV_VCNT			: std_logic_vector(8 downto 0);

-- TIMING VALUES
signal H_DISP_START	: std_logic_vector(8 downto 0);
signal H_DISP_WIDTH	: std_logic_vector(8 downto 0);
signal H_TOTAL_WIDTH	: std_logic_vector(8 downto 0);
signal H_SPENGINE_ON	: std_logic_vector(8 downto 0);
signal H_INT_POS		: std_logic_vector(8 downto 0);
signal HSYNC_START	: std_logic_vector(8 downto 0);
signal HSYNC_SZ		: std_logic_vector(8 downto 0);
signal HBLANK_START	: std_logic_vector(8 downto 0);
signal HBLANK_END		: std_logic_vector(8 downto 0);
signal V_DISP_START	: std_logic_vector(8 downto 0);
signal V_DISP_HEIGHT	: std_logic_vector(8 downto 0);
signal VSYNC_START	: std_logic_vector(8 downto 0);
signal V_TOTAL_HEIGHT: std_logic_vector(8 downto 0);
signal V_INT_POS		: std_logic_vector(8 downto 0);

----------------------------------------------------------------
-- VRAM CONTROLLER
----------------------------------------------------------------

type vmc_t is (
	VMC_IDLE,
	VMC_BGB,
	VMC_BGA,
	VMC_SP,
	VMC_DMA
);
signal VMC				: vmc_t := VMC_IDLE;
signal VMC_NEXT		: vmc_t := VMC_IDLE;

signal early_ack_bga	: std_logic;
signal early_ack_bgb	: std_logic;
signal early_ack_sp	: std_logic;
signal early_ack_dma : std_logic;
signal early_ack		: std_logic;

----------------------------------------------------------------
-- BACKGROUND RENDERING
----------------------------------------------------------------
signal BGEN_ACTIVE	: std_logic;
signal BG_Y				: std_logic_vector(8 downto 0);

-- BACKGROUND B
type bgc_t is (
	BGC_INIT,
	BGC_HS_RD,
	BGC_CALC_Y,
	BGC_BASE_RD,
	BGC_LOOP,
	BGC_LOOP_WR,
	BGC_TILE_RD,
	BGC_DONE
);
signal BGAC,BGBC : bgc_t;

signal BGB_COLINFO_ADDR_A	: std_logic_vector(8 downto 0);
signal BGB_COLINFO_D_A		: std_logic_vector(6 downto 0);
signal BGB_COLINFO_WE_A		: std_logic;
signal BGB_COLINFO_Q_B		: std_logic_vector(6 downto 0);

signal BGB_VRAM_ADDR			: std_logic_vector(14 downto 0);
signal BGB_VRAM_DO			: std_logic_vector(15 downto 0);
signal BGB_VRAM_DO_REG		: std_logic_vector(15 downto 0);
signal BGB_SEL					: std_logic;
signal BGB_DTACK_N			: std_logic;
signal BGB_VSRAM1_LATCH		: std_logic_vector(9 downto 0);

signal BGA_COLINFO_ADDR_A	: std_logic_vector(8 downto 0);
signal BGA_COLINFO_D_A		: std_logic_vector(6 downto 0);
signal BGA_COLINFO_WE_A		: std_logic;
signal BGA_COLINFO_Q_B		: std_logic_vector(6 downto 0);

signal BGA_VRAM_ADDR			: std_logic_vector(14 downto 0);
signal BGA_VRAM_DO			: std_logic_vector(15 downto 0);
signal BGA_VRAM_DO_REG		: std_logic_vector(15 downto 0);
signal BGA_SEL					: std_logic;
signal BGA_DTACK_N			: std_logic;
signal BGA_VSRAM0_LATCH		: std_logic_vector(9 downto 0);

----------------------------------------------------------------
-- SPRITE CACHE
----------------------------------------------------------------
signal CACHE_ADDR		: std_logic_vector(8 downto 0);
signal CACHE_WE_L		: std_logic;
signal CACHE_WE_U		: std_logic;

signal CACHE_Y			: std_logic_vector(15 downto 0);
signal CACHE_SZ_LINK	: std_logic_vector(15 downto 0);

----------------------------------------------------------------
-- SPRITE ENGINE
----------------------------------------------------------------
signal SPE_ACTIVE		: std_logic;

type spc_t is (
	SPC_INIT,
	SPC_Y_RD,
	SPC_Y_TST,
	SPC_X_RD,
	SPC_X_TST,
	SPC_CALC_XY,
	SPC_LOOP,
	SPC_WAIT,
	SPC_PLOT,
	SPC_TILE_RD,
	SPC_NEXT,
	SPC_DONE
);
signal SPC						: spc_t;

signal SP_Y						: std_logic_vector(8 downto 0);

signal SP_VRAM_ADDR			: std_logic_vector(14 downto 0);
signal SP_VRAM_DO				: std_logic_vector(15 downto 0);
signal SP_VRAM_DO_REG		: std_logic_vector(15 downto 0);
signal SP_SEL					: std_logic;
signal SP_DTACK_N				: std_logic;

signal OBJ_COLINFO_ADDR_A	: std_logic_vector(8 downto 0);
signal OBJ_COLINFO_D_A		: std_logic_vector(6 downto 0);
signal OBJ_COLINFO_WE_A		: std_logic;
signal OBJ_COLINFO_WE_B		: std_logic;
signal OBJ_COLINFO_Q_A		: std_logic_vector(6 downto 0);
signal OBJ_COLINFO_Q_B		: std_logic_vector(6 downto 0);
signal OBJ_NUM					: std_logic_vector(6 downto 0);

----------------------------------------------------------------
-- VIDEO OUTPUT
----------------------------------------------------------------
signal COLINFO_ADDR_B: std_logic_vector(8 downto 0);
signal COLOR_ADDR		: std_logic_vector(5 downto 0);
signal COLOR_D			: std_logic_vector(8 downto 0);
signal COLOR_Q			: std_logic_vector(8 downto 0);
signal COLOR_WE		: std_logic;
signal COLOR_NUM		: std_logic_vector(5 downto 0);
signal COLOR			: std_logic_vector(8 downto 0);

signal VSRAM_ADDR		: std_logic_vector(5 downto 0);
signal VSRAM_D			: std_logic_vector(10 downto 0);
signal VSRAM_Q0		: std_logic_vector(10 downto 0);
signal VSRAM_Q1		: std_logic_vector(10 downto 0);
signal VSRAM_NUMA		: std_logic_vector(4 downto 0);
signal VSRAM_NUMB		: std_logic_vector(4 downto 0);
signal VSRAM_BGA		: std_logic_vector(10 downto 0);
signal VSRAM_BGB		: std_logic_vector(10 downto 0);
signal VSRAM_WE		: std_logic;

signal DBG				: std_logic_vector(15 downto 0);
signal INTERLACE_FF  : std_logic;

begin

bgb_ci : entity work.dpram generic map(9,7)
port map(
	clock			=> MEMCLK,
	address_a	=> BGB_COLINFO_ADDR_A,
	data_a		=> BGB_COLINFO_D_A,
	wren_a		=> BGB_COLINFO_WE_A,
	address_b	=> COLINFO_ADDR_B,
	q_b			=> BGB_COLINFO_Q_B
);

bga_ci : entity work.dpram generic map(9,7)
port map(
	clock			=> MEMCLK,
	address_a	=> BGA_COLINFO_ADDR_A,
	data_a		=> BGA_COLINFO_D_A,
	wren_a		=> BGA_COLINFO_WE_A,
	address_b	=> COLINFO_ADDR_B,
	q_b			=> BGA_COLINFO_Q_B
);

obj_ci : entity work.dpram generic map(9,7)
port map(
	clock			=> MEMCLK,
	address_a	=> OBJ_COLINFO_ADDR_A,
	data_a		=> OBJ_COLINFO_D_A,
	wren_a		=> OBJ_COLINFO_WE_A,
	q_a			=> OBJ_COLINFO_Q_A,
	address_b	=> COLINFO_ADDR_B,
	wren_b		=> OBJ_COLINFO_WE_B,
	q_b			=> OBJ_COLINFO_Q_B
);

cache_y_u : entity work.dpram generic map(7,8)
port map(
	clock			=> MEMCLK,
	address_a	=> CACHE_ADDR(8 downto 2),
	data_a		=> DMA_VRAM_DI(15 downto 8),
	wren_a		=> CACHE_WE_U and not CACHE_ADDR(0),

	address_b	=> OBJ_NUM,
	q_b			=> CACHE_Y(15 downto 8)
);

cache_y_l : entity work.dpram generic map(7,8)
port map(
	clock			=> MEMCLK,
	address_a	=> CACHE_ADDR(8 downto 2),
	data_a		=> DMA_VRAM_DI(7 downto 0),
	wren_a		=> CACHE_WE_L and not CACHE_ADDR(0),

	address_b	=> OBJ_NUM,
	q_b			=> CACHE_Y(7 downto 0)
);

cache_sz_u : entity work.dpram generic map(7,8)
port map(
	clock			=> MEMCLK,
	address_a	=> CACHE_ADDR(8 downto 2),
	data_a		=> DMA_VRAM_DI(15 downto 8),
	wren_a		=> CACHE_WE_U and CACHE_ADDR(0),

	address_b	=> OBJ_NUM,
	q_b			=> CACHE_SZ_LINK(15 downto 8)
);

cache_sz_l : entity work.dpram generic map(7,8)
port map(
	clock			=> MEMCLK,
	address_a	=> CACHE_ADDR(8 downto 2),
	data_a		=> DMA_VRAM_DI(7 downto 0),
	wren_a		=> CACHE_WE_L and CACHE_ADDR(0),

	address_b	=> OBJ_NUM,
	q_b			=> CACHE_SZ_LINK(7 downto 0)
);

cram : entity work.dpram generic map(6,9) 
port map(
	clock			=> MEMCLK,
	address_a	=> COLOR_ADDR,
	data_a		=> COLOR_D,
	wren_a		=> COLOR_WE,
	q_a			=> COLOR_Q,

	address_b	=> COLOR_NUM,
	q_b			=> COLOR
);

vsram0 : entity work.dpram generic map(5,11)
port map(
	clock			=> MEMCLK,
	address_a	=> VSRAM_ADDR(5 downto 1),
	data_a		=> VSRAM_D,
	wren_a		=> VSRAM_WE and not VSRAM_ADDR(0),
	q_a			=> VSRAM_Q0,

	address_b	=> VSRAM_NUMA,
	q_b			=> VSRAM_BGA
);

vsram1 : entity work.dpram generic map(5,11)
port map(
	clock			=> MEMCLK,
	address_a	=> VSRAM_ADDR(5 downto 1),
	data_a		=> VSRAM_D,
	wren_a		=> VSRAM_WE and VSRAM_ADDR(0),
	q_a			=> VSRAM_Q1,

	address_b	=> VSRAM_NUMB,
	q_b			=> VSRAM_BGB
);

----------------------------------------------------------------
-- REGISTERS
----------------------------------------------------------------

M3    <= REG(0)(1);
IE1   <= REG(0)(4);

M5    <= REG(1)(2);
V30   <= REG(1)(3);
DMA   <= REG(1)(4);
IE0   <= REG(1)(5);
DE    <= REG(1)(6);
M128  <= REG(1)(7);

NTAB  <= REG(2)(5 downto 3);
NTWB  <= REG(3)(5 downto 2)&(REG(3)(1) and not H40);
NTBB  <= REG(4)(2 downto 0);
SATB  <= REG(5)(7 downto 1)&(REG(5)(0) and not H40);

BGCOL <= REG(7)(5 downto 0);

HIT   <= REG(10);

HSCR  <= REG(11)(1 downto 0);
VSCR  <= REG(11)(2);
H40   <= REG(12)(0);
LSM   <= REG(12)(2 downto 1);
SHI   <= REG(12)(3);

HSCB  <= REG(13)(5 downto 0);

ADDR_STEP <= REG(15);

HSIZE <= REG(16)(1 downto 0);
VSIZE <= REG(16)(5 downto 4);

WHP   <= REG(17)(4 downto 0);
WRIGT <= REG(17)(7);

WVP   <= REG(18)(4 downto 0);
WDOWN <= REG(18)(7);

INTERLACE_FF <= LSM(1) and LSM(0);
INTERLACE <= INTERLACE_FF;

STATUS <= "111111"
			& FIFO_EMPTY
			& FIFO_FULL
			& TG68_VINT_PENDING
			& SOVR
			& SCOL
			& ODD
			& (IN_VBL or not DE)
			& IN_HBL
			& IN_DMA
			& PAL;

IN_DMA <= DMA_FILL or DMA_COPY or DMA_VBUS;

----------------------------------------------------------------
-- VRAM CONTROLLER
----------------------------------------------------------------
vram_we  <= not DMA_VRAM_RNW when VMC=VMC_DMA else '0';

VRAM_REQ   <= vram_req_reg;
VRAM_WE_U  <= vram_we and not vram_uds_n;
VRAM_WE_L  <= vram_we and not vram_lds_n;

VRAM_DO    <= DMA_VRAM_DI                when M128 = '0' else DMA_VRAM_DI(7 downto 0) & DMA_VRAM_DI(7 downto 0);
DMA_VRAM_A <= DMA_VRAM_ADDR(14 downto 0) when M128 = '0' else DMA_VRAM_ADDR(15 downto 10) & DMA_VRAM_ADDR(8 downto 1) & DMA_VRAM_ADDR(9);
vram_uds_n <= DMA_VRAM_UDS_N             when M128 = '0' else not DMA_VRAM_ADDR(0);
vram_lds_n <= DMA_VRAM_LDS_N             when M128 = '0' else     DMA_VRAM_ADDR(0);
vram_r     <= VRAM_DI                    when M128 = '0' else VRAM_DI(7 downto 0)  & VRAM_DI(7 downto 0) when DMA_VRAM_ADDR(0) = '0'
                                                         else VRAM_DI(15 downto 8) & VRAM_DI(15 downto 8);

early_ack_bga <= '0' when VMC=VMC_BGA and vram_req_reg=VRAM_ACK else '1';
early_ack_bgb <= '0' when VMC=VMC_BGB and vram_req_reg=VRAM_ACK else '1';
early_ack_sp  <= '0' when VMC=VMC_SP  and vram_req_reg=VRAM_ACK else '1';
early_ack_dma <= '0' when VMC=VMC_DMA and vram_req_reg=VRAM_ACK else '1';

BGA_VRAM_DO <= VRAM_DI when early_ack_bga='0' and BGA_DTACK_N = '1' else BGA_VRAM_DO_REG;
BGB_VRAM_DO <= VRAM_DI when early_ack_bgb='0' and BGB_DTACK_N = '1' else BGB_VRAM_DO_REG;
SP_VRAM_DO  <= VRAM_DI when early_ack_sp ='0' and SP_DTACK_N  = '1'  else SP_VRAM_DO_REG;
DMA_VRAM_DO <= vram_r  when early_ack_dma='0' and DMA_DTACK_N = '1' else DMA_VRAM_DO_REG;

-- Priority encoder for next port...
VMC_NEXT <= VMC_SP  when SP_SEL  = '1' and SP_DTACK_N  = '1' and early_ack_sp ='1'
       else VMC_BGB when BGB_SEL = '1' and BGB_DTACK_N = '1' and early_ack_bgb='1'
       else VMC_BGA when BGA_SEL = '1' and BGA_DTACK_N = '1' and early_ack_bga='1'
       else VMC_DMA when DMA_SEL = '1' and DMA_DTACK_N = '1' and early_ack_dma='1'
       else VMC_IDLE;

process( CLK, RST_N )
begin
	if RST_N = '0' then
		BGB_DTACK_N <= '1';
		BGA_DTACK_N <= '1';
		SP_DTACK_N <= '1';
		DMA_DTACK_N <= '1';
		vram_req_reg <= '0';
		VMC<=VMC_IDLE;
	else
		if rising_edge(CLK) then

			if BGB_SEL = '0' then BGB_DTACK_N <= '1'; end if;
			if BGA_SEL = '0' then BGA_DTACK_N <= '1'; end if;
			if DMA_SEL = '0' then DMA_DTACK_N <= '1'; end if;
			SP_DTACK_N  <= '1';

			if vram_req_reg = VRAM_ACK then
				VMC <= VMC_NEXT;
				case VMC_NEXT is
					when VMC_BGA => VRAM_A <= BGA_VRAM_ADDR;
					when VMC_BGB => VRAM_A <= BGB_VRAM_ADDR;
					when VMC_SP  => VRAM_A <= SP_VRAM_ADDR;
					when VMC_DMA => VRAM_A <= DMA_VRAM_A;
					when others  => null;
				end case;

				if VMC_NEXT /= VMC_IDLE then
					vram_req_reg <= not VRAM_ACK;
				end if;

				case VMC is
					when VMC_BGA => BGA_VRAM_DO_REG <= VRAM_DI; BGA_DTACK_N <= '0';
					when VMC_BGB => BGB_VRAM_DO_REG <= VRAM_DI; BGB_DTACK_N <= '0';
					when VMC_SP  => SP_VRAM_DO_REG  <= VRAM_DI; SP_DTACK_N  <= '0';
					when VMC_DMA => DMA_VRAM_DO_REG <= vram_r;  DMA_DTACK_N <= '0';
					when others => null;
				end case;
			end if;
		end if;
	end if;
end process;


----------------------------------------------------------------
-- BACKGROUND B RENDERING
----------------------------------------------------------------
process( RST_N, CLK )
	variable V_BGB_XSTART	: std_logic_vector(9 downto 0);
	variable V_BGB_BASE		: std_logic_vector(15 downto 0);
	variable BGB_X				: std_logic_vector(9 downto 0);
	variable BGB_POS			: std_logic_vector(9 downto 0);
	variable BGB_Y				: std_logic_vector(9 downto 0);
	variable T_BGB_PRI		: std_logic;
	variable T_BGB_PAL		: std_logic_vector(1 downto 0);
	variable BGB_TILEBASE	: std_logic_vector(15 downto 0);
	variable BGB_HF			: std_logic;
	variable TEMP2				: std_logic_vector(13 downto 0);
	variable VS					: std_logic_vector(9 downto 0);
begin
	if RST_N = '0' then
		BGB_SEL <= '0';
		BGBC <= BGC_INIT;
		BGB_COLINFO_WE_A <= '0';
	elsif rising_edge(CLK) then
		BGB_COLINFO_WE_A <= '0';

		case BGBC is
		when BGC_INIT =>
			if BGEN_ACTIVE = '1' then
				case HSCR is -- Horizontal scroll mode
				when "00" => BGB_VRAM_ADDR <= HSCB & "000000001";
				when "01" => BGB_VRAM_ADDR <= HSCB & "00000" & BG_Y(2 downto 0) & '1';
				when "10" => BGB_VRAM_ADDR <= HSCB & BG_Y(7 downto 3) & "0001";
				when "11" => BGB_VRAM_ADDR <= HSCB & BG_Y(7 downto 0) & '1';
				when others => null;
				end case;
				BGB_SEL <= '1';
				BGBC <= BGC_HS_RD;
			end if;

		when BGC_HS_RD =>
			if early_ack_bgb = '0' then
				V_BGB_XSTART := "0000000000" - BGB_VRAM_DO(9 downto 0);
				BGB_SEL <= '0';
				BGB_X := ( V_BGB_XSTART(9 downto 3) & "000" ) and (HSIZE & "11111111");
				BGB_POS := "0000000000" - ( "0000000" & V_BGB_XSTART(2 downto 0) );
				VSRAM_NUMB <= BGB_POS(8 downto 4);
				BGBC <= BGC_CALC_Y;
			end if;

		when BGC_CALC_Y =>
			if BGB_POS(9) = '1' or VSCR = '0' then
				VS := BGB_VSRAM1_LATCH;
			else
				VS := VSRAM_BGB(9 downto 0);
			end if;
		
			if INTERLACE_FF = '0' then
				BGB_Y := (VS(9 downto 0) + BG_Y) and (VSIZE & "11111111");
			else
				BGB_Y := (VS(9 downto 1) + BG_Y) and (VSIZE & "11111111");
			end if;

			case HSIZE is
			when "00" => -- HS 32 cells
				V_BGB_BASE := (NTBB & "0000000000000") + (BGB_X(9 downto 3) & "0") + (BGB_Y(9 downto 3) & "00000" & "0");
			when "01" => -- HS 64 cells
				V_BGB_BASE := (NTBB & "0000000000000") + (BGB_X(9 downto 3) & "0") + (BGB_Y(9 downto 3) & "000000" & "0");
			when others => -- HS 128 cells
				V_BGB_BASE := (NTBB & "0000000000000") + (BGB_X(9 downto 3) & "0") + (BGB_Y(9 downto 3) & "0000000" & "0");
			end case;
			BGB_VRAM_ADDR <= V_BGB_BASE(15 downto 1);
			BGB_SEL <= '1';
			BGBC <= BGC_BASE_RD;

		when BGC_BASE_RD =>
			if early_ack_bgb='0' then
				BGB_SEL <= '0';
				T_BGB_PRI := BGB_VRAM_DO(15);
				T_BGB_PAL := BGB_VRAM_DO(14 downto 13);
				BGB_HF := BGB_VRAM_DO(11);
				if BGB_VRAM_DO(12) = '1' then	-- VF
					TEMP2 := BGB_VRAM_DO(10 downto 0) & not(BGB_Y(2 downto 0));
				else
					TEMP2 := BGB_VRAM_DO(10 downto 0) & (BGB_Y(2 downto 0));
				end if;

				if INTERLACE_FF = '0' then
					BGB_TILEBASE := TEMP2(13 downto 0) & "00";
				else
					BGB_TILEBASE := TEMP2(12 downto 0) & (ODD xor BGB_VRAM_DO(12)) & "00";
				end if;

				BGBC <= BGC_LOOP;
			end if;

		when BGC_LOOP =>
			if BGB_X(1 downto 0) = "00" and BGB_SEL = '0' then
				if BGB_X(2) = '0' then
					if BGB_HF = '1' then
						BGB_VRAM_ADDR <= BGB_TILEBASE(15 downto 2) & "1";
					else
						BGB_VRAM_ADDR <= BGB_TILEBASE(15 downto 2) & "0";
					end if;
				else
					if BGB_HF = '1' then
						BGB_VRAM_ADDR <= BGB_TILEBASE(15 downto 2) & "0";
					else
						BGB_VRAM_ADDR <= BGB_TILEBASE(15 downto 2) & "1";
					end if;
				end if;
				BGB_SEL <= '1';
				BGBC <= BGC_TILE_RD;
			else
				if BGB_POS(9) = '0' then
					BGB_COLINFO_ADDR_A <= BGB_POS(8 downto 0);
					BGB_COLINFO_WE_A <= '1';
					case BGB_X(1 downto 0) is
					when "00" =>
						if BGB_HF = '1' then
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(3 downto 0);
						else
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(15 downto 12);
						end if;
					when "01" =>
						if BGB_HF = '1' then
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(7 downto 4);
						else
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(11 downto 8);
						end if;
					when "10" =>
						if BGB_HF = '1' then
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(11 downto 8);
						else
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(7 downto 4);
						end if;
					when others =>
						if BGB_HF = '1' then
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(15 downto 12);
						else
							BGB_COLINFO_D_A <= T_BGB_PRI & T_BGB_PAL & BGB_VRAM_DO(3 downto 0);
						end if;
					end case;
				end if;
				if (H40 = '1' and BGB_POS = 319) or (H40 = '0' and BGB_POS = 255) then
					BGBC <= BGC_DONE;
				else
					BGB_POS := BGB_POS + 1;
					if BGB_X(2 downto 0) = "111" then
						BGBC <= BGC_CALC_Y;
					end if;
				end if;
				BGB_X := (BGB_X + 1) and (HSIZE & "11111111");
				BGB_SEL <= '0';
			end if;
			VSRAM_NUMB <= BGB_POS(8 downto 4);

		when BGC_TILE_RD =>
			if early_ack_bgb = '0' then
				BGBC <= BGC_LOOP;
			end if;

		when others =>	-- BGBC_DONE
			VSRAM_NUMB <= (others => '0');
			BGB_SEL <= '0';
			if BGEN_ACTIVE = '0' then
				BGBC <= BGC_INIT;
			end if;
		end case;
	end if;
end process;


----------------------------------------------------------------
-- BACKGROUND A RENDERING
----------------------------------------------------------------
process( RST_N, CLK )
	variable V_BGA_XSTART	: std_logic_vector(9 downto 0);
	variable V_BGA_BASE		: std_logic_vector(15 downto 0);
	variable BGA_X				: std_logic_vector(9 downto 0);
	variable BGA_POS			: std_logic_vector(9 downto 0);
	variable BGA_Y				: std_logic_vector(9 downto 0);
	variable T_BGA_PRI		: std_logic;
	variable T_BGA_PAL		: std_logic_vector(1 downto 0);
	variable T_BGA_COLNO		: std_logic_vector(3 downto 0);
	variable BGA_BASE			: std_logic_vector(15 downto 0);
	variable BGA_TILEBASE	: std_logic_vector(15 downto 0);
	variable BGA_HF			: std_logic;
	variable WIN_V				: std_logic;
	variable WIN_H				: std_logic;
	variable TEMP2				: std_logic_vector(13 downto 0);
	variable VS					: std_logic_vector(9 downto 0);
begin
	if RST_N = '0' then
		BGA_SEL <= '0';
		BGAC <= BGC_INIT;
		BGA_COLINFO_WE_A <= '0';
	elsif rising_edge(CLK) then
		BGA_COLINFO_WE_A <= '0';

		case BGAC is
		when BGC_INIT =>
			if BGEN_ACTIVE = '1' then
				if BG_Y(2 downto 0) = "000" then
					if BG_Y(7 downto 3) < WVP then
						WIN_V := not WDOWN;
					else
						WIN_V := WDOWN;
					end if;
				end if;
				if WHP = "00000" then
					WIN_H := WRIGT;
				else
					WIN_H := not WRIGT;
				end if;

				case HSCR is -- Horizontal scroll mode
				when "00" => BGA_VRAM_ADDR <= HSCB & "000000000";
				when "01" => BGA_VRAM_ADDR <= HSCB & "00000" & BG_Y(2 downto 0) & '0';
				when "10" => BGA_VRAM_ADDR <= HSCB & BG_Y(7 downto 3) & "0000";
				when "11" => BGA_VRAM_ADDR <= HSCB & BG_Y(7 downto 0) & '0';
				when others => null;
				end case;
				BGA_SEL <= '1';
				BGAC <= BGC_HS_RD;
			end if;

		when BGC_HS_RD =>
			if early_ack_bga='0' then
				V_BGA_XSTART := "0000000000" - BGA_VRAM_DO(9 downto 0);
				BGA_SEL <= '0';
				BGA_X := ( V_BGA_XSTART(9 downto 3) & "000" ) and (HSIZE & "11111111");
				BGA_POS := "0000000000" - ( "0000000" & V_BGA_XSTART(2 downto 0) );
				VSRAM_NUMA <= BGA_POS(8 downto 4);
				BGAC <= BGC_CALC_Y;
			end if;

		when BGC_CALC_Y =>
			if WIN_H = '1' or WIN_V = '1' then
				BGA_Y := '0' & BG_Y;
			else
				if BGA_POS(9) = '1' or VSCR = '0' then
					VS := BGA_VSRAM0_LATCH;
				else
					VS := VSRAM_BGA(9 downto 0);
				end if;

				if INTERLACE_FF = '0' then
					BGA_Y := (VS(9 downto 0) + BG_Y) and (VSIZE & "11111111");
				else
					BGA_Y := (VS(9 downto 1) + BG_Y) and (VSIZE & "11111111");
				end if;
			end if;

			if WIN_H = '1' or WIN_V = '1' then
				V_BGA_BASE := (NTWB & "00000000000") + (BGA_POS(9 downto 3) & "0");
				if H40 = '0' then -- WIN is 32 tiles wide in H32 mode
					V_BGA_BASE := V_BGA_BASE + (BGA_Y(9 downto 3) & "00000" & "0");
				else              -- WIN is 64 tiles wide in H40 mode
					V_BGA_BASE := V_BGA_BASE + (BGA_Y(9 downto 3) & "000000" & "0");
				end if;
			else
				V_BGA_BASE := (NTAB & "0000000000000") + (BGA_X(9 downto 3) & "0");

				case HSIZE is
				when "00" => -- HS 32 cells
					V_BGA_BASE := V_BGA_BASE + (BGA_Y(9 downto 3) & "00000" & "0");
				when "01" => -- HS 64 cells
					V_BGA_BASE := V_BGA_BASE + (BGA_Y(9 downto 3) & "000000" & "0");
				when others => -- HS 128 cells
					V_BGA_BASE := V_BGA_BASE + (BGA_Y(9 downto 3) & "0000000" & "0");
				end case;
			end if;

			BGA_VRAM_ADDR <= V_BGA_BASE(15 downto 1);
			BGA_SEL <= '1';
			BGAC <= BGC_BASE_RD;

		when BGC_BASE_RD =>
			if early_ack_bga='0' then
				BGA_SEL <= '0';
				T_BGA_PRI := BGA_VRAM_DO(15);
				T_BGA_PAL := BGA_VRAM_DO(14 downto 13);
				BGA_HF := BGA_VRAM_DO(11);

				if BGA_VRAM_DO(12) = '1' then	-- VF
					TEMP2 := BGA_VRAM_DO(10 downto 0) & not(BGA_Y(2 downto 0));
				else
					TEMP2 := BGA_VRAM_DO(10 downto 0) & (BGA_Y(2 downto 0));
				end if;

				if INTERLACE_FF = '0' then
					BGA_TILEBASE := TEMP2(13 downto 0) & "00";
				else
					BGA_TILEBASE := TEMP2(12 downto 0) & (ODD xor BGA_VRAM_DO(12)) & "00";
				end if;

				BGAC <= BGC_LOOP;
			end if;

		when BGC_LOOP =>
			if BGA_POS(9) = '0' and WIN_H = '0' and WRIGT = '1'
				and BGA_POS(3 downto 0) = "0000" and BGA_POS(8 downto 4) = WHP
			then
				WIN_H := not WIN_H;
				BGAC <= BGC_CALC_Y;
			elsif BGA_POS(9) = '0' and WIN_H = '1' and WRIGT = '0'
				and BGA_POS(3 downto 0) = "0000" and BGA_POS(8 downto 4) = WHP
			then
				WIN_H := not WIN_H;
				BGAC <= BGC_CALC_Y;
			elsif BGA_POS(1 downto 0) = "00" and BGA_SEL = '0' and (WIN_H = '1' or WIN_V = '1') then
				if BGA_POS(2) = '0' then
					if BGA_HF = '1' then
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "1";
					else
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "0";
					end if;
				else
					if BGA_HF = '1' then
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "0";
					else
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "1";
					end if;
				end if;
				BGA_SEL <= '1';
				BGAC <= BGC_TILE_RD;
			elsif BGA_X(1 downto 0) = "00" and BGA_SEL = '0' and (WIN_H = '0' and WIN_V = '0') then
				if BGA_X(2) = '0' then
					if BGA_HF = '1' then
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "1";
					else
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "0";
					end if;
				else
					if BGA_HF = '1' then
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "0";
					else
						BGA_VRAM_ADDR <= BGA_TILEBASE(15 downto 2) & "1";
					end if;
				end if;
				BGA_SEL <= '1';
				BGAC <= BGC_TILE_RD;
			else
				if BGA_POS(9) = '0' then
					BGA_COLINFO_WE_A <= '1';
					BGA_COLINFO_ADDR_A <= BGA_POS(8 downto 0);
					if WIN_H = '1' or WIN_V = '1' then
						case BGA_POS(1 downto 0) is
						when "00" =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(3 downto 0);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(15 downto 12);
							end if;
						when "01" =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(7 downto 4);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(11 downto 8);
							end if;
						when "10" =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(11 downto 8);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(7 downto 4);
							end if;
						when others =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(15 downto 12);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(3 downto 0);
							end if;
						end case;
					else
						case BGA_X(1 downto 0) is
						when "00" =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(3 downto 0);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(15 downto 12);
							end if;
						when "01" =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(7 downto 4);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(11 downto 8);
							end if;
						when "10" =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(11 downto 8);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(7 downto 4);
							end if;
						when others =>
							if BGA_HF = '1' then
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(15 downto 12);
							else
								BGA_COLINFO_D_A <= T_BGA_PRI & T_BGA_PAL & BGA_VRAM_DO(3 downto 0);
							end if;
						end case;
					end if;
				end if;
				if (H40 = '1' and BGA_POS = 319) or (H40 = '0' and BGA_POS = 255) then
					BGAC <= BGC_DONE;
				else
					if BGA_X(2 downto 0) = "111" and (WIN_H = '0' and WIN_V = '0') then
						BGAC <= BGC_CALC_Y;
					elsif BGA_POS(2 downto 0) = "111" and (WIN_H = '1' or WIN_V = '1') then
						BGAC <= BGC_CALC_Y;
					end if;
					BGA_POS := BGA_POS + 1;
				end if;
				BGA_X := (BGA_X + 1) and (HSIZE & "11111111");
				BGA_SEL <= '0';
			end if;
			VSRAM_NUMA <= BGA_POS(8 downto 4);

		when BGC_TILE_RD =>
			if early_ack_bga='0' then
				BGAC <= BGC_LOOP;
			end if;

		when others =>	-- BGAC_DONE
			VSRAM_NUMA <= (others => '0');
			BGA_SEL <= '0';
			if BGEN_ACTIVE = '0' then
				BGAC <= BGC_INIT;
			end if;
		end case;
	end if;
end process;

----------------------------------------------------------------
-- SPRITE CACHE
----------------------------------------------------------------

process(CLK)
	variable old_dma_sel : std_logic;
	variable addr : std_logic_vector(15 downto 0);
begin
	if rising_edge(CLK) then

		addr := DMA_VRAM_ADDR - (SATB & "00000000");

		CACHE_WE_U <= '0';
		CACHE_WE_L <= '0';
		if old_dma_sel = '0' and DMA_SEL = '1' and DMA_VRAM_RNW = '0' and addr(1) = '0' and addr(15 downto 9) = 0 then
			CACHE_ADDR <= addr(8 downto 0);
			CACHE_WE_U <= not DMA_VRAM_UDS_N;
			CACHE_WE_L <= not DMA_VRAM_LDS_N;
		end if;

		old_dma_sel := DMA_SEL;
	end if;
end process;

----------------------------------------------------------------
-- SPRITE RENDER
----------------------------------------------------------------
process( RST_N, MEMCLK )
	variable OBJ_NB			: std_logic_vector(6 downto 0);
	variable OBJ_PIX			: std_logic_vector(8 downto 0);
	variable OBJ_Y_OFS		: std_logic_vector(8 downto 0);
	variable OBJ_LINK			: std_logic_vector(6 downto 0);
	variable OBJ_HS			: std_logic_vector(1 downto 0);
	variable OBJ_VS			: std_logic_vector(2 downto 0);
	variable OBJ_X				: std_logic_vector(8 downto 0);
	variable OBJ_X_OFS		: std_logic_vector(4 downto 0);
	variable OBJ_PRI			: std_logic;
	variable OBJ_PAL			: std_logic_vector(1 downto 0);
	variable OBJ_VF			: std_logic;
	variable OBJ_HF			: std_logic;
	variable OBJ_POS			: std_logic_vector(8 downto 0);
	variable OBJ_TILEBASE	: std_logic_vector(14 downto 0);
	variable OBJ_COLNO		: std_logic_vector(3 downto 0);
	variable OBJ_MASKED		: std_logic;
	variable OBJ_VALID_X		: std_logic;
	variable OBJ_DOT_OVERFLOW: std_logic;
	variable OBJ_CNT      	: integer range 0 to 127;
begin
	if RST_N = '0' then
		SP_SEL <= '0';
		SPC <= SPC_INIT;
		OBJ_COLINFO_WE_A <= '0';
		SCOL <= '0';
		SOVR <= '0';
		OBJ_DOT_OVERFLOW := '0';

	elsif rising_edge(MEMCLK) then

		if SCOL_CLR = '1' then
			SCOL <= '0';
		end if;

		if SOVR_CLR = '1' then
			SOVR <= '0';
		end if;

		OBJ_COLINFO_WE_A <= '0';

		case SPC is
		when SPC_INIT =>
			if SPE_ACTIVE = '1' then
				SP_SEL <= '0';
				SP_Y <= HV_VCNT + 1;

				OBJ_NUM <= (others => '0');

				OBJ_COLINFO_ADDR_A <= (others => '0');
				OBJ_NB := (others => '0');
				OBJ_PIX := (others => '0');
				OBJ_MASKED := '0';
				OBJ_VALID_X := OBJ_DOT_OVERFLOW;
				OBJ_DOT_OVERFLOW := '0';
				OBJ_CNT := 0;

				SPC <= SPC_Y_RD;
			end if;

		when SPC_Y_RD =>
			SPC <= SPC_Y_TST;

		when SPC_Y_TST =>
			if INTERLACE_FF = '0' then
				OBJ_Y_OFS := SP_Y + 128 - CACHE_Y(8 downto 0);
			else
				OBJ_Y_OFS := SP_Y + 128 - CACHE_Y(9 downto 1);
			end if;
			OBJ_HS := CACHE_SZ_LINK(11 downto 10);
			OBJ_VS := '0'&CACHE_SZ_LINK(9 downto 8);
			if INTERLACE_FF = '1' then
				OBJ_VS(2) := '1';
			end if;
			OBJ_LINK := CACHE_SZ_LINK(6 downto 0);

			SP_VRAM_ADDR <= (SATB(6 downto 0) & "00000000") + (OBJ_NUM & "11");

			SPC <= SPC_NEXT;
			case OBJ_VS(1 downto 0) is
			when "00" =>	-- 8 pixels
				if OBJ_Y_OFS(8 downto 3) = "000000" then
					SPC <= SPC_X_RD;
					SP_SEL <= '1';
				end if;
			when "01" =>	-- 16 pixels
				if OBJ_Y_OFS(8 downto 4) = "00000" then
					SPC <= SPC_X_RD;
					SP_SEL <= '1';
				end if;
			when "11" =>	-- 32 pixels
				if OBJ_Y_OFS(8 downto 5) = "0000" then
					SPC <= SPC_X_RD;
					SP_SEL <= '1';
				end if;
			when others =>	-- 24 pixels
				if OBJ_Y_OFS(8 downto 5) = "0000" and OBJ_Y_OFS(4 downto 3) /= "11" then
					SPC <= SPC_X_RD;
					SP_SEL <= '1';
				end if;
			end case;

		when SPC_X_RD =>
			if early_ack_sp='0' then
				SP_SEL <= '0';
				OBJ_X := SP_VRAM_DO(8 downto 0);
				SPC <= SPC_X_TST;
			end if;

		when SPC_X_TST =>
			-- sprite masking algorithm as implemented by gens-ii
			if OBJ_X = "000000000" and OBJ_VALID_X = '1' then
				OBJ_MASKED := '1';
			end if;

			if OBJ_X /= "000000000" then
				OBJ_VALID_X := '1';
			end if;
			SP_VRAM_ADDR <= (SATB(6 downto 0) & "00000000") + (OBJ_NUM & "10");
			SP_SEL <= '1';
			SPC <= SPC_CALC_XY;

		when SPC_CALC_XY =>
			if early_ack_sp='0' then
				SP_SEL <= '0';
				OBJ_PRI := SP_VRAM_DO(15);
				OBJ_PAL := SP_VRAM_DO(14 downto 13);
				OBJ_VF  := SP_VRAM_DO(12);
				OBJ_HF  := SP_VRAM_DO(11);

				case OBJ_HS is
				when "00" =>	-- 8 pixels
					if OBJ_HF = '0' then
						OBJ_X_OFS := "00000";
					else
						OBJ_X_OFS := "00111";
					end if;
				when "01" =>	-- 16 pixels
					if OBJ_HF = '0' then
						OBJ_X_OFS := "00000";
					else
						OBJ_X_OFS := "01111";
					end if;
				when "11" =>	-- 32 pixels
					if OBJ_HF = '0' then
						OBJ_X_OFS := "00000";
					else
						OBJ_X_OFS := "11111";
					end if;
				when others =>	-- 24 pixels
					if OBJ_HF = '0' then
						OBJ_X_OFS := "00000";
					else
						OBJ_X_OFS := "10111";
					end if;
				end case;

				case OBJ_VS(1 downto 0) is
				when "00" =>	-- 8 pixels
					if OBJ_VF = '1' then
						OBJ_Y_OFS(4 downto 0) := "00" & not(OBJ_Y_OFS(2 downto 0));
					end if;
				when "01" =>	-- 16 pixels
					if OBJ_VF = '1' then
						OBJ_Y_OFS(4 downto 0) := "0" & not(OBJ_Y_OFS(3 downto 0));
					end if;
				when "11" =>	-- 32 pixels
					if OBJ_VF= '1' then
						OBJ_Y_OFS(4 downto 0) := not(OBJ_Y_OFS(4 downto 0));
					end if;
				when others =>	-- 24 pixels
					if OBJ_VF = '1' then
						OBJ_Y_OFS(2 downto 0) := not(OBJ_Y_OFS(2 downto 0));
						case OBJ_Y_OFS(4 downto 3) is
						when "00"   => OBJ_Y_OFS(4 downto 3) := "10";
						when "10"   => OBJ_Y_OFS(4 downto 3) := "00";
						when others => OBJ_Y_OFS(4 downto 3) := "01";
						end case;
					end if;
				end case;

				OBJ_NB := OBJ_NB + 1;
				OBJ_POS := OBJ_X - "010000000";
				if INTERLACE_FF = '0' then
					OBJ_TILEBASE := (SP_VRAM_DO(10 downto 0) & "0000") + (OBJ_Y_OFS & "0");
				else
					OBJ_TILEBASE := (SP_VRAM_DO(9 downto 0) & "00000") + (OBJ_Y_OFS(7 downto 0) & ODD & "0");
				end if;
				SPC <= SPC_LOOP;
			end if;

		-- loop over all sprite pixels on the current line
		when SPC_LOOP =>
			if (H40 = '1' and OBJ_PIX = 320) or (H40 = '0' and OBJ_PIX = 256) then
				-- limit total sprite pixels per line
				OBJ_DOT_OVERFLOW := '1';
				SPC <= SPC_DONE;
				SOVR <= '1';
			else
				OBJ_COLINFO_ADDR_A <= OBJ_POS;
				if (OBJ_X_OFS(1 downto 0) = "00" and OBJ_HF = '0') or (OBJ_X_OFS(1 downto 0) = "11" and OBJ_HF = '1') then

					case OBJ_VS is
					-- 8 pixels
					when "000"       => SP_VRAM_ADDR <= OBJ_TILEBASE + (OBJ_X_OFS(4 downto 3) & "000" & OBJ_X_OFS(2));
					-- 16 pixels
					when "001"|"100" => SP_VRAM_ADDR <= OBJ_TILEBASE + (OBJ_X_OFS(4 downto 3) & "0000" & OBJ_X_OFS(2));
					-- 24 pixels
					when "010" =>
						case OBJ_X_OFS(4 downto 3) is
						when "00"   => SP_VRAM_ADDR <= OBJ_TILEBASE + OBJ_X_OFS(2);
						when "01"   => SP_VRAM_ADDR <= OBJ_TILEBASE + ("0011000" & OBJ_X_OFS(2));
						when "11"   => SP_VRAM_ADDR <= OBJ_TILEBASE + ("1001000" & OBJ_X_OFS(2));
						when others => SP_VRAM_ADDR <= OBJ_TILEBASE + ("0110000" & OBJ_X_OFS(2));
						end case;
					-- 32 pixels
					when "011"|"101" => SP_VRAM_ADDR <= OBJ_TILEBASE + (OBJ_X_OFS(4 downto 3) & "00000" & OBJ_X_OFS(2));
					-- 48 pixels (doubleres)
					when "110" =>
						case OBJ_X_OFS(4 downto 3) is
						when "00"   => SP_VRAM_ADDR <= OBJ_TILEBASE + OBJ_X_OFS(2);
						when "01"   => SP_VRAM_ADDR <= OBJ_TILEBASE + ("00110000" & OBJ_X_OFS(2));
						when "11"   => SP_VRAM_ADDR <= OBJ_TILEBASE + ("10010000" & OBJ_X_OFS(2));
						when others => SP_VRAM_ADDR <= OBJ_TILEBASE + ("01100000" & OBJ_X_OFS(2));
						end case;
					-- 64 pixels (doubleres)
					when others    => SP_VRAM_ADDR <= OBJ_TILEBASE + (OBJ_X_OFS(4 downto 3) & "000000" & OBJ_X_OFS(2));
					end case;

					SP_SEL <= '1';
					SPC <= SPC_TILE_RD;
				else
					case OBJ_X_OFS(1 downto 0) is
					when "00"   => OBJ_COLNO := SP_VRAM_DO(15 downto 12);
					when "01"   => OBJ_COLNO := SP_VRAM_DO(11 downto 8);
					when "10"   => OBJ_COLNO := SP_VRAM_DO(7 downto 4);
					when others => OBJ_COLNO := SP_VRAM_DO(3 downto 0);
					end case;
					SPC <= SPC_WAIT;
				end if;
			end if;

		when SPC_WAIT =>
			SPC <= SPC_PLOT;

		when SPC_PLOT =>
			if OBJ_POS < 320 then
				if OBJ_COLINFO_Q_A(3 downto 0) = "0000" then
					if OBJ_MASKED = '0' then
						OBJ_COLINFO_WE_A <= '1';
						OBJ_COLINFO_D_A <= OBJ_PRI & OBJ_PAL & OBJ_COLNO;
					end if;
				else
					if OBJ_COLNO /= "0000" then
						SCOL <= '1';
					end if;
				end if;
			end if;
			OBJ_POS := OBJ_POS + 1;
			OBJ_PIX := OBJ_PIX + 1;
			if OBJ_HF = '1' then
				if OBJ_X_OFS = "00000" then
					SPC <= SPC_NEXT;
				else
					OBJ_X_OFS := OBJ_X_OFS - 1;
					SPC <= SPC_LOOP;
				end if;
			else
				if (OBJ_X_OFS = "00111" and OBJ_HS = "00")
				or (OBJ_X_OFS = "01111" and OBJ_HS = "01")
				or (OBJ_X_OFS = "11111" and OBJ_HS = "11")
				or (OBJ_X_OFS = "10111" and OBJ_HS = "10")
				then
					SPC <= SPC_NEXT;
				else
					OBJ_X_OFS := OBJ_X_OFS + 1;
					SPC <= SPC_LOOP;
				end if;
			end if;

		when SPC_TILE_RD =>
			if early_ack_sp='0' then
				SP_SEL <= '0';
				case OBJ_X_OFS(1 downto 0) is
				when "00"   => OBJ_COLNO := SP_VRAM_DO(15 downto 12);
				when "01"   => OBJ_COLNO := SP_VRAM_DO(11 downto 8);
				when "10"   => OBJ_COLNO := SP_VRAM_DO(7 downto 4);
				when others => OBJ_COLNO := SP_VRAM_DO(3 downto 0);
				end case;
				SPC <= SPC_PLOT;
			end if;

		when SPC_NEXT =>
			OBJ_NUM <= OBJ_LINK;
			
			-- counter to prevent endless loop.
			OBJ_CNT := OBJ_CNT + 1;

			-- limit number of sprites per line to 20 / 16
			if (H40 = '1' and OBJ_NB = 20)  or (H40 = '0' and  OBJ_NB = 16) then
				SPC <= SPC_DONE;
				SOVR <= '1';
			elsif OBJ_LINK = 0 or 
				 (H40 = '1' and (OBJ_LINK >= 80 or OBJ_CNT >= 80)) or 
				 (H40 = '0' and (OBJ_LINK >= 64 or OBJ_CNT >= 64))
			then
				SPC <= SPC_DONE;
			else
				SPC <= SPC_Y_RD;
			end if;

		when others => -- SPC_DONE
			SP_SEL <= '0';
			if SPE_ACTIVE = '0' then
				SPC <= SPC_INIT;
			end if;
		end case;
	end if;
end process;


----------------------------------------------------------------
-- VIDEO COUNTING
----------------------------------------------------------------
H_DISP_START    <= conv_std_logic_vector(H_DISP_START_H40, 9)     when H40='1'
              else conv_std_logic_vector(H_DISP_START_H32, 9);
H_DISP_WIDTH    <= conv_std_logic_vector(H_DISP_WIDTH_H40, 9)     when H40='1'
              else conv_std_logic_vector(H_DISP_WIDTH_H32, 9);
H_TOTAL_WIDTH   <= conv_std_logic_vector(H_TOTAL_WIDTH_H40, 9)    when H40='1'
              else conv_std_logic_vector(H_TOTAL_WIDTH_H32, 9);
H_INT_POS       <= conv_std_logic_vector(H_INT_H40, 9)            when H40='1'
              else conv_std_logic_vector(H_INT_H32, 9);
HSYNC_START     <= conv_std_logic_vector(HSYNC_START_H40, 9)      when H40='1'
              else conv_std_logic_vector(HSYNC_START_H32, 9);
HSYNC_SZ        <= conv_std_logic_vector(HSYNC_SZ_H40, 9)         when H40='1'
              else conv_std_logic_vector(HSYNC_SZ_H32, 9);
HBLANK_START    <= conv_std_logic_vector(HBLANK_START_H40, 9)     when H40='1'
              else conv_std_logic_vector(HBLANK_START_H32, 9);
HBLANK_END      <= conv_std_logic_vector(HBLANK_END_H40, 9)       when H40='1'
              else conv_std_logic_vector(HBLANK_END_H32, 9);

VSYNC_START     <= conv_std_logic_vector(VSYNC_START_PAL_V30, 9)  when V30='1' and PAL='1'
              else conv_std_logic_vector(VSYNC_START_PAL_V28, 9)  when V30='0' and PAL='1'
              else conv_std_logic_vector(VSYNC_START_NTSC_V30, 9) when V30='1' and PAL='0'
              else conv_std_logic_vector(VSYNC_START_NTSC_V28, 9);
V_DISP_START    <= conv_std_logic_vector(V_DISP_START_V30, 9)     when V30='1'
              else conv_std_logic_vector(V_DISP_START_PAL_V28, 9) when PAL='1'
              else conv_std_logic_vector(V_DISP_START_NTSC_V28, 9);
V_DISP_HEIGHT   <= conv_std_logic_vector(V_DISP_HEIGHT_V30, 9)    when V30='1'
              else conv_std_logic_vector(V_DISP_HEIGHT_V28, 9);
V_TOTAL_HEIGHT  <= conv_std_logic_vector(PAL_LINES, 9)            when PAL='1'
              else conv_std_logic_vector(NTSC_LINES, 9);
V_INT_POS       <= conv_std_logic_vector(V_INT_V30, 9)            when V30='1'
              else conv_std_logic_vector(V_INT_V28, 9);

HV8 <= HV_VCNT(8) when INTERLACE_FF = '1' else HV_VCNT(0);

TG68_HINT_FF <= IE1 and HINT_PENDING;
TG68_HINT <= TG68_HINT_FF;
TG68_VINT_FF <= IE0 and TG68_VINT_PENDING;
TG68_VINT <= TG68_VINT_FF;

process( RST_N, CLK )
	variable old_INTACK : std_logic;
begin
	if RST_N = '0' then

		HV_PIXDIV <= (others => '0');
		HV_HCNT <= (others => '0');
		HV_VCNT <= (others => '0');

		T80_VINT <= '0';
		TG68_VINT_PENDING <= '0';
		HINT_PENDING <= '0';

		IN_HBL <= '0';
		IN_VBL <= '1';

		FIFO_EN <= '0';
		FIFO_CNT <= (others => '0');

	elsif rising_edge(CLK) then

		if old_INTACK = '0' and TG68_INTACK = '1' then
			if TG68_VINT_FF = '1' then
				TG68_VINT_PENDING <= '0';
			elsif TG68_HINT_FF = '1' then
				HINT_PENDING <= '0';
			end if;
		end if;
		old_INTACK := TG68_INTACK;

		if T80_INTACK = '1' then
			T80_VINT <= '0';
		end if;

		if M3='0' then
			HV <= HV_VCNT(7 downto 1) & HV8 & HV_HCNT(8 downto 1);
		end if;

		FIFO_EN <= '0';

		CE_PIX <= '0';

		HV_PIXDIV <= HV_PIXDIV + 1;
		if (H40 = '1' and HV_PIXDIV = 8-1) or (H40 = '0' and HV_PIXDIV = 10-1) then
			HV_PIXDIV <= (others => '0');
			if HV_HCNT = H_DISP_START + H_TOTAL_WIDTH - 1 then
				-- we're just after HSYNC
				HV_HCNT <= H_DISP_START;
			else
				HV_HCNT <= HV_HCNT + 1;
			end if;

			CE_PIX <= '1';

			if HV_HCNT = H_INT_POS then
				if HV_VCNT = V_DISP_START + V_TOTAL_HEIGHT - 1 then --VDISP_START is negative
					--just after VSYNC
					HV_VCNT <= V_DISP_START;
					FIELD <= ODD;
				else
					HV_VCNT <= HV_VCNT + 1;
				end if;
				BGB_VSRAM1_LATCH <= VSRAM_BGB(9 downto 0);
				BGA_VSRAM0_LATCH <= VSRAM_BGA(9 downto 0);

				if HV_VCNT = "1"&x"FE" then
					IN_VBL <= '0';
				elsif HV_VCNT = "1"&x"FF" then
					IN_VBL_D <= '0';
					if HIT = 0 then
						HINT_PENDING <= '1';
						HINT_COUNT <= (others => '0');
					else
						HINT_COUNT <= HIT - 1;
					end if;
				elsif HV_VCNT < V_DISP_HEIGHT - 1
				then
					if HINT_COUNT = 0 then
						HINT_PENDING <= '1';
						HINT_COUNT <= HIT;
					else
						HINT_COUNT <= HINT_COUNT - 1;
					end if;
				end if;
				if HV_VCNT = V_DISP_HEIGHT - 1 then
					IN_VBL <= '1';
					IN_VBL_D <= '1';
					ODD <= not ODD and LSM(0);
				end if;
			end if;

			if HV_HCNT = HBLANK_END then --active display
				IN_HBL <= '0';
			end if;

			if HV_HCNT = HBLANK_START then -- blanking
				IN_HBL <= '1';
			end if;

			if HV_HCNT = 0 then
				if HV_VCNT = V_INT_POS
				then
					TG68_VINT_PENDING <= '1';
					T80_VINT <= '1';
				elsif HV_VCNT = V_INT_POS + 1
				then
					T80_VINT <= '0';
				end if;
			end if;

			FIFO_CNT <= FIFO_CNT + 1;
			if (H40 = '0' and FIFO_CNT = 20) or (H40 = '1' and FIFO_CNT = 22) or HV_HCNT = H_INT_POS then
				FIFO_CNT <= (others => '0');
			end if;

			if IN_VBL = '1' or DE = '0' then
				FIFO_EN <= '1'; --HV_VCNT(0);
			elsif FIFO_CNT = 0 then
				FIFO_EN <= '1';
			end if;
		end if;
	end if;
end process;

-- TIMING MANAGEMENT
BG_Y <= HV_VCNT;
PRE_V_ACTIVE <= '1' when HV_VCNT = "1"&x"FF" or HV_VCNT < V_DISP_HEIGHT - 1 else '0';
V_ACTIVE <= '1' when HV_VCNT < V_DISP_HEIGHT else '0';
-- Background generation runs during active display.
-- Original timing is 2 pixels (or cells?) before the actual pixel.
-- But the background generators are not timed, but free running now.
BGEN_ACTIVE <= '1' when V_ACTIVE = '1' and HV_HCNT = HBLANK_END - 8 else '0';

SPE_ACTIVE <= '1' when PRE_V_ACTIVE = '1' and HV_HCNT = H_INT_POS-2 else '0';

-- PIXEL COUNTER AND OUTPUT
-- ALSO CLEARS THE SPRITE COLINFO BUFFER RIGHT AFTER RENDERING
process( RST_N, CLK )
	variable v8   : std_logic;
	variable col  : std_logic_vector(5 downto 0);
	variable cold : std_logic_vector(5 downto 0);
	variable sh   : std_logic_vector(2 downto 0);
	variable act  : std_logic;
begin
	if rising_edge(CLK) then
		OBJ_COLINFO_WE_B <= '0';

		case HV_PIXDIV is
		when "0000" =>
			act := '0';
			if HV_HCNT > HBLANK_END and HV_HCNT <= HBLANK_END + H_DISP_WIDTH then
				act := '1';
			end if;

		when "0010" =>
			sh := "10" & (BGA_COLINFO_Q_B(6) or BGB_COLINFO_Q_B(6) or not SHI);
			if SHI = '1' and OBJ_COLINFO_Q_B(3 downto 0) /= "0000" and 
			   OBJ_COLINFO_Q_B(6) >= (BGA_COLINFO_Q_B(6) or BGB_COLINFO_Q_B(6))
			then
				if OBJ_COLINFO_Q_B(5 downto 0) = 62 then
					sh := sh + 1;
					sh(2) := '0';
				elsif OBJ_COLINFO_Q_B(5 downto 0) = 63 then
					sh := "000";
				elsif OBJ_COLINFO_Q_B(3 downto 0) = 14 then
					sh(0) := '1';
				else
					sh(0) := sh(0) or OBJ_COLINFO_Q_B(6);
				end if;
			end if;

			if DE = '0' then
				col := BGCOL;
			elsif OBJ_COLINFO_Q_B(3 downto 0) /= "0000" and OBJ_COLINFO_Q_B(6) = '1' and sh(2) = '1' then
				col := OBJ_COLINFO_Q_B(5 downto 0);
			elsif BGA_COLINFO_Q_B(3 downto 0) /= "0000" and BGA_COLINFO_Q_B(6) = '1' then
				col := BGA_COLINFO_Q_B(5 downto 0);
			elsif BGB_COLINFO_Q_B(3 downto 0) /= "0000" and BGB_COLINFO_Q_B(6) = '1' then
				col := BGB_COLINFO_Q_B(5 downto 0);
			elsif OBJ_COLINFO_Q_B(3 downto 0) /= "0000" and sh(2) = '1' then
				col := OBJ_COLINFO_Q_B(5 downto 0);
			elsif BGA_COLINFO_Q_B(3 downto 0) /= "0000" then
				col := BGA_COLINFO_Q_B(5 downto 0);
			elsif BGB_COLINFO_Q_B(3 downto 0) /= "0000" then
				col := BGB_COLINFO_Q_B(5 downto 0);
			else
				col := BGCOL;
			end if;
			
			case DBG(8 downto 7) is
				when "00" => cold := BGCOL;
				when "01" => cold := OBJ_COLINFO_Q_B(5 downto 0);
				when "10" => cold := BGA_COLINFO_Q_B(5 downto 0);
				when "11" => cold := BGB_COLINFO_Q_B(5 downto 0);
			end case;

			if DBG(6) = '1' then
				col := cold;
			elsif DBG(8 downto 7) /= "00" then
				col := col and cold;
			end if;

			COLOR_NUM <= col;
			OBJ_COLINFO_WE_B <= act;

		when "0100" =>
			HBL <= not act;
			VBL <= IN_VBL_D;

			COLINFO_ADDR_B <= COLINFO_ADDR_B + 1;
			if IN_VBL_D = '1' or act = '0' then
				R <= (others => '0');
				G <= (others => '0');
				B <= (others => '0');
				COLINFO_ADDR_B <= (others => '0');
			else
				if sh(1 downto 0) = 0 then
					B <= '0' & COLOR(8 downto 6);
					G <= '0' & COLOR(5 downto 3);
					R <= '0' & COLOR(2 downto 0);
				elsif sh(1 downto 0) = 1 then
					B <= COLOR(8 downto 6) & '0';
					G <= COLOR(5 downto 3) & '0';
					R <= COLOR(2 downto 0) & '0';
				else
					B <= '0' & COLOR(8 downto 6) + 7;
					G <= '0' & COLOR(5 downto 3) + 7;
					R <= '0' & COLOR(2 downto 0) + 7;
				end if;
			end if;
		when others => null;
		end case;
	end if;
end process;

process( RST_N, CLK )
	variable cnt : std_logic_vector(8 downto 0);
begin
	if RST_N = '0' then
		VS <= '0';
		HS <= '0';
	elsif rising_edge(CLK) then
		if HV_PIXDIV = 0 then
			if HV_HCNT = HSYNC_START then
				HS <= '1';
				cnt := HSYNC_SZ;
				if HV_VCNT = VSYNC_START then
					VS <= '1';
				end if;
			elsif cnt /= 0 then
				cnt := cnt - 1;
				if cnt = 0 then
					HS <= '0';
					if HV_VCNT = VSYNC_START + VS_LINES - 1 then
						VS <= '0';
					end if;
				end if;
			end if;
		end if;
	end if;
end process;

----------------------------------------------------------------
-- CPU INTERFACE
----------------------------------------------------------------

DTACK_N <= FF_DTACK_N;
DO <= FF_DO;
process( RST_N, CLK )
begin
	if RST_N = '0' then
		FF_DTACK_N <= '1';
		FF_DO <= (others => '1');

		PENDING <= '0';
		ADDR_LATCH <= (others => '0');
		ADDR_SET_REQ <= '0';
		REG_SET_REQ <= '0';
		CODE <= (others => '0');
		
		DT_RD_SEL <= '0';
		DT_FF_SEL <= '0';
		
		SOVR_CLR <= '0';
		SCOL_CLR <= '0';
		
	elsif rising_edge(CLK) then
		SOVR_CLR <= '0';
		SCOL_CLR <= '0';
	
		if SEL = '0' then
			FF_DTACK_N <= '1';
		elsif SEL = '1' and FF_DTACK_N = '1' then			
			if RNW = '0' then -- Write
				if A(4 downto 2) = "000" then
					-- Data Port 0-3
					PENDING <= '0';

					DT_FF_DATA <= DI;
					DT_FF_CODE <= CODE(3 downto 0);

					if DT_FF_DTACK_N = '1' then
						DT_FF_SEL <= '1';
					else
						DT_FF_SEL <= '0';
						FF_DTACK_N <= '0';
					end if;

				elsif A(4 downto 2) = "001" then
					-- Control Port 4-7
					if PENDING = '1' then
						CODE(4 downto 2) <= DI(6 downto 4);
						if DMA = '1' then
							CODE(5) <= DI(7);
						end if;
						ADDR_LATCH <= DI(2 downto 0) & ADDR(13 downto 0);

						-- In case of DMA VBUS request, hold the TG68 with DTACK_N
						-- it should avoid the use of a CLKEN signal
						if ADDR_SET_ACK = '0' or DMA_VBUS = '1' then							
							ADDR_SET_REQ <= '1';
						else
							ADDR_SET_REQ <= '0';
							FF_DTACK_N <= '0';
							PENDING <= '0';
						end if;
					else						
						CODE(1 downto 0) <= DI(15 downto 14);
						if DI(15 downto 14) = "10" then
							-- Register Set
							REG_LATCH <= DI;
							if REG_SET_ACK = '0' then
								REG_SET_REQ <= '1';
							else
								REG_SET_REQ <= '0';
								FF_DTACK_N <= '0';
							end if;							
						else
							-- Address Set
							ADDR_LATCH(13 downto 0) <= DI(13 downto 0);
							if ADDR_SET_ACK = '0' then
								ADDR_SET_REQ <= '1';
							else
								ADDR_SET_REQ <= '0';
								FF_DTACK_N <= '0';
								PENDING <= '1';
								CODE(5 downto 4) <= "00"; -- attempt to fix lotus i
							end if;
						end if;
						-- Note : Genesis Plus does address setting
						-- even in Register Set mode. Normal ?
					end if;
					
				elsif A(4 downto 2) = "111" then
					-- Debug port 1C - 1F
					DBG <= DI;
					FF_DTACK_N <= '0';

				else
					-- Unused
					FF_DTACK_N <= '0';

				end if;

			else -- Read
				if A(4) = '1' then
					-- Unused ports 10-1F
					FF_DO <= x"FFFF";
					FF_DTACK_N <= '0';

				elsif A(3) = '1' then
					-- HV Counter 08-0F
					FF_DO <= HV;
					FF_DTACK_N <= '0';
				
				elsif A(2) = '1' then
					-- Control Port (Read Status Register) 04-07
					PENDING <= '0';
					FF_DO <= STATUS;
					SOVR_CLR <= '1';
					SCOL_CLR <= '1';
					FF_DTACK_N <= '0';

				else
					-- Data Port 00-03
					PENDING <= '0';
					if CODE = "001000" -- CRAM Read
					or CODE = "000100" -- VSRAM Read
					or CODE = "000000" -- VRAM Read
					then
						if DT_RD_DTACK_N = '1' then
							DT_RD_SEL <= '1';
							DT_RD_CODE <= CODE(3 downto 0);
						else
							DT_RD_SEL <= '0';
							FF_DO <= DT_RD_DATA;
							FF_DTACK_N <= '0';
						end if;
					else
						FF_DTACK_N <= '0';
					end if;
				end if;
			end if;
		end if;
	end if;
end process;

----------------------------------------------------------------
-- DATA TRANSFER CONTROLLER
----------------------------------------------------------------
VBUS_ADDR <= FF_VBUS_ADDR;
VBUS_SEL <= FF_VBUS_SEL;
VBUS_BUSY <= DMA_VBUS;

process( RST_N, CLK )
begin
	if RST_N = '0' then

		REG <= (others => (others => '0'));

		ADDR <= (others => '0');
		ADDR_SET_ACK <= '0';
		REG_SET_ACK <= '0';
		
		DMA_SEL <= '0';
		
		FIFO_RD_POS <= "00";
		FIFO_WR_POS <= "00";
		FIFO_EMPTY <= '1';
		FIFO_FULL <= '0';
		FIFO_SKIP <= '0';

		DT_RD_DTACK_N <= '1';
		DT_FF_DTACK_N <= '1';

		FF_VBUS_ADDR <= (others => '0');
		FF_VBUS_SEL	<= '0';
		DT_VBUS_SEL <= '0';
		
		DMA_FILL_PRE <= '0';
		DMA_FILL <= '0';
		DMAF_SET_REQ <= '0';
		DMA_COPY <= '0';
		DMA_VBUS <= '0';
		DMA_SOURCE <= (others => '0');
		DMA_LENGTH <= (others => '0');
		
		DTC <= DTC_IDLE;
		DMAC <= DMA_IDLE;
		
		COLOR_WE <= '0';
		VSRAM_WE <= '0';
		
	elsif rising_edge(CLK) then

		if FIFO_RD_POS = FIFO_WR_POS then
			FIFO_EMPTY <= '1';
		else
			FIFO_EMPTY <= '0';
		end if;
		if FIFO_WR_POS + 1 = FIFO_RD_POS then
			FIFO_FULL <= '1';
		else
			FIFO_FULL <= '0';
		end if;		
		if DT_RD_SEL = '0' then
			DT_RD_DTACK_N <= '1';
		end if;
		if DT_FF_SEL = '0' and DT_VBUS_SEL = '0' then
			DT_FF_DTACK_N <= '1';
		end if;
		if ADDR_SET_REQ = '0' then
			ADDR_SET_ACK <= '0';
		end if;
		if REG_SET_REQ = '0' then
			REG_SET_ACK <= '0';
		end if;

		COLOR_WE <= '0';
		VSRAM_WE <= '0';

		if DT_FF_SEL = '1' and (FIFO_WR_POS + 1 /= FIFO_RD_POS) and DT_FF_DTACK_N = '1' then
			FIFO_ADDR( CONV_INTEGER( FIFO_WR_POS ) ) <= ADDR;
			FIFO_DATA( CONV_INTEGER( FIFO_WR_POS ) ) <= DT_FF_DATA;
			FIFO_CODE( CONV_INTEGER( FIFO_WR_POS ) ) <= DT_FF_CODE;
			FIFO_WR_POS <= FIFO_WR_POS + 1;
			ADDR <= ADDR + ADDR_STEP;
			DT_FF_DTACK_N <= '0';
		elsif DT_VBUS_SEL = '1' and (FIFO_WR_POS + 1 /= FIFO_RD_POS) and DT_FF_DTACK_N = '1' then
			FIFO_ADDR( CONV_INTEGER( FIFO_WR_POS ) ) <= ADDR;
			FIFO_DATA( CONV_INTEGER( FIFO_WR_POS ) ) <= DT_DMAV_DATA;
			FIFO_CODE( CONV_INTEGER( FIFO_WR_POS ) ) <= CODE(3 downto 0);
			FIFO_WR_POS <= FIFO_WR_POS + 1;
			ADDR <= ADDR + ADDR_STEP;
			DT_FF_DTACK_N <= '0';
		end if;

		if REG_SET_REQ = '1' and REG_SET_ACK = '0' and IN_DMA = '0' then
			if (M5 = '1' or REG_LATCH(12 downto 8) <= 10) then
				-- mask registers above 10 in Mode4
				if (REG_LATCH(12 downto 8) <= 23) then
					REG( CONV_INTEGER( REG_LATCH(12 downto 8)) ) <= REG_LATCH(7 downto 0);
				end if;
			end if;
			REG_SET_ACK <= '1';
		end if;

		case DTC is
		when DTC_IDLE =>
			if FIFO_EN = '1' then
				FIFO_SKIP <= '0';
			end if;
			if FIFO_EN = '1' and FIFO_SKIP = '0' then
				if FIFO_RD_POS /= FIFO_WR_POS then
					DTC <= DTC_FIFO_RD;
				elsif DT_RD_SEL = '1' and DT_RD_DTACK_N = '1' then
					case DT_RD_CODE is
					when "1000" => -- CRAM Read
						DTC <= DTC_CRAM_RD;
					when "0100" => -- VSRAM Read
						DTC <= DTC_VSRAM_RD;
					when others => -- VRAM Read
						DTC <= DTC_VRAM_RD1;
					end case;
				end if;
			end if;
		
		when DTC_FIFO_RD =>
			DT_WR_ADDR <= FIFO_ADDR( CONV_INTEGER( FIFO_RD_POS ) );
			DT_WR_DATA <= FIFO_DATA( CONV_INTEGER( FIFO_RD_POS ) );
			FIFO_RD_POS <= FIFO_RD_POS + 1;
			case FIFO_CODE( CONV_INTEGER( FIFO_RD_POS ) ) is
			when "0011" => -- CRAM Write
				DTC <= DTC_CRAM_WR;
			when "0101" => -- VSRAM Write
				DTC <= DTC_VSRAM_WR;
			when "0001" => -- VRAM Write
				DTC <= DTC_VRAM_WR1;
			when others => --invalid target
				DTC <= DTC_WR_END;
			end case;
		
		when DTC_VRAM_WR1 =>
			--skip next FIFO slot since we write 16 bit now instead of the original 8
			FIFO_SKIP <= '1';
			DMA_SEL <= '1';
			DMA_VRAM_ADDR <= DT_WR_ADDR(16 downto 1);
			DMA_VRAM_RNW <= '0';
			if DT_WR_ADDR(0) = '0' then 
				DMA_VRAM_DI <= DT_WR_DATA;
			else
				DMA_VRAM_DI <= DT_WR_DATA(7 downto 0) & DT_WR_DATA(15 downto 8);
			end if;
			DMA_VRAM_UDS_N <= '0';
			DMA_VRAM_LDS_N <= '0';
				
			DTC <= DTC_VRAM_WR2;
		
		when DTC_VRAM_WR2 =>
			if early_ack_dma='0' then
				DMA_SEL <= '0';
				DTC <= DTC_WR_END;
			end if;

		when DTC_CRAM_WR =>
			COLOR_ADDR <= DT_WR_ADDR(6 downto 1);
			COLOR_D <= DT_WR_DATA(11 downto 9)&DT_WR_DATA(7 downto 5)&DT_WR_DATA(3 downto 1);
			COLOR_WE <= '1';
			DTC <= DTC_WR_END;

		when DTC_VSRAM_WR =>
			VSRAM_ADDR <= DT_WR_ADDR(6 downto 1);
			VSRAM_D <= DT_WR_DATA(10 downto 0);
			VSRAM_WE <= '1';
			DTC <= DTC_WR_END;

		when DTC_WR_END =>
			if DMA_FILL_PRE = '1' then
				DMAF_SET_REQ <= '1';
			end if;
			DTC <= DTC_IDLE;

		when DTC_VRAM_RD1 =>
			DMA_SEL <= '1';
			DMA_VRAM_ADDR <= ADDR(16 downto 1);
			DMA_VRAM_RNW <= '1';
			DMA_VRAM_UDS_N <= '0';
			DMA_VRAM_LDS_N <= '0';
			DTC <= DTC_VRAM_RD2;
		
		when DTC_VRAM_RD2 =>
			if early_ack_dma='0' then
				DMA_SEL <= '0';	
				DT_RD_DATA <= DMA_VRAM_DO;
				DT_RD_DTACK_N <= '0';
				ADDR <= ADDR + ADDR_STEP;
				DTC <= DTC_IDLE;
			end if;

		when DTC_CRAM_RD =>
			COLOR_ADDR <= ADDR(6 downto 1);
			DTC <= DTC_CRAM_RD1;

		when DTC_CRAM_RD1 =>
			-- cram address is set up
			DTC <= DTC_CRAM_RD2;

		when DTC_CRAM_RD2 =>
			DT_RD_DATA(11 downto 9) <= COLOR_Q(8 downto 6);
			DT_RD_DATA(7 downto 5) <= COLOR_Q(5 downto 3);
			DT_RD_DATA(3 downto 1) <= COLOR_Q(2 downto 0);
			--unused bits come from the next FIFO entry
			DT_RD_DATA(15 downto 12) <= FIFO_DATA( CONV_INTEGER( FIFO_RD_POS ) )(15 downto 12);
			DT_RD_DATA(8) <= FIFO_DATA( CONV_INTEGER( FIFO_RD_POS ) )(8);
			DT_RD_DATA(4) <= FIFO_DATA( CONV_INTEGER( FIFO_RD_POS ) )(4);
			DT_RD_DATA(0) <= FIFO_DATA( CONV_INTEGER( FIFO_RD_POS ) )(0);
			DT_RD_DTACK_N <= '0';
			ADDR <= ADDR + ADDR_STEP;	
			DTC <= DTC_IDLE;
			
		when DTC_VSRAM_RD =>
			VSRAM_ADDR <= DT_WR_ADDR(6 downto 1);
			DTC <= DTC_VSRAM_RD1;

		when DTC_VSRAM_RD1 =>
			DTC <= DTC_VSRAM_RD2;

		when DTC_VSRAM_RD2 =>
			if VSRAM_ADDR(0) = '0' then
				DT_RD_DATA(10 downto 0) <= VSRAM_Q0;
			else
				DT_RD_DATA(10 downto 0) <= VSRAM_Q1;
			end if;
			DT_RD_DATA(15 downto 11) <= FIFO_DATA( CONV_INTEGER( FIFO_RD_POS ) )(15 downto 11);
			DT_RD_DTACK_N <= '0';
			ADDR <= ADDR + ADDR_STEP;	
			DTC <= DTC_IDLE;

		when others => null;
		end case;

		----------------------------------------------------------------
		-- DMA ENGINE
		----------------------------------------------------------------
		if ADDR_SET_REQ = '1' and ADDR_SET_ACK = '0' and IN_DMA = '0' then
			ADDR <= ADDR_LATCH;
			if CODE(5) = '1' and PENDING = '1' then
				if REG(23)(7) = '0' then
					DMA_VBUS <= '1';
				else
					if REG(23)(6) = '0' then
						DMA_FILL_PRE <= '1';
					else
						DMA_COPY <= '1';
					end if;
				end if;
			end if;
			ADDR_SET_ACK <= '1';
		end if;

		if DMA_FILL_PRE = '1' and DMAF_SET_REQ = '1' and FIFO_RD_POS = FIFO_WR_POS then
			DT_DMAF_DATA <= DT_FF_DATA;
			DMA_FILL <= '1';
			DMAF_SET_REQ <= '0';
		end if;

		case DMAC is
		when DMA_IDLE =>
			if DMA_VBUS = '1' then
				DMAC <= DMA_VBUS_INIT;
			elsif DMA_FILL = '1' then
				DMAC <= DMA_FILL_INIT;
			elsif DMA_COPY = '1' then
				DMAC <= DMA_COPY_INIT;
			end if;
		----------------------------------------------------------------
		-- DMA FILL
		----------------------------------------------------------------
			
		when DMA_FILL_INIT =>
			DMA_SOURCE <= REG(22) & REG(21);
			DMA_LENGTH <= REG(20) & REG(19);
			DMAC <= DMA_FILL_START;

		when DMA_FILL_START =>
			case CODE(3 downto 0) is
			when "0011" => -- CRAM Write
				DMAC <= DMA_FILL_CRAM;
			when "0101" => -- VSRAM Write
				DMAC <= DMA_FILL_VSRAM;
			when others => -- VRAM Write
				DMAC <= DMA_FILL_WR;
			end case;

		when DMA_FILL_CRAM =>
			COLOR_WE <= '1';
			COLOR_ADDR <= ADDR(6 downto 1);
			-- CRAM fill gets its data from the next FIFO write position
			COLOR_D(8 downto 6) <= FIFO_DATA( CONV_INTEGER( FIFO_WR_POS ) )(11 downto 9);
			COLOR_D(5 downto 3) <= FIFO_DATA( CONV_INTEGER( FIFO_WR_POS ) )(7 downto 5);
			COLOR_D(2 downto 0) <= FIFO_DATA( CONV_INTEGER( FIFO_WR_POS ) )(3 downto 1);
			ADDR <= ADDR + ADDR_STEP;
			DMA_SOURCE <= DMA_SOURCE + ADDR_STEP;
			DMA_LENGTH <= DMA_LENGTH - 1;
			DMAC <= DMA_FILL_LOOP;
			
		when DMA_FILL_VSRAM =>
			VSRAM_ADDR <= ADDR(6 downto 1);
			VSRAM_D <= DT_DMAF_DATA(10 downto 0);
			VSRAM_WE <= '1';
			ADDR <= ADDR + ADDR_STEP;
			DMA_SOURCE <= DMA_SOURCE + ADDR_STEP;
			DMA_LENGTH <= DMA_LENGTH - 1;
			DMAC <= DMA_FILL_LOOP;

		when DMA_FILL_WR =>
			DMA_SEL <= '1';
			DMA_VRAM_ADDR <= ADDR(16 downto 1);
			DMA_VRAM_RNW <= '0';
			DMA_VRAM_DI <= DT_DMAF_DATA(15 downto 8) & DT_DMAF_DATA(15 downto 8);
			if ADDR(0) = '0' then
				DMA_VRAM_UDS_N <= '1';
				DMA_VRAM_LDS_N <= '0';
			else
				DMA_VRAM_UDS_N <= '0';
				DMA_VRAM_LDS_N <= '1';									
			end if;					
			DMAC <= DMA_FILL_WR2;
			
		when DMA_FILL_WR2 =>
			if early_ack_dma='0' then
				DMA_SEL <= '0';	
				ADDR <= ADDR + ADDR_STEP;
				DMA_SOURCE <= DMA_SOURCE + ADDR_STEP;
				DMA_LENGTH <= DMA_LENGTH - 1;
				DMAC <= DMA_FILL_LOOP;
			end if;
		
		when DMA_FILL_LOOP =>
			if DMA_LENGTH = 0 then
				DMA_FILL_PRE <= '0';
				DMA_FILL <= '0';
				REG(20) <= x"00";
				REG(19) <= x"00";
				REG(22) <= DMA_SOURCE(15 downto 8);
				REG(21) <= DMA_SOURCE(7 downto 0);
				DMAC <= DMA_IDLE;
			else
				DMAC <= DMA_FILL_START;
			end if;

		----------------------------------------------------------------
		-- DMA COPY
		----------------------------------------------------------------

		when DMA_COPY_INIT =>
			DMA_LENGTH <= REG(20) & REG(19);
			DMA_SOURCE <= REG(22) & REG(21);
			DMAC <= DMA_COPY_RD;
			
		when DMA_COPY_RD =>
			DMA_SEL <= '1';
			DMA_VRAM_ADDR <= REG(23)(0) & DMA_SOURCE(15 downto 1);
			DMA_VRAM_RNW <= '1';
			DMA_VRAM_UDS_N <= '0';
			DMA_VRAM_LDS_N <= '0';
			DMAC <= DMA_COPY_RD2;
		
		when DMA_COPY_RD2 =>
			if early_ack_dma='0' then
				DMA_SEL <= '0';	
				DMAC <= DMA_COPY_WR;
			end if;

		when DMA_COPY_WR =>
			DMA_SEL <= '1';
			DMA_VRAM_ADDR <= ADDR(16 downto 1);
			DMA_VRAM_RNW <= '0';
			if DMA_SOURCE(0) = '0' then
				DMA_VRAM_DI <= DMA_VRAM_DO(7 downto 0) & DMA_VRAM_DO(7 downto 0);
			else
				DMA_VRAM_DI <= DMA_VRAM_DO(15 downto 8) & DMA_VRAM_DO(15 downto 8);
			end if;
			if ADDR(0) = '0' then
				DMA_VRAM_UDS_N <= '1';
				DMA_VRAM_LDS_N <= '0';
			else
				DMA_VRAM_UDS_N <= '0';
				DMA_VRAM_LDS_N <= '1';									
			end if;					
			DMAC <= DMA_COPY_WR2;

		when DMA_COPY_WR2 =>
			if early_ack_dma='0' then
				DMA_SEL <= '0';	
				ADDR <= ADDR + ADDR_STEP;
				DMA_LENGTH <= DMA_LENGTH - 1;
				DMA_SOURCE <= DMA_SOURCE + 1;
				DMAC <= DMA_COPY_LOOP;
			end if;
		
		when DMA_COPY_LOOP =>
			if DMA_LENGTH = 0 then
				DMA_COPY <= '0';
				REG(20) <= x"00";
				REG(19) <= x"00";
				REG(22) <= DMA_SOURCE(15 downto 8);
				REG(21) <= DMA_SOURCE(7 downto 0);
				DMAC <= DMA_IDLE;
			else
				DMAC <= DMA_COPY_RD;
			end if;

		----------------------------------------------------------------
		-- DMA VBUS
		----------------------------------------------------------------
			
		when DMA_VBUS_INIT =>
			DMA_LENGTH <= REG(20) & REG(19);
			DMA_SOURCE <= REG(22) & REG(21);
			DMAC <= DMA_VBUS_RD;
			
		when DMA_VBUS_RD =>
			FF_VBUS_SEL <= '1';
			FF_VBUS_ADDR <= REG(23)(6 downto 0) & DMA_SOURCE & '0';
			DMAC <= DMA_VBUS_RD2;

		when DMA_VBUS_RD2 =>
			if VBUS_DTACK_N = '0' then
				FF_VBUS_SEL <= '0';
				DT_DMAV_DATA <= VBUS_DATA;
				DMAC <= DMA_VBUS_SEL;
			end if;

		when DMA_VBUS_SEL =>
			if DT_FF_DTACK_N = '1' then
				DT_VBUS_SEL <= '1';
				DMA_LENGTH <= DMA_LENGTH - 1;
				DMA_SOURCE <= DMA_SOURCE + 1;
				DMAC <= DMA_VBUS_LOOP;
			end if;

		when DMA_VBUS_LOOP =>
			if DT_FF_DTACK_N = '0' then
				DT_VBUS_SEL <= '0';
				if DMA_LENGTH = 0 then
					DMA_VBUS <= '0';
					REG(20) <= x"00";
					REG(19) <= x"00";
					REG(22) <= DMA_SOURCE(15 downto 8);
					REG(21) <= DMA_SOURCE(7 downto 0);
					DMAC <= DMA_IDLE;
				else
					DMAC <= DMA_VBUS_RD;
				end if;
			end if;
			
		when others => null;
		end case;
	end if;
end process;

end rtl;
