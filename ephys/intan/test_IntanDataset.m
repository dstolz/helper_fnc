function test_IntanDataset()
%test_IntanDataset  Verification suite for the Intan -> Kilosort4 backend.
%   Builds synthetic *.rhd fixtures (valid magic + header + known data blocks),
%   then exercises parseIntanHeader, refreshMetadata, readData, toBin,
%   matrixToBin, filterContinuous, detectArtifacts, IntanKilosortProject
%   discovery and runKilosort(DryRun=true). Section 10 builds split-format
%   fixtures (info.rhd + flat .dat files) for the one-file-per-signal and
%   one-file-per-channel layouts and checks metadata, readData and a byte-correct
%   toBin for both. No real Intan files or Kilosort4 install are required.
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

fprintf('\n== 9. DatasetTracker integration (ds / project) ==\n');
% ds.OutputDir = out_stream (section 4); section 8 wrote a dry-run kilosort4/
% there (settings + script, but no spike output yet).
dt = ds.tracker();
check(isa(dt, 'DatasetTracker'), 'ds.tracker() returns a DatasetTracker');
check(dt.NumBinFiles == 1, 'tracker sees the streamed .bin');
check(dt.BinFiles(1).NChanBin == numAmp, 'tracker reads .bin sidecar (n_chan_bin)');
check(dt.NumKilosortRuns >= 1, 'tracker sees the kilosort4 run folder');
check(~dt.hasKilosort, 'no results yet (dry run wrote no spike_clusters.npy)');

% Simulate a completed sort (existence is all the tracker checks), re-snapshot.
ksDir = fullfile(char(ds.outputFolder()), 'kilosort4');
fclose(fopen(fullfile(ksDir, 'spike_clusters.npy'), 'w'));
fid = fopen(fullfile(ksDir, 'cluster_KSLabel.tsv'), 'w');
fprintf(fid, 'cluster_id\tKSLabel\n0\tgood\n1\tmua\n'); fclose(fid);
dt2 = ds.tracker();
check(dt2.hasKilosort, 'hasKilosort true after results appear');
run = dt2.latestKilosortRun();
check(~isempty(run) && run.HasResults && run.NumUnits == 2, ...
    'latestKilosortRun reports results + cluster count');

% Project-level wrappers + the new gatherMetadata column.
dtp = P.tracker(1);
check(isa(dtp, 'DatasetTracker'), 'P.tracker(idx) returns a DatasetTracker');
T2 = P.gatherMetadata();
check(any(strcmp('HasKilosort', T2.Properties.VariableNames)), ...
    'gatherMetadata exposes a HasKilosort column');
check(islogical(T2.HasKilosort) && ~any(T2.HasKilosort), ...
    'project datasets (no sorts) -> HasKilosort all false');

fprintf('\n== 10. split formats (one-file-per-signal / one-file-per-channel) ==\n');
% Known int16 amplifier codes; microvolts = 0.195 * int16 (no 32768 offset).
nSampSplit = 300;
ampI16   = int16(randi([-30000 30000], numAmp, nSampSplit));
expSigUV = 0.195 * double(ampI16).';            % [nSampSplit x numAmp]
digSplit = zeros(1, nSampSplit); digSplit(50:70) = 1;   % bit-0 line high 50..70

% --- one-file-per-signal: info.rhd + amplifier.dat (+ time/digitalin) --------
sigFolder = fullfile(root, 'split_signal');
mkdir(sigFolder);
writeInfoRHD(fullfile(sigFolder, 'info.rhd'), numAmp, Fs);
writeDat(fullfile(sigFolder, 'amplifier.dat'), ampI16, 'int16');      % channel-major/sample
writeDat(fullfile(sigFolder, 'time.dat'), int32(0:nSampSplit-1), 'int32');
writeDat(fullfile(sigFolder, 'digitalin.dat'), uint16(digSplit), 'uint16');

dsig = IntanDataset(sigFolder);
check(dsig.RecordingFormat == "one-file-per-signal", 'detect one-file-per-signal');
check(dsig.NumChannels == numAmp, 'signal: NumChannels from info.rhd');
check(dsig.Fs == Fs, 'signal: Fs from info.rhd');
check(dsig.NumSamples == nSampSplit, 'signal: NumSamples from amplifier.dat size');
check(abs(dsig.Duration - nSampSplit/Fs) < 1e-9, 'signal: Duration');
dats = dsig.readData();
check(isequal(size(dats.amplifier), [nSampSplit numAmp]), 'signal: amplifier [nSamples x nChan]');
check(all(abs(dats.amplifier - expSigUV) < 1e-9, 'all'), 'signal: amplifier microvolts (0.195*int16)');
check(numel(fieldnames(dats.events)) == 1, 'signal: one dig-in event field');
evN = fieldnames(dats.events); evSig = dats.events.(evN{1});
check(size(evSig,1) == 1 && abs(evSig(1,1) - 50/Fs) < 1e-9, 'signal: event onset (sample 50)');
dsig.OutputDir = fullfile(root, 'out_split_signal');
isig = dsig.toBin();
check(isig.nChan == numAmp && isig.nSamples == nSampSplit, 'signal: toBin nChan/nSamples');
rawSig = reshape(typecast(readBin(isig.filename), 'int16'), numAmp, nSampSplit);
check(max(abs(double(rawSig) - double(ampI16)), [], 'all') <= 1, 'signal: .bin int16 == source int16');

% --- one-file-per-channel: info.rhd + amp-A-00x.dat (+ time/board-DIN) -------
chanFolder = fullfile(root, 'split_channel');
mkdir(chanFolder);
writeInfoRHD(fullfile(chanFolder, 'info.rhd'), numAmp, Fs);
for c = 1:numAmp
    writeDat(fullfile(chanFolder, sprintf('amp-A-%03d.dat', c-1)), ampI16(c,:), 'int16');
end
writeDat(fullfile(chanFolder, 'time.dat'), int32(0:nSampSplit-1), 'int32');
writeDat(fullfile(chanFolder, 'board-DIN-00.dat'), uint16(digSplit), 'uint16');

dchan = IntanDataset(chanFolder);
check(dchan.RecordingFormat == "one-file-per-channel", 'detect one-file-per-channel');
check(dchan.NumChannels == numAmp, 'channel: NumChannels');
check(dchan.NumSamples == nSampSplit, 'channel: NumSamples from amp-A-000.dat size');
datc = dchan.readData();
check(all(abs(datc.amplifier - expSigUV) < 1e-9, 'all'), 'channel: amplifier microvolts');
check(numel(fieldnames(datc.events)) == 1, 'channel: one dig-in event field');
evcN = fieldnames(datc.events); evChan = datc.events.(evcN{1});
check(size(evChan,1) == 1 && abs(evChan(1,1) - 50/Fs) < 1e-9, 'channel: event onset (sample 50)');
dchan.OutputDir = fullfile(root, 'out_split_channel');
ic = dchan.toBin();
rawChan = reshape(typecast(readBin(ic.filename), 'int16'), numAmp, nSampSplit);
check(max(abs(double(rawChan) - double(ampI16)), [], 'all') <= 1, 'channel: .bin int16 == source int16');

% Split toBin must match the in-memory matrixToBin on the same microvolts.
dsig2 = IntanDataset(sigFolder); dsig2.OutputDir = fullfile(root, 'out_split_mem');
imem = dsig2.matrixToBin(expSigUV);
check(isequal(readBin(isig.filename), readBin(imem.filename)), ...
    'signal: streaming toBin == matrix2kilosort (byte-identical)');

fprintf('\n== 11. artifactIntervals (manual merge + auto streaming) ==\n');
dsi = IntanDataset(dsFolder);
% Manual-only: two overlapping periods merge into one; auto disabled by default.
dsi.ManualArtifacts = [0.001 0.003; 0.0025 0.004];
ivm = dsi.artifactIntervals();
check(size(ivm,1) == 1, 'artifactIntervals merges overlapping manual periods');
check(abs(ivm(1,1) - 0.001) < 1e-9 && abs(ivm(1,2) - 0.004) < 1e-9, ...
    'merged manual interval spans the union');
% IncludeAuto=false ignores ArtifactConfig even when Enabled.
dsi.ArtifactConfig.Enabled = true;
ivf = dsi.artifactIntervals(IncludeAuto=false);
check(size(ivf,1) == 1, 'IncludeAuto=false returns manual periods only');
% Auto detection streams the recording; a low microvolts threshold flags the
% random fixture broadly, exercising the offset accumulation + merge path.
dsi.ArtifactConfig.Method = "microvolts";
dsi.ArtifactConfig.Threshold = 3000;
dsi.ArtifactConfig.MinChannels = 1;
iva = dsi.artifactIntervals();
check(size(iva,2) == 2 && ~isempty(iva), 'artifactIntervals (auto) returns intervals');
check(all(iva(:,2) >= iva(:,1)), 'auto intervals are well-formed');
check(max(iva(:,2)) <= dsi.Duration + 1e-6, 'auto intervals lie within the recording');

fprintf('\n== 12. runSpikeInterface(DryRun=true) ==\n');
dsr = IntanDataset(dsFolder);
dsr.OutputDir = fullfile(root, 'out_si');
dsr.ProbeFile = probeFile;                 % from section 8
dsr.PythonExe = "C:\envs\kilosort\python.exe";
dsr.ExcludeChannels = 2;                    % 1-based .bin row -> 0-based idx 1
dsr.ManualArtifacts = [0.0005 0.001];
resSI = dsr.runSpikeInterface(DryRun=true);
check(isfile(resSI.settingsPath), 'si_config.json written');
check(isfile(resSI.scriptPath), 'run_si_ks4.py written');
cfgSI = jsondecode(fileread(resSI.settingsPath));
check(cfgSI.n_chan == numAmp, 'config n_chan');
check(abs(cfgSI.fs - Fs) < 1e-9, 'config fs');
check(strcmp(char(cfgSI.recording_format), 'traditional'), 'config recording_format');
check(numel(cfgSI.files) == 2, 'config lists both rhd files');
check(isequal(cfgSI.exclude_channels(:).', 1), 'exclude_channels 0-based (2 -> 1)');
check(cfgSI.preprocessing.detect_bad_channels.enabled, 'detect_bad_channels on by default');
check(cfgSI.preprocessing.silence_periods.enabled, 'silence enabled with a manual period');
check(~cfgSI.preprocessing.filter.enabled, 'SI bandpass off by default');
check(contains(resSI.command, 'run_si_ks4.py'), 'command references the script');
check(endsWith(char(resSI.resultsDir), 'kilosort4'), 'results dir is the kilosort4 run folder');

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


function writeInfoRHD(ffn, numAmp, Fs)
%writeInfoRHD  Write a header-only v2.0 info.rhd (no data blocks) for the split
%   formats. Declares numAmp amplifier channels (native names A-000..A-00N, so
%   amp-A-00x.dat filenames line up) plus one bit-0 dig-in line; no aux/adc.

fid = fopen(ffn, 'w', 'ieee-le');
assert(fid >= 0, 'cannot open %s', ffn);

fwrite(fid, hex2dec('c6912702'), 'uint32');   % magic
fwrite(fid, 2, 'int16');                       % main version (>1)
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
fwrite(fid, 0, 'int16');                        % num_temp_sensor_channels
fwrite(fid, 0, 'int16');                        % board_mode
writeQString(fid, '');                          % reference_channel (v>1)

fwrite(fid, 1, 'int16');                        % number_of_signal_groups
writeQString(fid, 'PortA');                     % group name
writeQString(fid, 'A');                         % group prefix
fwrite(fid, 1, 'int16');                        % group enabled
fwrite(fid, numAmp + 1, 'int16');               % group num channels
fwrite(fid, numAmp, 'int16');                   % group num amp channels
for c = 1:numAmp
    writeChannel(fid, sprintf('A-%03d', c-1), sprintf('amp%d', c-1), c-1, 0);
end
writeChannel(fid, 'DIN-00', 'din0', 0, 4);      % dig-in, native_order 0

fclose(fid);   % header only - no data blocks follow
end


function writeDat(ffn, data, prec)
%writeDat  Write a flat little-endian binary .dat file (split-format data file).
fid = fopen(ffn, 'w', 'ieee-le');
assert(fid >= 0, 'cannot open %s', ffn);
fwrite(fid, data, prec);
fclose(fid);
end


function bytes = readBin(ffn)
fid = fopen(ffn, 'r', 'ieee-le');
bytes = fread(fid, inf, '*uint8');
fclose(fid);
end
