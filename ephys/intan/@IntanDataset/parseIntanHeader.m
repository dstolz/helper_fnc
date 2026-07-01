function hdr = parseIntanHeader(ffn)
%parseIntanHeader  Read an Intan *.rhd header only; stop before data blocks.
%   HDR = IntanDataset.parseIntanHeader(FFN) parses the header of the RHD2000
%   file FFN and returns a struct of metadata WITHOUT allocating or reading the
%   amplifier matrix. This is a header-only extraction of
%   READ_INTAN_RHD2000_FILE_MODIFIED (lines ~47-296): it parses the header,
%   computes bytes_per_block, then derives the number of whole data blocks from
%   the remaining file size and closes the file at the data offset.
%
%   The full reader is preferred for actually loading data (readData/toBin);
%   it is avoided here because it always pre-allocates and reads the entire
%   amplifier matrix, which is wasteful when only metadata is needed.
%
%   Fields
%   ------
%     sampleRate              amplifier sample rate (Hz)
%     numAmplifierChannels    amplifier channel count
%     numAuxInputChannels     aux input channel count
%     numBoardADCChannels     board ADC channel count
%     numBoardDigInChannels   board digital-input channel count
%     numBoardDigOutChannels  board digital-output channel count
%     numSupplyVoltageChannels / numTempSensorChannels
%     channelNames            1xN string (custom_channel_name, amplifier)
%     nativeNames             1xN string (native_channel_name, amplifier)
%     digInNames              1xN string (custom_channel_name, dig-in)
%     digInNativeOrders       1xN double (native_order / bit position, dig-in)
%     bytesPerBlock           bytes per data block
%     numSamplesPerDataBlock  amplifier samples per data block (60 or 128)
%     numDataBlocks           whole data blocks present (floor)
%     numAmplifierSamples     numSamplesPerDataBlock * numDataBlocks
%     recordTime              numAmplifierSamples / sampleRate (s)
%     boardMode               board mode (ADC scaling)
%     mainVersion/secondaryVersion
%     headerBytes             byte offset where data blocks begin
%     dataPresent             true if any data blocks follow the header
%     partialBlock            true if a fractional trailing block was truncated
%
%   See also READ_INTAN_RHD2000_FILE_MODIFIED, IntanDataset.refreshMetadata.

arguments
    ffn (1,1) string {mustBeFile}
end

fid = fopen(ffn, 'r');
if fid < 0
    error('IntanDataset:parseIntanHeader:OpenFailed', 'Could not open %s', ffn);
end
cleaner = onCleanup(@() fclose(fid));  % close on any exit path

s = dir(ffn);
filesize = s.bytes;

% Magic number guard
magic_number = fread(fid, 1, 'uint32');
if magic_number ~= hex2dec('c6912702')
    error('IntanDataset:parseIntanHeader:BadMagic', 'Unrecognized file type: %s', ffn);
end

% Version
data_file_main_version_number      = fread(fid, 1, 'int16');
data_file_secondary_version_number = fread(fid, 1, 'int16');

if (data_file_main_version_number == 1)
    num_samples_per_data_block = 60;
else
    num_samples_per_data_block = 128;
end

% Sample rate + bandwidth settings
sample_rate            = fread(fid, 1, 'single');
dsp_enabled            = fread(fid, 1, 'int16'); %#ok<NASGU>
actual_dsp_cutoff      = fread(fid, 1, 'single'); %#ok<NASGU>
actual_lower_bandwidth = fread(fid, 1, 'single'); %#ok<NASGU>
actual_upper_bandwidth = fread(fid, 1, 'single'); %#ok<NASGU>
desired_dsp_cutoff     = fread(fid, 1, 'single'); %#ok<NASGU>
desired_lower_bw       = fread(fid, 1, 'single'); %#ok<NASGU>
desired_upper_bw       = fread(fid, 1, 'single'); %#ok<NASGU>

notch_filter_mode      = fread(fid, 1, 'int16'); %#ok<NASGU>

desired_impedance_freq = fread(fid, 1, 'single'); %#ok<NASGU>
actual_impedance_freq  = fread(fid, 1, 'single'); %#ok<NASGU>

% Notes (3 QStrings)
fread_QString(fid);
fread_QString(fid);
fread_QString(fid);

% Temp sensor channels (v1.1+)
num_temp_sensor_channels = 0;
if ((data_file_main_version_number == 1 && data_file_secondary_version_number >= 1) ...
        || (data_file_main_version_number > 1))
    num_temp_sensor_channels = fread(fid, 1, 'int16');
end

% Board mode (v1.3+)
board_mode = 0;
if ((data_file_main_version_number == 1 && data_file_secondary_version_number >= 3) ...
        || (data_file_main_version_number > 1))
    board_mode = fread(fid, 1, 'int16');
end

% Reference channel (v2.0+)
if (data_file_main_version_number > 1)
    fread_QString(fid);  % reference_channel
end

% Signal groups / channels
amplifier_names = strings(1,0);
amplifier_native = strings(1,0);
dig_in_names = strings(1,0);
dig_in_orders = [];   % native_order (bit position) of each enabled dig-in line

num_amplifier_channels      = 0;
num_aux_input_channels      = 0;
num_supply_voltage_channels = 0;
num_board_adc_channels      = 0;
num_board_dig_in_channels   = 0;
num_board_dig_out_channels  = 0;

number_of_signal_groups = fread(fid, 1, 'int16');
for signal_group = 1:number_of_signal_groups
    fread_QString(fid);  % signal_group_name
    fread_QString(fid);  % signal_group_prefix
    signal_group_enabled      = fread(fid, 1, 'int16');
    signal_group_num_channels = fread(fid, 1, 'int16');
    fread(fid, 1, 'int16');  % signal_group_num_amp_channels

    if (signal_group_num_channels > 0 && signal_group_enabled > 0)
        for signal_channel = 1:signal_group_num_channels
            native_name = fread_QString(fid);
            custom_name = fread_QString(fid);
            native_order = fread(fid, 1, 'int16');
            fread(fid, 1, 'int16');  % custom_order
            signal_type    = fread(fid, 1, 'int16');
            channel_enabled = fread(fid, 1, 'int16');
            fread(fid, 1, 'int16');  % chip_channel
            fread(fid, 1, 'int16');  % board_stream
            fread(fid, 1, 'int16');  % voltage_trigger_mode
            fread(fid, 1, 'int16');  % voltage_threshold
            fread(fid, 1, 'int16');  % digital_trigger_channel
            fread(fid, 1, 'int16');  % digital_edge_polarity
            fread(fid, 1, 'single'); % electrode_impedance_magnitude
            fread(fid, 1, 'single'); % electrode_impedance_phase

            if (channel_enabled)
                switch (signal_type)
                    case 0
                        num_amplifier_channels = num_amplifier_channels + 1;
                        amplifier_names(end+1)  = string(custom_name); %#ok<AGROW>
                        amplifier_native(end+1) = string(native_name); %#ok<AGROW>
                    case 1
                        num_aux_input_channels = num_aux_input_channels + 1;
                    case 2
                        num_supply_voltage_channels = num_supply_voltage_channels + 1;
                    case 3
                        num_board_adc_channels = num_board_adc_channels + 1;
                    case 4
                        num_board_dig_in_channels = num_board_dig_in_channels + 1;
                        dig_in_names(end+1) = string(custom_name); %#ok<AGROW>
                        dig_in_orders(end+1) = native_order; %#ok<AGROW>
                    case 5
                        num_board_dig_out_channels = num_board_dig_out_channels + 1;
                    otherwise
                        error('IntanDataset:parseIntanHeader:BadChannelType', ...
                            'Unknown channel type %d in %s', signal_type, ffn);
                end
            end
        end
    end
end

% Bytes per data block (mirrors the full reader exactly)
bytes_per_block = num_samples_per_data_block * 4;  % timestamps (int32)
bytes_per_block = bytes_per_block + num_samples_per_data_block * 2 * num_amplifier_channels;
bytes_per_block = bytes_per_block + (num_samples_per_data_block / 4) * 2 * num_aux_input_channels;
bytes_per_block = bytes_per_block + 1 * 2 * num_supply_voltage_channels;
bytes_per_block = bytes_per_block + num_samples_per_data_block * 2 * num_board_adc_channels;
if (num_board_dig_in_channels > 0)
    bytes_per_block = bytes_per_block + num_samples_per_data_block * 2;
end
if (num_board_dig_out_channels > 0)
    bytes_per_block = bytes_per_block + num_samples_per_data_block * 2;
end
if (num_temp_sensor_channels > 0)
    bytes_per_block = bytes_per_block + 1 * 2 * num_temp_sensor_channels;
end

% Data offset and whole-block count (floor; flag any partial trailing block)
header_bytes    = ftell(fid);
bytes_remaining = filesize - header_bytes;
data_present    = bytes_remaining > 0;

raw_blocks      = bytes_remaining / bytes_per_block;
num_data_blocks = floor(raw_blocks);
partial_block   = data_present && (num_data_blocks ~= raw_blocks);

num_amplifier_samples = num_samples_per_data_block * num_data_blocks;
record_time           = num_amplifier_samples / sample_rate;

hdr = struct( ...
    'name',                     string(s.name), ...
    'sampleRate',               sample_rate, ...
    'numAmplifierChannels',     num_amplifier_channels, ...
    'numAuxInputChannels',      num_aux_input_channels, ...
    'numBoardADCChannels',      num_board_adc_channels, ...
    'numBoardDigInChannels',    num_board_dig_in_channels, ...
    'numBoardDigOutChannels',   num_board_dig_out_channels, ...
    'numSupplyVoltageChannels', num_supply_voltage_channels, ...
    'numTempSensorChannels',    num_temp_sensor_channels, ...
    'channelNames',             amplifier_names, ...
    'nativeNames',              amplifier_native, ...
    'digInNames',               dig_in_names, ...
    'digInNativeOrders',        dig_in_orders, ...
    'bytesPerBlock',            bytes_per_block, ...
    'numSamplesPerDataBlock',   num_samples_per_data_block, ...
    'numDataBlocks',            num_data_blocks, ...
    'numAmplifierSamples',      num_amplifier_samples, ...
    'recordTime',               record_time, ...
    'boardMode',                board_mode, ...
    'mainVersion',              data_file_main_version_number, ...
    'secondaryVersion',         data_file_secondary_version_number, ...
    'headerBytes',              header_bytes, ...
    'dataPresent',              data_present, ...
    'partialBlock',             partial_block, ...
    'datenum',                  s.datenum);
end


function a = fread_QString(fid)
% Read a Qt-style QString (verbatim from READ_INTAN_RHD2000_FILE_MODIFIED).
% First uint32 is the length in bytes; 0xFFFFFFFF means null.
a = '';
len = fread(fid, 1, 'uint32');
if len == hex2num('ffffffff')
    return;
end
len = len / 2;  % bytes -> 16-bit Unicode words
for i = 1:len
    a(i) = fread(fid, 1, 'uint16'); %#ok<AGROW>
end
end
