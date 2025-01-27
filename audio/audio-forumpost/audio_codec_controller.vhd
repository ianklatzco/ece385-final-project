-- DE1 audio codec controller
-- This module is for controlling the codec via i2c
-- This module is executed by the top-level only once
-- References:  
-- 1.  DE1 User's manual
-- 2.  DE1 Reference design(s) (specifically, DE1_Default on DE1 CD)
-- 2.  Audio codec datasheet  
-- Bharathwaj Muthuswamy
-- EECS 3921 Fall 2010
-- muthuswamy@msoe.edu

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity audio_codec_controller is port(
	reset : in std_logic;
	clock : in std_logic;
	scl : out std_logic;
	sda : inout std_logic;
	stateOut : out integer range 0 to 7);
end audio_codec_controller;

architecture behavioral of audio_codec_controller is
	component i2c_controller is port
	(
		clock : in std_logic;
		i2c_scl : out std_logic;
		i2c_sda : inout std_logic;
		-- the input data to the i2c bus is given by the bus below
		-- we will shift out data from the bus (BIG-ENDIAN, MSb first)
		i2c_data : in std_logic_vector(23 downto 0); 
		reset : in std_logic; -- active low reset
		start : in std_logic;
		done : out std_logic;
		readWriteEnable : in std_logic;
		acknowledge : out std_logic);
	end component;

	signal i2cClock20KHz : std_logic := '0';
	signal i2cClockCounter : integer range 0 to 4095 := 0;
	
	signal i2cControllerData : std_logic_vector(23 downto 0);
	signal i2cRun,done,ack : std_logic;	
	
	signal muxSelect : integer range 0 to 15;
	signal incrementMuxSelect : std_logic := '0';
		
	signal i2cData : std_logic_vector(15 downto 0) := X"0000";
	type states is (resetState,transmit,checkAcknowledge,turnOffi2cControl,incrementMuxSelectBits,stop);
	signal currentState,nextState : states;
		
begin
		-- 20 KHz i2c clock (Mike: you are correct, i2c clock can go down to 10 KHz :D).
		process(clock,reset)
		begin
			if reset = '0' then
				i2cClockCounter <= 0;
				i2cClock20KHz <= '0';
			else
				if clock'event and clock = '1' then
						if i2cClockCounter <= 1249 then
							i2cClock20KHz <= '0';
							i2cClockCounter <= i2cClockCounter + 1;
						elsif i2cClockCounter >= 1250 and i2cClockCounter < 2499 then
							i2cClock20KHz <= '1';
							i2cClockCounter <= i2cClockCounter + 1;
						else
							i2cClockCounter <= 0;
							i2cClock20KHz <= '0';
						end if;
				end if;
			end if;
		end process;
		
		-- mini FSM to send out right data to audio codec via i2c
		process(i2cClock20KHz)
		begin
			if i2cClock20KHz'event and i2cClock20Khz = '1' then
				currentState <= nextState;
			end if;
		end process;
				
		process(currentState,reset,muxSelect,done,ack)
		begin
			case currentState is
				when resetState =>										
					if reset = '0' then
						nextState <= resetState;
					else
						nextState <= transmit;
					end if;
					incrementMuxSelect <= '0';
					i2cRun <= '0';
					 
				when transmit =>
					if muxSelect > 10 then					
						i2cRun <= '0';
						nextState <= stop;	
					else
						i2cRun <= '1';
						nextState <= checkAcknowledge;
					end if;		
					incrementMuxSelect <= '0';
					 
				when checkAcknowledge =>					
					if done = '1' then
						if ack = '0' then -- all the ACKs from codec better be low
							i2cRun <= '0';
							nextState <= turnOffi2cControl;
						else
							i2cRun <= '0';
							nextState <= transmit;
						end if;
					else					
						nextState <= checkAcknowledge;
					end if;					
					i2cRun <= '1';
					incrementMuxSelect <= '0';
					
				when turnOffi2cControl =>
					incrementMuxSelect <= '0';
					nextState <= incrementMuxSelectBits; 
					i2cRun <= '0';
 
				when incrementMuxSelectBits =>
					incrementMuxSelect <= '1';
					nextState <= transmit; 
					i2cRun <= '0';
 
				when stop =>
					nextState <= stop; -- don't need an others clause since all states have been accounted for
					i2cRun <= '0';
					incrementMuxSelect <= '0';					
 
			end case;
		end process;
		
		process(incrementMuxSelect,reset)
		begin
			if reset = '0' then
				muxSelect <= 0;
			else
				if incrementMuxSelect'event and incrementMuxSelect='1' then
					muxSelect <= muxSelect + 1;
				end if;				
			end if;
		end process;
		
		-- 0x34 is the base address of your device
		-- Refer to page 43 of the audio codec datasheet and the schematic
		-- on p. 38 of DE1 User's manual.  CSB is tied to ground so the 8-bit base address is
		-- b00110100 = 0x34.  		
		i2cControllerData <= X"34"&i2cData; 		
		-- data to be sent to audio code obtained via a MUX
		-- the select bits for the MUX are obtained by the mini FSM above
		-- the 16-bit value for each setting can be found
		-- in table 29 and 30 on pp. 46-50 of the audio codec datasheet (on the DE1 system CD)
		with muxSelect select
			i2cData <= X"0000" when 0, -- dummy data
						  X"001F" when 1, -- Left input volume is maximum
						  X"021F" when 2, -- Right input volume is maximum
						  X"0479" when 3, -- Left output volume is high
						  X"0679" when 4, -- Right output volume is high
						  X"0810" when 5, -- No sidetone, DAC: on, disable mic, line input to ADC: on
						  X"0A06" when 6, -- deemphasis to 48 KHz, enable high pass filter on ADC
						  X"0C00" when 7, -- no power down mode
						  X"0E01" when 8, -- MSB first, left-justified, slave mode
						  X"1002" when 9, -- 384 fs oversampling
						  X"1201" when 10, -- activate
						  X"ABCD" when others; -- should never occur
		
		
		-- instantiate i2c controller
		i2cController : i2c_controller port map (i2cClock20KHz,scl,sda,i2cControllerData,reset,i2cRun,done,'0',ack);
		
		-- User I/O
		with currentState select
			stateOut <= 0 when resetState,
						   1 when transmit,
							2 when checkAcknowledge,
							3 when turnOffi2cControl,
							4 when incrementMuxSelectBits,
							5 when stop;							
		
end behavioral;