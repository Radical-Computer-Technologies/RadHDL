library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package cordic_atan_pkg is
  constant CORDIC_PHASE_WIDTH : integer := 32;
  constant CORDIC_PI_POS : integer := 2147483647;
  constant CORDIC_PI_NEG : integer := -2147483647;
  type cordic_atan_array_t is array (0 to 31) of integer;
  constant CORDIC_ATAN : cordic_atan_array_t := (
    0 => 536870912,
    1 => 316933406,
    2 => 167458907,
    3 => 85004756,
    4 => 42667331,
    5 => 21354465,
    6 => 10679838,
    7 => 5340245,
    8 => 2670163,
    9 => 1335087,
    10 => 667544,
    11 => 333772,
    12 => 166886,
    13 => 83443,
    14 => 41722,
    15 => 20861,
    16 => 10430,
    17 => 5215,
    18 => 2608,
    19 => 1304,
    20 => 652,
    21 => 326,
    22 => 163,
    23 => 81,
    24 => 41,
    25 => 20,
    26 => 10,
    27 => 5,
    28 => 3,
    29 => 1,
    30 => 1,
    31 => 0
  );
end package;
