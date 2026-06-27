function test_IntanDataset()
%test_IntanDataset  Verification suite for the Intan -> Kilosort4 backend.
%   Builds synthetic *.rhd fixtures (valid magic + header + known data blocks),
%   then exercises parseIntanHeader, refreshMetadata, readData, toBin,
%   matrixToBin, filterContinuous, detectArtifacts, IntanKilosortProject
%   discovery and runKilosort(DryRun=true). No real Intan files or Kilosort4
%   install are required.
%
%   Usage:  test_IntanDataset
%
%   The fixtures live in a temp folder which is deleted on completion.

here = fileparts(mfilename('fullpath'));
addpath(here);                          % @IntanDataset / @IntanKilosortProject
addpath(fileparts(here));               % matrix2kilosort.m (ephys/)

root = fullfile(tempdir, sprintf('IntanDS_test_%s', datestr(now,'yyyymmdd_HHMMSSFFF'))); %#ok<TNOW1,DATST>
mkdir(root);
cleanup = onCleanup(@() rmdir(root, 's'));

nPass = 0; nFail = 0;
    function check(cond, msg)
        if cond
            nPass = nPass + 1;
            fprintf('  PASS: %s\n', msg);
        else
            nFail = nFail + 1;
            fprintf(2, '  FAIL: %s\n', msg);
        end
    end

rng(42);

% ---- Build a dataset folder with two chronological files ----------------
dsFolder = fullfile(root, 'subjA_day1');
mkdir(dsFolder);
numAmp = 4; blocksPerFile = 2; spb = 128;
samplesPerFile = blocksPerFile * spb;
Fs = 30000;

% Known raw amplifier values [numAmp x totalSamples] across both files
totalSamples = 2 * samplesPerFile;
ampRaw = uint16(randi([0 65535], numAmp, totalSamples));

% Digital line: high during samples 50..70 of file 1
digRaw = zeros(1, totalSamples);
digRaw(50:70) = 1;   % native_order 0 -> bit 0

f1 = fullfile(dsFolder, 'rec_001.rhd');
f2 = fullfile(dsFolder, 'rec_002.rhd');
writeSyntheticRHD(f1, ampRaw(:,1:samplesPerFile),            digRaw(1:samplesPerFile),            Fs, spb);
writeSyntheticRHD(f2, ampRaw(:,samplesPerFile+1:end),        digRaw(samplesPerFile+1:end),        Fs, spb);
% Force chronological datenum order (f1 older than f2)
java.io.File(f1).setLastModified(int64(1.0e12));
java.io.File(f2).setLastModified(int64(1.0e12 + 60000));

fprintf('\n== 1-2. refreshMetadata + header-only parse (via PerFile) ==\n');
ds = IntanDataset(dsFolder);   % AutoMetadata=true -> parseIntanHeader per file
check(ds.NumFiles == 2, 'discovered 2 files');
check(ds.Files(1) == "rec_001.rhd", 'chronological sort (file 1)');
check(ds.NumChannels == numAmp, 'NumChannels');
check(ds.Fs == Fs, 'Fs');
check(abs(ds.Duration - totalSamples/Fs) < 1e-9, 'Duration = sum of recordTime');
check(ds.NumSamples == totalSamples, 'NumSamples (dependent)');
% Header-only parse output surfaced through PerFile
pf = ds.PerFile(1);
check(pf.numAmplifierChannels == numAmp, 'PerFile amplifier channel count');
check(pf.numDataBlocks == blocksPerFile, 'PerFile whole data block count');
check(pf.numAmplifierSamples == samplesPerFile, 'PerFile amplifier sample count');
check(~pf.partialBlock, 'no partial block flagged');
% headerBytes must equal filesize - nBlocks*bytesPerBlock (parser stopped at data offset)
s = dir(f1);
check(pf.headerBytes == s.bytes - pf.numDataBlocks*pf.bytesPerBlock, ...
    'headerBytes at data offset (no amplifier matrix read)');

fprintf('\n== 3. readData (concat + events) ==\n');
data = ds.readData();
check(isequal(size(data.amplifier), [totalSamples numAmp]), 'amplifier [nSamples x nChan]');
expectedUV = 0.195 * (double(ampRaw) - 32768);   % [numAmp x totalSamples]
check(all(abs(data.amplifier - expectedUV.') < 1e-6, 'all'), 'amplifier microvolts match');
check(numel(fieldnames(data.events)) == 1, 'one dig-in event field');
evName = fieldnames(data.events); ev = data.events.(evName{1});
check(size(ev,1) == 1, 'one event interval detected');
check(abs(ev(1,1) - 50/Fs) < 1e-9, 'event onset (1-based sample 50, intan2matlab convention)');

fprintf('\n== 4. toBin streaming vs matrix2kilosort byte-identical ==\n');
ds.OutputDir = fullfile(root, 'out_stream');
info = ds.toBin();
check(info.nChan == numAmp && info.nSamples == totalSamples, 'toBin nChan/nSamples');
check(info.nBytes == numAmp * totalSamples * 2, 'byte invariant nBytes = nChan*nSamples*2');

% In-memory write of the same data via matrixToBin
ds2 = IntanDataset(dsFolder);
ds2.OutputDir = fullfile(root, 'out_mem');
info2 = ds2.matrixToBin(data.amplifier);   % uses Scale=1/0.195, Dtype int16
b1 = readBin(info.filename);
b2 = readBin(info2.filename);
check(isequal(b1, b2), 'streaming toBin == matrix2kilosort (byte-identical)');

fprintf('\n== 5. round-trip bin -> microvolts ==\n');
raw = reshape(typecast(b1, 'int16'), numAmp, totalSamples);  % [nChan x nSamples]
backUV = 0.195 * double(raw);                                % undo scale (offset 0)
check(all(abs(backUV.' - expectedUV.') < 0.2, 'all'), 'round-trip within rounding (<0.2 uV)');

fprintf('\n== 6. filterContinuous + detectArtifacts ==\n');
t = (0:totalSamples-1).'/Fs;
sig = 100*sin(2*pi*10*t) + 500;          % 10 Hz + big DC offset, single chan
hp = ds.filterContinuous(sig, Type="highpass", Cutoff=300, Fs=Fs);
check(abs(mean(hp)) < 1, 'highpass removes DC offset');

X = 5*randn(totalSamples, numAmp);
X(100:105, :) = X(100:105, :) + 2000;    % multi-channel transient
[mask, intervals] = ds.detectArtifacts(X, Method="microvolts", Threshold=1500, MinChannels=2);
check(all(mask(100:105)), 'artifact mask covers transient');
check(size(intervals,1) >= 1 && intervals(1,1) <= 100/Fs, 'artifact interval onset');
Xb = ds.blankArtifacts(X, mask, Fill="zero");
check(all(all(Xb(mask,:) == 0)), 'blankArtifacts zeroes flagged rows');

fprintf('\n== 7. IntanKilosortProject discovery ==\n');
% nested tree: 2 real dataset folders + 1 empty decoy
mkdir(fullfile(root, 'proj', 'mouse1', 'sess1'));
mkdir(fullfile(root, 'proj', 'mouse2', 'sess1'));
mkdir(fullfile(root, 'proj', 'empty_decoy'));
writeSyntheticRHD(fullfile(root,'proj','mouse1','sess1','a.rhd'), ampRaw(:,1:spb), digRaw(1:spb), Fs, spb);
writeSyntheticRHD(fullfile(root,'proj','mouse2','sess1','b.rhd'), ampRaw(:,1:spb), digRaw(1:spb), Fs, spb);
P = IntanKilosortProject(fullfile(root,'proj'));
check(P.NumDatasets == 2, 'discover finds exactly 2 dataset folders (decoy ignored)');
T = P.gatherMetadata();
check(height(T) == 2 && all(T.NumChannels == numAmp), 'gatherMetadata table');

fprintf('\n== 8. runKilosort(DryRun=true) ==\n');
% Minimal valid probe json
probeFile = fullfile(root, 'probe.json');
probe = struct('chanMap', 0:numAmp-1, 'xc', zeros(1,numAmp), 'yc', (0:numAmp-1)*20, ...
    'kcoords', zeros(1,numAmp), 'n_chan', numAmp);
fid = fopen(probeFile,'w'); fwrite(fid, jsonencode(probe), 'char'); fclose(fid);

ds.ProbeFile = probeFile;
ds.PythonExe = "C:\miniconda3\python.exe";
res = ds.runKilosort(DryRun=true);
check(isfile(res.settingsPath), 'settings.json written');
check(isfile(res.scriptPath), 'run_ks4.py written');
sett = jsondecode(fileread(res.settingsPath));
check(sett.n_chan_bin == numAmp, 'settings n_chan_bin');
check(sett.fs == Fs, 'settings fs');
check(contains(res.command, '"C:\miniconda3\python.exe"'), 'command quotes python path');
check(contains(res.command, '"'+string(res.scriptPath)+'"') || contains(res.command, res.scriptPath), ...
    'command references script');

fprintf('\n================  %d passed, %d failed  ================\n', nPass, nFail);
if nFail > 0
    error('test_IntanDataset:Failures', '%d checks failed.', nFail);
end
end


% =========================================================================
function writeSyntheticRHD(ffn, ampRaw, digRaw, Fs, spb)
%writeSyntheticRHD  Write a minimal valid v2.0 RHD2000 file.
%   ampRaw [numAmp x nSamples] uint16 raw codes; digRaw [1 x nSamples] (bit 0).
%   numAmp amplifier channels, 1 dig-in line, no aux/adc/supply/temp/dig-out.
%   nSamples must be a multiple of spb.

numAmp = size(ampRaw,1);
nSamples = size(ampRaw,2);
nBlocks = nSamples / spb;
assert(mod(nSamples, spb) == 0, 'nSamples must be a multiple of spb');

fid = fopen(ffn, 'w', 'ieee-le');
assert(fid >= 0, 'cannot open %s', ffn);

% --- Header ---
fwrite(fid, hex2dec('c6912702'), 'uint32');   % magic
fwrite(fid, 2, 'int16');                       % main version (>1 => 128 spb, int32 ts)
fwrite(fid, 0, 'int16');                       % secondary version
fwrite(fid, Fs, 'single');                     % sample_rate
fwrite(fid, 1, 'int16');                        % dsp_enabled
fwrite(fid, [1 1 7500], 'single');              % actual dsp cutoff, lower, upper bw
fwrite(fid, [1 1 7500], 'single');              % desired dsp cutoff, lower, upper bw
fwrite(fid, 0, 'int16');                        % notch_filter_mode
fwrite(fid, [1000 1000], 'single');             % desired/actual impedance test freq
writeQString(fid, '');                          % note1
writeQString(fid, '');                          % note2
writeQString(fid, '');                          % note3
fwrite(fid, 0, 'int16');                        % num_temp_sensor_channels (v1.1+/v>1)
fwrite(fid, 0, 'int16');                        % board_mode (v1.3+/v>1)
writeQString(fid, '');                          % reference_channel (v>1)

% One signal group holding numAmp amplifier channels + 1 dig-in
fwrite(fid, 1, 'int16');                        % number_of_signal_groups
writeQString(fid, 'PortA');                     % group name
writeQString(fid, 'A');                         % group prefix
fwrite(fid, 1, 'int16');                        % group enabled
fwrite(fid, numAmp + 1, 'int16');               % group num channels
fwrite(fid, numAmp, 'int16');                   % group num amp channels

for c = 1:numAmp
    writeChannel(fid, sprintf('A-%03d', c-1), sprintf('amp%d', c-1), c-1, 0); % signal_type 0
end
% dig-in line, native_order 0
writeChannel(fid, 'DIN-00', 'din0', 0, 4);      % signal_type 4

% --- Data blocks (channel-major amplifier per block, matching the reader) ---
for blk = 1:nBlocks
    cols = (blk-1)*spb + (1:spb);
    fwrite(fid, cols - 1, 'int32');             % timestamps (int32 for v>1)
    % amplifier: fread reads [spb, numAmp] column-major => write channel-major
    ampBlock = ampRaw(:, cols).';               % [spb x numAmp]
    fwrite(fid, ampBlock, 'uint16');            % column-major => ch1 spb samples, ch2...
    % dig-in raw uint16 (bit 0 carries the line)
    fwrite(fid, digRaw(cols), 'uint16');
end

fclose(fid);
end


function writeChannel(fid, nativeName, customName, nativeOrder, signalType)
writeQString(fid, nativeName);
writeQString(fid, customName);
fwrite(fid, nativeOrder, 'int16');   % native_order
fwrite(fid, 0, 'int16');             % custom_order
fwrite(fid, signalType, 'int16');    % signal_type
fwrite(fid, 1, 'int16');             % channel_enabled
fwrite(fid, 0, 'int16');             % chip_channel
fwrite(fid, 0, 'int16');             % board_stream
fwrite(fid, 0, 'int16');             % voltage_trigger_mode
fwrite(fid, 0, 'int16');             % voltage_threshold
fwrite(fid, 0, 'int16');             % digital_trigger_channel
fwrite(fid, 0, 'int16');             % digital_edge_polarity
fwrite(fid, 0, 'single');            % electrode_impedance_magnitude
fwrite(fid, 0, 'single');            % electrode_impedance_phase
end


function writeQString(fid, str)
% Qt QString: uint32 length in BYTES, then uint16 per char.
fwrite(fid, numel(str) * 2, 'uint32');
for i = 1:numel(str)
    fwrite(fid, double(str(i)), 'uint16');
end
end


function bytes = readBin(ffn)
fid = fopen(ffn, 'r', 'ieee-le');
bytes = fread(fid, inf, '*uint8');
fclose(fid);
end
