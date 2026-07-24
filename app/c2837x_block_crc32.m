function hash = c2837x_block_crc32(data)
%C2837X_BLOCK_CRC32 CRC-32/ISO-HDLC for Interface Hash octets or UTF-8 text.
%
%   hash = c2837x_block_crc32(data)
%
%   Parameters:
%       data - uint8 vector, char vector, or scalar string
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

    if isa(data, 'uint8')
        if ~isempty(data) && ~isvector(data)
            invalid_input();
        end
        data = data(:).';
    elseif ischar(data) && (isempty(data) || isvector(data))
        data = encode_text(data(:).');
    elseif isstring(data) && isscalar(data) && ~ismissing(data)
        data = encode_text(char(data));
    else
        invalid_input();
    end

    crc = uint32(0xFFFFFFFF);
    for i = 1:numel(data)
        idx = bitand(bitxor(crc, uint32(data(i))), uint32(0xFF));
        crc = bitxor(bitshift(crc, -8), crc_table(idx + 1));
    end
    hash = bitxor(crc, uint32(0xFFFFFFFF));
end

function data = encode_text(text)
try
    data = unicode2native(text, 'UTF-8');
catch cause
    failure = MException('C2837xBlock:CRC32:EncodingFailed', ...
        'Text could not be encoded as UTF-8.');
    throwAsCaller(addCause(failure, cause));
end
end

function invalid_input()
error('C2837xBlock:CRC32:InvalidInput', ...
    'Input must be a uint8 vector, char vector, or scalar string.');
end
