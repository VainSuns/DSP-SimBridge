function hash = c2837x_block_crc32(data)
%C2837X_BLOCK_CRC32  CRC-32/ISO-HDLC calculation for config_hash.
%
%   hash = c2837x_block_crc32(data)
%
%   Parameters:
%       data - uint8 array or char array (UTF-8 encoded string)
%       hash - uint32 CRC-32 hash value
%
%   CRC-32/ISO-HDLC parameters:
%       width:   32
%       poly:    0x04C11DB7
%       init:    0xFFFFFFFF
%       refin:   true
%       refout:  true
%       xorout:  0xFFFFFFFF
%
%   This produces the same result as Python binascii.crc32(),
%   Java java.util.zip.CRC32, and CRC-32 in PNG/ZIP/GZIP.

    persistent crc_table
    if isempty(crc_table)
        crc_table = zeros(1, 256, 'uint32');
        for i = 0:255
            crc = uint32(i);
            for j = 1:8
                if bitand(crc, uint32(1))
                    crc = bitxor(bitshift(crc, -1), uint32(0xEDB88320));
                else
                    crc = bitshift(crc, -1);
                end
            end
            crc_table(i + 1) = crc;
        end
    end

    if ischar(data)
        data = uint8(data);
    end

    crc = uint32(0xFFFFFFFF);
    for i = 1:numel(data)
        idx = bitand(bitxor(crc, uint32(data(i))), uint32(0xFF));
        crc = bitxor(bitshift(crc, -8), crc_table(idx + 1));
    end
    hash = bitxor(crc, uint32(0xFFFFFFFF));
end
