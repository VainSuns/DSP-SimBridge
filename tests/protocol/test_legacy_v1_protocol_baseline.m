function tests = test_legacy_v1_protocol_baseline
%TEST_LEGACY_V1_PROTOCOL_BASELINE V1 fixture and wire-compatibility tests.
tests = functiontests(localfunctions);
end

function testBaselineMetadata(testCase)
baseline = legacy_v1_protocol_baseline();
verifyEqual(testCase, baseline.commit, 'f209302ce3efc0fa15d217550f6d9b1dc00487fb');
verifyEqual(testCase, baseline.header_octets, uint16(4));
verifyEqual(testCase, baseline.wire_endianness, 'little');
verifyEqual(testCase, [baseline.messages.type], uint16(1:5));
verifyEqual(testCase, {baseline.files.blob_sha}, { ...
    '55b5a22e9eaf86a05d45a2cd43a377dbcced35b8', ...
    'e9c8a9a8a8851330311a6def4f02bb9d5dd9d2e7', ...
    '1367df1da60bd51df9098e337407be592bf283a0', ...
    'dfe1be29e257c3597484e0ff54a70bfcdee25d93'});
end

function testErrorCodeMatrix(testCase)
codes = legacy_v1_error_codes();
verifyEqual(testCase, [codes.value], uint16(0:8));
verifyEqual(testCase, numel(unique({codes.dsp_symbol})), 9);
verifyEqual(testCase, numel(unique({codes.pc_symbol})), 9);
verifyFalse(testCase, codes(9).new_architecture_produces);
end

function testGoldenFramesParseIdentically(testCase)
frames = legacy_v1_golden_frames();
for index = 1:numel(frames)
    dsp = legacy_v1_parse_dsp_frame(frames(index).frame_octets);
    pc = legacy_v1_parse_pc_frame(frames(index).frame_octets);
    verifyEqual(testCase, dsp, pc, sprintf('Parser mismatch for %s.', frames(index).name));
    verifyEqual(testCase, dsp.type, frames(index).type);
    verifyEqual(testCase, dsp.payload_length, frames(index).payload_octets);
end
end

function testKnownGoldenOctets(testCase)
frames = legacy_v1_golden_frames();
verifyEqual(testCase, frames(1).frame_octets, uint8([1 0 6 0 1 0 120 86 52 18]));
verifyEqual(testCase, frames(4).frame_octets, uint8([4 0 0 0]));
verifyEqual(testCase, frames(5).frame_octets, uint8([5 0 2 0 0 0]));
end

function testOddAndTruncatedFramesAreRejected(testCase)
verifyError(testCase, @() legacy_v1_parse_dsp_frame(uint8([1 0 1 0 0 0])), ...
    'MATLAB:assertion:failed');
verifyError(testCase, @() legacy_v1_parse_pc_frame(uint8([1 0 6 0 1 0])), ...
    'MATLAB:assertion:failed');
end
