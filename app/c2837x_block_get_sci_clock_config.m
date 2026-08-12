function config = c2837x_block_get_sci_clock_config()
%C2837X_BLOCK_GET_SCI_CLOCK_CONFIG Return the bring-up SCI clock config.

sysclkHz = 200e6;
lspclkDivisor = 14;
config = struct( ...
    'sysclk_hz', sysclkHz, ...
    'lspclk_divisor', lspclkDivisor, ...
    'lspclk_hz', sysclkHz / lspclkDivisor);
end
