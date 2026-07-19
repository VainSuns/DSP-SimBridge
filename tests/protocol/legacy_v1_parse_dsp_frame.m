function parsed = legacy_v1_parse_dsp_frame(frame_octets)
%LEGACY_V1_PARSE_DSP_FRAME Model the historical DSP word-buffer view.
frame_octets = uint8(frame_octets(:).');
assert(mod(numel(frame_octets), 2) == 0, 'DSP frame must contain whole C28x words.');
assert(numel(frame_octets) >= 4, 'Frame header is incomplete.');
words = uint16(frame_octets(1:2:end)) + bitshift(uint16(frame_octets(2:2:end)), 8);
msg_type = words(1);
payload_length = words(2);
assert(mod(double(payload_length), 2) == 0, 'Payload length must be even.');
assert(numel(frame_octets) == 4 + double(payload_length), 'Frame length mismatch.');
parsed = struct('type', msg_type, 'payload_length', payload_length, ...
    'payload', frame_octets(5:end));
end
